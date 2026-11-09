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
	my $r = $app->post('admin', 'set/', { action => 'set/index', blog_name => 'テストのブログ', description_txt => 'ブログの説明' });
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

	# ブラウザーや、User-AgentにMozilla/を含むクローラーにも出す
	local $app->{env} = { HTTP_USER_AGENT => 'Mozilla/5.0 (compatible; Googlebot/2.1; +http://www.google.com/bot.html)' };
	foreach my $q ('', $art) {
		my $b = body($app->get('guest', $q));
		like($b, qr{<meta name="description" content="[^"]+">}, "?$q はUser-Agentによらずdescriptionを出す");
		like($b, qr{<meta property="og:type" content="[^"]+">}, "?$q はUser-AgentによらずOGPを出す");
		like($b, qr{<meta name="twitter:card" content="[^"]+">}, "?$q はUser-AgentによらずTwitter Cardを出す");
	}
};

subtest 'OGPの言語、カードの種類、版の表示' => sub {
	my $b = body($app->get('guest', ''));
	like($b, qr{<meta property="og:locale" content="ja_JP">}, 'og:localeを出す');
	like($b, qr{<meta name="generator" content="[^"]* \d+\.\d{2}">}, 'generatorの版は小数2桁（4.30が4.3にならない）');
	like($b, qr{</a> v\d+\.\d{2} }, 'フッターの版は小数2桁');

	# ブログの画像を設定していないページは、既定のアイコン（正方形）なので小さいカード
	like($b, qr{<meta property="og:image" content="[^"]*/default-icon\.png">}, 'og:imageは既定のアイコン');
	like($b, qr{<meta name="twitter:card" content="summary">}, '既定のアイコンのtwitter:cardはsummary');

	# ブログの画像（バナーを想定）は大きいカード
	my $setting = "$dir/data/blog/setting.dat";
	my $org = read_file($setting);
	my $write = sub {
		open(my $fh, '>:utf8', $setting) || die "$setting: $!";
		print $fh shift;
		close($fh);
	};
	$write->($org . "blog_image=pub/attachments/\@system/sys-blog_image.png\n");
	$b = body($app->get('guest', ''));
	like($b, qr{<meta property="og:image" content="[^"]*/sys-blog_image\.png">}, 'og:imageはブログの画像');
	like($b, qr{<meta name="twitter:card" content="summary_large_image">}, 'ブログの画像のtwitter:cardはsummary_large_image');
	$write->($org);
};

subtest 'RSSのチャンネルの画像' => sub {
	my $setting = "$dir/data/blog/setting.dat";
	my $org = read_file($setting);
	my $file = sub {
		open(my $fh, '<:raw', "$FindBin::Bin/../pub/assets/dist/" . shift) || die $!;
		local $/; <$fh>;
	};
	my $big   = $file->('default-icon.png');	# 192x192（RSSの上限の幅144を超える）
	my $small = $file->('rss-icon.png');		# 80x15
	my $image = sub { (read_file("$dir/pub/rss.xml") =~ m{<image>(.*?)</image>}s)[0] // '' };
	my %base  = (action => 'set/index', blog_name => 'テストのブログ', description_txt => 'ブログの説明');

	my $r = $app->post('admin', 'set/', [ %base, iconfile => { filename => 'icon.png', content => $small, type => 'image/png' } ]);
	ok(AppTest::is_reload($r), 'サイトアイコンを上げられる');
	my $img = $image->();
	like($img, qr{<url>[^<]*/sys-iconfile\.png</url>}, 'ブログの画像がなければ、サイトアイコンを使う');
	like($img, qr{<width>80</width>\s*<height>15</height>}, '上限以内なので幅と高さを書く');

	$r = $app->post('admin', 'set/detail', [ action => 'set/detail', blog_image => { filename => 'banner.bmp', content => $big, type => 'image/bmp' } ]);
	ok(!AppTest::is_reload($r), 'ブログの画像にPNG・JPEG・GIF以外は上げられない');
	unlike(read_file($setting), qr/^blog_image=/m, '設定に入らない');

	$r = $app->post('admin', 'set/detail', [ action => 'set/detail', blog_image => { filename => 'banner.png', content => $big, type => 'image/png' } ]);
	ok(AppTest::is_reload($r), 'ブログの画像を上げられる');
	like(read_file($setting), qr/^blog_image_w=192$/m, '幅を設定に保存する');
	like(read_file($setting), qr/^blog_image_h=192$/m, '高さを設定に保存する');
	$img = $image->();
	like($img, qr{<url>[^<]*/sys-blog_image\.png</url>}, 'ブログの画像を使う');
	unlike($img, qr{<width>|<height>}, '上限を超えるので幅と高さを書かない');
	like(body($app->get('guest', '')), qr{<meta name="twitter:card" content="summary_large_image">}, 'twitter:cardはsummary_large_image');

	$r = $app->post('admin', 'set/detail', { action => 'set/detail', blog_image_void => 1 });
	ok(AppTest::is_reload($r), 'ブログの画像を消せる');
	unlike(read_file($setting), qr/^blog_image_[wh]=./m, '幅と高さも消える');
	like($image->(), qr{<url>[^<]*/sys-iconfile\.png</url>}, 'サイトアイコンに戻る');

	$r = $app->post('admin', 'set/', { %base, iconfile_void => 1 });
	ok(AppTest::is_reload($r), 'サイトアイコンを消せる');
	$img = $image->();
	like($img, qr{<url>[^<]*/default-icon\.png</url>}, '既定のアイコンに戻る');
	unlike($img, qr{<width>|<height>}, '大きさが分からないので幅と高さを書かない');

	open(my $fh, '>:utf8', $setting) || die "$setting: $!";
	print $fh $org;
	close($fh);
};

subtest 'コメントできる人' => sub {
	my $r = $app->post('admin', 'set/detail', { action => 'set/detail', allow_com_users => '' });
	ok(AppTest::is_reload($r), '管理者のみにする');
	like(body($app->get('admin', '/01')), qr/id="comment-form"/, '管理者にはコメント欄が出る');
	unlike(body($app->get('guest', '/01')), qr/id="comment-form"/, 'ログインしていない人には出ない');
	$r = $app->post('admin', 'set/detail', { action => 'set/detail', allow_com_users => '*' });
	ok(AppTest::is_reload($r), '誰でもにする');
	like(body($app->get('guest', '/01')), qr/id="comment-form"/, 'ログインしていない人にも出る');
};

subtest 'プライベートモードの削除' => sub {
	# 古い画面からPOSTされても、設定に入らず、閉じない
	my $setting = "$dir/data/blog/setting.dat";
	my $r = $app->post('admin', 'set/', { action => 'set/index', blog_name => 'テストのブログ', description_txt => 'ブログの説明', private => 1 });
	ok(AppTest::is_reload($r), '基本設定を保存できる');
	unlike(read_file($setting), qr/^(?:private=1|viewers=|view_pass=)/m, 'プライベートモード、閲覧者、表示パスワードは設定に入らない');
	is($app->get('guest', '/02')->{status}, 200, 'ログインしていない人も記事を見られる');
	is($app->get('guest', '/99999')->{status}, 404, '無い記事は404');
	foreach my $q ('set/', 'set/editor') {
		unlike(body($app->get('admin', $q)), qr/プライベートモード|name="(?:private|viewers|view_pass)"/, "?$q に設定の欄が出ない");
	}
};

subtest 'ブログの自動作成' => sub {
	# 空のデータを初めて開く
	my $fresh = AppTest->new();
	my $r = $fresh->get('guest', '');
	is($r->{status}, 302, '管理者がいなければ、トップは開けない');
	like($r->{headers}->{location} // '', qr{\?setup$}, '初期セットアップの画面へ送る');
	ok(-e "$fresh->{dir}/data/db/art", 'テーブルができる');
	ok(-e "$fresh->{dir}/data/db/link", '最後のテーブルまでできる');
	ok(-e "$fresh->{dir}/data/blog/design.dat", '標準のデザインが入る');
	ok(!-e "$fresh->{dir}/data/blog_create.lock", 'ロックのファイルは残らない');
	is($fresh->get('guest', 'setup')->{status}, 200, '初期セットアップの画面は開ける');

	$fresh->setup_admin('admin');
	is($fresh->get('guest', '')->{status}, 200, '管理者を作ると、トップが出る');
	is($fresh->get('guest', '/02')->{status}, 404, '無い記事は404');
	is($fresh->get('admin', 'set/')->{status}, 200, 'そのまま設定を開ける');

	# 同時に開いても壊れない
	my $race = AppTest->new();
	my @pid;
	foreach (1..4) {
		my $pid = fork();
		die if (!defined $pid);
		if (!$pid) { my $res = $race->get('guest', 'setup'); require POSIX; POSIX::_exit($res->{status} == 200 ? 0 : 1); }
		push(@pid, $pid);
	}
	my $fail = 0;
	foreach (@pid) { waitpid($_, 0); $fail++ if ($?); }
	is($fail, 0, '同時に開いても、すべて200');
	is($race->get('guest', 'setup')->{status}, 200, 'その後も開ける');
	ok(-e "$race->{dir}/data/blog/design.dat", '標準のデザインが入る');

	# 一部だけ残っているときは、作らず、消さない
	my $part = AppTest->new()->setup()->seed();
	system('rm', '-rf', "$part->{dir}/data/db/art") == 0 || die;
	$r = $part->get('guest', '');
	is($r->{status}, 503, 'artだけが無いと503');
	like(body($r), qr{ブログのデータを読めない}, '読めないことを知らせる');
	ok(!-e "$part->{dir}/data/db/art", '作らない');
	ok(-e "$part->{dir}/data/db/com/00001.dat", 'ほかのテーブルは消えない');
	ok(-e "$part->{dir}/data/blog/setting.dat", '設定は消えない');
	is($part->get('admin', 'set/')->{status}, 503, '管理者にも503');
	ok(!AppTest::is_reload($part->post('admin', 'set/', { action => 'set/index', blog_name => 'x' })), '操作もできない');

	# 書き込めないとき
	my $ro = AppTest->new();
	mkdir("$ro->{dir}/data/db");
	chmod(0555, "$ro->{dir}/data/db");
	is($ro->get('guest', 'setup')->{status}, 503, '書き込めないと503');
	chmod(0755, "$ro->{dir}/data/db");
	is($ro->get('guest', 'setup')->{status}, 200, '直せば作る');

	# ブログが無いままアップデートが要るとき
	my $old = AppTest->new()->setup();
	system('rm', '-rf', (map { "$old->{dir}/data/db/$_" } qw(art com tag tagart rev lastrev trash trashcom link)), "$old->{dir}/data/blog") == 0 || die;
	my $sys = "$old->{dir}/data/system_config.dat";
	my $conf = read_file($sys);
	$conf =~ s/^VERSION=.*$/VERSION=4.31/m;
	open(my $fh, '>:utf8', $sys) || die;
	print $fh $conf;
	close($fh);
	$r = $old->get('admin', 'menu');
	is($r->{status}, 302, '管理者は、ほかの画面を開けない');
	like($r->{headers}->{location} // '', qr{\?system/update$}, 'アップデート処理の画面へ送る');
	ok(!-e "$old->{dir}/data/db/art", '処理の前には作らない');
	is($old->get('guest', '')->{status}, 503, 'ほかの人にはメンテナンスの画面');
	is($old->get('admin', 'system/update')->{status}, 200, 'アップデート処理の画面は開ける');
	ok(AppTest::is_reload($old->post('admin', 'system/update', { action => 'system/update' })), 'アップデート処理を行える');
	is($old->get('guest', '')->{status}, 200, '処理の後は開ける');
	ok(-e "$old->{dir}/data/db/art", '処理の後に作る');
};

subtest 'メンテナンス中のログイン画面' => sub {
	my $m = AppTest->new()->setup();
	my $sys = "$m->{dir}/data/system_config.dat";
	my $conf = read_file($sys);
	$conf =~ s/^mainte_mode=.*\n//m;
	open(my $fh, '>:utf8', $sys) || die;
	print $fh "mainte_mode=1\n$conf";
	close($fh);

	# プラグインが作ったスケルトンに印を付ける
	my $skel = "$m->{dir}/data/blog/skel/_sub";
	system('mkdir', '-p', $skel) == 0 || die;
	open($fh, '>:utf8', "$m->{dir}/data/blog/skel/login.html") || die;
	print $fh "<\@7>PLUGIN-MARK";
	close($fh);

	my $r = $m->get('guest', '');
	is($r->{status}, 503, 'ログインしていない人にはメンテナンスの画面');
	like(body($r), qr{<a class="admin-bar-login" href="[^"]*\?login">}, '上のバーにログインのリンクを出す');
	$r = $m->get('guest', 'login');
	is($r->{status}, 200, 'ログイン画面は開ける');
	unlike(body($r), qr{admin-bar-login}, 'ログイン画面には、上のバーのログインのリンクを出さない');
	unlike(body($r), qr{PLUGIN-MARK}, 'プラグインが作ったスケルトンを使わない');
	ok($m->post('guest', '', { action => '_ajax_login', adiary_id => 'admin', pass => $AppTest::PASS })->{json}->{ret} eq '0', 'ログインできる');
};

subtest 'タグの削除' => sub {
	# seed() のタグ1（pkey=1）は記事1に付いている
	my $r = $app->post('admin', 'set2/tag_edit', { action => 'set2/tag_edit', del_ary => 1 });
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

	my $r = $app->post('admin', '', [ action => 'media/upload_form', folder => 'test/', size => 120,
		file_ary => { filename => 'up.png', content => $png, type => 'image/png' } ]);
	like($r->{body}, qr/^ret=0$/m, 'アップロードできる');
	ok(-f "$img/up.png", 'ファイルが置かれる');
	ok(-f "$img/.thumbnail/up.png.$ext", "サムネイルが作られる（$ext）");
	ok($ext eq 'jpg' || !-e "$img/.thumbnail/up.png.jpg", 'JPEGのサムネイルは作らない');

	$r = $app->post('admin', '', { action => 'media/load_image_files', folder => 'test/' });
	my ($up) = grep { $_->{name} eq 'up.png' } @{ ref($r->{json}) eq 'ARRAY' ? $r->{json} : [] };
	is($up && $up->{thumb}, "up.png.$ext", 'ファイルの一覧にサムネイルの名前が入る');

	# 記事のサムネイルは、あるほうの形式を指す
	$r = $app->post('admin', '', { %ART, title => 'サムネイルの記事', body_txt => "[image:S:test/:up.png]\n" });
	ok(AppTest::is_reload($r), 'サムネイルを貼った記事を保存できる');
	like(body($app->get('guest', '')), qr{src="[^"]*/test/\.thumbnail/up\.png\.$ext"}, "記事のサムネイルが .$ext を指す");

	$r = $app->post('admin', '', { action => 'media/rename_file', folder => 'test/', old => 'up.png', name => 'renamed.png' });
	ok(json_ok($r), '名前を変えられる');
	ok(!-e "$img/up.png" && -f "$img/renamed.png", 'ファイルの名前が変わる');
	ok(!-e "$img/.thumbnail/up.png.$ext" && -f "$img/.thumbnail/renamed.png.$ext", 'サムネイルの名前も変わる');

	$r = $app->post('admin', '', { action => 'media/create_folder', folder => '/', name => 'other' });
	ok(json_ok($r), 'フォルダを作れる');
	$r = $app->post('admin', '', { action => 'media/move_files', from => 'test/', to => 'other/', file_ary => 'renamed.png' });
	ok(json_ok($r), '移せる');
	ok(!-e "$img/renamed.png" && -f "$dir/pub/attachments/other/renamed.png", 'ファイルが移る');
	ok(-f "$dir/pub/attachments/other/.thumbnail/renamed.png.$ext", 'サムネイルも移る');

	$r = $app->post('admin', '', { action => 'media/delete_files', folder => 'other/', file_ary => 'renamed.png' });
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

	my $r = $app->post('admin', '', [ action => 'media/upload_form', folder => 'test/',
		file_ary => { filename => 'meta.jpg', content => $jpeg, type => 'image/jpeg' } ]);
	like($r->{body}, qr/^ret=0$/m, 'アップロードできる');
	my $saved = $read->("$img/meta.jpg");
	ok(index($saved, 'ns.adobe.com/xap') < 0, 'XMPは消える');
	ok(index($saved, "\xFF\xE5") < 0, 'APP5（機種独自の情報）は消える');
	ok(index($saved, "Exif\0\0") >= 0, 'Exifは残る');

	$r = $app->post('admin', '', [ action => 'media/upload_form', folder => 'test/',
		file_ary => { filename => 'meta.jpg', content => $jpeg, type => 'image/jpeg' } ]);
	like($r->{body}, qr/^ret=0$/m, '同じ画像をもう一度アップロードできる');
	ok(!grep({ /meta_\d/ } map { s|.*/||r } glob("$img/meta*")), 'メタ情報を消した後の中身で比べるので、別名で保存しない');

	$r = $app->post('admin', '', [ action => 'media/upload_form', folder => 'test/', del_exif => 1,
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
		return $app->post('admin', '', [ action => 'media/upload_video_thumbnail', folder => $AppTest::IMAGE_FOLDER, file => $AppTest::VIDEO_FILE,
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
	my $r = $app->post('admin', '', { %ART, title => '動画の記事', body_txt => "[file:mp4:$AppTest::IMAGE_FOLDER:$AppTest::VIDEO_FILE]\n" });
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
	$r = $app->post('admin', '', { action => 'media/rename_file', folder => $AppTest::IMAGE_FOLDER, old => $AppTest::VIDEO_FILE, name => 'v2.mp4' });
	ok(json_ok($r), '動画の名前を変えられる');
	ok(-e "$tdir/v2.mp4.poster.$ext" && -e "$tdir/v2.mp4.$ext" && !-e $poster, 'サムネイルの名前も変わる');
	$r = $app->post('admin', '', { action => 'media/move_files', from => $AppTest::IMAGE_FOLDER, to => 'other/', file_ary => 'v2.mp4' });
	ok(json_ok($r), '動画を移せる');
	ok(-e "$dir/pub/attachments/other/.thumbnail/v2.mp4.poster.$ext" && !-e "$tdir/v2.mp4.poster.$ext", '記事用のサムネイルも移る');
	$r = $app->post('admin', '', { action => 'media/delete_files', folder => 'other/', file_ary => 'v2.mp4' });
	ok(json_ok($r), '動画を削除できる');
	ok(!glob("$dir/pub/attachments/other/.thumbnail/v2.mp4.*"), 'サムネイルも消える');
};

done_testing();
