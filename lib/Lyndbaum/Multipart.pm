package Lyndbaum::Multipart;
# multipart/form-data（ファイルを送るフォーム）の本文を読む
#   CGI.pm は Perl 5.22 で標準ライブラリから外れたので使わず、必要なところだけを書く
#   本文はすべてメモリに読んでから分ける（大きさの上限は Lyndbaum::Request が確かめる）
use strict;
use warnings;
use utf8;

use Encode qw(decode_utf8);

# Content-Type から boundary を取り出す。multipart/form-data でなければ undef
sub boundary_of {
	my ($class, $content_type) = @_;
	return undef if ($content_type // '') !~ m{\Amultipart/form-data\s*;}i;
	my ($quoted, $plain) = $content_type =~ /\bboundary=(?:"([^"]+)"|([^\s;]+))/i;
	my $boundary = $quoted // $plain;
	return defined $boundary && length $boundary <= 200 ? $boundary : undef;
}

# 本文（バイト列）を分ける
#   戻り値は（{ 名前 => [値, ...] }, { 名前 => [ファイル, ...] }）
#   値は UTF-8 として読んだ文字列。ファイルは { filename => 名前（文字列）, type => Content-Type, data => 中身（バイト列） }
#   書き方が正しくなければ die する
sub parse {
	my ($class, $body, $boundary) = @_;
	my (%params, %files);
	my $delimiter = "--$boundary";
	my $start = index $body, $delimiter;
	die "フォームの本文が正しくありません\n" if $start < 0;
	my $pos = $start + length $delimiter;
	while (1) {
		# 区切りの直後が -- なら終わり。そうでなければ改行が続く
		last if substr($body, $pos, 2) eq '--';
		die "フォームの本文が正しくありません\n" if substr($body, $pos, 2) ne "\r\n";
		$pos += 2;
		my $header_end = index $body, "\r\n\r\n", $pos;
		die "フォームの本文が正しくありません\n" if $header_end < 0;
		my %header = _headers(substr $body, $pos, $header_end - $pos);
		my $data_start = $header_end + 4;
		my $next = index $body, "\r\n$delimiter", $data_start;
		die "フォームの本文が正しくありません\n" if $next < 0;
		my $data = substr $body, $data_start, $next - $data_start;
		$pos = $next + 2 + length $delimiter;

		my $disposition = $header{'content-disposition'} // next;
		my ($name) = _attr($disposition, 'name');
		next if !defined $name || $name eq '';
		my ($filename) = _attr($disposition, 'filename');
		if (defined $filename) {
			next if $filename eq '' && $data eq '';   # ファイルを選ばずに送られた欄
			push @{ $files{$name} }, { filename => $filename, type => $header{'content-type'} // '', data => $data };
		} else {
			push @{ $params{$name} }, decode_utf8($data);
		}
	}
	return (\%params, \%files);
}

sub _headers {
	my ($text) = @_;
	my %header;
	for my $line (split /\r\n/, $text) {
		my ($key, $value) = $line =~ /\A([^:]+):\s*(.*)\z/ or next;
		$header{ lc $key } = $value;
	}
	return %header;
}

# Content-Disposition の属性（name="…"、filename="…"）。ファイル名は UTF-8 として読む
#   ブラウザは " を %22 にして送るので、%22 だけを戻す
sub _attr {
	my ($disposition, $attr) = @_;
	my ($value) = $disposition =~ /;\s*\Q$attr\E="((?:[^"\\]|\\.)*)"/i or return;
	$value =~ s/%22/"/g;
	return decode_utf8($value);
}

1;
