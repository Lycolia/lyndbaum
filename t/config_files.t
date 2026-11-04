use strict;
use utf8;
#-------------------------------------------------------------------------------
# 設定ファイル（ユーザー設定）のテスト
#-------------------------------------------------------------------------------
# 実行: prove t/config_files.t
#
# ・ユーザー設定が無くても動く
# ・ユーザー設定で、コードの既定値と、初期化より前に要る値を変えられる
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
	$app->insert_user($id);
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
	my $r = $app->post('admin', '', { action => 'media/create_folder', folder => '/', name => 'test' });
	is(($r->{json} || {})->{ret}, 0, 'アルバムのフォルダを作る');

	my $upload = sub {
		my ($who, $name, $size) = @_;
		$app->post($who, '', [ action => 'media/upload_form', folder => 'test/', size => 120,
			file_ary => { filename => $name, content => 'x' x $size, type => 'text/plain' } ]);
		return -e "$dir/pub/attachments/test/$name";
	};
	ok($upload->('admin', 'small.txt', 2048), 'ログインしていれば、マルチパートで送れる');
	ok(!$upload->('guest', 'guest.txt', 2048), 'ログインしていなければ、マルチパートは受け付けない');

	# 1MBを超えると一時ファイルに書く。一時フォルダの場所はユーザー設定で変えられる
	write_file($user, "$PRAGMA<\$Temp = 'data/tmp2/'>\n");
	ok($upload->('admin', 'big.txt', 1048576 + 1024), '1MBを超えるファイルを送れる');
	is(-s "$dir/pub/attachments/test/big.txt", 1048576 + 1024, '中身が欠けない');
	ok(-d "$dir/data/tmp2", 'ユーザー設定の一時フォルダを使う');

	write_file($user, "$PRAGMA<\$v.uplaod_files_max = 1K>\n");
	ok(!$upload->('admin', 'over.txt', 2048), 'ユーザー設定の上限を超えると受け付けない');
	unlink($user);
	ok($upload->('admin', 'again.txt', 2048), 'ユーザー設定を消すと、既定の上限に戻る');
};

done_testing();
