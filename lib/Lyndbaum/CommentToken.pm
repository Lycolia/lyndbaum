package Lyndbaum::CommentToken;
# コメントのフォームに入れる、署名つきの時刻のトークン
#
#   形：v1.記事ID.発行した時刻.署名（署名は HMAC-SHA256 を base64url にしたもの）
#   フォームを開かずにいきなり送ってくるもの、早すぎるもの、古すぎるものをはじく
use strict;
use warnings;
use utf8;

use Digest::SHA qw(hmac_sha256_base64);
use Encode qw(encode_utf8);

# フォームを出してから、これより早い投稿は人ではないとみなす（秒）
our $MIN_AGE = 3;
# これより古いフォームからの投稿は受け付けない（秒）
our $MAX_AGE = 24 * 60 * 60;

sub issue {
	my ($class, $secret, $article_id, $now) = @_;
	my $payload = join '.', 'v1', $article_id, $now // time;
	return "$payload." . _sign($secret, $payload);
}

# トークンが正しく、その記事のもので、時間の範囲に入っていれば真
sub verify {
	my ($class, $secret, $token, $article_id, $now) = @_;
	my ($version, $id, $issued, $signature) = split /\./, $token // '', 4;
	return 0 if ($version // '') ne 'v1' || !defined $signature;
	require Lyndbaum::Password;
	return 0 if !Lyndbaum::Password::equal($signature, _sign($secret, "v1.$id.$issued"));
	return 0 if $id ne $article_id || $issued !~ /\A\d+\z/;
	my $age = ($now // time) - $issued;
	return $age >= $MIN_AGE && $age <= $MAX_AGE;
}

sub _sign {
	my ($secret, $payload) = @_;
	(my $signature = hmac_sha256_base64($payload, encode_utf8($secret))) =~ tr{+/}{-_};
	return $signature;
}

1;
