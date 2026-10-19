# index.fcgiを実際に起動し、FastCGIでリクエストを送って確かめる（Lyndbaum::FastCGI）
#   1つのプロセスで続けて受けたリクエストのあいだで、ログインの状態などが混ざらないこと
use strict;
use warnings;
use utf8;
use Test::More;

use Encode qw(decode_utf8 encode_utf8);
use File::Spec;
use File::Temp qw(tempdir);
use IO::Socket::UNIX;
use JSON::PP;
use Time::HiRes qw(sleep);
use AdminTest;
use TestUtil qw(root_dir insert_article);

plan skip_all => 'FCGIがありません' if !eval { require FCGI; 1 };

my $t = AdminTest->new;
insert_article($t->dbh, id => 7, title => 'こんにちは');
$t->dbh->disconnect;

my $dir    = tempdir(CLEANUP => 1);
my $config = File::Spec->catfile($dir, 'config.json');
open my $fh, '>', $config or die $!;
print $fh JSON::PP->new->canonical->encode({ %{ $t->app->config } });
close $fh;
my $socket = File::Spec->catfile($dir, 'fcgi.sock');

# 子のプロセスは1つ、1つの子が受けるのは4件まで。5件目からは作り直した子が受ける
sub start {
	my (%env) = @_;
	my @options = @{ delete $env{options} // [] };
	my $pid = fork // die $!;
	if (!$pid) {
		local %ENV = (%ENV, LYNDBAUM_CONFIG => $config, %env);
		open STDERR, '>', File::Spec->catfile($dir, 'stderr') or die $!;
		exec $^X, File::Spec->catfile(root_dir(), 'index.fcgi'), @options, $socket, 1, 4 or die $!;
	}
	for (1 .. 100) { last if -S $socket; sleep 0.05 }
	return $pid;
}

sub slurp { my ($file) = @_; open my $in, '<', $file or die "$file: $!"; local $/; return <$in> }

sub stop {
	my ($pid) = @_;
	kill TERM => $pid;
	waitpid $pid, 0;
	return $?;
}

# FastCGIのリクエストを1件送り、応答（ヘッダーと本文）を文字列で返す。リストで受けると、エラーの出力（warn）も返す
sub fcgi_request {
	my (%param) = @_;
	my $stdin = delete $param{STDIN} // '';
	my $sock = IO::Socket::UNIX->new(Peer => $socket) or die "$socket: $!";
	my $record = sub {
		my ($type, $content) = @_;
		return pack('CCnnCx', 1, $type, 1, length $content, 0) . $content;
	};
	my $length = sub { my $n = length $_[0]; $n < 128 ? pack('C', $n) : pack('N', $n | 0x80000000) };
	my $params = join '', map { my $v = encode_utf8($param{$_}); $length->($_) . $length->($v) . $_ . $v } sort keys %param;
	print {$sock} $record->(1, pack('nCx5', 1, 0)),   # BEGIN_REQUEST（RESPONDER）
		$record->(4, $params), $record->(4, ''),      # PARAMS
		($stdin ne '' ? $record->(5, $stdin) : ()), $record->(5, '');   # STDIN
	my ($out, $err) = ('', '');
	while (read($sock, my $header, 8) == 8) {
		my (undef, $type, undef, $len, $pad) = unpack 'CCnnC', $header;
		read $sock, my $content, $len + $pad;
		$out .= substr($content, 0, $len) if $type == 6;   # STDOUT
		$err .= substr($content, 0, $len) if $type == 7;   # STDERR
		last if $type == 3;                                # END_REQUEST
	}
	return wantarray ? (decode_utf8($out), decode_utf8($err)) : decode_utf8($out);
}

my %base = (HTTP_HOST => 'blog.example', HTTPS => 'on', REMOTE_ADDR => '192.0.2.1');

subtest '同じプロセスで続けて受けても、前のリクエストが残らない' => sub {
	my $pid = start();
	ok -S $socket, 'ソケットを開く';
	is sprintf('%04o', (stat $socket)[2] & 07777), '0660', '既定ではグループまで繋げる';

	my $out = fcgi_request(%base, REQUEST_METHOD => 'GET', PATH_INFO => '/07');
	like $out, qr{\AStatus: 200 OK\r\n}, 'ステータス行';
	like $out, qr{<h1 class="article-title">こんにちは</h1>}, 'UTF-8で出力する';
	unlike $out, qr{class="admin-bar"}, 'ログインしていなければ管理者のメニューは無い';

	my $body = "login=$AdminTest::LOGIN&password=" . ($AdminTest::PASSWORD =~ s/ /+/gr);
	$out = fcgi_request(%base, REQUEST_METHOD => 'POST', PATH_INFO => '/admin/login', HTTP_ORIGIN => $AdminTest::ORIGIN,
		CONTENT_TYPE => 'application/x-www-form-urlencoded', CONTENT_LENGTH => length $body, STDIN => $body);
	my ($cookie) = $out =~ /^Set-Cookie: (lyndbaum_session=[^;]+)/m;
	ok $cookie, 'POSTの本文を読んでログインする';

	like fcgi_request(%base, REQUEST_METHOD => 'GET', PATH_INFO => '/07', HTTP_COOKIE => $cookie),
		qr{class="admin-bar"}, 'Cookieがあれば管理者のメニューを出す';
	unlike fcgi_request(%base, REQUEST_METHOD => 'GET', PATH_INFO => '/07'),
		qr{class="admin-bar"}, '次のリクエストにCookieが残らない';

	like fcgi_request(%base, REQUEST_METHOD => 'GET', PATH_INFO => '/07'),
		qr{\AStatus: 200 OK\r\n}, '決まった数を受けた子を作り直して、続けて受ける';

	is stop($pid), 0, '止める合図で終わる';
	ok !-e $socket, 'ソケットのファイルを消す';
};

subtest 'ソケットの権限を変える' => sub {
	my $pid = start(options => ['--socket-mode', '0600']);
	is sprintf('%04o', (stat $socket)[2] & 07777), '0600';
	like fcgi_request(%base, REQUEST_METHOD => 'GET', PATH_INFO => '/07'), qr{\AStatus: 200 OK\r\n}, '繋げる';
	stop($pid);
};

subtest '権限の書き方が違えば起動しない' => sub {
	open my $saved, '>&', \*STDERR or die $!;
	open STDERR, '>', File::Spec->catfile($dir, 'stderr') or die $!;
	my $status = system $^X, File::Spec->catfile(root_dir(), 'index.fcgi'), '--socket-mode', '660x', $socket;
	open STDERR, '>&', $saved or die $!;
	is $status >> 8, 2;
	like slurp(File::Spec->catfile($dir, 'stderr')), qr{--socket-mode}, '使い方を出す';
	ok !-e $socket, 'ソケットを作らない';
};

subtest '例外が起きたら500' => sub {
	my $pid = start(LYNDBAUM_CONFIG => File::Spec->catfile($dir, 'missing.json'));
	my ($out, $err) = fcgi_request(%base, REQUEST_METHOD => 'GET', PATH_INFO => '/07');
	like $out, qr{\AStatus: 500 Internal Server Error\r\n};
	like $err, qr{設定ファイルを開けません}, '理由はWebサーバーのエラーログへ送る（UTF-8）';
	stop($pid);
	unlike slurp(File::Spec->catfile($dir, 'stderr')), qr{wide character}i, 'FCGIに文字のまま渡さない';
};

done_testing;
