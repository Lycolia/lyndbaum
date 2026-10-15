# 拒否するIPアドレスとホスト名の照合（Lyndbaum::AddressMatch）
use strict;
use warnings;
use utf8;
use Test::More;

use Lyndbaum::AddressMatch;
use TestUtil ();

my $M = 'Lyndbaum::AddressMatch';

subtest '書き方の確認' => sub {
	ok($M->valid_ip_rule($_), "正しい：$_") for qw(192.0.2.10 192.0.2.0/24 192.0.2. 10. 2001:db8::1 2001:db8::/32 2001:db8: ::1);
	ok(!$M->valid_ip_rule($_), "正しくない：$_") for ('', 'abc', '192.0.2.0/33', '2001:db8::/129', '999.0.0.1', '192.0.2.0/', 'example.net', '.', ':');
	ok($M->valid_host_rule($_), "正しい：$_") for qw(example.net .example.net spam-1.example.net localhost);
	ok(!$M->valid_host_rule($_), "正しくない：$_") for ('', '.', 'example..net', '-a.example.net', 'a b', 'example.net/');
};

subtest 'IPアドレス' => sub {
	my @rules = ('192.0.2.10', '198.51.100.0/24', '203.0.113.', '2001:db8::/32', '2001:db8:ffff::/48');
	ok($M->ip_matches('192.0.2.10', \@rules), 'そのアドレス');
	ok(!$M->ip_matches('192.0.2.11', \@rules), '違うアドレス');
	ok($M->ip_matches('198.51.100.255', \@rules), 'CIDRの中');
	ok(!$M->ip_matches('198.51.101.0', \@rules), 'CIDRの外');
	ok($M->ip_matches('203.0.113.7', \@rules), '前方一致');
	ok(!$M->ip_matches('203.0.11.7', \@rules), '前方一致の外');
	ok($M->ip_matches('2001:DB8:1::5', \@rules), 'IPv6のCIDR（大文字）');
	ok(!$M->ip_matches('2001:db9::1', \@rules), 'IPv6のCIDRの外');
	ok(!$M->ip_matches('192.0.2.10', ['2001:db8::/32']), 'IPv4とIPv6は比べない');
	ok($M->ip_matches('10.1.2.3', ['10.0.0.0/7']), 'バイトの途中で切れるCIDR');
	ok(!$M->ip_matches('12.0.0.1', ['10.0.0.0/7']));
	ok(!$M->ip_matches('', \@rules), '空');
};

subtest 'ホスト名' => sub {
	my @rules = ('example.net', '.Spam.Example');
	ok($M->host_matches('example.net', \@rules), 'そのホスト');
	ok($M->host_matches('a.b.EXAMPLE.net', \@rules), '下のホスト。大文字と小文字は区別しない');
	ok(!$M->host_matches('badexample.net', \@rules), '名前の途中では当てない');
	ok($M->host_matches('x.spam.example', \@rules), '先頭の . は付けても付けなくてもよい');
	ok(!$M->host_matches('', \@rules), '空');
};

done_testing;
