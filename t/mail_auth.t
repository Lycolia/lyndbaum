use strict;
use utf8;
#-------------------------------------------------------------------------------
# SMTP認証の失敗のテスト
#-------------------------------------------------------------------------------
# 実行: prove t/mail_auth.t
#
# 外部のサーバーには接続しない。手元で動かした偽のSMTPサーバーに接続する。
#
# 送信するのは新着コメントの通知で、そのとき画面を見ているのはコメントした人。
# ・エラーは画面のメッセージに出さず、エラーログ（STDERR）に書く
# ・認証に失敗しても、ユーザー名とパスワードをエラーに入れない
#
use FindBin;
BEGIN { push(@INC, "$FindBin::Bin/lib", "$FindBin::Bin/../lib"); }
use Test::More;
use IO::Socket::INET ();
use MIME::Base64 ();
use POSIX ();
use Satsuki::Base::Mail;

binmode(Test::More->builder->$_, ':utf8') foreach (qw(output failure_output todo_output));

alarm(60);	# 送信が戻らなくなったら、テスト全体を止める
$Satsuki::Base::Mail::TIMEOUT = 5;

my $USER = 'smtp-user-name';
my $PASS = 'smtp-pass-word';
my @servers;

#-------------------------------------------------------------------------------
# 偽のSMTPサーバー
#-------------------------------------------------------------------------------
# EHLOに$mechの認証方式を返し、認証の最後の行を535で断る。@repliesは途中の行への応答
sub start_server {
	my ($mech, @replies) = @_;
	my $listener = IO::Socket::INET->new(Listen => 1, LocalAddr => '127.0.0.1', LocalPort => 0, Proto => 'tcp') || die "listen: $!";
	my $port = $listener->sockport;
	my $pid = fork();
	die "fork: $!" if (!defined $pid);
	if (!$pid) {
		alarm(30);
		my $sock = $listener->accept() || POSIX::_exit(1);
		syswrite($sock, "220 test\r\n");
		read_line($sock);	# EHLO
		syswrite($sock, "250-test\r\n250 AUTH $mech\r\n");	# 2行を1回で送る（続きの行として読ませる）
		foreach my $reply (@replies, '535 authentication failed') {
			read_line($sock);
			syswrite($sock, "$reply\r\n");
		}
		read_line($sock);	# QUIT
		POSIX::_exit(0);
	}
	close($listener);
	push(@servers, $pid);
	return $port;
}
END {
	local $?;	# waitpidでテストの終了コードを変えない
	kill('KILL', @servers) if (@servers);
	waitpid($_, 0) foreach (@servers);
}
sub read_line {
	my $sock = shift;
	my $line = '';
	while (sysread($sock, my $c, 1)) {
		$line .= $c;
		last if ($c eq "\n");
	}
	return $line;
}

#-------------------------------------------------------------------------------
# 送信する
#-------------------------------------------------------------------------------
{
	package TestROBJ;
	sub new { return bless({ TM => time(), SystemCode => 'UTF-8' }); }
	sub message {
		my ($self, $format, @args) = @_;
		$self->{message} = sprintf($format, @args);
	}
}
sub send_to {
	my ($port, %opt) = @_;
	my $robj = TestROBJ->new();
	my $mail = Satsuki::Base::Mail->new($robj);
	my $log  = '';
	my $ret;
	{
		local *STDERR;
		open(STDERR, '>', \$log) || die "STDERR: $!";
		$ret = $mail->send_mail({
			to        => 'to@example.com',
			from      => 'from@example.com',
			subject   => 'test',
			text      => 'text',
			host      => '127.0.0.1',
			port      => $port,
			auth_name => $USER,
			auth_pass => $PASS,
			%opt
		});
	}
	return ($ret, $mail->{error}, $log, $robj->{message});
}
sub b64 {
	return MIME::Base64::encode_base64($_[0], '');
}

#-------------------------------------------------------------------------------
# テスト
#-------------------------------------------------------------------------------
foreach (
	[ 'PLAIN', [ '334 ' ],                          [ b64("\0$USER\0$PASS") ] ],
	[ 'LOGIN', [ '334 VXNlcm5hbWU6', '334 UGFzc3dvcmQ6' ], [ b64($USER), b64($PASS) ] ],
) {
	my ($mech, $replies, $secrets) = @$_;
	subtest "AUTH $mech の失敗" => sub {
		my ($ret, $error, $log, $message) = send_to(start_server($mech, @$replies));
		is($ret, 200, 'SMTPエラーになる');
		like($error, qr/AUTH $mech failed: 535 authentication failed/, '認証の失敗と、サーバーの応答が分かる');
		is($log, "Satsuki::Base::Mail: $error\n", 'エラーログに1行で書く');
		is($message, undef, '画面のメッセージには出さない');
		foreach my $out ($error, $log) {
			unlike($out, qr/\Q$USER\E/, 'ユーザー名を出さない');
			unlike($out, qr/\Q$PASS\E/, 'パスワードを出さない');
			unlike($out, qr/\Q$_\E/,    '送った認証の文字列を出さない') foreach (@$secrets);
		}
	};
}

subtest '認証のほかのエラーも、画面のメッセージに出さない' => sub {
	# 閉じたポート。開いてすぐ閉じたポートの番号を使う
	my $listener = IO::Socket::INET->new(Listen => 1, LocalAddr => '127.0.0.1', LocalPort => 0, Proto => 'tcp') || die "listen: $!";
	my $closed = $listener->sockport;
	close($listener);

	my ($ret, $error, $log, $message) = send_to($closed);
	is($ret, 21, '接続できない');
	is($error, "Can't connect '127.0.0.1'", '理由は呼び出し側で分かる');
	is($log, "Satsuki::Base::Mail: $error\n", 'エラーログに書く');
	is($message, undef, '画面のメッセージには出さない');

	($ret, $error, $log, $message) = send_to($closed, to => 'invalid address');
	is($ret, 1, '宛先が正しくない');
	is($error, '"To" is invalid', '理由は呼び出し側で分かる');
	is($log, "Satsuki::Base::Mail: $error\n", 'エラーログに書く');
	is($message, undef, '画面のメッセージには出さない');
};

subtest 'サーバーの応答に制御文字があっても、エラーログは1行' => sub {
	my $port = start_server('PLAIN', '334 ', "535 line1\x1b[31m\tline2");
	# 上のstart_serverは最後に535を足すので、ここでは334の次の応答（認証の結果）が自前の535になる
	my ($ret, $error, $log) = send_to($port);
	is($ret, 200, 'SMTPエラーになる');
	unlike($error, qr/[\x00-\x1f]/, '制御文字を消す');
	is(($log =~ tr/\n//), 1, '改行は最後の1つだけ');
};

done_testing();
