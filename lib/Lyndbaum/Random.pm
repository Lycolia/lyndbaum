package Lyndbaum::Random;
# 暗号に使える乱数（OSの /dev/urandom から読む）
#   Perl の rand は予測できるので、トークンやソルトには使わない
use strict;
use warnings;
use utf8;

use Exporter 'import';
our @EXPORT_OK = qw(random_bytes random_token);

# $length バイトの乱数（バイト列）
sub random_bytes {
	my ($length) = @_;
	open my $fh, '<:raw', '/dev/urandom' or die "/dev/urandom を開けません: $!\n";
	my $bytes;
	my $read = read $fh, $bytes, $length;
	close $fh;
	die "乱数を読めません\n" if !defined $read || $read != $length;
	return $bytes;
}

# URL や Cookie にそのまま使える乱数の文字列（$length バイトの乱数を base64url にしたもの）
sub random_token {
	my ($length) = @_;
	return _base64url(random_bytes($length // 32));
}

sub _base64url {
	my ($bytes) = @_;
	require MIME::Base64;
	my $text = MIME::Base64::encode_base64($bytes, '');
	$text =~ tr{+/}{-_};
	$text =~ s/=+\z//;
	return $text;
}

1;
