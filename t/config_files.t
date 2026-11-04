use strict;
use utf8;
#-------------------------------------------------------------------------------
# 設定ファイル（ユーザー設定）のテスト
#-------------------------------------------------------------------------------
# 実行: prove t/config_files.t
#
# ・ユーザー設定が無くても動く
# ・ユーザー設定で、コードの既定値と、初期化より前に要る値を変えられる
# ・4.27までの設定ファイルは、アップデート処理の前は今までどおり動き、処理でユーザー設定へ移る
#
use FindBin;
BEGIN { push(@INC, "$FindBin::Bin/lib", "$FindBin::Bin/../lib"); }
use Test::More;
use AppTest;
use OpsTest;

binmode(Test::More->builder->$_, ':utf8') foreach (qw(output failure_output todo_output));

my $app  = AppTest->new()->setup();
my $dir  = $app->dir;
my $user = "$dir/lyndbaum.user.cgi";
my $conf = "$dir/lyndbaum.conf.cgi";
my $env  = "$dir/lyndbaum.env.cgi";
my $sys  = "$dir/data/system_config.dat";
my $PRAGMA = "<\@20>\n<\@#>\n";

sub write_file {
	my ($file, $text) = @_;
	open(my $fh, '>:utf8', $file) || die "$file: $!";
	print $fh $text;
	close($fh);
}
sub set_version {
	my $t = read_file($sys);
	$t =~ s/^VERSION=.*$/VERSION=$_[0]/m;
	write_file($sys, $t);
}
sub login_ret {
	my ($id, $pass) = @_;
	my $r = $app->post('guest', '', { action => '_ajax_login', adiary_id => $id, pass => $pass });
	return ($r->{json} || {})->{ret};
}
# 続けて2回失敗すると、正しいパスワードでも入れないか
my $lock_no = 0;
sub locked_after_2_fails {
	my $id = 'lock' . ++$lock_no;
	$app->user_add('admin', $id, 0);
	login_ret($id, 'wrong-pass') foreach (1..2);
	return login_ret($id, $AppTest::PASS) ne '0';
}
# 記事の日付（ymdを送らないと、その時の日付になる）
my $art_no = 0;
sub today_ymd {
	my $r = $app->post('admin', '', { action => 'edit', parser => 'markdown', enable => 1, title => 'tz', body_txt => "本文\n" });
	ok(AppTest::is_reload($r), '記事を書く');
	$art_no++;
	return read_file(sprintf("$dir/data/db/art/%05d.dat", $art_no)) =~ /^yyyymmdd=(\d+)$/m ? $1 : undef;
}

#-------------------------------------------------------------------------------
subtest 'ユーザー設定が無くても動く' => sub {
	ok(!-e $user, 'ユーザー設定が無い');
	ok(!-e $conf, '4.27までの設定ファイルも無い');
	is($app->get('guest', '')->{status}, 200, '公開画面が出る');
	is($app->get('admin', 'menu')->{status}, 200, '管理画面が出る（最初の管理者は作ってある）');
	ok(!locked_after_2_fails(), 'コードの既定値（2回の失敗では止めない）で動く');
};

subtest '見本をそのままコピーしても動く' => sub {
	my $sample = read_file("$FindBin::Bin/../lyndbaum.user.cgi.sample");
	unlike($sample, qr/^\s*<\$/m, '見本の項目はどれも止めてある');
	write_file($user, $sample);
	my $r = $app->get('guest', '');
	is($r->{status}, 200, '公開画面が出る');
	is($r->{stderr}, '', 'エラーが出ない');

	# 見本の項目の書き方が正しいかを、行頭の # を外して確かめる（環境が変わるものは除く）
	(my $on = $sample) =~ s/^#(<\$(?!__cache_dir|Basepath|ModRewrite|ServerURL|CookiePath|Temp|Auth\.allow|end|ENV_print|No_redirect|CompilerLog|v\.stop_all_plugins|v\.plugin_symlink|DB\.set_debug))/$1/mg;
	write_file($user, $on);
	$r = $app->get('guest', '');
	is($r->{status}, 200, '項目を有効にしても公開画面が出る');
	is($r->{stderr}, '', '項目を有効にしてもエラーが出ない');
	unlink($user);
};

subtest 'ユーザー設定で値を変えられる' => sub {
	write_file($user, "$PRAGMA<\$Auth.fail_count = 2>\n");
	ok(locked_after_2_fails(), 'Authを作った後に読むので、値を変えられる');

	write_file($user, "$PRAGMA<\$Basepath = '/base/'>\n");
	like(body($app->get('guest', '')), qr{"/base/pub/assets/}, '初期化の前に読むので、Basepathを変えられる');

	write_file($user, "$PRAGMA<\$ServerURL = 'https://example.jp'>\n");
	# 未ログインの人には、管理者のアクセスで保存した値を使う（secure_http_host）ので、管理者で確かめる
	$app->get('admin', 'menu');
	like(read_file($sys), qr{^ServerURL=https://example\.jp$}m, 'ServerURLを変えられる');
	unlink($user);
	$app->get('admin', 'menu');	# 元に戻す

	# 26時間離れたタイムゾーンなら、いつ動かしても日付が変わる
	write_file($user, "$PRAGMA<\$ENV.TZ = 'XXX+12'>\n");
	my $west = today_ymd();
	write_file($user, "$PRAGMA<\$ENV.TZ = 'XXX-14'>\n");
	my $east = today_ymd();
	ok($west && $east && $west ne $east, "ENV.TZで日付が変わる（$west、$east）");

	write_file($user, "$PRAGMA<\$Develop = 1>\n");
	unlike(body($app->get('guest', '')), qr{\[call\]}, 'Developを有効にしても動く');
	unlink($user);
};

#-------------------------------------------------------------------------------
# フォームの制限（set_form_options）
#-------------------------------------------------------------------------------
subtest 'アップロード' => sub {
	mkdir("$dir/pub/attachments");
	my $r = $app->post('editor', '', { action => 'media/create_folder', folder => '/', name => 'test' });
	is(($r->{json} || {})->{ret}, 0, 'アルバムのフォルダを作る');

	my $upload = sub {
		my ($who, $name, $size) = @_;
		$app->post($who, '', [ action => 'media/upload_form', folder => 'test/', size => 120,
			file_ary => { filename => $name, content => 'x' x $size, type => 'text/plain' } ]);
		return -e "$dir/pub/attachments/test/$name";
	};
	ok($upload->('editor', 'small.txt', 2048), 'ログインしていれば、マルチパートで送れる');
	ok(!$upload->('guest', 'guest.txt', 2048), 'ログインしていなければ、マルチパートは受け付けない');

	# 1MBを超えると一時ファイルに書く。一時フォルダの場所はユーザー設定で変えられる
	write_file($user, "$PRAGMA<\$Temp = 'data/tmp2/'>\n");
	ok($upload->('editor', 'big.txt', 1048576 + 1024), '1MBを超えるファイルを送れる');
	is(-s "$dir/pub/attachments/test/big.txt", 1048576 + 1024, '中身が欠けない');
	ok(-d "$dir/data/tmp2", 'ユーザー設定の一時フォルダを使う');

	write_file($user, "$PRAGMA<\$v.uplaod_files_max = 1K>\n");
	ok(!$upload->('editor', 'over.txt', 2048), 'ユーザー設定の上限を超えると受け付けない');
	unlink($user);
	ok($upload->('editor', 'again.txt', 2048), 'ユーザー設定を消すと、既定の上限に戻る');
};

#-------------------------------------------------------------------------------
# 4.27までの設定ファイル。4.27の見本を元に、手で変えた形にする
#-------------------------------------------------------------------------------
my $sample = read_file("$dir/lib/SatsukiApp/lyndbaum_conf_427.txt");
my $old = $sample;
$old =~ s/^<\$v\.uplaod_files_max = 64M>$/<\$v.uplaod_files_max = 256M>/m || die;
$old =~ s/^<\$Auth\.table = '_users'>$/$&\n<\$Auth.fail_count = 2>\n<\$Auth.fail_minute = 30>\n<\$Auth.expires = 90day>\n<\$Auth.allow_ip = begin_array>\n\t# ローカル\n\t127.0.0.1\n<\$end>/m || die;
$old =~ s/^<\$v\.admin_trust_mode = 1>$/#$&/m || die;
$old =~ s/^<\$Auth\.start_up = true>$/#$&/m || die;
$old =~ s/^<\$v\.default_theme = .*$/<\$v.default_theme = 'other\/other'>/m || die;
$old =~ s/^<\$regist_skeleton\('skel\.local\/', 2\)>$/$&\n<\$regist_skeleton('skel.other\/', 3)>/m || die;

subtest 'アップデート処理の前は、今までの設定ファイルで動く' => sub {
	write_file($conf, $old);
	write_file($env, "$PRAGMA<\$Basepath = '/old/'>\n");
	like(body($app->get('guest', '')), qr{"/old/pub/assets/}, 'lyndbaum.env.cgiが効く');
	unlink($env);

	ok(locked_after_2_fails(), 'lyndbaum.conf.cgiが効く');
};

subtest 'ユーザー設定が書けないときは、今までの設定ファイルのまま動く' => sub {
	plan skip_all => 'rootではフォルダの権限で止められない' if ($> == 0);
	set_version('4.27');
	chmod(0555, $dir) || die;
	my $r = $app->post('admin', 'system/update', { action => 'system/update' });
	chmod(0755, $dir) || die;
	ok(AppTest::is_reload($r), 'アップデート処理を行える');
	ok(!-e $user, 'ユーザー設定はできない');
	is(read_file($conf), $old, '今までの設定ファイルは変わらない');
	ok(locked_after_2_fails(), '今までの設定で動き続ける');
};

subtest 'アップデート処理で、ユーザー設定へ移す' => sub {
	write_file("$dir/data/default_setting.dat", "enable=1\n");
	write_file($env, "$PRAGMA# 開発用\n<\$ENV_print = 0>\n");
	set_version('4.27');
	my $done = $app->post('admin', 'system/update', { action => 'system/update' });
	ok(AppTest::is_reload($done), 'アップデート処理を行える');
	like(body($done), qr{Auth\.fail_count = 2}, '画面の範囲の外の値を知らせる');
	like(read_file($sys), qr/^VERSION=4\.29$/m, '版が上がる');

	my $u = read_file($user);
	my $s = read_file($sys);
	like($s, qr/^upload_max_mb=256$/m, '画面で変える項目は、システム設定へ写す（単位を変える）');
	like($s, qr/^fail_minute=30$/m, '画面で変える項目は、システム設定へ写す');
	like($s, qr/^session_days=90$/m, '画面で変える項目は、システム設定へ写す（秒を日にする）');
	unlike($u, qr/uplaod_files_max|fail_minute|Auth\.expires/, 'システム設定へ写した項目は、ユーザー設定に書かない');
	like($u, qr/^<\$Auth\.fail_count = 2>$/m, '画面の範囲の外の値は、ユーザー設定で動かし続ける');
	unlike($s, qr/^fail_count=/m, '画面の範囲の外の値は、システム設定へ写さない');
	like($u, qr/^<\$Auth\.allow_ip = begin_array>\n\t127\.0\.0\.1\n<\$end>$/m, '複数行の設定を写す。中のコメントは写さない');
	like($u, qr/^<\$ENV_print = 0>$/m, 'lyndbaum.env.cgiの設定を写す');
	like($u, qr/^<\$v\.admin_trust_mode = 0>$/m, '止めていたadmin_trust_modeは、止めたままにする');
	like($u, qr/^<\$Auth\.start_up = 0>$/m, '止めていたAuth.start_upは、止めたままにする');
	unlike($u, qr/skel\.other/, '組み立ての行は写さない');
	unlike($u, qr/default_theme/, 'コードに移して変えないことにした項目は写さない');
	unlike($u, qr/loadpm|loadapp|album_jpeg_quality|v\.parsers/, '4.27の見本と同じ行は写さない');

	ok(!-e $conf, '今までの設定ファイルは無くなる');
	ok(!-e $env, '今までのlyndbaum.env.cgiは無くなる');
	is(read_file("$dir/data/lyndbaum.conf.cgi.428.bak"), $old, 'lyndbaum.conf.cgiの控えが残る');
	ok(-e "$dir/data/lyndbaum.env.cgi.428.bak", 'lyndbaum.env.cgiの控えが残る');
	ok(!-e "$dir/data/default_setting.dat", '使っていないdata/default_setting.datが消える');

	# 移したあとも画面が動き、値が効いている
	is($app->get('guest', '')->{status}, 200, '公開画面が出る');
	is($app->get('admin', 'menu')->{status}, 200, '管理画面が出る');
	ok(locked_after_2_fails(), '移した値が効いている');
	my $screen = body($app->get('admin', 'system/setting'));
	like($screen, qr{name="upload_max_mb"[^>]*value="256"}, '写した値が画面に出る');
	like($screen, qr{name="session_days"[^>]*value="90"}, '写した日数が画面に出る');
	unlike($screen, qr{name="fail_count"}, '画面の範囲の外の値は、欄を止めて送らない');
	like($screen, qr{value="2" disabled}, '止めた欄に今の値が出る');
	ok(AppTest::is_reload($app->post('admin', 'system/setting', { action => 'system/setting', mainte_mode => 0, upload_max_mb => 128, fail_minute => 30 })), '欄を止めていても、ほかの項目を保存できる');
	like(read_file($sys), qr/^upload_max_mb=128$/m, 'ほかの項目は保存される');
	unlike(read_file($sys), qr/^fail_count=/m, '止めた欄の値は保存されない');
	ok(locked_after_2_fails(), '止めた欄の項目は、ユーザー設定の値のまま');
};

subtest 'admin_trust_modeとAuth.start_upの行があれば、足さない' => sub {
	unlink($user);
	write_file($conf, $sample);
	set_version('4.27');
	ok(AppTest::is_reload($app->post('admin', 'system/update', { action => 'system/update' })), 'アップデート処理を行える');
	ok(-e $user, 'ユーザー設定ができる');
	unlike(read_file($user), qr/^<\$/m, '4.27の見本と同じなら、中身は無い');
	ok(!-e $conf, '今までの設定ファイルは無くなる');
};

subtest 'ユーザー設定があれば、移行の処理をしない' => sub {
	my $text = "$PRAGMA<\$v.uplaod_files_max = 128M>\n";
	write_file($user, $text);
	set_version('4.27');
	ok(AppTest::is_reload($app->post('admin', 'system/update', { action => 'system/update' })), 'アップデート処理を行える');
	is(read_file($user), $text, 'ユーザー設定は変わらない');
};

done_testing();
