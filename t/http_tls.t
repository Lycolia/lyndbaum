use strict;
use utf8;
#-------------------------------------------------------------------------------
# HTTPSの証明書の検証と通信のタイムアウトのテスト
#-------------------------------------------------------------------------------
# 実行: prove t/http_tls.t
#
# 外部のサイトには接続しない。opensslコマンドでテスト用のCAと証明書を作り、
# 手元で動かしたTLSサーバーに接続する。信頼するCAは環境変数で切り替える。
#
use FindBin;
BEGIN { push(@INC, "$FindBin::Bin/lib", "$FindBin::Bin/../lib"); }
use Test::More;
use File::Temp ();
use IO::Socket::INET ();
use Time::HiRes ();
use POSIX ();
use Config;
use Satsuki::Base::HTTP;

binmode(Test::More->builder->$_, ':utf8') foreach (qw(output failure_output todo_output));

if (!eval { require Net::SSLeay; 1 }) {
	plan skip_all => 'Net::SSLeayがありません';
}
if (system('openssl version >/dev/null 2>&1') != 0) {
	plan skip_all => 'opensslコマンドがありません';
}

my $dir = File::Temp::tempdir('adiary-tls-XXXXXX', TMPDIR => 1, CLEANUP => 1);
my @servers;

#-------------------------------------------------------------------------------
# 証明書を作る
#-------------------------------------------------------------------------------
sub openssl {
	my $cmd = join(' ', 'openssl', @_, ">>$dir/openssl.log 2>&1");
	system($cmd) == 0 || die "openssl failed: $cmd\n" . do { open(my $fh, '<', "$dir/openssl.log"); local $/; <$fh> };
}
sub write_file {
	my ($file, $text) = @_;
	open(my $fh, '>', $file) || die "$file: $!";
	print $fh $text;
	close($fh);
}

# CAを作る
sub make_ca {
	my $name = shift;
	my $d = "$dir/$name";
	mkdir($d);
	write_file("$d/index.txt", '');
	write_file("$d/serial", "01\n");
	write_file("$d/req.cnf", "[req]\ndistinguished_name=dn\n[dn]\n");
	openssl('req -x509 -newkey rsa:2048 -nodes -days 2 -sha256',
		"-config $d/req.cnf -subj /CN=$name -keyout $d/ca.key -out $d/ca.crt",
		'-addext basicConstraints=critical,CA:TRUE -addext keyUsage=critical,keyCertSign,cRLSign');
	return $d;
}

# サーバーの証明書を作る。$datesはopenssl caの日時の指定
sub make_cert {
	my ($ca, $name, $san, $dates) = @_;
	my $d = "$dir/$name";
	mkdir($d);
	write_file("$d/ca.cnf", <<CNF);
[ca]
default_ca=d
[d]
database=$ca/index.txt
new_certs_dir=$d
serial=$ca/serial
certificate=$ca/ca.crt
private_key=$ca/ca.key
default_md=sha256
policy=p
x509_extensions=e
unique_subject=no
[p]
commonName=supplied
[e]
subjectAltName=DNS:$san
[req]
distinguished_name=dn
[dn]
CNF
	openssl("req -newkey rsa:2048 -nodes -config $d/ca.cnf -subj /CN=$san -keyout $d/key.pem -out $d/csr.pem");
	openssl("ca -batch -notext -config $d/ca.cnf -in $d/csr.pem -out $d/cert.pem", $dates || '-days 2');
	return $d;
}

#-------------------------------------------------------------------------------
# TLSサーバーを動かす
#-------------------------------------------------------------------------------
sub start_server {
	my $cert = shift;

	my $probe = IO::Socket::INET->new(Listen => 1, LocalAddr => '127.0.0.1', LocalPort => 0, Proto => 'tcp') || die "listen: $!";
	my $port = $probe->sockport;
	close($probe);

	my $pid = fork();
	die "fork: $!" if (!defined $pid);
	if (!$pid) {
		open(STDIN,  '<', '/dev/null');
		open(STDOUT, '>', '/dev/null');
		open(STDERR, '>', '/dev/null');
		exec('openssl', 's_server', '-accept', "127.0.0.1:$port", '-cert', "$cert/cert.pem", '-key', "$cert/key.pem", '-www');
		POSIX::_exit(127);
	}
	push(@servers, $pid);

	foreach (1..100) {
		my $s = IO::Socket::INET->new(PeerAddr => '127.0.0.1', PeerPort => $port, Proto => 'tcp');
		if ($s) { close($s); return $port; }
		Time::HiRes::sleep(0.05);
	}
	die "server not started";
}

# 通信を止める接続先と、要求の本文をそのまま返す接続先。親でlistenしてから返す
sub start_test_server {
	my ($cert, $mode) = @_;
	my $listener = IO::Socket::INET->new(Listen => 1, LocalAddr => '127.0.0.1', LocalPort => 0, Proto => 'tcp') || die "listen: $!";
	my $port = $listener->sockport;
	setsockopt($listener, Socket::SOL_SOCKET(), Socket::SO_RCVBUF(), pack('i', 4096)) || die "SO_RCVBUF: $!";
	my $pid = fork();
	die "fork: $!" if (!defined $pid);
	if (!$pid) {
		# 実装が壊れていてもテストを無期限に止めない
		alarm(10);
		my $sock = $listener->accept() || POSIX::_exit(1);
		close($listener);
		if ($mode ne 'handshake') {
			my $ctx = Net::SSLeay::new_x_ctx();
			Net::SSLeay::CTX_use_certificate_file($ctx, "$cert/cert.pem", Net::SSLeay::FILETYPE_PEM()) || POSIX::_exit(2);
			Net::SSLeay::CTX_use_PrivateKey_file($ctx, "$cert/key.pem", Net::SSLeay::FILETYPE_PEM()) || POSIX::_exit(3);
			my $ssl = Net::SSLeay::new($ctx);
			Net::SSLeay::set_fd($ssl, fileno($sock));
			Net::SSLeay::accept($ssl) == 1 || POSIX::_exit(4);
			if ($mode eq 'echo') {
				my $request = '';
				while ($request !~ /\r\n\r\n/) {
					my $got = Net::SSLeay::read($ssl);
					POSIX::_exit(5) if (!defined($got) || $got eq '');
					$request .= $got;
				}
				my ($header, $body) = split(/\r\n\r\n/, $request, 2);
				my ($length) = $header =~ /Content-Length: (\d+)/i;
				while (length($body) < $length) {
					my $got = Net::SSLeay::read($ssl);
					POSIX::_exit(6) if (!defined($got) || $got eq '');
					$body .= $got;
				}
				Net::SSLeay::ssl_write_all($ssl, "HTTP/1.0 200 OK\r\nContent-Length: $length\r\n\r\n$body");
				Net::SSLeay::shutdown($ssl);
				POSIX::_exit(0);
			}
			if ($mode eq 'partial') {
				Net::SSLeay::ssl_write_all($ssl, "HTTP/1.0 200 OK\r\nContent-Length: 20\r\n\r\npart");
			}
			# writeでは要求を読まず、readでは応答を返さずに待つ
			sleep(8);
			POSIX::_exit(0);
		}
		sleep(8);
		POSIX::_exit(0);
	}
	close($listener);
	push(@servers, $pid);
	return $port;
}
END {
	local $?;	# waitpidでテストの終了コードを変えない
	kill('TERM', @servers) if (@servers);
	waitpid($_, 0) foreach (@servers);
}

#-------------------------------------------------------------------------------
# 接続する
#-------------------------------------------------------------------------------
# 信頼するCAを$caだけにして接続し、結果のHTTPオブジェクトを返す
sub connect_with {
	my ($ca, $url) = @_;
	my $empty = "$dir/empty";
	mkdir($empty);
	local $ENV{SSL_CERT_FILE} = "$ca/ca.crt";
	local $ENV{SSL_CERT_DIR}  = $empty;
	my $http = Satsuki::Base::HTTP->new(undef);
	$http->set_timeout(10);
	$http->get($url);
	return $http;
}

my $ca    = make_ca('ca');
my $other = make_ca('other');

my $good_cert    = make_cert($ca, 'good', 'localhost');
my $good_port    = start_server($good_cert);
my $wrong_port   = start_server(make_cert($ca, 'wrong',   'other.example'));
my $expired_port = start_server(make_cert($ca, 'expired', 'localhost', '-startdate 20200101000000Z -enddate 20200102000000Z'));

#-------------------------------------------------------------------------------
# テスト
#-------------------------------------------------------------------------------
subtest '正しい証明書' => sub {
	my $http = connect_with($ca, "https://localhost:$good_port/");
	is($http->{status}, 200, '接続できる');
	is($http->{error}, undef, 'エラーにならない');
};

subtest 'ホスト名が違う証明書' => sub {
	my $http = connect_with($ca, "https://localhost:$wrong_port/");
	isnt($http->{status}, 200, '接続を拒否する');
	like($http->{error}, qr/Certificate verification failed 'localhost' \(hostname mismatch\)/, 'エラーに理由が出る');
};

subtest '信頼していないCAの証明書' => sub {
	my $http = connect_with($other, "https://localhost:$good_port/");
	isnt($http->{status}, 200, '接続を拒否する');
	like($http->{error}, qr/Certificate verification failed 'localhost'/, 'エラーに理由が出る');
};

subtest '期限切れの証明書' => sub {
	my $http = connect_with($ca, "https://localhost:$expired_port/");
	isnt($http->{status}, 200, '接続を拒否する');
	like($http->{error}, qr/Certificate verification failed 'localhost' \(certificate has expired\)/, 'エラーに理由が出る');
};

subtest 'IPアドレスを指定したURL' => sub {
	my $http = connect_with($ca, "https://127.0.0.1:$good_port/");
	isnt($http->{status}, 200, '証明書にIPアドレスが無ければ拒否する');
	like($http->{error}, qr/Certificate verification failed '127\.0\.0\.1'/, 'エラーに理由が出る');
};

subtest 'Net::SSLeayの版が古い' => sub {
	local $Net::SSLeay::VERSION = '1.91';
	my $http = connect_with($ca, "https://localhost:$good_port/");
	isnt($http->{status}, 200, '接続しない');
	like($http->{error}, qr/Net::SSLeay Ver1\.91 is too old/, 'エラーに版が出る');
};

foreach my $mode (qw(handshake write read partial)) {
	subtest "HTTPSのタイムアウト（$mode）" => sub {
		my $port = start_test_server($good_cert, $mode);
		local $ENV{SSL_CERT_FILE} = "$ca/ca.crt";
		local $ENV{SSL_CERT_DIR} = "$dir/empty";
		my $http = Satsuki::Base::HTTP->new(undef);
		$http->set_timeout(0.3);
		my $start = Time::HiRes::time();
		my $result = $mode eq 'write'
			? $http->post("https://localhost:$port/", {}, 'x' x (16*1024*1024))
			: $http->get("https://localhost:$port/");
		my $elapsed = Time::HiRes::time() - $start;
		is($result, undef, '途中まで受信していても成功にしない');
		like($http->{error}, qr/Connection timeout/, 'タイムアウトとして返る');
		cmp_ok($elapsed, '>=', 0.25, '期限まで待つ');
		cmp_ok($elapsed, '<', 3, '応答が止まっても期限で抜ける');
	};
}

subtest 'TLSのバッファより大きいデータを欠落なく送受信する' => sub {
	my $port = start_test_server($good_cert, 'echo');
	local $ENV{SSL_CERT_FILE} = "$ca/ca.crt";
	local $ENV{SSL_CERT_DIR} = "$dir/empty";
	my $http = Satsuki::Base::HTTP->new(undef);
	$http->set_timeout(5);
	my $body = "\x00\xff0123456789\r\n" x 8192;
	my $result = $http->post("https://localhost:$port/", {}, $body);
	is($http->{status}, 200, '接続できる');
	is($http->{error}, undef, 'エラーにならない');
	ok(ref($result) eq 'ARRAY' && join('', @$result) eq $body, 'バイナリの本文が一致する');
};

subtest 'FastCGIと同じスレッド構成で、接続ごとにタイムアウトする' => sub {
	plan skip_all => 'スレッド非対応のPerlです' if (!$Config{useithreads});
	require threads;
	my @ports = map { start_test_server($good_cert, 'handshake') } (1..2);
	my @workers;
	foreach my $i (0..1) {
		push(@workers, threads->create(sub {
			my $http = Satsuki::Base::HTTP->new(undef);
			$http->set_timeout($i ? 1.5 : 0.3);
			my $start = Time::HiRes::time();
			my $result = $http->get("https://localhost:$ports[$i]/");
			return [$result, $http->{error}, Time::HiRes::time() - $start];
		}));
	}
	foreach my $i (0..1) {
		my $result = $workers[$i]->join();
		is($result->[0], undef, "スレッド$i: 接続は失敗する");
		like($result->[1], qr/Connection timeout/, "スレッド$i: プロセスを終了せずにエラーを返す");
		cmp_ok($result->[2], '>=', $i ? 1.4 : 0.25, "スレッド$i: 自分の期限まで待つ");
		cmp_ok($result->[2], '<', $i ? 3 : 1.2, "スレッド$i: 別の接続の期限に影響されない");
	}
	my $http = connect_with($ca, "https://localhost:$good_port/");
	is($http->{status}, 200, 'タイムアウトの後も通信できる');
};

done_testing();
