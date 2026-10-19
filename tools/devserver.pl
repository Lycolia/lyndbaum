#!/usr/bin/env perl
# 手元で動作を確かめるための簡単なHTTPサーバー（本番では使わない）
#   perl tools/devserver.pl [--host アドレス ...] [ポート]
#   --host は何度でも指定できる。既定は 127.0.0.1 と ::1（この端末の中だけ）、ポートは 8080
#   LAN内の別の端末から見るときは --host all（0.0.0.0 と :: の両方）にする
#   （認証がないので、信頼できるネットワークの中だけで使う）
# /pub/ 以下と /favicon.ico はファイルをそのまま返し、それ以外は index.cgi をCGIとして実行する
# 接続ごとに子プロセスを作って処理する。ブラウザは先回りして接続だけ張っておくことがあり、
# 1つずつ処理するとその接続を待ち続けて止まるため
use strict;
use warnings;
use utf8;

use FindBin;
use File::Spec;
use Getopt::Long;
use IO::Select;
use IO::Socket::IP;

binmode STDERR, ':encoding(UTF-8)';
my @hosts;
GetOptions('host=s' => \@hosts) or die "使い方: $0 [--host アドレス ...] [ポート]\n";
@hosts = ('127.0.0.1', '::1') if !@hosts;
@hosts = map { $_ eq 'all' ? ('0.0.0.0', '::') : $_ } @hosts;
my $root = File::Spec->rel2abs("$FindBin::Bin/..");
my $port = $ARGV[0] // 8080;
# 何も送ってこない接続を切るまでの秒数
my $TIMEOUT = 30;
my %TYPES = (css => 'text/css', js => 'text/javascript', png => 'image/png', jpg => 'image/jpeg',
	jpeg => 'image/jpeg', gif => 'image/gif', svg => 'image/svg+xml', webp => 'image/webp',
	xml => 'application/xml', mp4 => 'video/mp4', webm => 'video/webm', ico => 'image/vnd.microsoft.icon',
	# 添付ファイル（.htaccess の AddType と同じ）
	apng => 'image/apng', mp3 => 'audio/mpeg', txt => 'text/plain; charset=utf-8', md => 'text/plain; charset=utf-8',
	csv => 'text/csv; charset=utf-8', tsv => 'text/tab-separated-values; charset=utf-8', json => 'application/json', zip => 'application/zip',
	'7z' => 'application/x-7z-compressed', pdf => 'application/pdf');

my $select = IO::Select->new;
for my $host (@hosts) {
	my $server = IO::Socket::IP->new(
		LocalHost => $host,
		LocalPort => $port,
		Listen    => 10,
		ReuseAddr => 1,
		# IPv6 のソケットは IPv6 だけを受ける（IPv4 は 0.0.0.0 などのソケットで受ける）
		($host =~ /:/ ? (V6Only => 1) : ()),
	) or die "[$host]:$port で待ち受けできません: $@\n";
	$select->add($server);
	printf STDERR "http://%s:%d/ で待ち受けています\n", ($host =~ /:/ ? "[$host]" : $host), $port;
}
print STDERR "Ctrl+C で終了します\n";

# 終わった子プロセスは自動で片付ける
$SIG{CHLD} = 'IGNORE';

while (1) {
	for my $server ($select->can_read) {
		my $client = $server->accept or next;
		my $pid = fork;
		if (!defined $pid) {
			warn "fork できません: $!\n";
		} elsif ($pid == 0) {
			$_->close for $select->handles;
			local $SIG{ALRM} = sub { die "タイムアウトしました\n" };
			alarm $TIMEOUT;
			eval { handle($client); 1 } or do { warn $@ if $@ ne "タイムアウトしました\n" };
			close $client;
			exit 0;
		}
		close $client;
	}
}

sub handle {
	my ($client) = @_;
	binmode $client;
	my $request_line = <$client> // return;
	my ($method, $uri) = $request_line =~ m{\A(\S+) (\S+) HTTP/} or return;
	my %headers;
	while (my $line = <$client>) {
		last if $line =~ /\A\r?\n\z/;
		$headers{ lc $1 } = $2 if $line =~ /\A([^:]+):\s*(.*?)\r?\n\z/;
	}
	my $body = '';
	read $client, $body, $headers{'content-length'} if $headers{'content-length'};

	my ($path, $query) = split /\?/, $uri, 2;
	# /favicon.ico は、設定の画面で入れたアイコン、無ければ既定のロゴ（本番では .htaccess か nginx の設定で返す）
	$path = -f File::Spec->catfile($root, 'pub/branding/favicon.ico') ? '/pub/branding/favicon.ico' : '/pub/assets/logo/favicon.ico'
		if $path eq '/favicon.ico';
	my $status = $path =~ m{\A/pub/} ? serve_file($client, $path) : run_cgi($client, $method, $uri, $path, $query, \%headers, $body);
	print STDERR "$method $uri $status\n";
}

sub serve_file {
	my ($client, $path) = @_;
	$path =~ s/%([0-9A-Fa-f]{2})/chr hex $1/eg;
	my $file = File::Spec->catfile($root, $path);
	my ($ext) = $file =~ /\.(\w+)\z/;
	if ($path =~ m{(?:\A|/)\.\.(?:/|\z)} || !-f $file || !$TYPES{ lc($ext // '') }) {
		print $client "HTTP/1.0 404 Not Found\r\nConnection: close\r\nContent-Type: text/plain\r\n\r\nNot Found\n";
		return 404;
	}
	open my $fh, '<:raw', $file or die "$file: $!\n";
	my $data = do { local $/; <$fh> };
	print $client "HTTP/1.0 200 OK\r\nConnection: close\r\nContent-Type: $TYPES{lc $ext}\r\nX-Content-Type-Options: nosniff\r\nContent-Length: " . length($data) . "\r\n\r\n$data";
	return 200;
}

sub run_cgi {
	my ($client, $method, $uri, $path, $query, $headers, $body) = @_;
	local %ENV = (
		%ENV,
		GATEWAY_INTERFACE => 'CGI/1.1',
		REQUEST_METHOD    => $method,
		REQUEST_URI       => $uri,
		SCRIPT_NAME       => '',
		QUERY_STRING      => $query // '',
		SERVER_NAME       => $client->sockhost,
		SERVER_PORT       => $port,
		SERVER_PROTOCOL   => 'HTTP/1.0',
		REMOTE_ADDR       => $client->peerhost,
		CONTENT_LENGTH    => length $body,
		CONTENT_TYPE      => $headers->{'content-type'} // '',
		map { ('HTTP_' . uc($_) =~ tr/-/_/r) => $headers->{$_} } keys %$headers,
	);
	delete $ENV{PATH_INFO};

	# 本文は一時ファイルを通して標準入力に渡す
	open my $in, '+>', undef or die $!;
	binmode $in;
	print $in $body;
	seek $in, 0, 0;
	open my $saved_stdin, '<&', \*STDIN or die $!;
	open STDIN, '<&', $in or die $!;
	open my $cgi, '-|', $^X, File::Spec->catfile($root, 'index.cgi') or die $!;
	open STDIN, '<&', $saved_stdin or die $!;
	binmode $cgi;
	my $output = do { local $/; <$cgi> };
	close $cgi;

	my ($head, $content) = split /\r?\n\r?\n/, $output, 2;
	my $status = $head =~ s/^Status: (\d+[^\r\n]*)\r?\n//mi ? $1 : '200 OK';
	print $client "HTTP/1.0 $status\r\nConnection: close\r\n$head\r\nContent-Length: " . length($content // '') . "\r\n\r\n" . ($content // '');
	return (split / /, $status)[0];
}
