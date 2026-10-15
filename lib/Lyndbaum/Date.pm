package Lyndbaum::Date;
# 日時の整形。DBにはUNIX時刻で持ち、表示は日本時間にする
use strict;
use warnings;
use utf8;

use Exporter 'import';
our @EXPORT_OK = qw(format_date parse_input_date);

use Time::Local qw(timegm);

# 日本時間は夏時間がないので、9時間ずらすだけでよい
my $OFFSET = 9 * 60 * 60;

# 表示用の日時と、<time datetime> 用の日時を返す
sub format_date {
	my ($epoch) = @_;
	return undef if !defined $epoch;
	my ($sec, $min, $hour, $mday, $mon, $year) = gmtime($epoch + $OFFSET);
	$year += 1900;
	$mon  += 1;
	return {
		date     => sprintf('%04d-%02d-%02d', $year, $mon, $mday),
		datetime => sprintf('%04d-%02d-%02d %02d:%02d', $year, $mon, $mday, $hour, $min),
		iso      => sprintf('%04d-%02d-%02dT%02d:%02d:%02d+09:00', $year, $mon, $mday, $hour, $min, $sec),
		input    => sprintf('%04d-%02d-%02dT%02d:%02d', $year, $mon, $mday, $hour, $min),   # <input type="datetime-local"> 用
	};
}

# <input type="datetime-local"> の値（日本時間の YYYY-MM-DDTHH:MM。秒は省いてもよい）を UNIX 時刻にする
#   形が違うか、ありえない日時なら undef
sub parse_input_date {
	my ($text) = @_;
	my ($year, $mon, $mday, $hour, $min, $sec) = ($text // '') =~ /\A(\d{4})-(\d\d)-(\d\d)[T ](\d\d):(\d\d)(?::(\d\d))?\z/
		or return undef;
	return undef if $year < 1970 || $mon < 1 || $mon > 12 || $hour > 23 || $min > 59 || ($sec // 0) > 59;
	my $epoch = eval { timegm($sec // 0, $min, $hour, $mday, $mon - 1, $year) } // return undef;
	# timegm は 2月30日などを翌月に繰り越さずに die するが、念のため戻して確かめる
	my (undef, undef, undef, $d, $m) = gmtime $epoch;
	return undef if $d != $mday || $m != $mon - 1;
	return $epoch - $OFFSET;
}

1;
