use strict;
use utf8;
#-------------------------------------------------------------------------------
# ログインとCookieのテスト
#-------------------------------------------------------------------------------
# 実行: prove t/login.t
#
# ・ログインに失敗し続けたら止める（Auth.fail_count、標準15回）
# ・成功したら失敗の回数を戻す
# ・IDが無い・パスワードが違う・止めている、を応答から見分けられない
# ・HTTPSのときはCookieにSecureを付ける
#
use FindBin;
BEGIN { push(@INC, "$FindBin::Bin/lib", "$FindBin::Bin/../lib"); }
use Test::More;
use AppTest;

binmode(Test::More->builder->$_, ':utf8') foreach (qw(output failure_output todo_output));

my $app = AppTest->new()->setup();
my $FAIL_COUNT = 15;	# lyndbaum.conf.cgi.sample では変えていない（Auth.pmの標準）

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
subtest '失敗し続けたら止める' => sub {
	$app->user_add('admin', 'lock1', 0);
	fail_times('lock1', $FAIL_COUNT - 1);
	my ($ret) = try_login('lock1', $AppTest::PASS);
	is($ret, '0', "${FAIL_COUNT}回目より前なら、正しいパスワードで入れる");

	$app->user_add('admin', 'lock2', 0);
	fail_times('lock2', $FAIL_COUNT);
	($ret) = try_login('lock2', $AppTest::PASS);
	isnt($ret, '0', "${FAIL_COUNT}回失敗したら、正しいパスワードでも入れない");
};

subtest '成功したら失敗の回数を戻す' => sub {
	$app->user_add('admin', 'lock3', 0);
	fail_times('lock3', $FAIL_COUNT - 1);
	my ($ret) = try_login('lock3', $AppTest::PASS);
	is($ret, '0', 'ログインできる');
	fail_times('lock3', $FAIL_COUNT - 1);
	($ret) = try_login('lock3', $AppTest::PASS);
	is($ret, '0', '成功の後の失敗は1回目から数え直す');
};

subtest '失敗の理由を見分けられない' => sub {
	my (undef, $no_user)  = try_login('no-such-user', 'wrong-pass');
	my (undef, $bad_pass) = try_login('user', 'wrong-pass');
	my (undef, $locked)   = try_login('lock2', $AppTest::PASS);
	ok($no_user ne '', 'メッセージが出る');
	is($bad_pass, $no_user, 'パスワード違いとIDなしで同じメッセージ');
	is($locked,   $no_user, '止めているときとIDなしで同じメッセージ');
	unlike($no_user, qr/^[\x00-\x7f]*$/, 'メッセージが日本語に訳されている');
};

#-------------------------------------------------------------------------------
subtest 'HTTPSのときはCookieにSecureを付ける' => sub {
	my $session = sub { (grep { /^session=/ } @{ $_[0]->{cookies} })[0] // '' };

	my (undef, undef, $r) = try_login('user', $AppTest::PASS);
	like($session->($r), qr/HttpOnly/i, 'HTTPでもHttpOnlyは付く');
	unlike($session->($r), qr/\bSecure\b/i, 'HTTPではSecureを付けない');

	foreach my $env ({ HTTPS => 'on' }, { HTTP_X_FORWARDED_PROTO => 'https' }, { SERVER_PORT => 443 }) {
		my ($k) = keys(%$env);
		local $app->{env} = $env;
		(undef, undef, $r) = try_login('user', $AppTest::PASS);
		like($session->($r), qr/\bSecure\b/i, "$k=$env->{$k} ならSecureを付ける");
	}
};

done_testing();
