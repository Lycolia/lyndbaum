package AdminTest;
# 管理画面のテストの補助。管理者を登録したテスト用のアプリに、リクエストを送る
#
#   my $t = AdminTest->new;          # テスト用のアプリを作り、管理者 admin を登録する
#   my $res = $t->request(GET => '/admin?status=held', cookie => $cookie);
#   my ($cookie) = $t->login;
use strict;
use warnings;
use utf8;

use Encode qw(encode_utf8);
use Lyndbaum::App;
use Lyndbaum::Model::Admin;
use Lyndbaum::Model::Setting;
use Lyndbaum::Password;
use TestUtil qw(new_test_app);

our $ORIGIN   = 'https://blog.example';
our $LOGIN    = 'admin';
our $PASSWORD = 'correct horse battery';

# テストを速くするため、反復回数を減らす
$Lyndbaum::Password::ITERATIONS = 1000;

sub new {
	my ($class) = @_;
	my $app = new_test_app();
	Lyndbaum::Model::Setting->set($app->db, blog_title => 'テストのブログ');
	Lyndbaum::Model::Admin->set_password($app->db, $LOGIN, $PASSWORD);
	return bless { app => $app }, $class;
}

sub app { $_[0]{app} }
sub dbh { $_[0]{app}->db }

# $path にはクエリを付けてよい
# %opt：body（フォームの値の配列）、cookie、origin（undef なら付けない）、ip、env（足す環境変数）
#       raw_body と content_type を渡すと、その本文をそのまま送る（ファイルを送るフォームなど）
sub request {
	my ($self, $method, $path, %opt) = @_;
	my ($path_info, $query) = split /\?/, $path, 2;
	my @kv = @{ $opt{body} // [] };
	my @pairs;
	while (my ($key, $value) = splice @kv, 0, 2) {
		push @pairs, join '=', map { _escape($_) } $key, $value;
	}
	my $body = $opt{raw_body} // join '&', @pairs;
	my $type = $opt{content_type} // 'application/x-www-form-urlencoded';
	open my $input, '<', \$body or die $!;
	# 1リクエストごとにアプリを作り直す（設定などを使い回さないため）
	my $app = Lyndbaum::App->new(root => $self->{app}{root}, config => $self->{app}->config);
	return $app->handle({
		REQUEST_METHOD => $method,
		PATH_INFO      => encode_utf8($path_info),
		QUERY_STRING   => $query // '',
		HTTP_HOST      => 'blog.example',
		HTTPS          => 'on',
		REMOTE_ADDR    => $opt{ip} // '192.0.2.1',
		($method eq 'POST' ? (CONTENT_TYPE => $type, CONTENT_LENGTH => length $body) : ()),
		(exists $opt{origin} ? (defined $opt{origin} ? (HTTP_ORIGIN => $opt{origin}) : ()) : (HTTP_ORIGIN => $ORIGIN)),
		(defined $opt{cookie} ? (HTTP_COOKIE => $opt{cookie}) : ()),
		%{ $opt{env} // {} },
	}, input => $input);
}

# ログインして、Cookie の値（lyndbaum_session=…）と応答を返す。%opt は request に渡す
sub login {
	my ($self, %opt) = @_;
	my $res = $self->request(POST => '/admin/login', body => [ login => $LOGIN, password => $PASSWORD ], %opt);
	my ($cookie) = (header($res, 'Set-Cookie') // '') =~ /\A(lyndbaum_session=[^;]+)/;
	return ($cookie, $res);
}

# ログイン中の画面にある CSRF トークン
sub csrf_of {
	my ($self, $cookie) = @_;
	my ($token) = $self->request(GET => '/admin', cookie => $cookie)->body =~ /name="csrf_token" value="([^"]+)"/;
	return $token;
}

sub header {
	my ($res, $name) = @_;
	return ($res->headers_of($name))[0];
}

sub _escape {
	my $bytes = encode_utf8($_[0]);
	$bytes =~ s/([^A-Za-z0-9])/sprintf '%%%02X', ord $1/eg;
	return $bytes;
}

1;
