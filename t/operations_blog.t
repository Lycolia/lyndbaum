use strict;
use utf8;
#-------------------------------------------------------------------------------
# 主な操作の中身のテスト（ブログの設定、画像アルバム）
#-------------------------------------------------------------------------------
# 実行: prove t/operations_blog.t
#
# 操作をしてから画面やファイルを見て、思ったとおりに変わったかを確かめる。
# 権限は t/permission_*.t、画面のエラーは t/screens_*.t で確かめる。
# 並べて動かしたときに早く終わるよう、t/operations_*.t に分けてある。
# どれも、AppTestのsetup()とseed()の後から始める。共通のものは t/lib/OpsTest.pm。
#
use FindBin;
BEGIN { push(@INC, "$FindBin::Bin/lib", "$FindBin::Bin/../lib"); }
use Test::More;
our $TODO;
use AppTest;
use OpsTest;

binmode(Test::More->builder->$_, ':utf8') foreach (qw(output failure_output todo_output));

my $app = AppTest->new()->setup()->seed();
my $dir = $app->dir;

#-------------------------------------------------------------------------------
# ブログの設定
#-------------------------------------------------------------------------------
subtest 'ブログの基本設定' => sub {
	my $r = $app->post('owner', 'set/', { action => 'set/index', blog_name => 'テストのブログ', description_txt => 'ブログの説明' });
	ok(AppTest::is_reload($r), '保存できる');
	$r = $app->get('guest', '');
	is($r->{title}, 'テストのブログ', 'トップの題名が変わる');
	like(body($r), qr{ブログの説明}, '説明が出る');
	like(read_file("$dir/pub/rss.xml"), qr{テストのブログ}, 'RSSの題名も変わる');
};

#-------------------------------------------------------------------------------
# 公開画面のメタ情報（PageSpeed Insights の指摘）。ブログの説明を入れた後、記事を書き足す前に確かめる
#-------------------------------------------------------------------------------
subtest 'メタディスクリプション' => sub {
	# 記事は、トップに出ている最初の記事（ほかのテストで公開の状態が変わるため）
	my ($art) = body($app->get('guest', '')) =~ m{<a href="[^"]*?(/\d+)" class="title">};
	ok($art, "記事のURLが取れる（$art）");
	foreach my $q ('', $art) {
		my $b = body($app->get('guest', $q));
		my @desc = $b =~ m{<meta name="description" content="([^"]*)">}g;
		my ($og) = $b =~ m{<meta property="og:description" content="([^"]*)">};
		is(scalar(@desc), 1, "?$q に1つだけ出る");
		ok($desc[0] ne '' && $desc[0] eq $og, "?$q の中身はog:descriptionと同じ（$og）");
	}
};

subtest 'ブログの権限' => sub {
	is($app->get('user', 'edit')->{status}, 403, 'userは記事を書けない');
	my $r = $app->post('owner', 'set/role', { action => 'set/role', admin_users => 'owner', editors => 'editor, user', viewers => '', view_pass => '' });
	ok(AppTest::is_reload($r), 'userを編集者にする');
	is($app->get('user', 'edit')->{status}, 200, 'userが記事を書ける');

	$r = $app->post('owner', 'set/role', { action => 'set/role', admin_users => 'owner', editors => 'editor', viewers => '', view_pass => '' });
	ok(AppTest::is_reload($r), '元に戻す');
	is($app->get('user', 'edit')->{status}, 403, 'userはまた記事を書けない');
};

subtest 'プライベートモードと表示パスワード' => sub {
	# 表示パスワードは、プライベートモードのときだけ効く
	my $r = $app->post('owner', 'set/', { action => 'set/index', blog_name => 'テストのブログ', description_txt => 'ブログの説明', private => 1 });
	ok(AppTest::is_reload($r), 'プライベートモードにする');
	foreach my $q ('', '/02', '&t=' . AppTest::_uri_escape('タグ2'), '&q=owner') {
		$r = $app->get('guest', $q);
		my $b = body($r);
		ok($r->{status} == 403 && $b !~ /ownerの記事|本文2|タグ2/, "ログインしていない人には ?$q で記事が出ない（403）");
	}
	like(body($app->get('guest', '')), qr{ブログを見る権限がありません}, 'ログインしていない人には、権限が無いことを出す');
	is($app->get('guest', '/99999')->{status}, 403, '無い記事でも同じ403（記事があるかは分からない）');
	is($app->get('guest', 'login')->{status}, 200, 'ログインの画面は開ける');
	like(body($app->get('editor', '/02')), qr{本文2}, '編集者には記事が出る');

	# 公開フォルダのファイルは、推測できない名前のフォルダへ移る
	my ($private) = map { m{/(private\.[^/]+)$} } glob("$dir/pub/private.*");
	ok($private, '公開フォルダのファイルを、推測できない名前のフォルダへ移す');
	ok(!-e "$dir/pub/rss.xml" && -f "$dir/pub/$private/rss.xml", 'RSSが移る');
	ok(!-e "$dir/pub/attachments" && -f "$dir/pub/$private/attachments/test/a.png", '画像が移る');
	ok(-d "$dir/pub/assets", '配布物（pub/assets/）は移さない');
	like(body($app->get('editor', '')), qr{/pub/$private/rss\.xml}, '編集者の画面のRSSのURLも変わる');

	$r = $app->post('owner', 'set/role', { action => 'set/role', admin_users => 'owner', editors => 'editor', viewers => '', view_pass => 'secret' });
	ok(AppTest::is_reload($r), '表示パスワードを設定する');

	$r = $app->get('guest', '/02');
	is($r->{status}, 403, 'パスワードが無いと記事を見られない');
	unlike(body($r), qr{本文2}, '記事の中身は出ない');

	$app->set_cookie('reader', 'view-pass', 'wrong');
	is($app->get('reader', '/02')->{status}, 403, 'パスワードが違うと見られない');
	$app->set_cookie('reader', 'view-pass', 'secret');
	is($app->get('reader', '/02')->{status}, 200, 'パスワードが合うと見られる');

	$r = $app->post('owner', 'set/role', { action => 'set/role', admin_users => 'owner', editors => 'editor', viewers => '', view_pass => '' });
	ok(AppTest::is_reload($r), '表示パスワードを消す');
	$r = $app->post('owner', 'set/', { action => 'set/index', blog_name => 'テストのブログ', description_txt => 'ブログの説明', private => 0 });
	ok(AppTest::is_reload($r), 'プライベートモードを外す');
	is($app->get('guest', '/02')->{status}, 200, 'ログインしていない人も見られる');
	ok(!glob("$dir/pub/private.*") && -f "$dir/pub/rss.xml" && -f "$dir/pub/attachments/test/a.png", '公開フォルダのファイルが pub/ に戻る');
};

subtest 'タグの削除' => sub {
	# seed() のタグ1（pkey=1）は記事1に付いている
	my $r = $app->post('editor', 'set2/tag_edit', { action => 'set2/tag_edit', del_ary => 1 });
	ok(AppTest::is_reload($r), '削除できる');
	is($app->get('guest', '&t=' . AppTest::_uri_escape('タグ1'))->{status}, 404, 'タグの一覧に記事が出ない');
	like(body($app->get('guest', '&t=' . AppTest::_uri_escape('タグ2'))), qr{ownerの記事}, 'ほかのタグはそのまま');
};

#-------------------------------------------------------------------------------
# 画像アルバム
#-------------------------------------------------------------------------------
subtest '画像アルバム' => sub {
	my $png = do {
		open(my $fh, '<:raw', "$FindBin::Bin/../pub/assets/dist/default-icon.png") || die $!;
		local $/; <$fh>;
	};
	my $img = "$dir/pub/attachments/test";
	require Satsuki::ImageFormat;
	my $ext = Satsuki::ImageFormat::can_write_avif() ? 'avif' : 'jpg';	# 画像のサムネイルの形式

	my $r = $app->post('editor', '', [ action => 'media/upload_form', folder => 'test/', size => 120,
		file_ary => { filename => 'up.png', content => $png, type => 'image/png' } ]);
	like($r->{body}, qr/^ret=0$/m, 'アップロードできる');
	ok(-f "$img/up.png", 'ファイルが置かれる');
	ok(-f "$img/.thumbnail/up.png.$ext", "サムネイルが作られる（$ext）");
	ok($ext eq 'jpg' || !-e "$img/.thumbnail/up.png.jpg", 'JPEGのサムネイルは作らない');

	$r = $app->post('editor', '', { action => 'media/load_image_files', folder => 'test/' });
	my ($up) = grep { $_->{name} eq 'up.png' } @{ ref($r->{json}) eq 'ARRAY' ? $r->{json} : [] };
	is($up && $up->{thumb}, "up.png.$ext", 'ファイルの一覧にサムネイルの名前が入る');

	# 記事のサムネイルは、あるほうの形式を指す
	$r = $app->post('editor', '', { %ART, title => 'サムネイルの記事', body_txt => "[image:S:test/:up.png]\n" });
	ok(AppTest::is_reload($r), 'サムネイルを貼った記事を保存できる');
	like(body($app->get('guest', '')), qr{src="[^"]*/test/\.thumbnail/up\.png\.$ext"}, "記事のサムネイルが .$ext を指す");

	$r = $app->post('editor', '', { action => 'media/rename_file', folder => 'test/', old => 'up.png', name => 'renamed.png' });
	ok(json_ok($r), '名前を変えられる');
	ok(!-e "$img/up.png" && -f "$img/renamed.png", 'ファイルの名前が変わる');
	ok(!-e "$img/.thumbnail/up.png.$ext" && -f "$img/.thumbnail/renamed.png.$ext", 'サムネイルの名前も変わる');

	$r = $app->post('editor', '', { action => 'media/create_folder', folder => '/', name => 'other' });
	ok(json_ok($r), 'フォルダを作れる');
	$r = $app->post('editor', '', { action => 'media/move_files', from => 'test/', to => 'other/', file_ary => 'renamed.png' });
	ok(json_ok($r), '移せる');
	ok(!-e "$img/renamed.png" && -f "$dir/pub/attachments/other/renamed.png", 'ファイルが移る');
	ok(-f "$dir/pub/attachments/other/.thumbnail/renamed.png.$ext", 'サムネイルも移る');

	$r = $app->post('editor', '', { action => 'media/delete_files', folder => 'other/', file_ary => 'renamed.png' });
	ok(json_ok($r), '削除できる');
	ok(!-e "$dir/pub/attachments/other/renamed.png", 'フォルダから消える');
	ok(!-e "$dir/pub/attachments/other/.thumbnail/renamed.png.$ext", 'サムネイルも消える');
};

subtest 'アップロードした画像のメタ情報' => sub {
	require Image::Magick;
	my $im = Image::Magick->new(size => '40x30');
	$im->Read('xc:green');
	my ($jpeg) = $im->ImageToBlob(magick => 'JPEG');
	# Exif（中身が空のIFD）とXMPを足す
	my $exif = "Exif\0\0II*\0" . pack('V', 8) . pack('v', 0) . pack('V', 0);
	my $xmp  = "http://ns.adobe.com/xap/1.0/\0<x:xmpmeta xmlns:x='adobe:ns:meta/'/>";
	my $seg  = sub { "\xFF" . chr($_[0]) . pack('n', length($_[1]) + 2) . $_[1] };
	$jpeg = "\xFF\xD8" . $seg->(0xE1, $exif) . $seg->(0xE1, $xmp) . $seg->(0xE5, 'x' x 100) . substr($jpeg, 2);
	my $img = "$dir/pub/attachments/test";
	my $read = sub { open(my $fh, '<:raw', shift) || return ''; local $/; <$fh> };

	my $r = $app->post('editor', '', [ action => 'media/upload_form', folder => 'test/',
		file_ary => { filename => 'meta.jpg', content => $jpeg, type => 'image/jpeg' } ]);
	like($r->{body}, qr/^ret=0$/m, 'アップロードできる');
	my $saved = $read->("$img/meta.jpg");
	ok(index($saved, 'ns.adobe.com/xap') < 0, 'XMPは消える');
	ok(index($saved, "\xFF\xE5") < 0, 'APP5（機種独自の情報）は消える');
	ok(index($saved, "Exif\0\0") >= 0, 'Exifは残る');

	$r = $app->post('editor', '', [ action => 'media/upload_form', folder => 'test/',
		file_ary => { filename => 'meta.jpg', content => $jpeg, type => 'image/jpeg' } ]);
	like($r->{body}, qr/^ret=0$/m, '同じ画像をもう一度アップロードできる');
	ok(!grep({ /meta_\d/ } map { s|.*/||r } glob("$img/meta*")), 'メタ情報を消した後の中身で比べるので、別名で保存しない');

	$r = $app->post('editor', '', [ action => 'media/upload_form', folder => 'test/', del_exif => 1,
		file_ary => { filename => 'noexif.jpg', content => $jpeg, type => 'image/jpeg' } ]);
	like($r->{body}, qr/^ret=0$/m, 'Exifの削除を選んでアップロードできる');
	ok(index($read->("$img/noexif.jpg"), "Exif\0\0") < 0, 'Exifも消える');
};

subtest '動画のサムネイルの大きさの上限' => sub {
	require Image::Magick;
	require Satsuki::ImageFormat;
	# ブラウザーは動画の1コマをPNGで送る
	my $image = sub {
		my ($w, $h, $format) = @_;
		my $img = Image::Magick->new(size => "${w}x$h");
		$img->Read('xc:gray');
		return $img->ImageToBlob(magick => $format || 'png');
	};
	my $post_data = sub {
		return $app->post('editor', '', [ action => 'media/upload_video_thumbnail', folder => $AppTest::IMAGE_FOLDER, file => $AppTest::VIDEO_FILE,
			poster => { filename => 'poster.png', content => shift, type => 'image/png' } ]);
	};
	my $post = sub { return $post_data->( $image->(@_) ) };
	# 画像のサムネイルと同じく、AVIFを書けるならAVIF、書けなければJPEG
	my ($ext, $format) = Satsuki::ImageFormat::can_write_avif() ? ('avif', 'avif') : ('jpg', 'jpeg');
	my $th     = "$dir/pub/attachments/$AppTest::IMAGE_FOLDER.thumbnail/$AppTest::VIDEO_FILE";
	my $poster = "$th.poster.$ext";
	my $thumb  = "$th.$ext";

	ok(!json_ok($post->(961, 540)), '961pxなら受け付けない');
	ok(!-e $poster, '受け付けなければ、記事用のサムネイルは置かれない');
	ok(json_ok($post->(960, 540)), '960pxなら受け付ける');
	is(Satsuki::ImageFormat::detect($poster), $format, "記事用のサムネイルは、サーバーで画像のサムネイルと同じ形式（$format）にする");
	is(join('x', Satsuki::ImageFormat::get_size($poster)), '960x540', '記事用のサムネイルの大きさ');
	is(Satsuki::ImageFormat::detect($thumb), $format, '一覧用のサムネイルも同じ形式');
	is(join('x', Satsuki::ImageFormat::get_size($thumb)), '320x180', '一覧用のサムネイルは、設定の大きさに縮めて作る');
	ok(!glob("$th.*tmp") && !glob("$th.*new*"), '作業用のファイルが残らない');
	ok($ext eq 'jpg' || (!-e "$th.poster.jpg" && !-e "$th.jpg"), 'JPEGのサムネイルは残らない');

	# 記事には、記事用のサムネイルを出す
	my $r = $app->post('editor', '', { %ART, title => '動画の記事', body_txt => "[file:mp4:$AppTest::IMAGE_FOLDER:$AppTest::VIDEO_FILE]\n" });
	ok(AppTest::is_reload($r), '動画を貼った記事を保存できる');
	like(body($app->get('guest', '')), qr{class="video-thumb"[^>]*><img [^>]*src="[^"]*\.thumbnail/\Q$AppTest::VIDEO_FILE\E\.poster\.$ext"}, "記事のサムネイルが .poster.$ext を指す");
	ok(!json_ok($post->(540, 961)), '縦長でも、長い辺が961pxなら受け付けない');
	ok(!json_ok($post->(960, 540, 'jpeg')), 'JPEGは受け付けない（PNGだけ）');
	ok(!json_ok($post_data->('not an image')), '画像でなければ受け付けない');
	is(join('x', Satsuki::ImageFormat::get_size($poster)), '960x540', '受け付けなければ、前の記事用のサムネイルが残る');

	# アップデートの画面で作る動画の一覧
	my $listed = sub { return index(body($app->get('admin', 'system/update')), "data-name=\"$AppTest::VIDEO_FILE\"") >= 0; };
	ok(!$listed->(), '今の大きさのサムネイルがあれば、アップデートの画面の一覧に出ない');
	open(my $fh, '>:raw', $poster) || die "$poster: $!";
	print $fh $image->(1280, 720, 'jpeg');
	close($fh);
	ok($listed->(), '4.18より前の大きさ（1280px）のサムネイルなら、一覧に出る');
	unlink($poster);
	ok($listed->(), 'サムネイルが無ければ、一覧に出る');
	ok(json_ok($post->(960, 540)), '作り直せる');
	ok(!$listed->(), '作り直すと、一覧から消える');

	# v4.19のアップデート処理より前に作った記事用のサムネイル（ブラウザーが作ったJPEG）
	my $sys = "$dir/data/system_config.dat";
	my $time = time();
	open($fh, '>>', $sys) || die "$sys: $!";
	print $fh "video_poster_time=$time\n";
	close($fh);
	utime($time - 60, $time - 60, $poster);
	ok($listed->(), 'アップデート処理より前に作ったサムネイルなら、一覧に出る');
	ok(json_ok($post->(960, 540)), '作り直せる');
	ok(!$listed->(), '作り直すと、一覧から消える');

	# AVIFを書けるサーバーで、記事用のサムネイルがJPEG（4.25より前に作ったもの）
	SKIP: {
		skip('ImageMagickでAVIFを書けない', 4) if $ext ne 'avif';
		unlink($poster, $thumb);
		open($fh, '>:raw', "$th.poster.jpg") || die "$th.poster.jpg: $!";
		print $fh $image->(960, 540, 'jpeg');
		close($fh);
		ok($listed->(), '記事用のサムネイルがJPEGなら、一覧に出る');
		ok(json_ok($post->(960, 540)), '作り直せる');
		ok(-e $poster && !-e "$th.poster.jpg", '作り直すと、AVIFになり、JPEGは消える');
		ok(!$listed->(), '作り直すと、一覧から消える');
	}

	# 名前の変更、移動、削除で、記事用のサムネイルもついて行く
	my $tdir = "$dir/pub/attachments/$AppTest::IMAGE_FOLDER.thumbnail";
	$r = $app->post('editor', '', { action => 'media/rename_file', folder => $AppTest::IMAGE_FOLDER, old => $AppTest::VIDEO_FILE, name => 'v2.mp4' });
	ok(json_ok($r), '動画の名前を変えられる');
	ok(-e "$tdir/v2.mp4.poster.$ext" && -e "$tdir/v2.mp4.$ext" && !-e $poster, 'サムネイルの名前も変わる');
	$r = $app->post('editor', '', { action => 'media/move_files', from => $AppTest::IMAGE_FOLDER, to => 'other/', file_ary => 'v2.mp4' });
	ok(json_ok($r), '動画を移せる');
	ok(-e "$dir/pub/attachments/other/.thumbnail/v2.mp4.poster.$ext" && !-e "$tdir/v2.mp4.poster.$ext", '記事用のサムネイルも移る');
	$r = $app->post('editor', '', { action => 'media/delete_files', folder => 'other/', file_ary => 'v2.mp4' });
	ok(json_ok($r), '動画を削除できる');
	ok(!glob("$dir/pub/attachments/other/.thumbnail/v2.mp4.*"), 'サムネイルも消える');
};

done_testing();
