# 外部へのHTTPアクセス（Lyndbaum::HttpClient）
use strict;
use warnings;
use utf8;
use Test::More;

use Lyndbaum::HttpClient;
use Lyndbaum::Version;
use TestUtil ();

# 送った内容を記録して、決まった応答を返す偽物
{
	package FakeHttp;
	sub new { bless { sent => [] }, shift }
	sub request {
		my ($self, $method, $url, $opt) = @_;
		push @{ $self->{sent} }, [ $method, $url, $opt ];
		return { success => 1, status => 200, url => $url, headers => { 'set-cookie' => [ 'a=1', 'b=2' ] }, content => 'ok' };
	}
}

subtest '既定の設定' => sub {
	my $client = Lyndbaum::HttpClient->new;
	my $http = $client->{http};
	isa_ok $http, 'HTTP::Tiny';
	is $http->timeout, 10, '待ち時間';
	is $http->max_size, 1024 * 1024, '読む大きさ';
	is $http->agent, "Lyndbaum/$Lyndbaum::Version::VERSION", 'User-Agentはバージョンつき';
	ok $http->verify_SSL, '証明書を確かめる';

	$http = Lyndbaum::HttpClient->new(timeout => 3, agent => 'Test/1.0', headers => { 'X-A' => 'b' })->{http};
	is $http->timeout, 3, '待ち時間を変える';
	is $http->agent, 'Test/1.0', 'User-Agentを変える';
	is_deeply $http->default_headers, { 'X-A' => 'b' }, '毎回送るヘッダー';
	is $http->max_size, 1024 * 1024, '指定しなかったものは既定のまま';
};

subtest '標準のUser-Agent' => sub {
	my $v = $Lyndbaum::Version::VERSION;
	like $v, qr/\A\d/, 'バージョンがある';
	is(Lyndbaum::HttpClient->default_agent('https://blog.example.com'), "Lyndbaum/$v (+https://blog.example.com)", 'site_urlをカッコに入れる');
	is(Lyndbaum::HttpClient->default_agent(''), "Lyndbaum/$v", 'site_urlが空ならカッコを付けない');
	is(Lyndbaum::HttpClient->default_agent(undef), "Lyndbaum/$v", 'site_urlが無ければカッコを付けない');
	is(Lyndbaum::HttpClient->new(site_url => 'https://blog.example.com')->{http}->agent, "Lyndbaum/$v (+https://blog.example.com)", 'newにsite_urlを渡す');
	is(Lyndbaum::HttpClient->new(site_url => 'https://blog.example.com', agent => 'Test/1.0')->{http}->agent, 'Test/1.0', 'agentを指定すればそちらを使う');
};

subtest 'GETとPOST' => sub {
	my $fake = FakeHttp->new;
	my $client = Lyndbaum::HttpClient->new(http => $fake);
	my $res = $client->get('https://example.com/', headers => { Accept => 'text/html' });
	ok $res->{success}, '応答をそのまま返す';
	is_deeply $fake->{sent}[0], [ GET => 'https://example.com/', { headers => { Accept => 'text/html' } } ], 'GET';

	$client->post_form('http://example.com/form', [ q => 'あ b', n => 1 ]);
	my ($method, $url, $opt) = @{ $fake->{sent}[1] };
	is $method, 'POST', 'POST';
	is $opt->{headers}{'content-type'}, 'application/x-www-form-urlencoded', 'フォームの形';
	is $opt->{content}, 'q=%E3%81%82+b&n=1', '中身を符号化する';
};

subtest 'httpとhttps以外は送らない' => sub {
	my $fake = FakeHttp->new;
	my $client = Lyndbaum::HttpClient->new(http => $fake);
	for my $url ('file:///etc/passwd', 'ftp://example.com/', 'javascript:alert(1)', '//example.com/', '', undef) {
		my $res = $client->get($url);
		ok !$res->{success}, 'URL: ' . ($url // 'undef');
		is $res->{status}, 599, '通信の失敗と同じ形';
	}
	is scalar @{ $fake->{sent} }, 0, '一つも送らない';
	ok $client->get('HTTPS://example.com/')->{success}, 'スキームの大文字小文字は問わない';
};

subtest 'ヘッダーの値' => sub {
	my $res = { headers => { 'content-type' => 'text/html', 'set-cookie' => [ 'a=1', 'b=2' ] } };
	is(Lyndbaum::HttpClient->header($res, 'Content-Type'), 'text/html', '名前の大文字小文字は問わない');
	is(Lyndbaum::HttpClient->header($res, 'set-cookie'), 'a=1, b=2', '複数あればつなぐ');
	is(Lyndbaum::HttpClient->header($res, 'X-None'), undef, '無い');
};

done_testing;
