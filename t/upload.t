# 添付ファイルのアップロード（Lyndbaum::Upload、Lyndbaum::Thumbnail、/admin/upload）
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
use Lyndbaum::Thumbnail;
use Lyndbaum::Upload;
use AdminTest;

# サムネイルを作れなかったときの記録（warn）は、テストの出力に混ぜない
local $SIG{__WARN__} = sub { warn @_ if $_[0] !~ /サムネイルを作れませんでした/ };

my $HAS_GD = eval { require GD; 1 };
my $NOW = 1791979500;   # 2026-10-14 21:05（日本時間）
my $dir = tempdir(CLEANUP => 1);
sub save { Lyndbaum::Upload->save(dir => $dir, thumbnail_size => 240, now => $NOW, @_) }
sub exists_file { -e encode_utf8(File::Spec->catfile($dir, split m{/}, $_[0])) }

# 中身の先頭だけが正しい、画像としては読めないファイル
my %FAKE = (jpg => "\xFF\xD8\xFF\xE0fake", png => "\x89PNG\r\n\x1A\nfake", gif => 'GIF89afake',
	webp => 'RIFF1234WEBPfake', mp4 => "\0\0\0\x18ftypmp42", webm => "\x1A\x45\xDF\xA3fake");

subtest 'ファイル名' => sub {
	is(Lyndbaum::Upload->clean_name('a b:c].png'), 'a_b_c_.png', '空白と、記法の区切りは _ にする');
	is(Lyndbaum::Upload->clean_name('C:\\Users\\x\\写真.JPG'), '写真.JPG', 'パスは除く。日本語と大文字の拡張子はそのまま');
	is(Lyndbaum::Upload->clean_name('../.hidden.png'), 'hidden.png', '先頭の . は取る');
	is(Lyndbaum::Upload->clean_name('a.tar.png'), 'a_tar.png', '名前の中のピリオドは _ にする（拡張子を1つにする）');
	is(Lyndbaum::Upload->clean_name('shell.php.mp4'), 'shell_php.mp4', 'スクリプトの拡張子を中に入れても、拡張子は最後の1つだけ');
	is(Lyndbaum::Upload->clean_name('x.cgi.png'), 'x_cgi.png');
	is(Lyndbaum::Upload->clean_name('.png'), 'file.png');
	is length(Lyndbaum::Upload->clean_name(('あ' x 200) . '.jpeg')), 100, '100文字まで（拡張子は残す）';
	is(Lyndbaum::Upload->folder_of($NOW), 'posts/2026/10/', '日本時間の年月のフォルダ');
	is(Lyndbaum::Upload->folder_of(1793458800 - 1), 'posts/2026/10/', '10月31日の23:59:59（日本時間）');
	is(Lyndbaum::Upload->folder_of(1793458800), 'posts/2026/11/', '11月1日の0:00（日本時間）');
};

subtest '種類を確かめる' => sub {
	for my $ext (sort keys %FAKE) {
		my $file = save(filename => "a.$ext", data => $FAKE{$ext});
		ok exists_file("posts/2026/10/$file->{name}"), "$ext は置ける";
	}
	eval { save(filename => 'a.exe', data => 'MZ') };
	like $@, qr{置けない種類のファイル}, '拡張子が許していないもの';
	eval { save(filename => 'a.png', data => $FAKE{jpg}) };
	like $@, qr{拡張子と中身の種類が合いません}, '拡張子と中身が違う';
	eval { save(filename => 'a.jpg', data => '<?php') };
	like $@, qr{拡張子と中身の種類が合いません}, '画像のふりをしたファイル';
	eval { save(filename => 'noext', data => $FAKE{jpg}) };
	like $@, qr{置けない種類};
};

subtest '同じ名前' => sub {
	my $first  = save(filename => 'same.mp4', data => $FAKE{mp4});
	my $second = save(filename => 'same.mp4', data => $FAKE{mp4});
	my $third  = save(filename => 'same.mp4', data => $FAKE{mp4});
	is_deeply [ map { $_->{name} } $first, $second, $third ], ['same.mp4', 'same-2.mp4', 'same-3.mp4'], '上書きせず、番号を付ける';
	opendir my $dh, File::Spec->catdir($dir, 'posts', '2026', '10') or die $!;
	is_deeply [ grep { /\A\.upload-/ } readdir $dh ], [], '一時ファイルを残さない';
};

subtest '記法' => sub {
	my $video = save(filename => 'v.webm', data => $FAKE{webm});
	is(Lyndbaum::Upload->tag_of($video), '[file:webm:posts/2026/10/:v.webm]', '動画は file');
	my $broken = save(filename => 'broken.jpg', data => $FAKE{jpg});
	is $broken->{thumbnail}, 0, '読めない画像はサムネイルを作れない';
	is(Lyndbaum::Upload->tag_of($broken), '[image:L:posts/2026/10/:broken.jpg]', 'サムネイルが無ければ、元の画像を出す（L）');
	is(Lyndbaum::Upload->tag_of({ %$broken, thumbnail => 1 }), '[image:S:posts/2026/10/:broken.jpg]');
};

subtest 'Exif の向き' => sub {
	# APP1（Exif）の IFD0 に Orientation（0x0112）だけを持つ JPEG の頭
	my $exif = sub {
		my ($order, $value) = @_;
		my ($s, $l) = $order eq 'II' ? ('v', 'V') : ('n', 'N');
		my $tiff = $order . pack($s, 42) . pack($l, 8) . pack($s, 1) . pack("$s$s$l", 0x0112, 3, 1) . pack($s, $value) . "\0\0" . pack($l, 0);
		return "\xFF\xD8" . "\xFF\xE1" . pack('n', 2 + 6 + length $tiff) . "Exif\0\0" . $tiff . "\xFF\xDA";
	};
	is(Lyndbaum::Thumbnail->orientation($exif->('II', 6)), 6, 'リトルエンディアン');
	is(Lyndbaum::Thumbnail->orientation($exif->('MM', 8)), 8, 'ビッグエンディアン');
	is(Lyndbaum::Thumbnail->orientation($exif->('II', 9)), 1, 'ありえない値');
	is(Lyndbaum::Thumbnail->orientation("\xFF\xD8\xFF\xDA"), 1, 'Exif が無い');
	is(Lyndbaum::Thumbnail->orientation("\xFF\xD8\xFF\xE1\0\x02"), 1, '壊れている');
};

SKIP: {
	skip 'GD が無いので、サムネイルの作成は確かめない（sudo apt install libgd-perl）', 1 if !$HAS_GD;
	subtest 'サムネイル' => sub {
		my $image = GD::Image->new(800, 400, 1);
		$image->filledRectangle(0, 0, 399, 399, $image->colorAllocate(255, 0, 0));
		my $file = save(filename => '横長.png', data => $image->png);
		is $file->{thumbnail}, 1;
		my $thumb = GD::Image->newFromJpeg(encode_utf8(File::Spec->catfile($dir, 'posts', '2026', '10', '.thumbnail', '横長.png.jpg')), 1);
		is_deeply [ $thumb->getBounds ], [240, 120], '長い辺を240pxにする';

		my $small = GD::Image->new(100, 50, 1);
		$file = Lyndbaum::Upload->save(dir => $dir, filename => 'small.png', data => $small->png, thumbnail_size => 240, now => $NOW);
		$thumb = GD::Image->newFromJpeg(encode_utf8(File::Spec->catfile($dir, 'posts', '2026', '10', '.thumbnail', 'small.png.jpg')), 1);
		is_deeply [ $thumb->getBounds ], [100, 50], '元の画像のほうが小さければ、元の大きさ';

		# 向き 6（時計回りに90度回して見る）なら、縦長のサムネイルになる
		my $jpeg = $image->jpeg;
		my $tiff = 'II' . pack('v', 42) . pack('V', 8) . pack('v', 1) . pack('vvV', 0x0112, 3, 1) . pack('v', 6) . "\0\0" . pack('V', 0);
		my $app1 = "\xFF\xE1" . pack('n', 2 + 6 + length $tiff) . "Exif\0\0" . $tiff;
		substr($jpeg, 2, 0) = $app1;
		my $out = GD::Image->newFromJpegData(Lyndbaum::Thumbnail->make($jpeg, 'jpeg', 240), 1);
		is_deeply [ $out->getBounds ], [120, 240], 'Exif の向きに合わせて回す';
		my $kept = save(filename => 'exif.jpg', data => $jpeg);
		open my $fh, '<:raw', encode_utf8(File::Spec->catfile($dir, 'posts', '2026', '10', 'exif.jpg')) or die $!;
		is do { local $/; <$fh> }, $jpeg, '元の画像には手を加えない（Exif も残す）';
	};

	subtest 'サムネイルを作り直す（tools/rebuild-thumbnails.pl）' => sub {
		my $root = tempdir(CLEANUP => 1);
		my $put = sub {
			my ($path, $data) = @_;
			my $file = encode_utf8(File::Spec->catfile($root, split m{/}, $path));
			make_path((File::Spec->splitpath($file))[1]);
			open my $fh, '>:raw', $file or die $!;
			print $fh $data;
			close $fh;
		};
		my $image = GD::Image->new(800, 400, 1);
		$put->('posts/2026/10/あり.png', $image->png);
		$put->('posts/2026/10/.thumbnail/あり.png.jpg', GD::Image->new(240, 120, 1)->jpeg);
		$put->('@system/素材/なし.png', $image->png);
		$put->('@system/偽物.png', 'not png');
		$put->('@system/動画.mp4', $FAKE{mp4});
		$put->('.trashbox/posts/ゴミ.png', $image->png);
		my $media = Lyndbaum::Media->new(dir => $root, trash_dir => "$root/.trashbox");
		my $bounds = sub { [ GD::Image->newFromJpeg(encode_utf8("$root/$_[0]"), 1)->getBounds ] };

		my $result = Lyndbaum::Upload->rebuild_thumbnails(dir => $root, media => $media, size => 160, missing => 1);
		is_deeply $result, { made => 1, skipped => 1, errors => [] }, '--missing：無いものだけ作る（画像でないもの、中身の合わないものは数えない）';
		is_deeply $bounds->('@system/素材/.thumbnail/なし.png.jpg'), [160, 80];
		is_deeply $bounds->('posts/2026/10/.thumbnail/あり.png.jpg'), [240, 120], 'あるものは変えない';

		$result = Lyndbaum::Upload->rebuild_thumbnails(dir => $root, media => $media, size => 320);
		is $result->{made}, 2, 'すべて作り直す';
		is_deeply $bounds->('posts/2026/10/.thumbnail/あり.png.jpg'), [320, 160], '新しい大きさにする';
		ok !-e encode_utf8("$root/\@system/.thumbnail/偽物.png.jpg"), '中身の合わないものには作らない';
		ok !-e encode_utf8("$root/.trashbox/posts/.thumbnail/ゴミ.png.jpg"), 'ゴミ箱の中は作らない';
	};
}

subtest '/admin/upload' => sub {
	my $t = AdminTest->new;
	my $root = tempdir(CLEANUP => 1);
	$t->{app} = Lyndbaum::App->new(root => $t->app->{root},
		config => Lyndbaum::Config->new(%{ $t->app->config }, attachment_dir => $root, upload_max_mb => 1));
	my ($cookie) = $t->login;
	my $csrf = $t->csrf_of($cookie);
	my $B = 'BOUNDARY';
	my $multipart = sub {
		my (@parts) = @_;
		my $body = '';
		while (my ($name, $value, $filename) = splice @parts, 0, 3) {
			$body .= "--$B\r\nContent-Disposition: form-data; name=\"$name\"" . (defined $filename ? "; filename=\"$filename\"" : '') . "\r\n\r\n$value\r\n";
		}
		return encode_utf8($body) . "--$B--\r\n";
	};
	my $post = sub {
		my ($body, %opt) = @_;
		return $t->request(POST => '/admin/upload', cookie => $cookie, raw_body => $body, content_type => "multipart/form-data; boundary=$B", %opt);
	};

	my $res = $post->($multipart->(csrf_token => $csrf, undef, file => $FAKE{mp4}, '動画.mp4', file => 'MZ', 'virus.exe'));
	is $res->status, 200;
	is $res->content_type, 'application/json';
	my $json = JSON::PP->new->decode($res->body);
	my $folder = Lyndbaum::Upload->folder_of(time);
	is_deeply $json->{files}, [ { name => '動画.mp4', url => "/pub/attachments/$folder%E5%8B%95%E7%94%BB.mp4", tag => "[file:mp4:$folder:動画.mp4]" } ],
		'置いたファイルと、本文に入れる記法';
	like $json->{errors}[0], qr{「virus\.exe」は置けない種類}, '置けなかったファイルの理由';

	make_path(encode_utf8("$root/\@system/素材"));
	$res = $post->($multipart->(csrf_token => $csrf, undef, folder => '@system/素材/', undef, file => $FAKE{mp4}, 'b.mp4'));
	is(JSON::PP->new->decode($res->body)->{files}[0]{tag}, '[file:mp4:@system/素材/:b.mp4]', '置くフォルダを決められる（メディアの画面）');
	ok -f encode_utf8("$root/\@system/素材/b.mp4");
	for my $bad ('無い/', '../', '/') {
		$res = $post->($multipart->(csrf_token => $csrf, undef, folder => $bad, undef, file => $FAKE{mp4}, 'c.mp4'));
		is $res->status, 400, "「$bad」には置かない";
	}

	is $post->($multipart->(csrf_token => $csrf, undef))->status, 400, 'ファイルが無い';
	is $post->($multipart->(csrf_token => 'wrong', undef, file => $FAKE{mp4}, 'a.mp4'))->status, 403, 'CSRFトークンが違う';
	is $t->request(POST => '/admin/upload', raw_body => $multipart->(file => $FAKE{mp4}, 'a.mp4'),
		content_type => "multipart/form-data; boundary=$B")->status, 303, 'ログインしていなければ受け付けない';

	$res = $post->($multipart->(csrf_token => $csrf, undef, file => 'x' x (1024 * 1024 + 1), 'big.mp4'));
	is $res->status, 413, '大きすぎる';
	like(JSON::PP->new->decode($res->body)->{errors}[0], qr{1MBまで});
	is $t->request(POST => '/admin/upload', raw_body => 'x' x (1024 * 1024 + 1),
		content_type => "multipart/form-data; boundary=$B")->status, 303, 'ログインしていなければ、大きさにかかわらずログインの画面へ';
};

done_testing;
