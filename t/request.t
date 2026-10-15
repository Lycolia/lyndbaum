# リクエストの情報（Lyndbaum::Request）
use strict;
use warnings;
use utf8;
use Test::More;

use Lyndbaum::Request;
use TestUtil ();

subtest 'ホスト名' => sub {
	my $host = sub { Lyndbaum::Request->new({ @_ })->remote_host };
	is $host->(REMOTE_ADDR => '192.0.2.1', REMOTE_HOST => 'a.example.jp'), 'a.example.jp', 'WebサーバーのREMOTE_HOSTを使う';
	is $host->(REMOTE_ADDR => '192.0.2.1', REMOTE_HOST => ''), '', 'REMOTE_HOSTが空なら逆引きしない';
	is $host->(REMOTE_ADDR => '2001:db8::1'), '', 'IPv6は逆引きしない';
	is $host->(REMOTE_ADDR => '::1'), '';
	is $host->(), '', 'IPアドレスが無い';
};

subtest 'FCrDNS（逆引きの名前を正引きして確かめる）' => sub {
	# DNSには問い合わせず、逆引きと正引きの答えを差し替える
	my %ptr = ('192.0.2.1' => 'ok.example.jp', '192.0.2.2' => 'fake.example.jp', '192.0.2.3' => '');
	my %a   = ('ok.example.jp' => ['192.0.2.9', '192.0.2.1'], 'fake.example.jp' => ['198.51.100.1']);
	no warnings 'redefine';
	local *Lyndbaum::Request::_ptr       = sub { $ptr{ $_[0] } // '' };
	local *Lyndbaum::Request::_addresses = sub { @{ $a{ $_[0] } // [] } };
	my $host = sub { Lyndbaum::Request->new({ REMOTE_ADDR => $_[0] })->remote_host };
	is $host->('192.0.2.1'), 'ok.example.jp', '正引きで元のアドレスに戻る';
	is $host->('192.0.2.2'), '', '正引きで元のアドレスに戻らない名前は使わない';
	is $host->('192.0.2.3'), '', '逆引きできない';
	is $host->('::ffff:192.0.2.1'), 'ok.example.jp', 'IPv4をIPv6の形で書いたもの';

	local *Lyndbaum::Request::_ptr = sub { sleep 5; 'slow.example.jp' };
	local $Lyndbaum::Request::DNS_TIMEOUT = 1;
	is $host->('192.0.2.1'), '', '時間がかかりすぎたら打ち切る';
};

done_testing;
