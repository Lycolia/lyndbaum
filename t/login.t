use strict;
use utf8;
#-------------------------------------------------------------------------------
# ログインとCookieのテスト
#-------------------------------------------------------------------------------
# 実行: prove t/login.t
#
# ・同じIPからログインに失敗し続けたら、そのIPを止める（Auth.fail_count_ip、標準15回）
# ・1つのアカウントで失敗し続けたら、そのアカウントを止める（Auth.fail_count、標準100回）
# ・成功したら失敗の回数を戻す
# ・IDが無い・パスワードが違う・止めている、を応答から見分けられない
# ・操作の記録は、Auth.log_days日（標準365日）より古い行を消す
# ・HTTPSのときはCookieにSecureを付ける
#
use FindBin;
BEGIN { push(@INC, "$FindBin::Bin/lib", "$FindBin::Bin/../lib"); }
use Test::More;
use AppTest;

binmode(Test::More->builder->$_, ':utf8') foreach (qw(output failure_output todo_output));

my $app = AppTest->new()->setup();
my $FAIL_COUNT_IP = 15;	# Auth.pmの標準
my $user_cgi = $app->dir() . '/lyndbaum.user.cgi';

# テストごとに接続元を分ける（同じIPの失敗の回数が混ざらないように）
my $ip_no = 0;
sub next_ip { return '10.0.0.' . ++$ip_no; }

# ユーザー設定を入れて動かす
sub with_auth_config {
	my ($config, $code) = @_;
	open(my $fh, '>', $user_cgi) || die "$user_cgi: $!";
	print $fh "<\@20>\n<\@#>\n", join("\n", map { "<\$Auth.$_ = $config->{$_}>" } sort keys(%$config)), "\n";
	close($fh);
	$code->();
	unlink($user_cgi);
}

sub try_login {
	my ($id, $pass) = @_;
	my $r = $app->post('guest', '', { action => '_ajax_login', adiary_id => $id, pass => $pass });
	my $j = $r->{json} || {};
	my $msg = $j->{msg} // '';
	utf8::decode($msg);
	return ($j->{ret}, $msg, $r);
}
sub fail_times {
	my ($id, $n) = @_;
	try_login($id, 'wrong-pass') foreach (1..$n);
}

#-------------------------------------------------------------------------------
subtest '同じIPから失敗し続けたら止める' => sub {
	local $app->{env} = { REMOTE_ADDR => next_ip() };
	$app->insert_user('lock1');
	fail_times('lock1', $FAIL_COUNT_IP - 1);
	my ($ret) = try_login('lock1', $AppTest::PASS);
	is($ret, '0', "${FAIL_COUNT_IP}回目より前なら、正しいパスワードで入れる");

	$app->insert_user('lock2');
	fail_times('lock2', $FAIL_COUNT_IP);
	($ret) = try_login('lock2', $AppTest::PASS);
	isnt($ret, '0', "${FAIL_COUNT_IP}回失敗したら、正しいパスワードでも入れない");

	local $app->{env} = { REMOTE_ADDR => next_ip() };
	($ret) = try_login('lock2', $AppTest::PASS);
	is($ret, '0', 'ほかのIPからは、同じアカウントに入れる');
};

subtest 'IDを変えながら失敗しても、同じIPとして数える' => sub {
	local $app->{env} = { REMOTE_ADDR => next_ip() };
	$app->insert_user('vary');
	try_login("no-such-$_", 'wrong-pass') foreach (1..$FAIL_COUNT_IP);
	my ($ret) = try_login('vary', $AppTest::PASS);
	isnt($ret, '0', '無いIDへの失敗も数える');
};

subtest '成功したら失敗の回数を戻す' => sub {
	local $app->{env} = { REMOTE_ADDR => next_ip() };
	$app->insert_user('lock3');
	fail_times('lock3', $FAIL_COUNT_IP - 1);
	my ($ret) = try_login('lock3', $AppTest::PASS);
	is($ret, '0', 'ログインできる');
	fail_times('lock3', $FAIL_COUNT_IP - 1);
	($ret) = try_login('lock3', $AppTest::PASS);
	is($ret, '0', '成功の後の失敗は1回目から数え直す');
};

subtest 'IPv6は/64ごとに数える' => sub {
	$app->insert_user('v6');
	my $try = sub {
		my ($ip, $pass) = @_;
		local $app->{env} = { REMOTE_ADDR => $ip };
		return (try_login('v6', $pass))[0];
	};
	$try->("2001:db8:1:2::$_", 'wrong-pass') foreach (1..$FAIL_COUNT_IP);
	isnt($try->('2001:db8:1:2:ffff::1', $AppTest::PASS), '0', '同じ/64の別のアドレスは止まる');
	isnt($try->('2001:0DB8:0001:0002:0000:0000:0000:0001', $AppTest::PASS), '0', '表記が違っても同じIPとして数える');
	is($try->('2001:db8:1:3::1', $AppTest::PASS), '0', '別の/64からは入れる');
};

subtest '::ffff:の形はIPv4ごとに数える' => sub {
	$app->insert_user('mapped');
	my $try = sub {
		my ($ip, $pass) = @_;
		local $app->{env} = { REMOTE_ADDR => $ip };
		return (try_login('mapped', $pass))[0];
	};
	$try->('::ffff:10.2.0.1', 'wrong-pass') foreach (1..$FAIL_COUNT_IP);
	isnt($try->('10.2.0.1', $AppTest::PASS), '0', '同じIPv4は止まる');
	is($try->('::ffff:10.2.0.2', $AppTest::PASS), '0', 'ほかのIPv4からは入れる');
};

subtest 'アカウントの上限' => sub {
	$app->insert_user('cap1');
	$app->insert_user('cap2');
	with_auth_config({ fail_count_ip => 3, fail_count => 5 }, sub {
		foreach my $n (2, 2, 1) {	# どのIPも上限に届かない
			local $app->{env} = { REMOTE_ADDR => next_ip() };
			fail_times('cap1', $n);
		}
		local $app->{env} = { REMOTE_ADDR => next_ip() };
		my ($ret) = try_login('cap1', $AppTest::PASS);
		isnt($ret, '0', 'IPを分けても、アカウントの上限で止まる');

		# 止められたIPの試行は、アカウントの回数に足さない
		fail_times('cap2', 3 + 5);
		local $app->{env} = { REMOTE_ADDR => next_ip() };
		($ret) = try_login('cap2', $AppTest::PASS);
		is($ret, '0', '1つのIPからでは、アカウントの上限に届かない');
	});
};

subtest '回数制限を止められる' => sub {
	$app->insert_user('noiplimit');
	with_auth_config({ fail_count_ip => 0 }, sub {
		local $app->{env} = { REMOTE_ADDR => next_ip() };
		fail_times('noiplimit', $FAIL_COUNT_IP + 1);
		my ($ret) = try_login('noiplimit', $AppTest::PASS);
		is($ret, '0', 'fail_count_ip=0なら、同じIPからの回数では止めない');
	});
};

subtest 'fail_minute分たつと数え直す' => sub {
	$app->insert_user('window');
	local $app->{env} = { REMOTE_ADDR => next_ip() };
	# 止まっていることは、標準のfail_minuteのまま確かめる（負荷が高くても時間切れにならない）
	with_auth_config({ fail_count_ip => 3 }, sub {
		fail_times('window', 3);
		my ($ret) = try_login('window', $AppTest::PASS);
		isnt($ret, '0', '止まっている');
	});
	with_auth_config({ fail_count_ip => 3, fail_minute => 0.01 }, sub {	# 0.6秒
		sleep(2);
		my ($ret) = try_login('window', $AppTest::PASS);
		is($ret, '0', '時間がたつと入れる');
	});
};

subtest '失敗の理由を見分けられない' => sub {
	my $ip = next_ip();
	local $app->{env} = { REMOTE_ADDR => next_ip() };
	my (undef, $no_user)  = try_login('no-such-user', 'wrong-pass');
	my (undef, $bad_pass) = try_login('lock3', 'wrong-pass');
	ok($no_user ne '', 'メッセージが出る');
	is($bad_pass, $no_user, 'パスワード違いとIDなしで同じメッセージ');
	unlike($no_user, qr/^[\x00-\x7f]*$/, 'メッセージが日本語に訳されている');

	# 同じIPの回数制限で止めているとき
	local $app->{env} = { REMOTE_ADDR => $ip };
	fail_times('lock3', $FAIL_COUNT_IP);
	my (undef, $locked) = try_login('lock3', $AppTest::PASS);
	is($locked, $no_user, 'IPで止めているときとIDなしで同じメッセージ');

	# アカウントの上限で止めているとき
	$app->insert_user('msgcap');
	with_auth_config({ fail_count => 3 }, sub {
		local $app->{env} = { REMOTE_ADDR => next_ip() };
		fail_times('msgcap', 3);
		my (undef, $capped) = try_login('msgcap', $AppTest::PASS);
		is($capped, $no_user, 'アカウントで止めているときとIDなしで同じメッセージ');
	});
};

subtest '止めた試行の記録' => sub {
	my $ip = next_ip();
	$app->insert_user('logged');
	{
		local $app->{env} = { REMOTE_ADDR => $ip };
		fail_times('logged', $FAIL_COUNT_IP + 1);
	}
	$app->insert_user('logview');
	$app->login('logview');
	my $b = $app->get('logview', 'user/log&result=fail&id=logged')->{body};
	utf8::decode($b);
	like($b, qr{<strong class="warning">失敗（同じIPの回数制限）</strong></td>\s*<td>\Q$ip\E</td>}, '操作の記録の画面に表示名とIPが出る');
};

subtest '古い操作の記録を消す' => sub {
	require Satsuki::Base;
	my $dbdir = $app->dir() . '/data/db/';
	# アプリは別のプロセスで動くので、毎回読み直す
	my $count = sub {
		my $ROBJ = Satsuki::Base->new();
		my $DB   = $ROBJ->loadpm('DB_text', $dbdir);
		return scalar(@{ $DB->select_match('_users_log', 'id', $_[0]) });
	};
	my $put = sub {
		my ($id, $days) = @_;
		my $ROBJ = Satsuki::Base->new();
		my $DB   = $ROBJ->loadpm('DB_text', $dbdir);
		$DB->begin();
		$DB->insert('_users_log', { id => $id, type => 'login', tm => time() - $days*86400 });
		if ($DB->commit()) { die "insert log $id failed"; }
	};
	$app->insert_user('expire');
	local $app->{env} = { REMOTE_ADDR => next_ip() };

	$put->('old-log', 366);
	$put->('new-log', 364);
	with_auth_config({ log_days => 0 }, sub {
		my ($ret) = try_login('expire', $AppTest::PASS);
		is($ret, '0', 'ログインできる');
		is($count->('old-log'), 1, 'log_days=0なら、古い記録を消さない');
	});

	try_login('no-such-user', 'wrong-pass');
	is($count->('old-log'), 0, '失敗を記録するときにも、365日より古い記録が消える');
	is($count->('new-log'), 1, '365日より新しい記録は残る');
	ok(0 < $count->('expire'), '今の記録は残る');

	$put->('old-log', 366);
	my ($ret) = try_login('expire', $AppTest::PASS);
	is($ret, '0', 'ログインできる');
	is($count->('old-log'), 0, '成功を記録するときにも消える');

	$put->('old-log', 31);
	with_auth_config({ log_days => 30 }, sub {
		try_login('expire', $AppTest::PASS);
		is($count->('old-log'), 0, 'log_daysを変えると、その日数で消える');
		is($count->('new-log'), 0, 'log_daysを変えると、その日数で消える（364日前）');
	});

	my $b = $app->get('guest', 'user/log')->{body};
	utf8::decode($b);
	unlike($b, qr/古い記録は消えます/, 'ログインしていなければ、操作の記録は見えない');
	$app->login('expire');
	$b = $app->get('expire', 'user/log')->{body};
	utf8::decode($b);
	like($b, qr/365日より古い記録は消えます/, '操作の記録の画面に、保持日数が出る');
};

subtest 'log_daysを短くしても、同じIPの回数制限に要る記録は残す' => sub {
	$app->insert_user('keepfail');
	local $app->{env} = { REMOTE_ADDR => next_ip() };
	with_auth_config({ fail_count_ip => 3, log_days => '0.00001' }, sub {	# 1秒足らず。数のままだと1e-05と書かれる
		fail_times('keepfail', 3);
		sleep(2);
		# 1回目の記録のときに掃除が走るので、2回目で確かめる
		try_login('keepfail', $AppTest::PASS);
		my ($ret) = try_login('keepfail', $AppTest::PASS);
		isnt($ret, '0', 'log_daysを過ぎても、fail_minute分の失敗は消えず、止まったまま');
	});
};

#-------------------------------------------------------------------------------
subtest 'URLからパスワードを受け取らない' => sub {
	my $r = $app->get('guest', 'login&id=test&pass=URL-PASS');
	is($r->{status}, 200, 'ログイン画面を開ける');
	unlike($r->{body}, qr/URL-PASS/, 'URLのパスワードを画面に出さない');
	like($r->{body}, qr/name="adiary_id"[^>]*value="test"/, 'URLのIDは初期値に入れる');
};

#-------------------------------------------------------------------------------
subtest 'HTTPSのときはCookieにSecureを付ける' => sub {
	my $session = sub { (grep { /^session=/ } @{ $_[0]->{cookies} })[0] // '' };

	my (undef, undef, $r) = try_login('lock3', $AppTest::PASS);
	like($session->($r), qr/HttpOnly/i, 'HTTPでもHttpOnlyは付く');
	unlike($session->($r), qr/\bSecure\b/i, 'HTTPではSecureを付けない');

	foreach my $env ({ HTTPS => 'on' }, { HTTP_X_FORWARDED_PROTO => 'https' }, { SERVER_PORT => 443 }) {
		my ($k) = keys(%$env);
		local $app->{env} = $env;
		(undef, undef, $r) = try_login('lock3', $AppTest::PASS);
		like($session->($r), qr/\bSecure\b/i, "$k=$env->{$k} ならSecureを付ける");
	}
};

done_testing();
