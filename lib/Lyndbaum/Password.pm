package Lyndbaum::Password;
# パスワードのハッシュ（bcrypt）
#
#   OWASP の Password Storage Cheat Sheet に合わせる：コストは10以上、パスワードは72バイトまで
#   保存する形：$2b$コスト$ソルトとハッシュ（crypt(3) の形。全部で60文字）
#   コストを一緒に保存するので、既定のコストを変えても、今のパスワードはそのまま確かめられる
#   bcrypt の計算は OS の crypt(3) に任せる（XS のモジュールを足さないため。動くかは tools/check-env.pl で確かめる）
#
# crypt で bcrypt になるわけ
#   crypt(3) は、昔の Unix で /etc/passwd のパスワードをハッシュにするために作られた関数で、当時は DES の方式しかなかった。
#   その後、関数名と使い方はそのままで、ソルトの書き出しで方式を選ぶ形に広がった
#   （印なし：DES、$1$：MD5、$2b$：bcrypt、$5$：SHA-256、$6$：SHA-512、$y$：yescrypt）。Perl の crypt は、この crypt(3) を呼ぶ
#   - ハッシュにするときは、ソルトに「$2b$コスト$」と22文字の乱数を渡して、bcrypt を選ぶ
#   - 確かめるときは、保存したハッシュをそのままソルトとして渡す。方式とコストとソルトがそこから読まれるので、同じ結果になれば合っている
#   - $2b$ に対応していない OS では、別の形の文字列か undef が返る。hash は結果が $2b$ の形でなければ die する
use strict;
use warnings;
use utf8;

use Encode qw(encode_utf8);
use MIME::Base64 qw(encode_base64);
use Unicode::Normalize qw(NFC);
use Lyndbaum::Random qw(random_bytes);

# 既定のコスト（OWASPの推奨値）
our $COST = 10;

my $SALT_LENGTH = 16;

# パスワードの決まり：12文字以上、UTF-8 で72バイトまで（bcrypt は72バイトより後ろを無視するため）
#   文字の種類は問わない。ただし NUL は使えない（crypt(3) は NUL の手前で切ってしまうため）
our $MIN_LENGTH = 12;
our $MAX_BYTES  = 72;

my $HASH_PATTERN = qr{\A\$2b\$(0[4-9]|[12][0-9]|3[01])\$[./A-Za-z0-9]{53}\z};

# 決まりに合わなければ、理由の文を返す（合えば undef）
sub format_error {
	my ($class, $password) = @_;
	return 'パスワードを入れてください' if !defined $password || $password eq '';
	return 'パスワードに NUL 文字は使えません' if $password =~ /\0/;
	return "パスワードは${MIN_LENGTH}文字以上にしてください" if length $password < $MIN_LENGTH;
	return "パスワードは UTF-8 で${MAX_BYTES}バイトまでにしてください（ASCII の文字なら${MAX_BYTES}文字、日本語なら24文字ほど）"
		if length _bytes($password) > $MAX_BYTES;
	return undef;
}

# %opt
#   cost  コスト（テストで小さくするときに使う）
sub hash {
	my ($class, $password, %opt) = @_;
	my $cost = $opt{cost} // $COST;
	my $hash = crypt _bytes($password), sprintf('$2b$%02d$%s', $cost, _bcrypt_base64(random_bytes($SALT_LENGTH)));
	die "この環境の crypt(3) は bcrypt に対応していません\n" if !defined $hash || $hash !~ $HASH_PATTERN;
	return $hash;
}

# パスワードが保存したハッシュと合えば真
sub verify {
	my ($class, $password, $stored) = @_;
	return 0 if !defined $stored || $stored !~ $HASH_PATTERN;
	return equal(crypt(_bytes($password), $stored), $stored);
}

# ログイン名が違うときも、パスワードを確かめるのと同じだけ時間をかける
#   かかる時間の違いから、ログイン名が合っているかを知られないようにするため
sub waste_time {
	my ($class, $password) = @_;
	my $ignored = crypt _bytes($password), sprintf('$2b$%02d$%s', $COST, '.' x 22);
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

# ハッシュにかけるバイト列
#   NFC にそろえる（同じ見た目の文字でも、入力した端末によって合成済みかどうかが違うことがあるため）
sub _bytes {
	my ($password) = @_;
	return encode_utf8(NFC($password));
}

# bcrypt の base64（文字の並びが ./A-Za-z0-9 で、= で埋めない）
sub _bcrypt_base64 {
	my ($bytes) = @_;
	(my $text = encode_base64($bytes, '')) =~ tr{A-Za-z0-9+/=}{./A-Za-z0-9}d;
	return $text;
}

1;
