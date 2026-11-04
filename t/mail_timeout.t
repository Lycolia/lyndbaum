use strict;
use utf8;
#-------------------------------------------------------------------------------
# メール送信の制限時間のテスト
#-------------------------------------------------------------------------------
# 実行: prove t/mail_timeout.t
#
# 外部のサーバーには接続しない。手元で動かした偽のSMTPサーバーに接続する。
#
use FindBin;
BEGIN { push(@INC, "$FindBin::Bin/lib", "$FindBin::Bin/../lib"); }
use Test::More;
use IO::Socket::INET ();
use Socket ();
use Time::HiRes ();
use POSIX ();
use Config;
use Satsuki::Base::Mail;

binmode(Test::More->builder->$_, ':utf8') foreach (qw(output failure_output todo_output));

alarm(120);	# 送信が戻らなくなったら、テスト全体を止める

# 制限時間まで待つテストが多いので、短くして動かす
my $TIMEOUT = $Satsuki::Base::Mail::TIMEOUT = 1;

my $BIG = 32 * 1024 * 1024;	# ソケットの送信バッファに必ず収まらない大きさ
my @servers;

#-------------------------------------------------------------------------------
# 偽のSMTPサーバー
#-------------------------------------------------------------------------------
# DATAの354までを応答する。そのあとの動きは$afterに渡す
sub start_server {
	my ($after) = @_;
	my $listener = IO::Socket::INET->new(Listen => 1, LocalAddr => '127.0.0.1', LocalPort => 0, Proto => 'tcp') || die "listen: $!";
	setsockopt($listener, Socket::SOL_SOCKET(), Socket::SO_RCVBUF(), pack('i', 4096)) || die "SO_RCVBUF: $!";
	my $port = $listener->sockport;
	pipe(my $reader, my $writer) || die "pipe: $!";
	my $pid = fork();
	die "fork: $!" if (!defined $pid);
	if (!$pid) {
		alarm(60);
		close($reader);
		my $sock = $listener->accept() || POSIX::_exit(1);
		$after->($sock, $writer);
		POSIX::_exit(0);
	}
	close($listener);
	close($writer);
	push(@servers, $pid);
	return ($port, $reader);
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
sub until_data {
	my $sock = shift;
	syswrite($sock, "220 test\r\n");
	foreach my $reply ('250 test', '250 ok', '250 ok', '354 go') {
		read_line($sock);
		syswrite($sock, "$reply\r\n");
	}
}
# 本文の終わりまで読み、受け取った内容をテスト側に返す
sub read_message {
	my ($sock, $writer, $first) = @_;
	my $data = $first;
	while (substr($data, -5) ne "\r\n.\r\n") {
		my $got = sysread($sock, $data, 1024 * 1024, length($data));
		POSIX::_exit(2) if (!$got);
	}
	syswrite($sock, "250 ok\r\n");
	read_line($sock);	# QUIT
	my $written = 0;
	while ($written < length($data)) {
		$written += syswrite($writer, $data, 1024 * 1024, $written);
	}
}

#-------------------------------------------------------------------------------
# 送信する
#-------------------------------------------------------------------------------
{
	package TestROBJ;
	sub new { return bless({ TM => time(), SystemCode => 'UTF-8' }); }
	sub message {
		my ($self, $format, @args) = @_;
		$self->{error} = sprintf($format, @args);
	}
}
sub send_to {
	my ($port, $text) = @_;
	my $robj = TestROBJ->new();
	my $mail = Satsuki::Base::Mail->new($robj);
	my $start = Time::HiRes::clock_gettime(Time::HiRes::CLOCK_MONOTONIC());
	my $ret = $mail->send_mail({
		to      => 'to@example.com',
		from    => 'from@example.com',
		subject => 'test',
		text    => $text,
		host    => '127.0.0.1',
		port    => $port
	});
	my $elapsed = Time::HiRes::clock_gettime(Time::HiRes::CLOCK_MONOTONIC()) - $start;
	return ($ret, $elapsed, $robj->{error});
}
sub receive_all {
	my $reader = shift;
	my $data = '';
	while (sysread($reader, $data, 1024 * 1024, length($data))) {}
	return $data;
}
sub near_timeout {
	my ($elapsed, $name) = @_;
	ok($TIMEOUT * 0.8 < $elapsed && $elapsed < $TIMEOUT + 4, "$name（" . sprintf('%.1f', $elapsed) . '秒）');
}

#-------------------------------------------------------------------------------
# テスト
#-------------------------------------------------------------------------------
subtest '短いメールを送信できる' => sub {
	my ($port, $reader) = start_server(sub {
		my ($sock, $writer) = @_;
		until_data($sock);
		read_message($sock, $writer, '');
	});
	# アプリケーションの文字列はバイト列
	utf8::encode(my $text = "本文\n.dot");
	my ($ret, $elapsed, $error) = send_to($port, $text);
	is($ret, 0, '成功する') || diag($error);
	my $data = receive_all($reader);
	utf8::encode(my $body = "本文\n..dot\r\n.\r\n");
	like($data, qr/\Q$body\E\z/, '本文が届く');
};

subtest '送信バッファより大きなメールを欠落なく送信できる' => sub {
	my ($port, $reader) = start_server(sub {
		my ($sock, $writer) = @_;
		until_data($sock);
		read_message($sock, $writer, '');
	});
	my $text = join("\n", map { sprintf("%07d", $_) } 1 .. $BIG / 8);
	my ($ret, $elapsed, $error) = send_to($port, $text);
	is($ret, 0, '成功する') || diag($error);
	my $data = receive_all($reader);
	$data =~ s/.*?\n\n//s;		# ヘッダー
	$data =~ s/\r\n\.\r\n\z//;	# 本文の終わり
	ok($data eq $text, '全ての行が順番どおりに届く');
};

subtest '遅くても受信が進んでいれば、制限時間を超えても失敗にしない' => sub {
	my ($port, $reader) = start_server(sub {
		my ($sock, $writer) = @_;
		until_data($sock);
		my $data = '';
		foreach (1 .. 7) {
			Time::HiRes::sleep($TIMEOUT * 0.2);	# 1回の間隔は制限時間より短く、合計は長く
			my $left = 2 * 1024 * 1024;
			while ($left > 0) {
				my $got = sysread($sock, $data, $left, length($data)) || POSIX::_exit(2);
				$left -= $got;
			}
		}
		read_message($sock, $writer, $data);
	});
	my ($ret, $elapsed, $error) = send_to($port, 'x' x $BIG);
	is($ret, 0, '成功する') || diag($error);
	ok($elapsed > $TIMEOUT, '制限時間より長く掛かっている（' . sprintf('%.1f', $elapsed) . '秒）');
};

subtest 'DATAの後に読まないサーバーへの送信はタイムアウトする' => sub {
	my ($port) = start_server(sub {
		my ($sock) = @_;
		until_data($sock);
		sleep(30);
	});
	my ($ret, $elapsed, $error) = send_to($port, 'x' x $BIG);
	is($ret, 200, 'SMTPエラーになる');
	like($error, qr/send timeout/, '送信のタイムアウトと分かる');
	near_timeout($elapsed, '制限時間で戻る');
};

subtest '接続後に応答しないサーバーはタイムアウトする' => sub {
	my ($port) = start_server(sub { sleep(30); });
	my ($ret, $elapsed) = send_to($port, 'text');
	is($ret, 200, 'SMTPエラーになる');
	near_timeout($elapsed, '制限時間で戻る');
};

subtest 'FastCGIと同じスレッド構成で、送信がタイムアウトする' => sub {
	plan skip_all => 'スレッド非対応のPerlです' if (!$Config{useithreads});
	require threads;
	my ($port) = start_server(sub {
		my ($sock) = @_;
		until_data($sock);
		sleep(30);
	});
	my $worker = threads->create(sub { return [ send_to($port, 'x' x $BIG) ]; });
	my $beats  = threads->create(sub {
		my $count = 0;
		foreach (1 .. 20) {
			Time::HiRes::sleep(0.1);
			$count++;
		}
		return $count;
	});
	is($beats->join(), 20, '他のスレッドは動き続ける');
	my $result = $worker->join();
	is($result->[0], 200, 'プロセスを終了せずにエラーを返す');
	like($result->[2], qr/send timeout/, '送信のタイムアウトと分かる');
};

done_testing();
