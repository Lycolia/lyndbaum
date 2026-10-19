package Lyndbaum::HttpClient;
# 外部へのHTTPアクセス（HTTP::Tinyを包んだもの）
#   既定で、待ち時間と読む大きさに上限を設け、httpsの証明書を確かめる
#   応答はHTTP::Tinyと同じ形のハッシュ（success、status、reason、headers、content）。
#   通信できなかったときもdieせず、status 599の応答を返す（HTTP::Tinyと同じ）
use strict;
use warnings;
use utf8;

use HTTP::Tiny;
use Lyndbaum::Version;

my %DEFAULT = (
	timeout      => 10,              # 秒
	max_size     => 1024 * 1024,     # 読むのは1MBまで
	max_redirect => 5,
);

# %opt
#   timeout、max_size、max_redirect  上の%DEFAULTを参照
#   agent     User-Agent。無ければdefault_agent(site_url)を使う
#   site_url  User-Agentに入れるサイトのURL
#   headers   毎回送るヘッダー（ハッシュ）
#   http      HTTP::Tinyと同じrequestを持つオブジェクト（テスト用）
sub new {
	my ($class, %opt) = @_;
	my %conf = map { $_ => $opt{$_} // $DEFAULT{$_} } keys %DEFAULT;
	$conf{agent} = $opt{agent} // $class->default_agent($opt{site_url});
	my $http = $opt{http} // HTTP::Tiny->new(
		%conf,
		verify_SSL      => 1,
		default_headers => $opt{headers} // {},
	);
	return bless { http => $http }, $class;
}

# 標準のUser-Agent。Lyndbaum/0.1-beta6 (+https://blog.example.jp)の形で、site_urlが無ければカッコを付けない
sub default_agent {
	my ($class, $site_url) = @_;
	my $agent = "Lyndbaum/$Lyndbaum::Version::VERSION";
	return defined $site_url && $site_url ne '' ? "$agent (+$site_url)" : $agent;
}

# GETする。%optはHTTP::Tiny->requestのオプション（headersなど）
sub get {
	my ($self, $url, %opt) = @_;
	return $self->request(GET => $url, %opt);
}

# フォームの形（application/x-www-form-urlencoded）でPOSTする。$formはハッシュか配列のリファレンス
sub post_form {
	my ($self, $url, $form, %opt) = @_;
	return $self->request(POST => $url, %opt,
		headers => { 'content-type' => 'application/x-www-form-urlencoded', %{ $opt{headers} // {} } },
		content => HTTP::Tiny->www_form_urlencode($form));
}

# 任意のメソッドで送る。httpとhttps以外のURLは送らずに失敗の応答を返す
sub request {
	my ($self, $method, $url, %opt) = @_;
	return _error($url, 'URLが空です') if !defined $url || $url eq '';
	return _error($url, 'httpかhttpsのURLではありません') if $url !~ m{\Ahttps?://}i;
	return $self->{http}->request($method, $url, \%opt);
}

# 応答のヘッダーの値。同じ名前が複数あればカンマでつなぐ。無ければundef
sub header {
	my ($class, $res, $name) = @_;
	my $value = $res->{headers}{ lc $name };
	return ref $value ? join(', ', @$value) : $value;
}

# HTTP::Tinyが通信の失敗に返すのと同じ形の応答
sub _error {
	my ($url, $reason) = @_;
	return { url => $url // '', success => '', status => 599, reason => 'Internal Exception',
		headers => { 'content-type' => 'text/plain' }, content => "$reason\n" };
}

1;
