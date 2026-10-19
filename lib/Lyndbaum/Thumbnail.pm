package Lyndbaum::Thumbnail;
# サムネイル（JPEG）を作る。GD（さくらのレンタルサーバーにプリインストールされている）を使う
#   GD は使うときに読み込む（GD の無い環境でも、サムネイルを作らないだけでほかは動くように）
#   元の画像には手を加えない（Exif もそのまま残す。作者の判断）
use strict;
use warnings;
use utf8;

my $QUALITY = 85;

# 画像（バイト列）からサムネイルの JPEG（バイト列）を作る
#   $kind は jpeg、png、gif、webp。$size は長い辺（px）。元の画像のほうが小さければ、元の大きさのまま
#   JPEG は Exif の向き（Orientation）に合わせて回す（GD は Exif を読まないため。スマートフォンの縦の写真など）
#   透明なところは白にする。読めなければ die する
sub make {
	my ($class, $data, $kind, $size) = @_;
	my $src = _read($data, $kind);

	my ($w, $h) = $src->getBounds;
	my $scale = $w > $size || $h > $size ? $size / ($w > $h ? $w : $h) : 1;
	my ($tw, $th) = (_round($w * $scale) || 1, _round($h * $scale) || 1);
	my $thumb = GD::Image->new($tw, $th, 1);
	$thumb->filledRectangle(0, 0, $tw - 1, $th - 1, $thumb->colorAllocate(255, 255, 255));
	$thumb->alphaBlending(1);
	$thumb->copyResampled($src, 0, 0, 0, 0, $tw, $th, $w, $h);

	$thumb = _orient($thumb, $kind eq 'jpeg' ? $class->orientation($data) : 1);
	return $thumb->jpeg($QUALITY);
}

# 画像（バイト列）を GD の画像（フルカラー。透明なところは残す）にする。JPEG は Exif の向きに合わせて回す
#   サイトのアイコン（Lyndbaum::SiteIcon）が使う。読めなければ die する
sub load {
	my ($class, $data, $kind) = @_;
	my $image = _read($data, $kind);
	return _orient($image, $kind eq 'jpeg' ? $class->orientation($data) : 1);
}

sub _read {
	my ($data, $kind) = @_;
	require GD;
	GD::Image->trueColor(1);
	my $method = { jpeg => 'newFromJpegData', png => 'newFromPngData', gif => 'newFromGifData', webp => 'newFromWebpData' }->{$kind}
		// die "サムネイルを作れない種類です: $kind\n";
	die "この GD は $kind を読めません\n" if !GD::Image->can($method);
	# フルカラーで読む引数があるのは PNG と JPEG だけ（GIF と WebP に渡すと、引数の数が違うので die する）
	my $image = ($kind eq 'png' || $kind eq 'jpeg' ? GD::Image->$method($data, 1) : GD::Image->$method($data))
		// die "画像を読めません\n";
	return $image if $image->isTrueColor;
	# GIF は256色の画像になるので、フルカラーの画像に写す（透明な色のところは透明のまま）
	my ($w, $h) = $image->getBounds;
	my $true = GD::Image->new($w, $h, 1);
	$true->alphaBlending(0);
	$true->saveAlpha(1);
	$true->filledRectangle(0, 0, $w - 1, $h - 1, $true->colorAllocateAlpha(0, 0, 0, 127));
	$true->copy($image, 0, 0, 0, 0, $w, $h);
	return $true;
}

sub _round { int($_[0] + 0.5) }

# Exif の向き（1〜8）に合わせて回す・裏返す
#   1 そのまま、2 左右反転、3 180度、4 上下反転、5 左右反転して反時計回りに90度、6 時計回りに90度、
#   7 左右反転して時計回りに90度、8 反時計回りに90度
sub _orient {
	my ($image, $o) = @_;
	return $image if $o == 1;
	return $image->copyRotate180 if $o == 3;
	return $image->copyRotate90  if $o == 6;
	return $image->copyRotate270 if $o == 8;
	if ($o == 2 || $o == 4) {
		$o == 2 ? $image->flipHorizontal : $image->flipVertical;
		return $image;
	}
	if ($o == 5 || $o == 7) {
		$image->flipHorizontal;
		return $o == 5 ? $image->copyRotate270 : $image->copyRotate90;
	}
	return $image;
}

# JPEG の Exif の向き（Orientation、1〜8）。無ければ 1
#   APP1（Exif）の TIFF の IFD0 から、タグ 0x0112 を探す
sub orientation {
	my ($class, $data) = @_;
	my $pos = 2;
	while ($pos + 4 <= length $data) {
		my ($marker, $type, $len) = unpack 'CCn', substr($data, $pos, 4);
		return 1 if $marker != 0xFF || $type == 0xDA || $type == 0xD9;   # 画像のデータが始まったら終わり
		if ($type == 0xE1 && substr($data, $pos + 4, 6) eq "Exif\0\0") {
			my $tiff = substr $data, $pos + 10, $len - 8;
			my $order = substr $tiff, 0, 2;
			my ($s, $l) = $order eq 'II' ? ('v', 'V') : $order eq 'MM' ? ('n', 'N') : return 1;
			my $ifd = unpack $l, substr($tiff, 4, 4);
			return 1 if $ifd + 2 > length $tiff;
			my $count = unpack $s, substr($tiff, $ifd, 2);
			for my $i (0 .. $count - 1) {
				my $entry = $ifd + 2 + $i * 12;
				last if $entry + 12 > length $tiff;
				next if unpack($s, substr($tiff, $entry, 2)) != 0x0112;
				my $value = unpack $s, substr($tiff, $entry + 8, 2);
				return $value >= 1 && $value <= 8 ? $value : 1;
			}
			return 1;
		}
		$pos += 2 + $len;
	}
	return 1;
}

1;
