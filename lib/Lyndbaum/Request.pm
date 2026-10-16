package Lyndbaum::Request;
# CGIの環境変数から、リクエストの情報を取り出す
use strict;
use warnings;
use utf8;

use Encode qw(decode_utf8);

use Lyndbaum::Multipart;

# POST の本文の大きさの上限（バイト）。フォームの送信だけなので小さくてよい
my $MAX_BODY = 1024 * 1024;

# %opt
#   input       POST の本文を読むファイルハンドル（既定は STDIN）
#   max_upload  ファイルを送るフォーム（multipart/form-data）の本文の大きさの上限（バイト。既定は 20MB）
sub new {
	my ($class, $env, %opt) = @_;
	return bless { env => $env, input => $opt{input} // \*STDIN, max_upload => $opt{max_upload} // 20 * 1024 * 1024 }, $class;
}

sub method {
	my ($self) = @_;
	return uc($self->{env}{REQUEST_METHOD} // 'GET');
}

# アプリの中でのパス（先頭は必ず /）
#   /index.cgi/123 のように呼ばれたときは PATH_INFO を使う
#   mod_rewrite で /123 を index.cgi に渡したときは REQUEST_URI から取る
sub path {
	my ($self) = @_;
	return $self->{path} //= do {
		my $env  = $self->{env};
		my $path = $env->{PATH_INFO};
		if (!defined $path || $path eq '') {
			$path = $env->{REQUEST_URI} // '/';
			$path =~ s/\?.*\z//s;
			$path =~ s/%([0-9A-Fa-f]{2})/chr(hex($1))/eg;
		}
		$path = decode_utf8($path);
		$path eq '' ? '/' : $path;
	};
}

# クエリ。QUERY_STRINGだけを使い、REQUEST_URIからは取らない
#   Webサーバーが必ず QUERY_STRING を渡すように設定する（docs/nginx.conf.sample を参照）
sub query_string {
	my ($self) = @_;
	return $self->{env}{QUERY_STRING} // '';
}

# クエリの値。同じ名前が複数あるときは最初のもの
sub param {
	my ($self, $name) = @_;
	my ($first) = $self->params($name);
	return $first;
}

# クエリの値をすべて
sub params {
	my ($self, $name) = @_;
	$self->{params} //= do {
		my %params;
		for my $pair (split /[&;]/, $self->query_string) {
			my ($key, $value) = map { _decode_component($_) } split /=/, $pair, 2;
			push @{ $params{$key} }, $value // '' if defined $key && $key ne '';
		}
		\%params;
	};
	return @{ $self->{params}{$name} // [] };
}

# POST の本文（application/x-www-form-urlencoded）の値。同じ名前が複数あるときは最初のもの
sub body_param {
	my ($self, $name) = @_;
	my ($first) = $self->body_params($name);
	return $first;
}

# POST の本文の値をすべて（同じ名前で複数送られるもの。記事のタグなど）
sub body_params {
	my ($self, $name) = @_;
	$self->_read_form;
	return @{ $self->{body_params}{$name} // [] };
}

# ファイルを送るフォームで送られたファイル [ { filename, type, data }, ... ]（Lyndbaum::Multipart）
sub uploads {
	my ($self, $name) = @_;
	$self->_read_form;
	return @{ $self->{uploads}{$name} // [] };
}

# ファイルを送るフォームの本文が、上限より大きかったか（そのときは本文を読まず、値もファイルも空にする）
sub body_too_large {
	my ($self) = @_;
	$self->_read_form;
	return $self->{too_large} ? 1 : 0;
}

sub _read_form {
	my ($self) = @_;
	return if $self->{body_params};
	$self->{uploads} = {};
	if (my $boundary = $self->method eq 'POST' ? Lyndbaum::Multipart->boundary_of($self->{env}{CONTENT_TYPE}) : undef) {
		my $length = $self->{env}{CONTENT_LENGTH} // '';
		if ($length !~ /\A\d+\z/ || $length > $self->{max_upload}) {
			$self->{too_large} = 1;
			$self->{body_params} = {};
			return;
		}
		@$self{qw(body_params uploads)} = Lyndbaum::Multipart->parse($self->_read($length), $boundary);
		return;
	}
	my %params;
	for my $pair (split /&/, $self->_body) {
		my ($key, $value) = map { _decode_component($_) } split /=/, $pair, 2;
		push @{ $params{$key} }, $value // '' if defined $key && $key ne '';
	}
	$self->{body_params} = \%params;
}

# POST の本文（バイト列）。フォームの送信でなければ空
sub _body {
	my ($self) = @_;
	my $env = $self->{env};
	return '' if $self->method ne 'POST';
	return '' if ($env->{CONTENT_TYPE} // '') !~ m{\Aapplication/x-www-form-urlencoded\s*(?:;|\z)}i;
	my $length = $env->{CONTENT_LENGTH} // 0;
	die "POST の本文が大きすぎます\n" if $length !~ /\A\d+\z/ || $length > $MAX_BODY;
	return $self->_read($length);
}

sub _read {
	my ($self, $length) = @_;
	binmode $self->{input};
	my $body = '';
	while (length $body < $length) {
		my $read = read $self->{input}, $body, $length - length $body, length $body;
		last if !$read;
	}
	return $body;
}

# Cookie の値。無ければ undef
sub cookie {
	my ($self, $name) = @_;
	$self->{cookies} //= do {
		my %cookies;
		for my $pair (split /;\s*/, $self->{env}{HTTP_COOKIE} // '') {
			my ($key, $value) = split /=/, $pair, 2;
			$cookies{$key} //= $value if defined $key && defined $value;
		}
		\%cookies;
	};
	return $self->{cookies}{$name};
}

# 接続してきた IP アドレス
sub remote_addr {
	my ($self) = @_;
	return $self->{env}{REMOTE_ADDR} // '';
}

# 接続してきたホストの名前。WebサーバーがREMOTE_HOSTを渡していればそれ（空でも）、無ければ逆引きする
#   逆引きは $DNS_TIMEOUT 秒で打ち切る。引けなければ空
#   IPv6は逆引きしない（設定していないプロバイダーが多く、関係のない名前が返ることもあるため）
our $DNS_TIMEOUT = 2;
sub remote_host {
	my ($self) = @_;
	return $self->{remote_host} //= do {
		my $env = $self->{env};
		exists $env->{REMOTE_HOST} ? $env->{REMOTE_HOST} // '' : _reverse_lookup($self->remote_addr);
	};
}

sub user_agent {
	my ($self) = @_;
	return decode_utf8($self->{env}{HTTP_USER_AGENT} // '');
}

# 逆引きした名前を正引きし、元のIPアドレスに戻るときだけ使う（FCrDNS）
#   逆引きの名前は、そのIPアドレスを持つ人が自由に付けられるため
#   2回の問い合わせを合わせて $DNS_TIMEOUT 秒で打ち切る
sub _reverse_lookup {
	my ($ip) = @_;
	# IPv4をIPv6の形で書いたもの（::ffff:192.0.2.1）は、中のIPv4で引く
	$ip = $1 if $ip =~ /\A::ffff:(\d+\.\d+\.\d+\.\d+)\z/i;
	return '' if $ip eq '' || $ip =~ /:/;
	my $host = eval {
		local $SIG{ALRM} = sub { die "timeout\n" };
		alarm $DNS_TIMEOUT;
		my $name = _ptr($ip);
		my $confirmed = $name ne '' && grep { $_ eq $ip } _addresses($name);
		alarm 0;
		$confirmed ? $name : '';
	};
	alarm 0;
	return $host // '';
}

# IPv4アドレスの逆引き。引けなければ空
sub _ptr {
	my ($ip) = @_;
	require Socket;
	my $packed = Socket::inet_pton(Socket::AF_INET(), $ip) // return '';
	my ($error, $name) = Socket::getnameinfo(Socket::pack_sockaddr_in(0, $packed), Socket::NI_NAMEREQD());
	return $error ? '' : $name;
}

# 名前の正引き（IPv4のアドレスの一覧）
sub _addresses {
	my ($name) = @_;
	require Socket;
	my ($error, @results) = Socket::getaddrinfo($name, undef, { family => Socket::AF_INET(), socktype => Socket::SOCK_STREAM() });
	return () if $error;
	return map {
		my (undef, $packed) = Socket::unpack_sockaddr_in($_->{addr});
		Socket::inet_ntop(Socket::AF_INET(), $packed);
	} @results;
}

# リクエストの Origin ヘッダー。無ければ Referer の scheme://host[:port] の部分。どちらも無ければ undef
sub origin {
	my ($self) = @_;
	my $env = $self->{env};
	return $env->{HTTP_ORIGIN} if defined $env->{HTTP_ORIGIN} && $env->{HTTP_ORIGIN} ne '';
	return $1 if ($env->{HTTP_REFERER} // '') =~ m{\A(https?://[^/?#]+)}i;
	return undef;
}

# このサイトの scheme://host[:port]（Host ヘッダーから作る）
sub own_origin {
	my ($self) = @_;
	my $env = $self->{env};
	my $https = lc($env->{HTTPS} // '') eq 'on' || lc($env->{REQUEST_SCHEME} // '') eq 'https';
	return ($https ? 'https' : 'http') . '://' . ($env->{HTTP_HOST} // '');
}

sub _decode_component {
	my ($text) = @_;
	$text =~ tr/+/ /;
	$text =~ s/%([0-9A-Fa-f]{2})/chr(hex($1))/eg;
	return decode_utf8($text);
}

1;
