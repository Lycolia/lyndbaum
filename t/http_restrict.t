use strict;
use utf8;
#-------------------------------------------------------------------------------
# HTTPクライアントの接続先と大きさの制限のテスト
#-------------------------------------------------------------------------------
# 実行: prove t/http_restrict.t
#
# 内部のアドレスとポートは、接続する前に断るので、外部のネットワークは要らない。
#
use FindBin;
BEGIN { push(@INC, "$FindBin::Bin/../lib"); }
use Test::More;
use IO::Socket::INET;
use POSIX ();
use Socket qw(inet_aton);
use Satsuki::Base::HTTP;

binmode(Test::More->builder->$_, ':utf8') foreach (qw(output failure_output todo_output));

my @servers;

# $responseを返して切る接続先
sub start_server {
	my $response = shift;
	my $listener = IO::Socket::INET->new(Listen => 1, LocalAddr => '127.0.0.1', LocalPort => 0, Proto => 'tcp') || die "listen: $!";
	my $port = $listener->sockport;
	my $pid = fork();
	die "fork: $!" if (!defined $pid);
	if (!$pid) {
		alarm(10);
		my $sock = $listener->accept() || POSIX::_exit(1);
		sysread($sock, my $request, 4096);
		syswrite($sock, $response);
		POSIX::_exit(0);
	}
	close($listener);
	push(@servers, $pid);
	return $port;
}
END {
	local $?;
	kill('TERM', @servers) if (@servers);
	waitpid($_, 0) foreach (@servers);
}

#-------------------------------------------------------------------------------
# 内部のアドレス
#-------------------------------------------------------------------------------
subtest '内部のアドレスを判定する' => sub {
	foreach my $ip (qw(0.0.0.0 10.0.0.1 100.64.0.1 100.127.255.255 127.0.0.1 127.1.2.3 169.254.169.254
			172.16.0.1 172.31.255.255 192.0.0.1 192.0.2.1 192.168.0.1 198.18.0.1 198.19.255.255
			198.51.100.1 203.0.113.1 224.0.0.1 240.0.0.1 255.255.255.255)) {
		ok(Satsuki::Base::HTTP->is_internal_ip(inet_aton($ip)), "$ip は内部");
	}
	foreach my $ip (qw(1.1.1.1 8.8.8.8 9.255.255.255 11.0.0.1 100.63.255.255 100.128.0.1 126.255.255.255 128.0.0.1
			169.253.255.255 169.255.0.1 172.15.255.255 172.32.0.1 192.167.255.255 192.169.0.1
			198.17.255.255 198.20.0.1 223.255.255.255)) {
		ok(!Satsuki::Base::HTTP->is_internal_ip(inet_aton($ip)), "$ip は外部");
	}
};

subtest '内部のアドレスに接続しない' => sub {
	my $port  = start_server("HTTP/1.0 200 OK\r\n\r\nsecret");
	my $http  = Satsuki::Base::HTTP->new(undef);
	$http->{allow_internal} = 1;
	like(join('', @{ $http->get("http://127.0.0.1:$port/") || [] }), qr/secret/, '制限を外せばテストの接続先につながる');

	foreach my $host ('127.0.0.1', '127.1', '2130706433', '0x7f.0.0.1', '0177.0.0.1', '169.254.169.254', '10.0.0.1', 'localhost') {
		$http = Satsuki::Base::HTTP->new(undef);
		is($http->get("http://$host/"), undef, "$host は失敗する");
		like($http->{error}, qr/Can't connect to internal address '\Q$host\E'/, "$host: エラーに理由が出る");
	}
};

subtest 'リダイレクト先が内部のアドレスなら辿らない' => sub {
	my $target = start_server("HTTP/1.0 200 OK\r\n\r\nsecret");
	my $port   = start_server("HTTP/1.0 302 Found\r\nLocation: http://127.0.0.1:$target/\r\n\r\n");

	# 最初の接続だけ制限を外す（外部のサイトからのリダイレクトの代わり）
	no warnings 'redefine';
	my $orig = \&Satsuki::Base::HTTP::connect_host;
	local *Satsuki::Base::HTTP::connect_host = sub {
		my $self = shift;
		my $r = $orig->($self, @_);
		$self->{allow_internal} = 0;
		return $r;
	};
	my $http = Satsuki::Base::HTTP->new(undef);
	$http->{allow_internal} = 1;
	is($http->get("http://127.0.0.1:$port/"), undef, 'リダイレクト先の本文を返さない');
	like($http->{error}, qr/Can't connect to (?:internal address|port)/, 'エラーに理由が出る');

	# 80番へのリダイレクトでも、アドレスで断る
	$port = start_server("HTTP/1.0 302 Found\r\nLocation: http://169.254.169.254/latest/\r\n\r\n");
	$http = Satsuki::Base::HTTP->new(undef);
	$http->{allow_internal} = 1;
	is($http->get("http://127.0.0.1:$port/"), undef, 'メタデータのアドレスへ辿らない');
	like($http->{error}, qr/Can't connect to internal address '169\.254\.169\.254'/, 'エラーに理由が出る');
};

#-------------------------------------------------------------------------------
# ポート
#-------------------------------------------------------------------------------
subtest '80番と443番のほかには接続しない' => sub {
	foreach my $url ('http://1.1.1.1:8080/', 'https://1.1.1.1:8443/', 'http://1.1.1.1:22/', 'http://1.1.1.1:6379/') {
		my $http = Satsuki::Base::HTTP->new(undef);
		is($http->get($url), undef, "$url は失敗する");
		like($http->{error}, qr/Can't connect to port \d+/, "$url: エラーに理由が出る");
	}
};

#-------------------------------------------------------------------------------
# 応答の大きさ
#-------------------------------------------------------------------------------
subtest '応答の大きさに上限がある' => sub {
	my $http = Satsuki::Base::HTTP->new(undef);
	$http->{allow_internal} = 1;
	$http->{max_size} = 1000;
	my $port = start_server("HTTP/1.0 200 OK\r\n\r\n" . ('x' x 900));
	like(join('', @{ $http->get("http://127.0.0.1:$port/") || [] }), qr/^x{900}$/, '上限より小さければ受け取る');
	is($http->{error}, undef, 'エラーにならない');

	$port = start_server("HTTP/1.0 200 OK\r\n\r\n" . ('x' x 5000));
	is($http->get("http://127.0.0.1:$port/"), undef, '上限を超えたら本文を返さない');
	like($http->{error}, qr/Response too large '127\.0\.0\.1'/, 'エラーに理由が出る');

	ok(Satsuki::Base::HTTP->new(undef)->{max_size} > 0, '既定で上限がある');
};

done_testing();
