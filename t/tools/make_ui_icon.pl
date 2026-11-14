#!/usr/bin/perl
use strict;
#-------------------------------------------------------------------------------
# UIアイコン（ui-icon）の画像を作り直し、adiary.jsに埋め込む
#-------------------------------------------------------------------------------
# 実行: perl t/tools/make_ui_icon.pl [元の画像]
#
# 元の画像（既定は pub/assets/dist/ui-icon/ui-icon.png。PNGかGIF）を、
# 2色のパレットのPNGにして、次の2つを置き換える。
#	・tools/js/src/adiary.jsの「ui-iconの生成」の埋め込み（Base64）
#	・pub/assets/dist/ui-icon/ui-icon.png（埋め込みと同じものにする）
#
# 元の画像は、左上の画素の色と透明な画素を背景、それ以外をアイコンとする。
# アイコンは1色で描く（色はテーマのCSSで決めるので、何色でもよい）。
#
# adiary.js は、パレットの0番（アイコンの色）をテーマの色に書き換え、CRCを
# 計算し直して使う。そのため、PNGは次の形にする（画像編集ソフトで保存すると、
# 日時（tIME）やガンマ（gAMA）などが入って位置がずれるので、このスクリプトで作る）。
#	IHDR（ビット深度1、パレット）、PLTE（0番：アイコン、1番：背景）、
#	tRNS（0番：不透明、1番：透明）、IDAT、IEND の順。PLTE の中身は先頭から 0x29
#
use FindBin;
use GD ();
use Compress::Zlib ();
use MIME::Base64 ();

my $ROOT = "$FindBin::Bin/../..";
my $SRC  = shift || "$ROOT/pub/assets/dist/ui-icon/ui-icon.png";
my $DIST = "$ROOT/pub/assets/dist/ui-icon/ui-icon.png";
my $JS   = "$ROOT/tools/js/src/adiary.js";

#-------------------------------------------------------------------------------
# 元の画像を読む
#-------------------------------------------------------------------------------
my $im = ($SRC =~ /\.gif$/i ? GD::Image->newFromGif($SRC) : GD::Image->newFromPng($SRC, 1))
	or die "Can't read image: $SRC\n";
my ($w, $h) = $im->getBounds();

# 画素の色（透明なら undef）
sub pixel {
	my ($x, $y) = @_;
	my $c = $im->getPixel($x, $y);
	if ($im->isTrueColor) {
		return undef if ((($c >> 24) & 0x7f) == 0x7f);		# 透明
		return $c & 0xffffff;
	}
	return undef if ($c == $im->transparent);
	my ($r, $g, $b) = $im->rgb($c);
	return ($r << 16) | ($g << 8) | $b;
}
my $bg = pixel(0, 0);

#-------------------------------------------------------------------------------
# 2色のパレットのPNGを作る
#-------------------------------------------------------------------------------
my $raw = '';
my $icons = 0;
for my $y (0 .. $h-1) {
	my $bits = '';
	for my $x (0 .. $w-1) {
		my $c = pixel($x, $y);
		my $is_bg = !defined($c) || defined($bg) && $c == $bg;
		$bits .= $is_bg ? '1' : '0';		# 0番：アイコン、1番：背景
		$icons++ if (!$is_bg);
	}
	$raw .= "\0" . pack('B*', $bits);		# フィルターは0（なし）
}
die "No icon pixels: $SRC\n" if (!$icons);

sub chunk {
	my ($type, $data) = @_;
	return pack('N', length($data)) . $type . $data . pack('N', Compress::Zlib::crc32($type . $data));
}
my $png = "\x89PNG\r\n\x1a\n"
	. chunk('IHDR', pack('NNCCCCC', $w, $h, 1, 3, 0, 0, 0))
	. chunk('PLTE', pack('H*', '0000fffcfcfc'))
	. chunk('tRNS', "\xff\x00")
	. chunk('IDAT', Compress::Zlib::compress($raw, 9))
	. chunk('IEND', '');
die "PLTE is not at 0x25\n" if (substr($png, 0x25, 4) ne 'PLTE');

#-------------------------------------------------------------------------------
# 書き出す
#-------------------------------------------------------------------------------
my $b64 = MIME::Base64::encode_base64($png, '');
{
	open(my $fh, '<:utf8', $JS) || die "$JS: $!\n";
	local $/;
	my $js = <$fh>;
	close($fh);
	my $n = ($js =~ s/(\blet png = atob\( ')[^']*(')/$1$b64$2/);
	die "Embedded image not found: $JS\n" if ($n != 1);
	open($fh, '>:utf8', $JS) || die "$JS: $!\n";
	print $fh $js;
	close($fh);
}
{
	open(my $fh, '>:raw', $DIST) || die "$DIST: $!\n";
	print $fh $png;
	close($fh);
}
print "${w}x${h}, " . length($png) . " bytes\n";
print "updated: tools/js/src/adiary.js, pub/assets/dist/ui-icon/ui-icon.png\n";
print "pub/assets/js/adiary.min.jsを作り直すため、tools/jsでnpm run buildを実行してください\n";
