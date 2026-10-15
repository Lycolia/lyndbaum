# 添付ファイルの一覧とゴミ箱（Lyndbaum::Media、/admin/media）
use strict;
use warnings;
use utf8;
use Test::More;

use Encode qw(encode_utf8);
use File::Path qw(make_path);
use File::Spec;
use File::Temp qw(tempdir);
use JSON::PP ();
use Lyndbaum::App;
use Lyndbaum::Config;
use Lyndbaum::Media;
use Lyndbaum::URL;
use AdminTest;
use TestUtil qw(insert_article);

my $dir   = tempdir(CLEANUP => 1);
my $trash = File::Spec->catdir($dir, '.trashbox');   # ゴミ箱は添付ファイルの置き場所の .trashbox（Lyndbaum::App->media）
sub put {
	my ($path, $data, $mtime) = @_;
	my $file = encode_utf8(File::Spec->catfile($dir, split m{/}, $path));
	my (undef, $parent) = File::Spec->splitpath($file);
	make_path($parent);
	open my $fh, '>:raw', $file or die "$file: $!";
	print $fh $data // 'x';
	close $fh;
	utime $mtime, $mtime, $file if $mtime;
}
sub has { -e encode_utf8(File::Spec->catfile($_[0], split m{/}, $_[1])) }

put('posts/2026/10/写真.jpg', 'jpeg', 2000);
put('posts/2026/10/.thumbnail/写真.jpg.jpg', 'thumb');
put('posts/2026/10/b.mp4', 'mp4', 3000);
put('posts/2026/09/old.png', 'png', 1000);
put('posts/2026/09/.hidden', 'x');
put('@system/logo.png', 'png');
put('.trashbox/x.png', 'x');

my $media = Lyndbaum::Media->new(dir => $dir, trash_dir => $trash);

subtest 'フォルダとファイル' => sub {
	my $tree = $media->folders;
	is_deeply [ map { $_->{folder} } @$tree ], ['posts/', '@system/'], '. で始まるフォルダ（.trashbox など）は出さない。名前の逆順';
	is_deeply [ map { [ $_->{folder}, $_->{count} ] } @{ $tree->[0]{children}[0]{children} } ],
		[ ['posts/2026/10/', 2], ['posts/2026/09/', 1] ], '新しい年月を先に。ファイルの数（. で始まるものは数えない）';
	my $files = $media->files('posts/2026/10/');
	is_deeply [ map { $_->{name} } @$files ], ['b.mp4', '写真.jpg'], '新しい順';
	is_deeply [ @{ $files->[1] }{qw(kind thumbnail size)} ], ['image', 1, 4];
	is_deeply [ @{ $files->[0] }{qw(kind thumbnail)} ], ['video', 0];

	is(Lyndbaum::Media->clean_folder('posts/2026/10'), 'posts/2026/10/', '/ で終わる形にする');
	is(Lyndbaum::Media->clean_folder(''), '');
	is(Lyndbaum::Media->clean_folder($_), undef, "「$_」は正しくない") for '../etc/', 'posts/../x/', '/abs/', 'a//b/', '.thumbnail/';
	ok !Lyndbaum::Media->valid_name($_), "名前「$_」は正しくない" for '', '../x', 'a/b', '.htaccess';
};

subtest '使っている記事' => sub {
	my $t = AdminTest->new;
	my $dbh = $t->dbh;
	insert_article($dbh, id => 1, title => '記法', body_src => '[image:S:posts/2026/10/:写真.jpg:代替]');
	insert_article($dbh, id => 2, title => 'URL', body_src => '![](/pub/attachments/posts/2026/10/写真.jpg)', deleted_at => 1);
	insert_article($dbh, id => 3, title => 'OGP', og_image => 'posts/2026/10/写真.jpg');
	insert_article($dbh, id => 4, title => '別の画像', body_src => '[image:S:posts/2026/10/:写真.jpg.bak] /pub/attachments/posts/2026/10/写真.jpg.bak [image:S:posts/2026/09/:写真.jpg]');
	insert_article($dbh, id => 5, title => '記法だけ', body_src => '[image:L:posts/2026/10/:写真.jpg]');
	my $used = $media->usage($dbh, 'posts/2026/10/', '写真.jpg');
	is_deeply [ map { $_->{id} } @$used ], [5, 3, 2, 1], '記法、URL、OGP（ゴミ箱の記事を含む）。名前の頭が同じだけのファイルや、ほかのフォルダは当たらない';
};

subtest 'ゴミ箱' => sub {
	my $trashed = $media->trash('posts/2026/10/', '写真.jpg', now => 1791979500);   # 2026-10-14 21:05:00（日本時間）
	is $trashed, '写真.#20261014-210500.jpg', '名前に消した日時を入れる（旧システムの .trashbox と同じ形）';
	ok !has($dir, 'posts/2026/10/写真.jpg'), '元の場所から無くなる';
	ok !has($dir, 'posts/2026/10/.thumbnail/写真.jpg.jpg'), 'サムネイルも';
	ok has($trash, "posts/2026/10/$trashed");
	ok has($trash, "posts/2026/10/.thumbnail/$trashed.jpg");
	is $media->trash('posts/2026/10/', 'b.mp4', now => 1791979500), 'b.#20261014-210500.mp4';

	put('posts/2026/10/写真.jpg', 'new');
	$media->trash('posts/2026/10/', '写真.jpg', now => 1791979500);
	ok has($trash, 'posts/2026/10/写真.#20261014-210500-2.jpg'), '同じ日時なら番号を付ける';

	my $list = $media->trash_files;
	is scalar @$list, 3;
	my ($video) = grep { $_->{original} eq 'b.mp4' } @$list;
	is_deeply [ @$video{qw(folder name deleted kind)} ], ['posts/2026/10/', 'b.#20261014-210500.mp4', '2026-10-14 21:05', 'video'];

	put('posts/2026/10/写真.jpg', 'another');
	is $media->restore('posts/2026/10/', $trashed), '写真-2.jpg', '戻す。同じ名前があれば番号を付ける';
	ok has($dir, 'posts/2026/10/.thumbnail/写真-2.jpg.jpg'), 'サムネイルも戻す';
	ok $media->purge('posts/2026/10/', 'b.#20261014-210500.mp4');
	ok !has($trash, 'posts/2026/10/b.#20261014-210500.mp4'), '完全に消す';
	eval { $media->trash('posts/2026/10/', '無い.jpg') };
	like $@, qr{ありません};
	eval { $media->restore('posts/2026/10/', '無い.#20261014-210500.jpg') };
	like $@, qr{ありません};
};

subtest '/admin/media' => sub {
	my $t = AdminTest->new;
	$t->{app} = Lyndbaum::App->new(root => $t->app->{root},
		config => Lyndbaum::Config->new(%{ $t->app->config }, attachment_dir => $dir));
	insert_article($t->dbh, id => 1, title => '使う記事', body_src => '[image:S:@system/:logo.png]');
	my ($cookie) = $t->login;
	my $csrf = $t->csrf_of($cookie);
	my $get  = sub { $t->request(GET => $_[0], cookie => $cookie) };
	my $json = sub { JSON::PP->new->decode($_[0]->body) };

	is $t->request(GET => '/admin/media/folders')->status, 303, 'ログインしていなければ使えない';
	like $get->('/admin/media')->body, qr{<div class="media-page" data-base="/admin/media" data-csrf="[^"]+"></div>};
	my $folders = $json->($get->('/admin/media/folders'));
	is $folders->{folders}[1]{folder}, '@system/';
	like $folders->{current}, qr{\Aposts/\d{4}/\d\d/\z}, '今月のフォルダ（最初に開く）';

	my $res = $get->('/admin/media/files?folder=%40system%2F');
	is $res->status, 200;
	is header($res, 'Cache-Control'), 'no-store';
	is_deeply $json->($res)->{files}[0], {
		name => 'logo.png', folder => '@system/', kind => 'image', size => 3, mtime => $json->($res)->{files}[0]{mtime},
		url => '/pub/attachments/%40system/logo.png', thumbnail => undef, tag => '[image:L:@system/:logo.png]',
	}, 'サムネイルが無い画像の記法は L';
	is $get->('/admin/media/files?folder=..%2F')->status, 400, 'フォルダの外は見られない';

	my $usage = $json->($get->('/admin/media/usage?folder=%40system%2F&name=logo.png'));
	is_deeply $usage->{articles}, [ { id => 1, title => '使う記事', trashed => JSON::PP::false, edit_url => '/admin/articles/1' } ];

	my $post = sub { my ($path, @body) = @_; $t->request(POST => $path, cookie => $cookie, body => [ csrf_token => $csrf, @body ]) };
	$res = $post->('/admin/media/trash', folder => '@system/', name => 'logo.png', name => '無い.png');
	is_deeply $json->($res)->{done}, ['logo.png'];
	like $json->($res)->{errors}[0], qr{「\@system/無い\.png」はありません};
	is $t->request(POST => '/admin/media/trash', cookie => $cookie, body => [ folder => '@system/', name => 'x' ])->status, 403, 'CSRFトークンが無い';

	my $list = $json->($get->('/admin/media/trash'))->{files};
	my ($logo) = grep { $_->{original} eq 'logo.png' } @$list;
	is $logo->{item}, "\@system/$logo->{name}";
	is $logo->{url}, '/pub/attachments/.trashbox/%40system/' . Lyndbaum::URL::escape_segment($logo->{name}), 'ゴミ箱の中も Web から見える';
	$res = $post->('/admin/media/trash/restore', item => $logo->{item});
	is_deeply $json->($res)->{done}, [ $logo->{item} ];
	ok has($dir, '@system/logo.png'), '戻す';

	$res = $post->('/admin/media/trash/purge', all => 1);
	is scalar @{ $json->($res)->{done} }, scalar(@$list) - 1, 'ゴミ箱を空にする';
	is_deeply $json->($get->('/admin/media/trash'))->{files}, [];
	is_deeply $json->($post->('/admin/media/trash/restore', item => '../../etc/passwd'))->{errors}, ['ファイルの名前が正しくありません。'], 'フォルダの外は戻せない';
};

sub header { AdminTest::header(@_) }

done_testing;
