package Lyndbaum::Model::Session;
# 管理者のログインのセッション
#   Cookie に入れるのはトークンそのもの、DB に保存するのはそのハッシュ
#   （DB の中身が漏れても、そこからログインできないようにするため）
use strict;
use warnings;
use utf8;

use Digest::SHA qw(sha256_hex);
use Lyndbaum::Random qw(random_token);

# セッションの有効期限（秒）。ログインしてからの期間で、使っても延びない
our $LIFETIME = 14 * 24 * 60 * 60;

# 新しいセッションを作り、{ token, csrf_token, expires_at } を返す
sub create {
	my ($class, $dbh, $now) = @_;
	$now //= time;
	$dbh->do('DELETE FROM sessions WHERE expires_at <= ?', undef, $now);
	my %session = (token => random_token(32), csrf_token => random_token(32), expires_at => $now + $LIFETIME);
	$dbh->do('INSERT INTO sessions (token_hash, csrf_token, created_at, expires_at) VALUES (?, ?, ?, ?)', undef,
		sha256_hex($session{token}), $session{csrf_token}, $now, $session{expires_at});
	return \%session;
}

# トークンから有効なセッションを探す。無いか期限切れなら undef
sub find {
	my ($class, $dbh, $token, $now) = @_;
	return undef if !defined $token || $token eq '';
	return $dbh->selectrow_hashref('SELECT csrf_token, created_at, expires_at FROM sessions WHERE token_hash = ? AND expires_at > ?',
		undef, sha256_hex($token), $now // time);
}

sub delete {
	my ($class, $dbh, $token) = @_;
	$dbh->do('DELETE FROM sessions WHERE token_hash = ?', undef, sha256_hex($token // ''));
}

1;
