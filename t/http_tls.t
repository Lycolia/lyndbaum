use strict;
use utf8;
#-------------------------------------------------------------------------------
# HTTPSの証明書の検証のテスト
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

my $good_port    = start_server(make_cert($ca, 'good',    'localhost'));
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

done_testing();
