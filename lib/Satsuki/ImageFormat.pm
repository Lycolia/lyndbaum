use strict;
#-------------------------------------------------------------------------------
# 画像の形式の判定と、ImageMagickでの読み込み
#-------------------------------------------------------------------------------
# ImageMagickはファイルの中身で形式を決めるため、拡張子が.pngでも中身がSVGやMVG、
# PostScriptなどなら、その形式として処理してしまう（ImageTragickの入り口）。
# ファイルの先頭のバイトで形式を確かめ、その形式を指定して読み込む。
#
# 扱う形式：JPEG, PNG（APNGはPNGとして1枚目を読む）, GIF, WebP, AVIF
#
package Satsuki::ImageFormat;
our $VERSION = '1.00';
################################################################################
# ■メイン
################################################################################
#-------------------------------------------------------------------------------
# ●ImageMagickで読み込む
#-------------------------------------------------------------------------------
# $img  : Image::Magickオブジェクト
# $file : 読み込むファイル（実パス）
# $opt->{first} : 真なら1枚目だけ読む（アニメーションの全コマを読むと、ImageMagickの上限を超えることがある）
# ret   : 成功なら空。失敗ならエラーメッセージ（Image::MagickのReadと同じ）
#
sub read {
	my ($img, $file, $opt) = @_;
	my $format = &detect($file);
	if (!$format) { return "Unsupported image format: $file"; }
	return $img->Read("$format:$file" . ($opt && $opt->{first} ? '[0]' : ''));
}

#-------------------------------------------------------------------------------
# ●形式を判定する
#-------------------------------------------------------------------------------
# ret : ImageMagickの形式名（jpeg, png, gif, webp, avif）。扱えない形式ならundef
#
sub detect {
	my $file = shift;
	my $fh;
	if (!open($fh, '<', $file)) { return; }
	binmode($fh);
	read($fh, my $head, 64);
	close($fh);

	if ($head =~ /^\xff\xd8\xff/)            { return 'jpeg'; }
	if ($head =~ /^\x89PNG\r\n\x1a\n/)        { return 'png';  }
	if ($head =~ /^GIF8[79]a/)               { return 'gif';  }
	if ($head =~ /^RIFF.{4}WEBP/s)           { return 'webp'; }

	# AVIF : ISO BMFFのftypボックスの、メジャーブランドか互換ブランドがavifかavis
	if (substr($head, 4, 4) eq 'ftyp') {
		my $size = unpack('N', substr($head, 0, 4));
		if ($size > length($head)) { $size = length($head); }
		my @brands = (substr($head, 8, 4));
		for(my $i=16; $i+4 <= $size; $i+=4) {
			push(@brands, substr($head, $i, 4));
		}
		if (grep { $_ eq 'avif' || $_ eq 'avis' } @brands) { return 'avif'; }
	}
	return;
}

#-------------------------------------------------------------------------------
# ●縦と横の大きさを読む
#-------------------------------------------------------------------------------
# ファイルの先頭だけを読み、ImageMagickは使わない（記事のHTMLにwidthとheightを書くため）
# JPEGはExifの向きが縦（5〜8）なら、AVIFは回転（irot）が90度か270度なら、表示に合わせて縦と横を入れ替える
#
# ret : (幅, 高さ)。読めない形式や壊れたファイルなら空
#
sub get_size {
	my $file = shift;
	my $format = &detect($file) || return;
	my $fh;
	if (!open($fh, '<', $file)) { return; }
	binmode($fh);
	my @size;
	if    ($format eq 'jpeg') { @size = &jpeg_size($fh); }
	elsif ($format eq 'png' ) { read($fh, my $h, 24); @size = unpack('NN', substr($h, 16, 8)); }
	elsif ($format eq 'gif' ) { read($fh, my $h, 10); @size = unpack('vv', substr($h, 6, 4)); }
	elsif ($format eq 'webp') { @size = &webp_size($fh); }
	elsif ($format eq 'avif') { @size = &avif_size($fh); }
	close($fh);
	if (!$size[0] || !$size[1]) { return; }
	return @size;
}

sub jpeg_size {
	my $fh = shift;
	my $rotate;
	read($fh, my $soi, 2);
	while(1) {
		read($fh, my $m, 4) == 4 || return;
		my ($ff, $marker, $len) = unpack('CCn', $m);
		if ($ff != 0xff) { return; }
		# SOF0〜SOF15（DHT、JPG、DACを除く）に大きさがある
		if ($marker >= 0xc0 && $marker <= 0xcf && $marker != 0xc4 && $marker != 0xc8 && $marker != 0xcc) {
			read($fh, my $sof, 5) == 5 || return;
			my ($h, $w) = unpack('xnn', $sof);
			return $rotate ? ($h, $w) : ($w, $h);
		}
		if ($len < 2) { return; }
		read($fh, my $data, $len-2) == $len-2 || return;
		if ($marker == 0xe1 && substr($data, 0, 6) eq "Exif\0\0") {
			my $o = &exif_orientation(substr($data, 6));
			$rotate = ($o >= 5 && $o <= 8);
		}
	}
}

# ExifのIFD0から向き（0x0112）を読む
sub exif_orientation {
	my $tiff = shift;
	my $le   = substr($tiff, 0, 2) eq 'II';
	my $u16  = $le ? 'v' : 'n';
	my $u32  = $le ? 'V' : 'N';
	my $ifd  = unpack($u32, substr($tiff, 4, 4));
	if ($ifd + 2 > length($tiff)) { return; }
	my $num  = unpack($u16, substr($tiff, $ifd, 2));
	for(my $i=0; $i<$num; $i++) {
		my $p = $ifd + 2 + $i*12;
		if ($p + 12 > length($tiff)) { return; }
		if (unpack($u16, substr($tiff, $p, 2)) == 0x0112) {
			return unpack($u16, substr($tiff, $p+8, 2));
		}
	}
	return;
}

sub webp_size {
	my $fh = shift;
	read($fh, my $h, 30) == 30 || return;
	my $chunk = substr($h, 12, 4);
	if ($chunk eq 'VP8 ') {		# 非可逆
		my ($w, $h2) = unpack('vv', substr($h, 26, 4));
		return ($w & 0x3fff, $h2 & 0x3fff);
	}
	if ($chunk eq 'VP8L') {		# 可逆
		my $b = unpack('V', substr($h, 21, 4));
		return (($b & 0x3fff) + 1, (($b >> 14) & 0x3fff) + 1);
	}
	if ($chunk eq 'VP8X') {		# 拡張形式（アニメーションなど）
		my @b = unpack('C6', substr($h, 24, 6));
		return (1 + ($b[0] | $b[1]<<8 | $b[2]<<16), 1 + ($b[3] | $b[4]<<8 | $b[5]<<16));
	}
	return;
}

#-------------------------------------------------------------------------------
# ○AVIFの大きさ
#-------------------------------------------------------------------------------
# metaボックスの中の、主画像（pitm）に結び付いた（ipma）プロパティ（ipco）の ispe と irot を読む
#
sub avif_size {
	my $fh = shift;
	read($fh, my $d, 65536);
	my $meta = &bmff_box($d, 0, length($d), 'meta') || return;
	my ($ms, $me) = ($meta->[0] + 4, $meta->[1]);	# metaはFullBox
	my $pitm = &bmff_box($d, $ms, $me, 'pitm') || return;
	my $iprp = &bmff_box($d, $ms, $me, 'iprp') || return;
	my $ipco = &bmff_box($d, $iprp->[0], $iprp->[1], 'ipco') || return;
	my $ipma = &bmff_box($d, $iprp->[0], $iprp->[1], 'ipma') || return;

	my $pver = ord(substr($d, $pitm->[0], 1));
	my $primary = $pver ? unpack('N', substr($d, $pitm->[0]+4, 4)) : unpack('n', substr($d, $pitm->[0]+4, 2));

	# ipcoの中のプロパティ（1から数える）
	my @props = (undef);
	for(my $p=$ipco->[0]; $p+8 <= $ipco->[1]; ) {
		my ($size, $type) = unpack('Na4', substr($d, $p, 8));
		if ($size < 8) { return; }
		push(@props, [$type, $p+8]);
		$p += $size;
	}

	# ipmaから、主画像のプロパティの番号を拾う
	my ($ver, $flags) = (ord(substr($d, $ipma->[0], 1)), unpack('N', substr($d, $ipma->[0], 4)) & 0xffffff);
	my $p = $ipma->[0] + 4;
	my $count = unpack('N', substr($d, $p, 4));
	$p += 4;
	my @idx;
	for(my $i=0; $i<$count && $p < $ipma->[1]; $i++) {
		my $id = $ver ? unpack('N', substr($d, $p, 4)) : unpack('n', substr($d, $p, 2));
		$p += $ver ? 4 : 2;
		my $n = ord(substr($d, $p++, 1));
		for(my $j=0; $j<$n; $j++) {
			my $x;
			if ($flags & 1) { $x = unpack('n', substr($d, $p, 2)) & 0x7fff; $p+=2; }
			else            { $x = ord(substr($d, $p, 1)) & 0x7f;           $p++;  }
			if ($id == $primary) { push(@idx, $x); }
		}
	}

	my ($w, $h, $rot);
	foreach(@idx) {
		my $prop = $props[$_] || next;
		if ($prop->[0] eq 'ispe') { ($w, $h) = unpack('NN', substr($d, $prop->[1]+4, 8)); }
		if ($prop->[0] eq 'irot') { $rot = ord(substr($d, $prop->[1], 1)) & 3; }
	}
	if (!$w || !$h) { return; }
	return ($rot == 1 || $rot == 3) ? ($h, $w) : ($w, $h);
}

# 範囲の中から、その種類のボックスを探す。ret : [中身の始め, 終わり]
sub bmff_box {
	my ($d, $p, $end, $want) = @_;
	while($p + 8 <= $end) {
		my ($size, $type) = unpack('Na4', substr($d, $p, 8));
		my $hd = 8;
		if ($size == 1) { $size = unpack('N', substr($d, $p+12, 4)); $hd = 16; }	# 64bitの大きさ（4GB未満のみ）
		if ($size == 0) { $size = $end - $p; }
		if ($size < $hd || $p + $size > $end) { return; }
		if ($type eq $want) { return [$p + $hd, $p + $size]; }
		$p += $size;
	}
	return;
}

################################################################################
# ■サムネイル
################################################################################
our $AVIF;	# AVIFを書けるか（試しに書いた結果を覚えておく）

#-------------------------------------------------------------------------------
# ●ImageMagickでAVIFを書けるか
#-------------------------------------------------------------------------------
# 形式の一覧にあっても、AV1のエンコーダーが無いと書けないので、小さな画像を実際に書いて確かめる
#
sub can_write_avif {
	if (defined $AVIF) { return $AVIF; }
	$AVIF = 0;
	eval {
		require Image::Magick;
		my $img = Image::Magick->new(size => '8x8');
		$img->Read('xc:white');
		my ($blob) = $img->ImageToBlob(magick => 'AVIF');
		if (length($blob) && substr($blob, 4, 4) eq 'ftyp') { $AVIF = 1; }
	};
	return $AVIF;
}

#-------------------------------------------------------------------------------
# ●サムネイルを作る
#-------------------------------------------------------------------------------
# Exifの向きのとおりに回転し、メタ情報を消して、縮めて書き出す。
# 色を正しく出すため、ICCプロファイルだけは残す（sRGBでない写真の色が変わらないように）
#
#	$src  : 読む画像の実パス
#	$dest : 書き出す実パス。拡張子が .avif ならAVIF、ほかはJPEG
#	$size : 長い辺の大きさ。これより小さい画像は縮めない
#	$opt  : { quality => 画質（既定はAVIFが65、JPEGが80）, 'jpeg:size' => 読み込みの大きさのヒント }
#	ret   : 0=成功、-99=ImageMagickが無い、-1=読めない、-2=縮められない、-3=書けない
#
# 書き出しの設定（画質など）は、読み込んだ入れ物（$img）に設定する。$img->[0] に差し替えると効かない
#
sub make_thumbnail {
	my ($src, $dest, $size, $opt) = @_;
	$opt ||= {};
	my $avif    = ($dest =~ /\.avif$/i);
	my $quality = $opt->{quality} || ($avif ? 65 : 80);

	eval { require Image::Magick; };
	if ($@) { return -99; }
	my $img = Image::Magick->new( 'jpeg:size' => "$size x $size" );

	my ($w, $h);
	eval {
		my $err = &read($img, $src, { first => 1 });	# 1枚目だけ読む
		if ($err && !@$img) { die $err; }
		$#$img = 0;			# アニメーションは1枚目だけ
		$img->AutoOrient();
		($w, $h) = $img->Get('width', 'height');
	};
	if ($@ || !$w || !$h) { return -1; }

	if ($w<=$size && $h<=$size) {
		$size = 0;	# 縮めない
	} elsif ($w>$h) {
		$h = int($h*($size/$w)) || 1;
		$w = $size;
	} else {
		$w = int($w*($size/$h)) || 1;
		$h = $size;
	}
	if ($size) {
		my $err = eval { $img->Thumbnail(width => $w, height => $h); };
		if ($@ || $err) { return -2; }
	}

	# メタ情報を消す（ICCは残す）
	my $icc = $img->Get('icc');
	$img->Strip();
	if ($icc ne '') { $img->Profile(name => 'icc', profile => $icc); }

	$img->Set( quality => $quality );
	$img->Set( 'sampling-factor' => '2x2,1x1,1x1' );	# 4:2:0
	my $blob;
	if ($avif) {
		$img->Set( 'heic:speed' => 6 );
		($blob) = $img->ImageToBlob( magick => 'AVIF' );
	} else {
		$img->Set( interlace => 'Plane' );		# プログレッシブ
		($blob) = $img->ImageToBlob( magick => 'JPEG' );
	}
	if (!length($blob)) { return -3; }

	# 一時ファイルに書いてから置き換える（書きかけのサムネイルを見せない）
	my $tmp = "$dest.tmp";
	my $fh;
	if (!open($fh, '>:raw', $tmp)) { return -3; }
	my $ok = print $fh $blob;
	$ok = close($fh) && $ok;
	if (!$ok || !rename($tmp, $dest)) { unlink($tmp); return -3; }
	return 0;
}

1;
