package Lyndbaum::Password;
# パスワードのハッシュ（PBKDF2-HMAC-SHA256）
#
#   保存する形：pbkdf2-sha256$反復回数$ソルト$ハッシュ（ソルトとハッシュは base64）
#   反復回数を一緒に保存するので、既定の回数を変えても、今のパスワードはそのまま確かめられる
use strict;
use warnings;
use utf8;

use Digest::SHA qw(hmac_sha256);
use Encode qw(encode_utf8);
use MIME::Base64 qw(encode_base64 decode_base64);
use Lyndbaum::Random qw(random_bytes);

# 既定の反復回数（OWASPの推奨値）
our $ITERATIONS = 600_000;

my $SALT_LENGTH = 16;

# パスワードの決まり：印字できる ASCII の文字（空白から ~ まで）を12文字以上、64文字まで
#   64バイト以内なら、HMAC の鍵が SHA-256 のブロックの長さに収まり、反復のたびに鍵をハッシュし直さない。
#   長いパスワードで PBKDF2 を重くされないようにするため（ASCII なら1文字が1バイトなので、64文字で64バイト）
our $MIN_LENGTH = 12;
our $MAX_LENGTH = 64;

# 決まりに合わなければ、理由の文を返す（合えば undef）
sub format_error {
	my ($class, $password) = @_;
	return 'パスワードを入れてください' if !defined $password || $password eq '';
	return 'パスワードに使えるのは、ASCII の英数字と記号、空白だけです' if $password =~ /[^\x20-\x7E]/;
	return "パスワードは${MIN_LENGTH}文字以上にしてください" if length $password < $MIN_LENGTH;
	return "パスワードは${MAX_LENGTH}文字までにしてください" if length $password > $MAX_LENGTH;
	return undef;
}

# %opt
#   iterations  反復回数（テストで短くするときに使う）
sub hash {
	my ($class, $password, %opt) = @_;
	my $iterations = $opt{iterations} // $ITERATIONS;
	my $salt = random_bytes($SALT_LENGTH);
	return join '$', 'pbkdf2-sha256', $iterations, encode_base64($salt, ''), encode_base64(_pbkdf2($password, $salt, $iterations), '');
}

# パスワードが保存したハッシュと合えば真
sub verify {
	my ($class, $password, $stored) = @_;
	my ($scheme, $iterations, $salt, $hash) = split /\$/, $stored // '';
	return 0 if ($scheme // '') ne 'pbkdf2-sha256' || ($iterations // '') !~ /\A[1-9]\d*\z/ || !defined $hash;
	return equal(_pbkdf2($password, decode_base64($salt), $iterations), decode_base64($hash));
}

# ログイン名が違うときも、パスワードを確かめるのと同じだけ時間をかける
#   かかる時間の違いから、ログイン名が合っているかを知られないようにするため
sub waste_time {
	my ($class, $password) = @_;
	_pbkdf2($password, "\0" x $SALT_LENGTH, $ITERATIONS);
	return 0;
}

# 2つの文字列を、中身によって時間が変わらないように比べる
sub equal {
	my ($x, $y) = @_;
	return 0 if !defined $x || !defined $y || length $x != length $y;
	my $diff = 0;
	$diff |= ord(substr $x, $_, 1) ^ ord(substr $y, $_, 1) for 0 .. length($x) - 1;
	return $diff == 0;
}

# PBKDF2（RFC 8018）。出力はHMAC-SHA256の1ブロック分（32バイト）
sub _pbkdf2 {
	my ($password, $salt, $iterations) = @_;
	my $key = encode_utf8($password);
	my $u = hmac_sha256($salt . pack('N', 1), $key);
	my $t = $u;
	for (2 .. $iterations) {
		$u = hmac_sha256($u, $key);
		$t ^= $u;
	}
	return $t;
}

1;
