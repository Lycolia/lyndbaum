use strict;
use utf8;
#-------------------------------------------------------------------------------
# 主な操作の中身のテスト（ユーザー、パスワード、アップデート処理、システムの設定、ディレクトリ使用量、編集画面の設定、ページ送り）
#-------------------------------------------------------------------------------
# 実行: prove t/operations_user.t
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
require SatsukiApp::adiary;
# アップデート処理の後の版。版を上げるたびに変わるので決め打ちしない
my $DATA_VERSION = $SatsukiApp::adiary::DATA_VERSION;

binmode(Test::More->builder->$_, ':utf8') foreach (qw(output failure_output todo_output));

my $app = AppTest->new()->setup()->seed();
my $dir = $app->dir;

#-------------------------------------------------------------------------------
# ユーザー
#-------------------------------------------------------------------------------
subtest 'ユーザー' => sub {
	$app->insert_user('user');
	$app->login('user');

	my $r = $app->post('user', '', { action => '_ajax_self_change_name', name => '新しい名前' });
	ok(json_ok($r), '自分の名前を変えられる');
	like(body($app->get('user', 'menu')), qr{新しい名前}, '変えた名前が出る');

	$r = $app->post('user', '', { action => '_ajax_self_change_pass', now_pass => 'wrong', pass => 'new-pass-5678', pass2 => 'new-pass-5678' });
	ok(!json_ok($r), '今のパスワードが違うと変えられない');
	$r = $app->post('user', '', { action => '_ajax_self_change_pass', now_pass => $AppTest::PASS, pass => 'new-pass-5678', pass2 => 'new-pass-5678' });
	ok(json_ok($r), 'パスワードを変えられる');
	is($app->get('user', 'menu')->{status}, 403, 'パスワードを変えると、ログインしていたセッションが切れる');

	$r = $app->post('user', '', { action => '_ajax_login', adiary_id => 'user', pass => $AppTest::PASS });
	ok(!json_ok($r), '前のパスワードではログインできない');
	$r = $app->post('user', '', { action => '_ajax_login', adiary_id => 'user', pass => 'new-pass-5678' });
	ok(json_ok($r), '新しいパスワードでログインできる');

	# 管理者がいるときは、ユーザーを作れない
	$r = $app->post('admin', '', AppTest::setup_form('newuser'));
	ok(!json_ok($r), '管理者は初期セットアップでユーザーを作れない');
	$r = $app->post('guest', '', AppTest::setup_form('newuser'));
	ok(!json_ok($r), 'ログインしていない人も作れない');
	is($app->get('admin', 'setup')->{status}, 302, '管理者は初期セットアップの画面を開けない');
	is($app->get('guest', 'setup')->{status}, 302, 'ログインしていない人も開けない');
};

subtest '初期セットアップ' => sub {
	my $fresh = AppTest->new();
	mkdir("$fresh->{dir}/__cache");		# 書き込めないフォルダがあると、画面に入力の欄を出さない
	my $setup = sub { $fresh->post('first', '', AppTest::setup_form('first', @_)) };
	my $to_setup = sub {
		my $r = shift;
		return $r->{status} == 302 && ($r->{headers}->{location} // '') =~ m{\?setup$};
	};

	# セットアップの前は、ほかの画面を開けない
	foreach my $q ('', '/01', 'login', 'menu', 'system/', 'set/', 'edit', 'artlist', 'user/log') {
		ok($to_setup->($fresh->get('guest', $q)), "?$q は初期セットアップの画面へ送る");
	}
	my $b = body($fresh->get('guest', 'setup'));
	like($b, qr{<title>初期セットアップ}, '初期セットアップの画面が出る');
	foreach my $n (qw(adiary_id name pass pass2 blog_name)) {
		like($b, qr{name="$n"}, "$n の欄がある");
	}
	unlike($b, qr{value="（サイトのタイトルを入力）"}, 'サイト名の欄に、初めの値を入れない');
	unlike($b, qr{（サイトのタイトルを入力）}, "上のバーやタブの題にも、初めのサイト名を出さない");
	like($b, qr{<span class="admin-bar-blog">Lyndbaum</span>}, "上のバーにはシステム名を出す");
	unlike($b, qr{id="admin-nav"}, '管理画面のナビは出ない');

	my $before = $fresh->fingerprint();
	ok(!json_ok($fresh->post('guest', '', { action => '_ajax_login', adiary_id => 'first', pass => $AppTest::PASS })), 'ログインの処理は動かない');
	is_deeply([ AppTest::diff_fingerprint($before, $fresh->fingerprint()) ], [], 'ほかの処理では何も変わらない');

	# 入力の誤り
	ok(!json_ok($setup->(blog_name => '')), 'サイト名が空なら作らない');
	ok(!json_ok($setup->(blog_name => 'あ' x 49)), 'サイト名が49文字なら作らない');
	ok(!json_ok($setup->(pass => 'abcdefg', pass2 => 'abcdefg')), 'パスワードが7文字なら作らない');
	ok(!json_ok($setup->(pass2 => 'different-pass')), '確認用のパスワードが違うと作らない');
	ok(!json_ok($setup->(adiary_id => '1abc')), 'IDの先頭が数字なら作らない');
	ok(!json_ok($setup->(name => '')), '名前が空なら作らない');
	my $r = $setup->(blog_name => '', adiary_id => '');
	ok($r->{json} && $r->{json}->{errs} && $r->{json}->{errs}->{blog_name} && $r->{json}->{errs}->{id}, 'サイト名と管理者の誤りをまとめて返す');
	ok($to_setup->($fresh->get('guest', '')), '誤りのときは、セットアップの前のまま');

	# 作る
	$r = $setup->(blog_name => '<b>最初</b>のサイト');
	ok(json_ok($r), '管理者を作れる');
	ok($fresh->{cookie}->{first}->{session}, 'ログインしたCookieが返る');
	is($fresh->get('first', 'menu')->{status}, 200, 'そのままダッシュボードを開ける');
	like(body($fresh->get('guest', '')), qr{<title>&lt;b&gt;最初&lt;/b&gt;のサイト}, 'サイト名が入る（タグはエスケープする）');
	ok(!-e "$fresh->{dir}/data/setup.lock", 'ロックのファイルは残らない');

	# 2回目は作れない
	ok(!json_ok($fresh->post('guest', '', AppTest::setup_form('second'))), '2回目は作れない');
	ok(!json_ok($fresh->post('second', '', { action => '_ajax_login', adiary_id => 'second', pass => $AppTest::PASS })), '2人目はいない');
	is($fresh->get('guest', 'setup')->{status}, 302, 'セットアップの画面はもう開けない');

	# 同時に送っても、作るのは1人だけ
	my $race = AppTest->new();
	$race->get('guest', 'setup');
	my @pid;
	foreach my $n (1..4) {
		my $pid = fork();
		die if (!defined $pid);
		if (!$pid) { my $res = $race->post("u$n", '', AppTest::setup_form("u$n")); require POSIX; POSIX::_exit(json_ok($res) ? 0 : 1); }
		push(@pid, $pid);
	}
	my $ok = 0;
	foreach (@pid) { waitpid($_, 0); $ok++ if (!$?); }
	is($ok, 1, '同時に送っても、作れるのは1回だけ');
	my @users = glob("$race->{dir}/data/db/_users/0*.dat");
	is(scalar(@users), 1, 'ユーザーは1人だけ');
};

subtest 'パスワード' => sub {
	my $pass_of = sub {
		my $id = shift;
		foreach my $file (glob("$dir/data/db/_users/0*.dat")) {
			my $t = read_file($file);
			return $1 if ($t =~ /^id=\Q$id\E$/m && $t =~ /^pass=(.*)$/m);
		}
		return '';
	};
	like($pass_of->('admin'), qr/^\$2b\$12\$[.\/A-Za-z0-9]{53}$/, 'bcryptで保存する');

	$app->insert_user('reset');
	$app->login('reset');
	my $change = sub {
		my ($pass, $pass2) = @_;
		return $app->post('reset', '', { action => '_ajax_self_change_pass', now_pass => $AppTest::PASS, pass => $pass, pass2 => $pass2 // $pass });
	};
	ok(!json_ok($change->('abcdefg')), '7文字では変えられない');
	ok(!json_ok($change->('a' x 73)), '72バイトを超えると変えられない');
	ok(!json_ok($change->('abcdefgh', 'abcdefgx')), '確認用と違うと変えられない');
	ok(json_ok($change->('abcdefgh')), '8文字なら変えられる');
	like($pass_of->('reset'), qr/^\$2b\$/, '変えたパスワードもbcrypt');
	isnt($pass_of->('reset'), $pass_of->('admin'), 'saltは毎回違う');
};

subtest 'ページキャッシュの設定は画面に出ない' => sub {
	unlike(body($app->get('admin', 'system/setting')), qr{html_cache|search_cache}, 'キャッシュの欄が無い');
};

subtest '同時ログイン数' => sub {
	# システム設定の画面のフォームの値に、変えたい値を重ねて保存する
	my $save = sub {
		my %set = @_;
		my $b = body($app->get('admin', 'system/setting'));
		my %form;
		while ($b =~ m{<input\b([^>]*)>}g) {
			my $a = $1;
			my ($name) = $a =~ /\bname="([^"]*)"/ or next;
			my ($type) = $a =~ /\btype="([^"]*)"/;
			my ($val)  = $a =~ /\bvalue="([^"]*)"/;
			next if (($type // '') eq 'checkbox' && $a !~ /\bchecked\b/);
			$form{$name} = $val // '';
		}
		while ($b =~ m{<textarea\b[^>]*\bname="([^"]*)"[^>]*>(.*?)</textarea>}sg) { $form{$1} = $2; }
		return $app->post('admin', 'system/setting', { %form, %set, action => 'system/setting' });
	};
	# 同じユーザーで、別の端末（Cookie）からログインする
	$app->insert_user('multi');
	# ログインの時刻（login_tm）は秒単位なので、どれが古いか分かるよう1秒あける
	my $login = sub {
		my $who = shift;
		sleep(1);
		return json_ok($app->post($who, '', { action => '_ajax_login', adiary_id => 'multi', pass => $AppTest::PASS }));
	};
	my $alive = sub { $app->get(shift, 'menu')->{status} == 200 };

	like(body($app->get('admin', 'system/setting')), qr{name="max_sessions"[^>]*value="1"}, '設定ファイルに書いていなければ1');

	ok(AppTest::is_reload($save->(max_sessions => 2)), '2にできる');
	like(body($app->get('admin', 'system/setting')), qr{name="max_sessions"[^>]*value="2"}, '保存した値が出る');
	ok($login->("multi-$_"), "${_}回目のログイン") foreach (1..3);
	ok(!$alive->('multi-1'), '3回目のログインで、いちばん古いログインが切れる');
	ok($alive->('multi-2') && $alive->('multi-3'), '新しい2つは残る');

	ok(AppTest::is_reload($save->(max_sessions => 1)), '1にできる');
	ok($login->('multi-4'), 'もう一度ログインする');
	ok(!$alive->('multi-2') && !$alive->('multi-3'), '1にすると、前のログインがすべて切れる');
	ok($alive->('multi-4'), '新しいログインは残る');

	foreach (0, 11) {
		ok(!AppTest::is_reload($save->(max_sessions => $_)), "${_}は保存できない");
	}
	like(body($app->get('admin', 'system/setting')), qr{name="max_sessions"[^>]*value="1"}, '保存できなかったときは前の値のまま');
	unlike(body($app->get('guest', '')), qr{メンテナンス}, 'ほかの設定は変わらない');
};

subtest 'アップデートが必要なときの知らせ' => sub {
	# 公開している記事（アップデートが必要なときも、記事のページが404にならないことを確かめる）
	ok(AppTest::is_reload($app->post('admin', '', { %ART, title => 'アップデート待ちの記事', body_txt => "本文\n" })), '記事を書く');
	my ($pkey) = body($app->get('admin', 'artlist')) =~ m{href="[^"]*/0(\d+)\?edit"[^>]*>アップデート待ちの記事<};
	my $art = "/0$pkey";
	is($app->get('admin', $art)->{status}, 200, '書いた記事は見られる');

	my $sys = "$dir/data/system_config.dat";
	my $conf = read_file($sys);
	$conf =~ s/^VERSION=.*$/VERSION=4.42/m;
	open(my $fh, '>:utf8', $sys) || die "$sys: $!";
	print $fh $conf;
	close($fh);

	my $link = qr{href="[^"]*\?system/update"};
	foreach my $p ('menu', 'artlist', 'system/setting') {
		my $b = body($app->get('admin', $p));
		like($b, qr{<article class="system notice require-update">.*?アップデート処理が必要です。.*?$link}s, "管理画面（?$p）に、知らせとアップデート処理の画面へのリンクが出る");
		unlike($b, qr{アップデートが必要です。}, "管理画面（?$p）に、リンクの無いメッセージは出ない");
	}
	unlike(body($app->get('admin', 'system/update')), qr{require-update}, 'アップデート処理の画面には、知らせを出さない');

	foreach my $p ('', $art) {
		my $r = $app->get('admin', $p);
		is($r->{status}, 200, "公開画面（$p）は、システム管理者には200");
		like(body($r), qr{<a class="admin-bar-update" $link}, "公開画面（$p）の管理バーに、アップデート処理の画面へのリンクが出る");
		unlike(body($r), qr{require-update|アップデートが必要です。}, "公開画面（$p）の本文には出さない");
		is($r->{headers}->{'cache-control'}, 'private, no-store', "ログイン中の公開画面（$p）は保存させない");
	}
	is($app->get('admin', 'menu')->{headers}->{'cache-control'}, 'private, no-store', 'ログイン中の管理画面は保存させない');

	foreach my $who ('guest') {
		foreach my $p ('', $art, 'menu') {
			my $r = $app->get($who, $p);
			is($r->{status}, 503, "$who には、?$p はメンテナンスの画面");
			unlike(body($r), qr{system/update}, "$who には、?$p にアップデート処理の画面へのリンクを出さない");
		}
	}
	is($app->get('guest', $art)->{headers}->{'cache-control'}, 'no-cache', 'ログインしていない人の画面は今までどおり');

	ok(AppTest::is_reload($app->post('admin', 'system/update', { action => 'system/update' })), 'アップデート処理を行える');
	unlike(body($app->get('admin', 'menu')), qr{require-update}, 'アップデート処理の後は、管理画面に知らせが出ない');
	unlike(body($app->get('admin', $art)), qr{admin-bar-update}, 'アップデート処理の後は、管理バーにリンクが出ない');
	is($app->get('guest', $art)->{headers}->{'cache-control'}, 'no-cache', 'ログインしていない人の記事は、no-cacheのまま');
};

subtest '4.42より古いデータからのアップデート' => sub {
	my $sys = "$dir/data/system_config.dat";
	my $set_version = sub {
		my $conf = read_file($sys);
		$conf =~ s/^VERSION=.*$/VERSION=$_[0]/m;
		open(my $fh, '>:utf8', $sys) || die "$sys: $!";
		print $fh $conf;
		close($fh);
	};
	my $update = sub { return $app->post('admin', 'system/update', { action => 'system/update' }); };

	$set_version->('4.41');
	my $b = body($app->get('admin', 'system/update'));
	like($b, qr{このデータの版（4\.41）からは、直接アップデートできません}, '画面で知らせる');
	like($b, qr{value="system/update"[^>]*disabled}, 'ボタンを押せない');

	ok(!AppTest::is_reload($update->()), '直接送っても断る');
	like(read_file($sys), qr/^VERSION=4\.41$/m, '版はそのまま');

	$set_version->('4.42');
	{	# 4.43より前の名前で保存したサムネイルの品質。新しい名前の行は消しておく
		my $conf = read_file($sys);
		$conf =~ s/^media_\w+_quality=.*\n?//mg;
		$conf =~ s/\n?\z/\nalbum_jpeg_quality=70\nalbum_avif_quality=50\n/;
		open(my $fh, '>:utf8', $sys) || die "$sys: $!";
		print $fh $conf;
		close($fh);
	}
	# 4.43より前の添付ファイルのフォルダ（pub/attachments/）と、そこを指すパスを書いた記事とサイトの設定
	my $att     = "$dir/pub/attach";
	my $old_att = "$dir/pub/attachments";
	my $img     = "$AppTest::IMAGE_FOLDER$AppTest::IMAGE_FILE";
	ok(AppTest::is_reload($app->post('admin', '', { action => 'edit', parser => 'markdown', enable => 1, ymd => '2026-10-01',
		title => '古い添付ファイルのパス', body_txt => "![](pub/attachments/$img)\n", page => 1, link_key_txt => 'old-attach' })), '古いパスを書いた記事を保存できる');
	rename($att, $old_att) || die "$att: $!";
	my $setting = "$dir/data/blog/setting.dat";
	my $set_org = read_file($setting);
	{
		open(my $fh, '>:utf8', $setting) || die "$setting: $!";
		print $fh $set_org . "blog_image=pub/attachments/\@system/sys-blog_image.png\n";
		close($fh);
	}

	unlike(body($app->get('admin', 'system/update')), qr{直接アップデートできません}, '4.42なら知らせない');
	ok(AppTest::is_reload($update->()), '4.42からはアップデートできる');
	ok(-f "$att/$img" && !-e $old_att, '添付ファイルのフォルダをpub/attach/に移す');
	like(read_file($setting), qr{^blog_image=pub/attach/\@system/sys-blog_image\.png$}m, 'サイトの設定のパスを書き換える');
	{
		my $b = body($app->get('guest', '/old-attach'));
		unlike($b, qr{pub/attachments/}, '記事に古いパスが残らない');
		my ($src) = $b =~ m{<img[^>]*src="[^"]*?(pub/attach/[^"]+)"};
		is($src, "pub/attach/$img", '記事の画像は新しいパスを指す');
		ok(defined $src && -f "$dir/$src", '記事の画像のパスにファイルがある');
		my $art = join('', map { read_file($_) } glob("$dir/data/db/{art,rev,lastrev,trash}/*.dat"));
		unlike($art, qr{pub/attachments/}, 'DBに古いパスが残らない');
	}
	{	# 後のテストのため、サイトの設定を戻す
		open(my $fh, '>:utf8', $setting) || die "$setting: $!";
		print $fh $set_org;
		close($fh);
	}
	my $conf = read_file($sys);
	like($conf, qr/^VERSION=\Q$DATA_VERSION\E$/m, '版が上がる');
	like($conf, qr/^media_jpeg_quality=70$/m, 'JPEGの品質を新しい名前に移す');
	like($conf, qr/^media_avif_quality=50$/m, 'AVIFの品質を新しい名前に移す');
	unlike($conf, qr/^album_/m, '古い名前は消す');
	{	# 後のテストのため、移した行を消して既定値に戻す
		$conf =~ s/^media_\w+_quality=.*\n?//mg;
		open(my $fh, '>:utf8', $sys) || die "$sys: $!";
		print $fh $conf;
		close($fh);
	}
};

#-------------------------------------------------------------------------------
# 画面で変える設定（ログイン、アップロード、画像）
#-------------------------------------------------------------------------------
subtest 'システム設定：ログイン、アップロード、画像' => sub {
	my $sys = "$dir/data/system_config.dat";
	my $form = sub {
		my $b = body($app->get('admin', 'system/setting'));
		my %f = map { $_ => '' } qw(mainte_txt);
		while ($b =~ /<input[^>]*type="number"[^>]*>/g) {
			my $t = $&;
			my ($n) = $t =~ /name="(\w+)"/;
			my ($v) = $t =~ /value="([^"]*)"/;
			if (defined $n) { $f{$n} = $v; }
		}
		return %f;
	};
	my $save = sub {
		my %set = @_;
		return $app->post('admin', 'system/setting', { $form->(), %set, action => 'system/setting' });
	};
	my $field = sub {
		my ($name, $val, $msg) = @_;
		like(body($app->get('admin', 'system/setting')), qr{name="$name"[^>]*value="$val"}, $msg);
	};

	$field->('pass_min', 8, 'パスワードの最低文字数は、何も保存していなければ既定値');
	$field->('session_days', 14, 'ログインの保持日数は、何も保存していなければ既定値');
	$field->('fail_count_ip', 15, '同じIPからの失敗の回数は、何も保存していなければ既定値');
	$field->('fail_count', 100, 'アカウントの失敗の回数は、何も保存していなければ既定値');
	$field->('upload_max_mb', 64, 'アップロードの上限は、何も保存していなければ既定値');
	$field->('post_max_mb', 8, '投稿の上限は、何も保存していなければ既定値');
	$field->('media_avif_quality', 65, 'AVIFの品質は、何も保存していなければ既定値');

	# 範囲の外は保存できない（ほかの欄は今の値のまま送る。前のテストの保存で、今の値が入っていることがある）
	$app->insert_user('syslock');
	$app->insert_user('passmin');
	$app->login('passmin');
	# 書き戻すと行の順番が変わるので、この項目の行だけを比べる
	my $saved = sub { join("\n", sort grep { /^(?:pass_min|session_days|all_logout|fail_count_ip|fail_count|fail_minute|upload_max_mb|post_max_mb|media_jpeg_quality|media_avif_quality)=/ } split(/\n/, read_file($sys))) };
	my $before = $saved->();
	foreach my $bad ([pass_min => 7], [pass_min => 65], [session_days => 0], [session_days => 366],
		[fail_count_ip => 0], [fail_count_ip => 2], [fail_count_ip => 101],
		[fail_count => 0], [fail_count => 2], [fail_count => 101], [fail_minute => 0], [fail_minute => 1441],
		[upload_max_mb => 0], [upload_max_mb => 2049], [post_max_mb => 0], [post_max_mb => 65], [media_jpeg_quality => 0], [media_avif_quality => 101]) {
		ok(!AppTest::is_reload($save->(@$bad)), "$bad->[0]=$bad->[1] は保存できない");
	}
	$field->('pass_min', 8, '保存できなかったときは前の値のまま');
	is($saved->(), $before, '保存できなかったときは、ファイルを変えない');

	# 管理者以外は保存できない
	$app->post('guest', 'system/setting', { action => 'system/setting', pass_min => 20 });
	is($saved->(), $before, '管理者でなければ保存できない');

	# 値が効く
	ok(AppTest::is_reload($save->(pass_min => 20, fail_count_ip => 4, fail_count => 3, fail_minute => 5, upload_max_mb => 1, post_max_mb => 1, media_avif_quality => 40, session_days => 30, all_logout => 1)), '保存できる');
	$field->('pass_min', 20, '保存した値が欄に出る');
	like(read_file($sys), qr/^session_days=30$/m, '保存した値がファイルに入る');
	like(body($app->get('admin', 'system/setting')), qr{name="all_logout"[^>]*checked}, 'ONにした項目が欄に出る');

	# パスワードの最低文字数は、新しいパスワードに効く
	my $change = sub {
		my $pass = shift;
		return ($app->post('passmin', '', { action => '_ajax_self_change_pass', now_pass => $AppTest::PASS, pass => $pass, pass2 => $pass })->{json} || {})->{ret};
	};
	isnt($change->('abcdefgh1'), '0', '最低文字数より短いパスワードには変えられない');
	is($change->('abcdefgh1abcdefgh1ab'), '0', '最低文字数を満たせば、変えられる');

	# ログインの失敗の回数
	my $try = sub { ($app->post('guest', '', { action => '_ajax_login', adiary_id => 'syslock', pass => shift })->{json} || {})->{ret} };
	{
		local $app->{env} = { REMOTE_ADDR => '10.1.0.1' };
		$try->('wrong-pass') foreach (1..3);
		isnt($try->($AppTest::PASS), '0', '保存した回数（3回）で、正しいパスワードでも止まる');
	}

	# 同じIPからの失敗の回数
	$app->insert_user('sysip');
	my $try_ip = sub {
		my ($ip, $id, $pass) = @_;
		local $app->{env} = { REMOTE_ADDR => $ip };
		return ($app->post('guest', '', { action => '_ajax_login', adiary_id => $id, pass => $pass })->{json} || {})->{ret};
	};
	$field->('fail_count_ip', 4, '保存した値が欄に出る（同じIP）');
	$try_ip->('10.1.0.2', 'no-such-user', 'wrong-pass') foreach (1..4);
	isnt($try_ip->('10.1.0.2', 'sysip', $AppTest::PASS), '0', '保存した回数（4回）で、そのIPからは正しいパスワードでも止まる');
	is($try_ip->('10.1.0.3', 'sysip', $AppTest::PASS), '0', 'ほかのIPからは入れる');

	# アップロードの上限
	my $r = $app->post('admin', '', [ action => 'media/upload_form', folder => 'test/', size => 120,
		file_ary => { filename => 'sysmax.txt', content => 'x' x (1048576 + 1024), type => 'text/plain' } ]);
	ok(!-e "$dir/pub/attach/test/sysmax.txt", '保存した上限（1MB）を超えると受け付けない');

	# 投稿の上限（URLエンコードした後の大きさ。日本語は1文字9バイト）
	my %art = (action => 'edit', parser => 'markdown', enable => 1, ymd => '2026-10-01');
	ok(!AppTest::is_reload($app->post('admin', '', { %art, title => '上限を超える記事', body_txt => 'あ' x 120000 })), '保存した投稿の上限（1MB）を超えると保存しない');
	ok(AppTest::is_reload($app->post('admin', '', { %art, title => '上限の内の記事', body_txt => 'あ' x 100000 })), '投稿の上限（1MB）の内なら保存できる');

	# 空にすると既定値に戻す
	ok(AppTest::is_reload($save->(pass_min => '', fail_count_ip => '', fail_count => '', fail_minute => '', upload_max_mb => '', post_max_mb => '', media_avif_quality => '', session_days => '', all_logout => 0)), '空で保存できる');
	$field->('pass_min', 8, '空にすると既定値に戻る');
	$field->('upload_max_mb', 64, '空にすると既定値に戻る（上限）');
	$field->('post_max_mb', 8, '空にすると既定値に戻る（投稿の上限）');
	$field->('fail_count_ip', 15, '空にすると既定値に戻る（同じIP）');
	unlike(body($app->get('admin', 'system/setting')), qr{name="all_logout"[^>]*checked}, 'OFFにできる');
};

#-------------------------------------------------------------------------------
# 標準記法で書いた古い記事
#-------------------------------------------------------------------------------
subtest '標準記法の記事' => sub {
	my $write = sub {
		my ($file, $text) = @_;
		open(my $fh, '>:utf8', $file) || die "$file: $!";
		print $fh $text;
		close($fh);
	};

	my $b = body($app->get('admin', 'edit'));
	unlike($b, qr{<option value="default}, '記事の作成画面で、標準記法を選べない');
	unlike($b, qr{この記事の記法（}, '新しい記事では、選べない記法の知らせを出さない');

	# 標準記法で書いた古い記事は、黙ってMarkdownに変わらないように知らせる
	ok(AppTest::is_reload($app->post('admin', '', { %ART, title => '標準記法の記事', body_txt => "本文\n" })), '記事を書く');
	my ($pkey) = body($app->get('admin', 'artlist')) =~ m{href="[^"]*/0(\d+)\?edit"[^>]*>標準記法の記事<};
	my $af = sprintf("$dir/data/db/art/%05d.dat", $pkey);
	my $a = read_file($af);
	ok($a =~ s/^parser=.*$/parser=default/m, '記事の記法を標準記法にする');
	$write->($af, $a);
	like(body($app->get('admin', "/0$pkey?edit")), qr{この記事の記法（default）は選べません。}, '標準記法の記事の編集画面に、知らせを出す');
};

subtest '同時編集の確認の残りを消すアップデート（4.43）' => sub {
	my $sys  = "$dir/data/system_config.dat";
	my $lock = "$dir/data/blog/lock";
	my $update = sub {	# 4.42のデータにして、アップデート処理を行う
		my $add = shift // '';
		my $conf = read_file($sys);
		$conf =~ s/^VERSION=.*$/VERSION=4.42/m;
		open(my $fh, '>:utf8', $sys) || die "$sys: $!";
		print $fh $conf . $add;
		close($fh);
		return $app->post('admin', 'system/update', { action => 'system/update' });
	};

	my $snap = $app->snapshot();
	mkdir($lock) || die "$lock: $!";
	open(my $fh, '>', "$lock/1") || die "$lock/1: $!";
	print $fh "admin\t2026/11/13 10:00:00\t1700000000\n";
	close($fh);
	my $setting = "$dir/data/blog/setting.dat";
	open($fh, '>>:utf8', $setting) || die "$setting: $!";
	print $fh "suggest_link_key=1\n";
	close($fh);
	ok(AppTest::is_reload($update->("edit_lock_interval=30\n")), 'アップデート処理を行える');
	like(read_file($sys), qr/^VERSION=\Q$DATA_VERSION\E$/m, '版が上がる');
	unlike(read_file($sys), qr/^edit_lock_interval=/m, 'システム設定の間隔を消す');
	ok(!-e $lock, 'サイトのlock/を消す');
	unlike(read_file($setting), qr/^suggest_link_key=/m, '消した設定suggest_link_keyをサイトの設定から消す');
	$app->restore($snap);

	$snap = $app->snapshot();
	ok(!-e $lock, '作った状態の確認：lock/が無い');
	ok(AppTest::is_reload($update->()), 'lock/も間隔も無いときも、アップデート処理を行える');
	like(read_file($sys), qr/^VERSION=\Q$DATA_VERSION\E$/m, '版が上がる');
	$app->restore($snap);
};

subtest '見出しの段を上げるアップデート（4.45）' => sub {
	my $sys  = "$dir/data/system_config.dat";
	my $snap = $app->snapshot();
	my $edit = sub {	# ファイルの中身を書き換える
		my ($file, $func) = @_;
		local $_ = read_file($file);
		my $n = $func->();
		open(my $fh, '>:utf8', $file) || die "$file: $!";
		print $fh $_;
		close($fh);
		return $n;
	};

	ok(AppTest::is_reload($app->post('admin', '', { %ART, title => '見出しの段の記事', body_txt => "# 大見出し\n\n本文\n\n## 小見出し\n" })), '見出しのある記事を書く');
	my ($key) = body($app->get('admin', '')) =~ m{/(\d+)"[^>]*>見出しの段の記事<};
	ok($key, '記事のURL');
	my $h2 = qr{<h2 id="[^"]+"><a [^>]*>大見出し</a></h2>};
	my $h3 = qr{<h3 id="[^"]+"><a [^>]*>小見出し</a></h3>};
	my $title = qr{<h1[^>]*>(?:(?!</h1>).)*見出しの段の記事}s;
	my $b = body($app->get('guest', "/$key"));
	like($b, $h2, '新しく書いた記事は、本文の見出しがh2から始まる');
	like($b, $h3, '次の段はh3');
	like($b, $title, '記事のタイトルはh1');
	unlike($b, qr{<h1[^>]*id="page-title"}, 'サイトのタイトルはh1にしない');
	like($b, qr{<div id="page-title" class="site-title"}, 'サイトのタイトルはdiv');

	# デザインの編集画面と同じく、保存する場所（save_ary）を送らずに保存すると、_articleと_mainも作る
	ok(AppTest::is_reload($app->post('admin', 'design/edit', [ action => 'design/edit',
		header_ary => 'deh_login', header_ary => 'deh_title', art_h_ary => 'dea_art-info', side_a_ary => 'des_searchbox' ])), 'デザインを保存する');
	my @skel = grep { -f $_ } glob("$dir/data/blog/{skel,skel_theme/*}/{_article,_main}.html");
	is(scalar(@skel), 4, '保存したデザインのスケルトン（標準とlyndbaumの_article、_main）がある');
	like(body($app->get('guest', "/$key")), $title, '保存したデザインでも、記事のタイトルはh1');

	# 4.44までの形にする。DBの本文はh3から、保存したデザインのスケルトンは記事のタイトルがh2
	my $af = sprintf("$dir/data/db/art/%05d.dat", int($key));
	ok($edit->($af, sub { s{<(/?)h([23])\b}{"<$1h" . ($2+1)}ge }), '本文の見出しをh3からにする');
	foreach my $f (@skel) {
		ok($edit->($f, sub { s{<(/?)h1\b}{<$1h2}g }), '記事のタイトルをh2にする');
	}
	$b = body($app->get('guest', "/$key"));
	like($b, qr{<h3 id="[^"]+"><a [^>]*>大見出し</a></h3>}, '作った状態の確認：本文の見出しがh3から');
	unlike($b, $title, '作った状態の確認：記事のタイトルがh1でない');
	unlike(body($app->get('guest', '/')), $title, '作った状態の確認：一覧でも記事のタイトルがh1でない');

	$edit->($sys, sub { s/^VERSION=.*$/VERSION=4.44/m });
	ok(AppTest::is_reload($app->post('admin', 'system/update', { action => 'system/update' })), 'アップデート処理を行える');
	like(read_file($sys), qr/^VERSION=\Q$DATA_VERSION\E$/m, '版が上がる');

	$b = body($app->get('guest', "/$key"));
	like($b, $h2, '記事を作り直して、本文の見出しがh2からになる');
	like($b, $h3, '次の段はh3になる');
	like($b, $title, 'デザインを作り直して、記事のタイトルがh1になる');
	like(body($app->get('guest', '/')), $title, '一覧でも記事のタイトルがh1になる');
	$app->restore($snap);
};

subtest 'サイドバーのクラスからhatenaを外すアップデート（4.45）' => sub {
	my $sys  = "$dir/data/system_config.dat";
	my $set  = "$dir/data/blog/setting.dat";
	my $snap = $app->snapshot();
	my $edit = sub {	# ファイルの中身を書き換える
		my ($file, $func) = @_;
		local $_ = read_file($file);
		my $n = $func->();
		open(my $fh, '>:utf8', $file) || die "$file: $!";
		print $fh $_;
		close($fh);
		return $n;
	};
	my $old = qr/hatena-(?:module|section|body)/;
	my @mods = qw(des_freetext des_artlist des_comlist des_monthlist des_taglist des_contents_list des_searchbox);

	ok(AppTest::is_reload($app->post('admin', 'design/edit', [ action => 'design/edit',
		header_ary => 'deh_login', header_ary => 'deh_title', art_h_ary => 'dea_art-info', map { (side_a_ary => $_) } @mods ])), 'サイドバーにモジュールを置く');
	my $r = $app->post('admin', '', { action => 'plugin/plugin_setting', module_name => 'des_freetext', title => 'フリー', class => 'side-module my-box', free_txt => '中身' });
	like($r->{body}, qr/^ret=0$/m, 'フリー入力のクラスを保存できる');
	my $b = body($app->get('guest', '/'));
	like($b, qr{<div id="columns">}, '外枠のidはcolumns');
	like($b, qr{<div class="side-module my-box"[^>]*>\s*<div class="side-module-title">フリー</div>\s*<div class="side-module-body">}, 'フリー入力のモジュールが新しいクラスで出る');
	like($b, qr{<ul class="side-module-list">}, '一覧のモジュールが新しいクラスで出る');
	unlike($b, $old, '古いクラス、idは出ない');

	# 4.44までの形にする。保存したデザインのスケルトン、プラグインの雛形の写し、設定（生成した一覧のHTML、フリー入力のクラス）を古い名前にする
	my @files = grep { -f $_ } ($set, glob("$dir/data/blog/{skel,skel_theme/*}/{*.html,_format/*.html}"));
	my $n = 0;
	foreach my $f (@files) {
		$n += $edit->($f, sub {
			my $c = 0;
			$c += s/side-module-title/hatena-moduletitle/g;
			$c += s/side-module-body/hatena-modulebody/g;
			$c += s/side-module-list/hatena-section/g;
			$c += s/side-module/hatena-module/g;
			return $c;
		});
	}
	cmp_ok($n, '>', 0, '保存したファイルを古い名前にする');
	like(read_file($set), qr/^p:des_freetext(?:,\d+)?:class=hatena-module my-box$/m, '作った状態の確認：フリー入力のクラスが古い名前');
	like(body($app->get('guest', '/')), qr{<div class="hatena-module my-box"}, '作った状態の確認：古いクラスが出る');

	$edit->($sys, sub { s/^VERSION=.*$/VERSION=4.44/m });
	ok(AppTest::is_reload($app->post('admin', 'system/update', { action => 'system/update' })), 'アップデート処理を行える');
	like(read_file($sys), qr/^VERSION=\Q$DATA_VERSION\E$/m, '版が上がる');

	like(read_file($set), qr/^p:des_freetext(?:,\d+)?:class=side-module my-box$/m, 'フリー入力のクラスを新しい名前に移す');
	foreach my $f (grep { -f $_ } ($set, glob("$dir/data/blog/{skel,skel_theme/*}/{*.html,_format/*.html}"))) {
		unlike(read_file($f), $old, substr($f, length($dir) + 1) . 'に古い名前が残らない');
	}
	$b = body($app->get('guest', '/'));
	like($b, qr{<div class="side-module my-box"[^>]*>\s*<div class="side-module-title">フリー</div>}, 'フリー入力のモジュールが新しいクラスで出る');
	like($b, qr{<ul class="side-module-list">}, '一覧のモジュールが新しいクラスで出る');
	unlike($b, $old, '古いクラス、idは出ない');
	$app->restore($snap);
};

subtest 'RSSと書き出しの投稿者は管理者の表示名' => sub {
	my $snap = $app->snapshot();
	ok(json_ok($app->post('admin', '', { action => '_ajax_self_change_name', name => 'A&B 管理者' })), '管理者の名前を変える');
	ok(AppTest::is_reload($app->post('admin', '', { %ART, title => '名前の確かめ', body_txt => "本文\n" })), '記事を書く');
	like(read_file("$dir/pub/rss.xml"), qr{<dc:creator>A&amp;B 管理者</dc:creator>}, 'RSSはエスケープして出す');

	my $mt = $app->post('admin', '', { action => 'mainte/export', file => '10_movable_type' })->{body};
	utf8::decode($mt);
	like($mt, qr/^AUTHOR: A&B /m, 'Movable Typeの形式のAUTHORに出る');
	foreach my $f (qw(20_jugem 25_sb)) {
		my $x = $app->post('admin', '', { action => 'mainte/export', file => $f })->{body};
		utf8::decode($x);
		like($x, qr{<author>A&amp;B }, "$f の<author>に出る");
	}
	my $ad = $app->post('admin', '', { action => 'mainte/export', file => '00_adiary' })->{body};
	unlike($ad, qr/^\s*(?:name|id|ip|host|agent)="/m, 'adiary形式の記事に投稿者の項目が出ない');
	$app->restore($snap);
};

subtest 'パスワードを忘れたときの復旧' => sub {
	my $fresh = AppTest->new()->setup();
	system('rm', '-rf', map { "$fresh->{dir}/data/db/$_" } qw(_users _users_sid _users_log)) == 0 || die;
	$fresh->{cookie} = {};
	is($fresh->get('admin', 'menu')->{status}, 302, 'ユーザーのフォルダを消すと、前の管理者のセッションでは入れない');
	$fresh->setup_admin('again');
	is($fresh->get('again', 'menu')->{status}, 200, '初期セットアップから管理者を作り直せる');
	is($fresh->get('again', 'set/')->{status}, 200, 'サイトの設定はそのまま使える');

	# 記事が残っているときは、公開画面を止めない
	my $kept = AppTest->new()->setup()->seed();
	system('rm', '-rf', map { "$kept->{dir}/data/db/$_" } qw(_users _users_sid _users_log)) == 0 || die;
	$kept->{cookie} = {};
	mkdir("$kept->{dir}/__cache");
	is($kept->get('guest', '')->{status}, 200, '記事があれば、管理者がいなくてもトップを開ける');
	is($kept->get('guest', '/01')->{status}, 200, '記事も開ける');
	is($kept->get('guest', 'menu')->{status}, 403, '管理画面は開けない');
	like(body($kept->get('guest', 'setup')), qr{<title>初期セットアップ}, '初期セットアップの画面は開ける');
	like(body($kept->get('guest', 'setup')), qr{name="blog_name" [^>]*value="テストのサイト"}, 'サイト名の欄に今の名前を入れる');
	$kept->setup_admin('again');
	is($kept->get('again', 'menu')->{status}, 200, '管理者を作り直せる');
	like(body($kept->get('again', 'artlist')), qr{editorの記事}, '記事はそのまま');
};

subtest '操作の記録' => sub {
	# 無いIDでの失敗を12件。タグになる文字を混ぜて、エスケープとURLのエンコードも確かめる
	{
		local $app->{env} = { REMOTE_ADDR => '10.1.0.4' };	# 同じIPの回数制限に当たらないように
		$app->post('admin', '', { action => '_ajax_login', adiary_id => 'nobody<x>', pass => 'wrong' }) foreach (1..12);
	}
	my $rows = sub { my @r = (shift =~ m{<td>nobody&lt;x&gt;</td>\s*<td>ログイン</td>\s*<td><strong class="warning">失敗</strong></td>}g); scalar(@r) };

	my $b = body($app->get('admin', 'user/log&loads=10&result=fail&id=' . AppTest::_uri_escape('nobody<x>')));
	is($rows->($b), 10, '1ページ目に10件出る');
	like($b, qr{全12件}, '絞り込んだ件数が出る');
	unlike($b, qr{>user<}, '成功の記録やほかのIDは出ない');

	# 画面のページ送りのリンクをそのまま辿る
	my ($link) = $b =~ m{<a href="[^"?]*\?([^"]*page=2)">};
	ok($link, '2ページ目へのリンクがある');
	$link =~ s/&amp;/&/g;
	unlike($link, qr{<|>}, 'リンクにテンプレートの書きかけが残っていない');
	$b = body($app->get('admin', $link));
	is($rows->($b), 2, '2ページ目に残りの2件が出る');
	like($b, qr{全12件}, '2ページ目でも絞り込みが引き継がれる');
};

#-------------------------------------------------------------------------------
# ディレクトリ使用量（?system/disk）
#-------------------------------------------------------------------------------
subtest 'ディレクトリ使用量' => sub {
	require Satsuki::Base;
	require File::Path;
	my $att = "$dir/pub/attach";
	ok(-d $att && !-l $att, 'テストの添付ファイルのフォルダは、本物へのリンクではない');

	# 画面の表を { 見出し => { 行の名前 => ファイル数（表示のまま） } } にする
	my $tables = sub {
		my %t;
		foreach (split(m{<h2>}, shift)) {
			my ($h) = m{^([^<]*)</h2>} or next;
			$t{$h}{$1} = $2 while (m{<td>([^<]*)</td><td class="r">[^<]*</td><td class="r">([^<]*)</td>}g);
		}
		return \%t;
	};
	my $num = sub { my $n = int(shift); 1 while ($n =~ s/^(-?\d+)(\d{3})/$1,$2/); $n };

	# システム管理のタブのリンクを辿る
	my ($link) = body($app->get('admin', 'system/check')) =~ m{<a href="[^"?]*\?([^"]*)">ディレクトリ使用量</a>};
	is($link, 'system/disk', 'システム管理のタブにリンクがある');
	my $b = body($app->get('admin', $link));
	unlike($b, qr{class="warning"}, '読めないフォルダが無ければ警告は出ない');
	my $t0 = $tables->($b);
	is_deeply([ sort keys(%$t0) ], [ sort('全体', '添付ファイル', 'データベース') ], '表は全体、添付ファイル、データベースの3つ');
	is_deeply([ sort keys(%{ $t0->{'全体'} }) ], [ sort('__cache/', 'pub/attach/', 'data/db/', '合計') ], '全体は3つのフォルダと合計');
	ok(exists $t0->{'データベース'}{'data/db/art/'}, 'データベースはテーブルごとに出る');
	is_deeply([ grep { !m{^data/db/\w+/$} } keys(%{ $t0->{'データベース'} }) ], [], 'データベースにはテーブルのフォルダの行だけが出る');

	# 元のファイル1000個、サムネイル2個、ゴミ箱2個（ゴミ箱の中のサムネイルはゴミ箱に数える）、リンク2つを足す
	my $put = sub { my $f = shift; open(my $fh, '>', $f) || die "$f: $!"; print $fh 'x' x (shift // 0); close($fh); };
	File::Path::make_path("$att/disk/.thumbnail", "$att/.trashbox/.thumbnail");
	$put->("$att/disk/$_.txt") foreach (1..1000);
	$put->("$att/disk/.thumbnail/$_.jpg") foreach (1..2);
	$put->("$att/.trashbox/a.png");
	$put->("$att/.trashbox/.thumbnail/a.png.jpg");
	symlink("$dir/data/db", "$att/disk/link-dir") || die $!;
	symlink("$dir/lyndbaum.cgi", "$att/disk/link-file") || die $!;

	my $t1 = $tables->(body($app->get('admin', $link)));
	my $diff = sub {
		my ($h, $row, $add) = @_;
		my $before = $t0->{$h}{$row} =~ s/,//gr;
		is($t1->{$h}{$row}, $num->($before + $add), "${h}：${row}は${add}個増え、桁区切りで出る");
	};
	$diff->('添付ファイル', 'サムネイル以外', 1000);
	$diff->('添付ファイル', 'サムネイル', 2);
	$diff->('添付ファイル', 'ゴミ箱', 2);
	$diff->('添付ファイル', '合計', 1004);
	$diff->('全体', 'pub/attach/', 1004);
	$diff->('全体', '合計', 1004);
	like($t1->{'全体'}{'合計'}, qr{^\d{1,3}(?:,\d{3})+$}, '1000を超えるファイル数に桁区切りが入る');

	# 大きさはファイルの大きさの合計。リンクは辿らず、数えもしない
	my $o = bless({}, 'Satsuki::Base');
	my $s0 = $o->get_dir_size("$att/disk", 1);
	$put->("$att/disk/sub.txt", 1234);
	File::Path::make_path("$att/disk/d1/d2");
	$put->("$att/disk/d1/d2/deep.txt", 10);
	my $s = $o->get_dir_size("$att/disk", 1, '.thumbnail');
	is($s->{size}  - $s0->{size},  1244, '大きさはファイルの大きさの合計');
	is($s->{files} - $s0->{files}, 2, '足したファイルの数だけ増える');
	is_deeply({ map { $_->{name} => $_->{files} } @{ $s->{list} } }, { '' => 1001, 'd1/' => 1 }, '内訳は指定の深さのフォルダごと。深いところのファイルはその行に入り、直下のファイルはnameが空');
	is($s->{split}{'.thumbnail'}{files}, 2, '別に数えるフォルダは内訳に入れない');
	is_deeply($o->get_dir_size("$att/none"), { size => 0, files => 0, errors => 0, list => [], split => {} }, '無いフォルダは0で、読めないものに数えない');
	is(join(' ', map { $o->num_format($_) } (0, 999, 1000, 1234567, -1234)), '0 999 1,000 1,234,567 -1,234', 'num_formatの桁区切り');

	# 読めないフォルダがあると警告を出す（rootはどのフォルダも読めてしまう）
	SKIP: {
		skip('rootでは読めないフォルダを作れない', 2) if ($> == 0);
		mkdir("$att/disk/ng");
		chmod(0, "$att/disk/ng");
		$b = body($app->get('admin', $link));
		chmod(0755, "$att/disk/ng");
		like($b, qr{<strong class="warning">読めないフォルダがありました。}, '読めないフォルダがあると警告が出る');
		is($o->get_dir_size("$att/disk")->{errors}, 0, '読めるように戻すと数えない');
	}

	# 後のテストに残さない
	File::Path::remove_tree("$att/disk");
	unlink("$att/.trashbox/a.png", "$att/.trashbox/.thumbnail/a.png.jpg");
	is_deeply($tables->(body($app->get('admin', $link))), $t0, '足したものを消すと元の表に戻る');
};

#-------------------------------------------------------------------------------
# 編集画面の設定（保存すると、送らなかったflagが0になるので最後に置く）
#-------------------------------------------------------------------------------
subtest '編集画面の画像の既定値とサムネイルの大きさ' => sub {
	# 編集画面のUploadボタン（貼り付けが使う値）と、アップロードのダイアログ
	my $edit = sub {
		my $b = body($app->get('admin', 'edit'));
		my ($btn)  = $b =~ m{(<button type="button" id="edit-file-upload"[^>]*>)};
		my ($form) = $b =~ m{(<form id="upload-form">.*?</form>)}s;
		return ($btn, $form);
	};

	my ($btn, $form) = $edit->();
	like($btn, qr{data-paste="" data-exif="0" data-class=""}, '設定していないときの貼り付けの値');
	unlike($form, qr{name="size"}, 'ダイアログでサムネイルの大きさを選ばせない');
	unlike($form, qr{ selected>(?:大きい画像|センタリング|左寄せ|右寄せ)|paste-to-exif" checked}, '設定していないときは、サムネイル、そのまま、Exifなし');
	my @saves = $form =~ m{class="([^"]*\bjs-save\b[^"]*)"}g;
	is_deeply(\@saves, ['js-switch js-save'], 'ダイアログの欄はブラウザに覚えさせない（覚えるのは「詳細」の開閉だけ）');

	# 選択肢に無い大きさも保存できる
	my %SET = (action => 'set/editor', edit_thumb_size => 200, edit_paste => 'large', edit_paste_exif => 1, edit_paste_class => 'float-r');
	my $r = $app->post('admin', 'set/editor', \%SET);
	ok(AppTest::is_reload($r), '保存できる');
	($btn, $form) = $edit->();
	like($btn, qr{data-paste="large" data-exif="1" data-class="float-r"}, '貼り付けの値が設定になる');
	like($form, qr{<option value="0" selected>大きい画像を貼付</option>}, 'ダイアログが大きい画像になる');
	like($form, qr{id="paste-to-exif" checked}, 'ダイアログのExifが付く');
	like($form, qr{<option value="float-r" selected>}, 'ダイアログの表示が右寄せになる');
	like(body($app->get('admin', 'set/editor')), qr{<option value="200" selected>200px</option>}, '設定の画面にも出る');

	# 範囲外や、選択肢に無い値は拒む
	foreach my $bad ([ edit_thumb_size => 50 ], [ edit_thumb_size => 900 ], [ edit_paste => 'xx' ], [ edit_paste_class => 'xx' ]) {
		$r = $app->post('admin', 'set/editor', { %SET, @$bad });
		ok(!AppTest::is_reload($r), "$bad->[0]=$bad->[1] は保存できない");
	}
	($btn) = $edit->();
	like($btn, qr{data-paste="large"}, '拒んだ後も前の設定のまま');

	# サムネイルは、送られた大きさではなく設定の大きさで作る（元の画像は192px）
	$r = $app->post('admin', 'set/editor', { %SET, edit_thumb_size => 100 });
	ok(AppTest::is_reload($r), '大きさを100にする');
	my $png = do {
		open(my $fh, '<:raw', "$FindBin::Bin/../pub/assets/dist/default-icon.png") || die $!;
		local $/; <$fh>;
	};
	require Satsuki::ImageFormat;
	my $thumb = "$dir/pub/attach/test/.thumbnail/size.png." . (Satsuki::ImageFormat::can_write_avif() ? 'avif' : 'jpg');
	$r = $app->post('admin', '', [ action => 'media/upload_form', folder => 'test/', size => 640,
		file_ary => { filename => 'size.png', content => $png, type => 'image/png' } ]);
	like($r->{body}, qr/^ret=0$/m, 'アップロードできる');
	is(join('x', Satsuki::ImageFormat::get_size($thumb)), '100x100', 'アップロードでは設定の大きさで作る');

	$r = $app->post('admin', 'set/editor', { %SET, edit_thumb_size => 150 });
	$r = $app->post('admin', '', { action => 'media/remake_thumbnail', folder => 'test/', file_ary => 'size.png', size => 640 });
	ok(json_ok($r), '再生成できる');
	is(join('x', Satsuki::ImageFormat::get_size($thumb)), '150x150', '再生成でも設定の大きさで作る');
	unlike(body($app->get('admin', 'media/')), qr{name="size"|thumbnail-size}, 'メディア管理でサムネイルの大きさを選ばせない');
};

#-------------------------------------------------------------------------------
# 公開画面のページ送り（PageSpeed Insights の指摘）
#-------------------------------------------------------------------------------
# 保存すると、送らなかったflagが0になるので最後に置く
subtest 'ページ送りの行けない方向はリンクにしない' => sub {
	my $r = $app->post('admin', 'set/detail', { action => 'set/detail', load_items => 1 });
	ok(AppTest::is_reload($r), '1ページ1件にする');

	# 前後だけの形（トップ）と、番号付きの形（検索）。最後のページまで「次のページ」を辿る
	foreach my $base ('', '&q=' . AppTest::_uri_escape('記事')) {
		my ($nav, @nohref, $first, $last);
		for (my $p=1; $p<20; $p++) {
			my $b = body($app->get('guest', "$base&p=$p"));
			$nav = join('', $b =~ m{(<nav class="page-nav.*?</nav>)}sg);
			push(@nohref, map { "p=$p $_" } $nav =~ m{(<a(?![^>]*\bhref=)[^>]*>)}g);
			$first //= $nav;
			$last = $p;
			last if ($nav !~ /class="next-page" rel="next"/);
		}
		ok(1 < $last, "?$base は$last ページある");
		is_deeply(\@nohref, [], "?$base のどのページのページ送りにも、hrefの無いaが無い");
		like($first, qr{<span class="prev-page" aria-hidden="true">前のページ</span>}, "?$base の1ページ目の「前のページ」は見えないspan");
		like($first, qr{<a href="[^"]+" class="next-page" rel="next">次のページ</a>},  "?$base の1ページ目の「次のページ」はリンク");
		like($nav, qr{<a href="[^"]*" class="prev-page" rel="prev">前のページ</a>},    "?$base の最後のページの「前のページ」はリンク");
		like($nav, qr{<span class="next-page" aria-hidden="true">次のページ</span>},  "?$base の最後のページの「次のページ」は見えないspan");
	}
};

done_testing();
