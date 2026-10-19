# サイトのアイコンとブログの画像（pub/branding/。Lyndbaum::SiteIcon、Lyndbaum::BlogImage、/admin/settings/icon、/admin/settings/blog_image）
use strict;
use warnings;
use utf8;
use Test::More;

use Encode qw(encode_utf8);
use File::Spec;
use File::Temp ();
use Lyndbaum::App;
use Lyndbaum::BlogImage::Writer;
use Lyndbaum::Branding::Writer;
use Lyndbaum::Config;
use Lyndbaum::SiteIcon::Writer;
use AdminTest;
use TestUtil qw(root_dir);

plan skip_all => 'GD がありません' if !eval { require GD; 1 };
# 読めない画像の記録（warn と GD の警告）は、テストの出力に混ぜない
local $SIG{__WARN__} = sub { warn @_ if $_[0] !~ /サイトのアイコンを作れませんでした|ブログの画像を読めませんでした/ };

# 横長の画像。左右の端は赤、真ん中の正方形は青（切り抜いたら青だけが残る）。$alpha なら真ん中を半分透かす
sub wide_image {
	my ($format, $alpha) = @_;
	my $image = GD::Image->new(300, 200, 1);
	$image->alphaBlending(0);
	$image->saveAlpha(1);
	$image->filledRectangle(0, 0, 299, 199, $image->colorAllocate(255, 0, 0));
	$image->filledRectangle(50, 0, 249, 199, $alpha ? $image->colorAllocateAlpha(0, 0, 255, 64) : $image->colorAllocate(0, 0, 255));
	return $format eq 'jpeg' ? $image->jpeg(90) : $image->$format;
}

sub size_of { my ($png) = @_; return [ unpack 'NN', substr($png, 16, 8) ] }
sub read_file { my ($file) = @_; open my $fh, '<:raw', $file or die "$file: $!"; local $/; return <$fh> }

subtest 'ICO' => sub {
	my %files = %{ Lyndbaum::SiteIcon::Writer->make(wide_image('png'), 'png') };
	my ($reserved, $type, $count) = unpack 'vvv', $files{'favicon.ico'};
	is_deeply [ $reserved, $type, $count ], [ 0, 1, 2 ], 'アイコンが2つ入った ICO';
	my @entries = map { [ unpack 'CCCCvvVV', substr($files{'favicon.ico'}, 6 + 16 * $_, 16) ] } 0, 1;
	is_deeply [ map { [ @$_[0, 1] ] } @entries ], [ [ 16, 16 ], [ 32, 32 ] ], '16 と 32';
	my ($len, $offset) = @{ $entries[1] }[6, 7];
	is substr($files{'favicon.ico'}, $offset, 8), "\x89PNG\r\n\x1A\n", '中身は PNG';
	is_deeply size_of(substr $files{'favicon.ico'}, $offset, $len), [ 32, 32 ];
	is_deeply { map { $_ => size_of($files{$_}) } grep { /\.png\z/ } keys %files },
		{ 'icon-32.png' => [ 32, 32 ], 'icon-192.png' => [ 192, 192 ], 'apple-touch-icon.png' => [ 180, 180 ] }, '大きさ';

	my $icon = GD::Image->newFromPngData($files{'icon-192.png'}, 1);
	is_deeply [ $icon->rgb($icon->getPixel(2, 96)) ], [ 0, 0, 255 ], '真ん中を正方形に切り抜く（端の赤は入らない）';

	my $default = read_file(File::Spec->catfile(root_dir(), qw(pub assets logo favicon.ico)));
	is_deeply [ unpack 'vvv', $default ], [ 0, 1, 2 ], '既定のロゴの favicon.ico もある';
};

subtest '透明なところ' => sub {
	my %files = %{ Lyndbaum::SiteIcon::Writer->make(wide_image('png', 1), 'png') };
	my $icon = GD::Image->newFromPngData($files{'icon-32.png'}, 1);
	ok $icon->alpha($icon->getPixel(16, 16)) > 0, 'icon は透明なところを残す';
	my $apple = GD::Image->newFromPngData($files{'apple-touch-icon.png'}, 1);
	is $apple->alpha($apple->getPixel(90, 90)), 0, 'apple-touch-icon は白に重ねて透かさない';
};

my $t = AdminTest->new;
my ($cookie) = $t->login;
my $csrf = $t->csrf_of($cookie);
my $dir = Lyndbaum::Branding::Writer->dir($t->app);
my $B = 'BOUNDARY';
# multipart/form-data で送る。値を [ 中身, ファイル名 ] にするとファイル
my $post = sub {
	my ($key, %form) = @_;
	my $body = '';
	for my $name (sort keys %form) {
		my ($value, $filename) = ref $form{$name} ? @{ $form{$name} } : ($form{$name});
		$body .= encode_utf8("--$B\r\nContent-Disposition: form-data; name=\"$name\""
			. (defined $filename ? "; filename=\"$filename\"" : '') . "\r\n\r\n") . $value . "\r\n";
	}
	return $t->request(POST => "/admin/settings/$key", cookie => $cookie, raw_body => "$body--$B--\r\n",
		content_type => "multipart/form-data; boundary=$B");
};
my $get = sub { $t->request(GET => $_[0], cookie => $cookie)->body };
sub setting { $t->app->db->selectrow_array('SELECT value FROM settings WHERE key = ?', undef, $_[0]) }

subtest 'サイトのアイコンを入れ替える' => sub {
	my $body = $get->('/admin/settings/blog');
	like $body, qr{<h2 id="icon">サイトのアイコン</h2>};
	like $body, qr{<form class="admin-form branding-form" method="post" action="/admin/settings/icon" enctype="multipart/form-data">};
	like $body, qr{<img src="/pub/assets/logo/logo-192\.png" width="64" height="64" alt="今のサイトのアイコン"> 既定のロゴ};
	unlike $body, qr{消して既定のロゴに戻す}, '既定のロゴなら、消すボタンは出さない';
	like $get->('/'), qr{<link rel="icon" href="/pub/assets/logo/logo-32\.png" sizes="32x32">}, '公開側は既定のロゴ';
	like $body, qr{<link rel="apple-touch-icon" href="/pub/assets/logo/logo-180\.png">}, '管理画面も';

	my $res = $post->(icon => csrf_token => $csrf, op => 'upload', file => [ wide_image('jpeg'), '写真.JPG' ]);
	is $res->status, 303, 'JPEG を入れる';
	is AdminTest::header($res, 'Location'), '/admin/settings/blog?done=saved&image=icon#icon';
	ok -f File::Spec->catfile($dir, $_), "$_ を書き出す" for qw(icon-32.png icon-192.png apple-touch-icon.png favicon.ico);
	is substr(read_file(File::Spec->catfile($dir, 'icon-32.png')), 0, 8), "\x89PNG\r\n\x1A\n", 'PNG にする';
	my $version = setting('site_icon');
	like $version, qr/\A\d+\z/, '書き出した時刻を設定に入れる';

	$body = $get->('/admin/settings/blog?done=saved&image=icon');
	like $body, qr{<p class="admin-notice" role="status">サイトのアイコンを入れ替えました。</p>};
	unlike $body, qr{ブログの画像を入れ替えました。}, '知らせは入れ替えたものの所にだけ出す';
	like $body, qr{<img src="/pub/branding/icon-192\.png\?v=$version" width="64" height="64" alt="今のサイトのアイコン"> 入れた画像};
	like $body, qr{<button type="submit" name="op" value="delete" class="button">消して既定のロゴに戻す</button>};
	like $get->('/'), qr{<link rel="icon" href="/pub/branding/icon-32\.png\?v=$version" sizes="32x32">},
		'URLに時刻を付ける（入れ替えたときに、ブラウザに古いアイコンを使わせない）';

	for my $format (qw(webp gif)) {
		is $post->(icon => csrf_token => $csrf, op => 'upload', file => [ wide_image($format), "a.$format" ])->status, 303, "$format も入れられる";
		my $icon = GD::Image->newFromPngData(read_file(File::Spec->catfile($dir, 'icon-192.png')), 1);
		is_deeply [ $icon->rgb($icon->getPixel(2, 96)) ], [ 0, 0, 255 ], "$format から PNG を作る";
	}
	$res = $post->(icon => csrf_token => $csrf, op => 'upload', file => [ "\0\0\0\x18ftypmp42", 'a.mp4' ]);
	is $res->status, 400, '画像でないものは受け付けない';
	like $res->body, qr{サイトのアイコンを入れ替えられませんでした。「a\.mp4」は置けない種類のファイルです（置けるのは png、jpg、jpeg、webp、gif）。};
	$res = $post->(icon => csrf_token => $csrf, op => 'upload', file => [ 'not png', 'a.png' ]);
	like $res->body, qr{「a\.png」は、拡張子と中身の種類が合いません。}, '中身も確かめる';
	$res = $post->(icon => csrf_token => $csrf, op => 'upload', file => [ "\x89PNG\r\n\x1A\nbroken", 'a.png' ]);
	is $res->status, 400, '画像として読めない';
	like $res->body, qr{「a\.png」を画像として読めませんでした。};
	like $post->(icon => csrf_token => $csrf, op => 'upload')->body, qr{画像を選んでください。};
	is $post->(icon => csrf_token => 'wrong', op => 'delete')->status, 403, 'CSRFトークンが違う';
	ok -f File::Spec->catfile($dir, 'favicon.ico'), '失敗しても今のアイコンはそのまま';
	is $t->request(POST => '/admin/settings/other', cookie => $cookie, body => [ csrf_token => $csrf ])->status, 404, '無い設定';

	$res = $post->(icon => csrf_token => $csrf, op => 'delete');
	is $res->status, 303, '消す';
	is AdminTest::header($res, 'Location'), '/admin/settings/blog?done=deleted&image=icon#icon';
	ok !-e File::Spec->catfile($dir, $_), "$_ を消す" for qw(icon-32.png icon-192.png apple-touch-icon.png favicon.ico);
	like $get->('/admin/settings/blog?done=deleted&image=icon'), qr{サイトのアイコンを消して、既定のロゴに戻しました。};
	like $get->('/'), qr{<link rel="icon" href="/pub/assets/logo/logo-32\.png" sizes="32x32">}, '既定のロゴに戻る';
};

subtest 'ブログの画像を入れ替える' => sub {
	my $body = $get->('/admin/settings/blog');
	like $body, qr{<h2 id="blog_image">ブログの画像</h2>};
	like $body, qr{<p class="branding-preview">ありません（OGPに画像を出しません）</p>}, '入れていなければ画像を出さない';
	unlike $body, qr{>消す</button>};

	my $jpeg = wide_image('jpeg');
	my $res = $post->(blog_image => csrf_token => $csrf, op => 'upload', file => [ $jpeg, 'ogp.JPEG' ]);
	is $res->status, 303;
	is AdminTest::header($res, 'Location'), '/admin/settings/blog?done=saved&image=blog_image#blog_image';
	my $name = setting('blog_image');
	like $name, qr/\Ablog-image-\d+\.jpg\z/, '名前は blog-image-時刻.拡張子（JPEG は jpg）';
	is read_file(File::Spec->catfile($dir, $name)), $jpeg, '画像はそのまま置く';
	$body = $get->("/admin/settings/blog?done=saved&image=blog_image");
	like $body, qr{ブログの画像を入れ替えました。};
	like $body, qr{<img src="/pub/branding/$name" alt="今のブログの画像"> 入れた画像};
	like $get->('/'), qr{<meta property="og:image" content="[^"]*/pub/branding/$name">}, 'OGP に出す';

	# 前の画像は消す（時刻を変えるため、名前を書き換えておく）
	$t->app->db->do(q{UPDATE settings SET value = 'blog-image-1.jpg' WHERE key = 'blog_image'});
	rename File::Spec->catfile($dir, $name), File::Spec->catfile($dir, 'blog-image-1.jpg');
	is $post->(blog_image => csrf_token => $csrf, op => 'upload', file => [ wide_image('png'), 'b.png' ])->status, 303;
	like setting('blog_image'), qr/\Ablog-image-\d+\.png\z/;
	ok !-e File::Spec->catfile($dir, 'blog-image-1.jpg'), '前の画像は消す';

	like $post->(blog_image => csrf_token => $csrf, op => 'upload', file => [ "\x89PNG\r\n\x1A\nbroken", 'a.png' ])->body,
		qr{ブログの画像を入れ替えられませんでした。「a\.png」を画像として読めませんでした。}, '読めない画像は置かない';

	my $current = setting('blog_image');
	$res = $post->(blog_image => csrf_token => $csrf, op => 'delete');
	is $res->status, 303, '消す';
	is setting('blog_image'), '';
	ok !-e File::Spec->catfile($dir, $current), '画像も消す';
	like $get->('/admin/settings/blog?done=deleted&image=blog_image'), qr{ブログの画像を消しました。};
	unlike $get->('/'), qr{og:image}, 'OGP に画像を出さない';
};

subtest '旧データの取り込み（添付ファイルから写す）' => sub {
	# 添付ファイルは一時ディレクトリに置く（リポジトリの pub/attachments/ を書き換えないように）
	my $app = Lyndbaum::App->new(root => $t->app->{root}, config => Lyndbaum::Config->new(%{ $t->app->config },
		attachment_dir => File::Temp::tempdir(CLEANUP => 1)));
	my $folder = File::Spec->catdir($app->attachment_dir, '@system');
	mkdir $folder or die $!;
	open my $fh, '>:raw', File::Spec->catfile($folder, 'sys-blog_image.png') or die $!;
	print {$fh} wide_image('png');
	close $fh;
	my $name = Lyndbaum::BlogImage::Writer->copy_attachment($app, '@system/sys-blog_image.png');
	like $name, qr/\Ablog-image-\d+\.png\z/;
	is read_file(File::Spec->catfile($dir, $name)), wide_image('png'), '添付ファイルの画像を pub/branding/ へ写す';
	eval { Lyndbaum::BlogImage::Writer->copy_attachment($app, '@system/none.png') };
	like $@, qr{none\.png}, '無ければ die する';
};

done_testing;
