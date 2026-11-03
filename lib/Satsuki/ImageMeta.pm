use strict;
#-------------------------------------------------------------------------------
# 画像のメタ情報を消す（JPEG, PNG, WebP）
#-------------------------------------------------------------------------------
# 画像のデータは読み直さず、セグメントやチャンクを選んでつなぎ直す（画質は変わらない）。
#
# 標準で消すもの（撮影情報と、表示に要るもの以外）
#	JPEG : XMP（ゲインマップの hdrgm を含むものは残す）、拡張XMP（ぼかし写真の元画像と深度マップなど）、
#	       APP3〜APP13、APP15、APP1とAPP2のその他（Flashpixなど）、コメント、MPFが指していない末尾のデータ
#	PNG  : XMP（iTXt の XML:com.adobe.xmp）。tEXtなどの文字の情報（ComfyUIやdraw.ioの情報）は残す
#	WebP : XMP
# exif => 1 のとき、さらに消すもの
#	JPEG : Exif
#	PNG  : eXIf、tEXt、zTXt、iTXt、tIME
#	WebP : EXIF
# いつも残すもの
#	JPEG : JFIF（APP0）、ICC（APP2）、MPF（APP2）とMPFが指す2枚目以降の画像（Ultra HDRのゲインマップなど）、Adobe（APP14）
#	PNG  : iCCP、sRGB、gAMA、cHRMなどの色の情報
#	WebP : ICCP
#
package Satsuki::ImageMeta;
our $VERSION = '1.00';

#-------------------------------------------------------------------------------
# ●ファイルのメタ情報を消す
#-------------------------------------------------------------------------------
#	$file : 実パス
#	$opt  : { exif => 1 } でExifなども消す
#	ret   : (結果, 減ったバイト数)
#		結果 : 0=成功（消すものが無いときも0）、1=扱わない形式、負=壊れたファイルや書き込みの失敗
#
# 消すものがあるときは、同じフォルダの一時ファイルに書いてから置き換える（途中で失敗しても元は壊れない）
#
sub clean_file {
	my ($file, $opt) = @_;
	my $fh;
	if (!open($fh, '<:raw', $file)) { return (-10, 0); }
	my $data = do { local $/; <$fh> };
	close($fh);

	my ($r, $new) = &clean_data($data, $opt);
	if ($r || !defined $new) { return ($r, 0); }

	my $tmp  = "$file.meta-tmp";
	my $mode = (stat($file))[2] & 07777;
	if (!open($fh, '>:raw', $tmp)) { return (-11, 0); }
	my $ok = print $fh $new;
	$ok = close($fh) && $ok;
	if (!$ok) { unlink($tmp); return (-12, 0); }
	chmod($mode, $tmp);
	if (!rename($tmp, $file)) { unlink($tmp); return (-13, 0); }
	return (0, length($data) - length($new));
}

#-------------------------------------------------------------------------------
# ●データのメタ情報を消す
#-------------------------------------------------------------------------------
#	ret : (結果, 新しいデータ)。消すものが無ければ新しいデータはundef。結果はclean_fileと同じ
#
sub clean_data {
	my ($data, $opt) = @_;
	$opt ||= {};
	if (substr($data, 0, 3) eq "\xFF\xD8\xFF")         { return &clean_jpeg($data, $opt); }
	if (substr($data, 0, 8) eq "\x89PNG\r\n\x1a\n")     { return &clean_png ($data, $opt); }
	if ($data =~ /^RIFF.{4}WEBP/s)                      { return &clean_webp($data, $opt); }
	return (1);
}

################################################################################
# ■JPEG
################################################################################
my $XMP_ID     = "http://ns.adobe.com/xap/1.0/\x00";
my $XMP_EXT_ID = "http://ns.adobe.com/xmp/extension/\x00";

sub clean_jpeg {
	my ($d, $opt) = @_;
	my $len = length($d);

	# SOSまでのセグメント
	my @segs;
	my $mpf;	# MPFのセグメントの番号
	my $p = 2;
	while(1) {
		if ($p + 4 > $len || substr($d, $p, 1) ne "\xFF") { return (-2); }
		my $m = ord(substr($d, $p+1, 1));
		if ($m == 0xFF) { $p++; next; }		# 詰め物
		if ($m == 0xDA) { last; }		# SOS（画像のデータ）
		my $size = unpack('n', substr($d, $p+2, 2)) + 2;
		if ($size < 4 || $p + $size > $len) { return (-2); }
		my $body = substr($d, $p+4, $size-4);
		my $keep = &jpeg_keep($m, $body, $opt);
		push(@segs, { off => $p, size => $size, keep => $keep });
		if ($m == 0xE2 && substr($body, 0, 4) eq "MPF\x00") { $mpf = $#segs; }
		$p += $size;
	}
	my $sos = $p;
	my $eoi = &jpeg_find_eoi($d, $sos);
	if (!$eoi) { return (-3); }

	# 消すバイト数（本体の中）と、MPFより後で消すバイト数
	my $removed = 0;
	my $removed_after_mpf = 0;
	for(my $i=0; $i<=$#segs; $i++) {
		if ($segs[$i]->{keep}) { next; }
		$removed += $segs[$i]->{size};
		if (defined $mpf && $i > $mpf) { $removed_after_mpf += $segs[$i]->{size}; }
	}

	# 末尾のデータ。MPFが指す画像までは残し、その後ろと、MPFが無いときの末尾は消す
	my $tail_end = $eoi;
	my $mpf_body;
	if (defined $mpf) {
		my $s = $segs[$mpf];
		my ($end, $body) = &mpf_fix(substr($d, $s->{off}+4, $s->{size}-4), $s->{off}+8, $d, $eoi,
			$removed, $removed_after_mpf);
		if ($end) {
			$tail_end = $end;
			$mpf_body = $body;
		} else {
			# MPFが読めなければ、何も変えない（ずれた位置を指すMPFにしない）
			return (0);
		}
	}
	if (!$removed && $tail_end == $len) { return (0); }

	my $out = "\xFF\xD8";
	for(my $i=0; $i<=$#segs; $i++) {
		my $s = $segs[$i];
		if (!$s->{keep}) { next; }
		if (defined $mpf && $i == $mpf) {
			$out .= substr($d, $s->{off}, 4) . $mpf_body;
			next;
		}
		$out .= substr($d, $s->{off}, $s->{size});
	}
	$out .= substr($d, $sos, $tail_end - $sos);
	return (0, $out);
}

#-------------------------------------------------------------------------------
# ○残すセグメントか
#-------------------------------------------------------------------------------
sub jpeg_keep {
	my ($m, $body, $opt) = @_;
	if ($m < 0xE0 || $m == 0xE0 || $m == 0xEE) { return 1; }	# DQTやDHTなど、JFIF、Adobe
	if ($m == 0xE1) {
		if (substr($body, 0, 6) eq "Exif\x00\x00") { return !$opt->{exif}; }
		# ゲインマップ（Ultra HDR）の情報を持つXMPは残す。2枚目の画像の場所もここにある
		if (substr($body, 0, length($XMP_ID)) eq $XMP_ID) {
			return ($body =~ /hdrgm|GContainer/) ? 1 : 0;
		}
		return 0;	# 拡張XMPなど
	}
	if ($m == 0xE2) {
		if (substr($body, 0, 12) eq "ICC_PROFILE\x00") { return 1; }
		if (substr($body, 0, 4)  eq "MPF\x00")         { return 1; }
		return 0;
	}
	if ($m >= 0xE3 && $m <= 0xEF) { return 0; }	# APP3〜APP15（APP14以外）
	if ($m == 0xFE) { return 0; }			# コメント
	return 1;
}

#-------------------------------------------------------------------------------
# ○EOIの直後の位置を探す
#-------------------------------------------------------------------------------
# 画像のデータの中の0xFFは、0x00を続けるか（値の0xFF）、RSTn（D0〜D7）。
# プログレッシブなどでは、途中にDHTやSOSのセグメントが挟まるので、長さの分を飛ばす
#
sub jpeg_find_eoi {
	my ($d, $p) = @_;
	my $len = length($d);
	$p += unpack('n', substr($d, $p+2, 2)) + 2;	# SOSのヘッダー
	while(1) {
		$p = index($d, "\xFF", $p);
		if ($p < 0 || $p + 1 >= $len) { return; }
		my $m = ord(substr($d, $p+1, 1));
		if ($m == 0x00 || ($m >= 0xD0 && $m <= 0xD7)) { $p += 2; next; }
		if ($m == 0xFF) { $p++; next; }
		if ($m == 0xD9) { return $p + 2; }
		if ($p + 4 > $len) { return; }
		$p += unpack('n', substr($d, $p+2, 2)) + 2;
	}
}

#-------------------------------------------------------------------------------
# ○MPFの位置を直す
#-------------------------------------------------------------------------------
# MPFの各画像の開始位置は、MPFのヘッダー（エンディアンの印）からの距離で書かれている。
# MPFより後ろのセグメントを消すと、2枚目以降の画像までの距離が縮むので、その分を引く。
# 1枚目（この画像）の大きさも、消した分を引く。
#
#	$body : MPFのセグメントの中身（"MPF\0"から）
#	$hdr  : ファイルの中での、MPFのヘッダーの位置
#	ret   : (2枚目以降の画像の終わりの位置, 直したMPFの中身)。読めなければ空
#
sub mpf_fix {
	my ($body, $hdr, $d, $eoi, $removed, $removed_after) = @_;
	my $t = substr($body, 4);
	my $bo = substr($t, 0, 2);
	if ($bo ne 'II' && $bo ne 'MM') { return; }
	my ($u16, $u32) = $bo eq 'II' ? ('v', 'V') : ('n', 'N');
	if (unpack($u16, substr($t, 2, 2)) != 0x2A) { return; }
	my $ifd = unpack($u32, substr($t, 4, 4));
	if ($ifd + 2 > length($t)) { return; }
	my $num = unpack($u16, substr($t, $ifd, 2));

	my ($count, $offset);
	for(my $i=0; $i<$num; $i++) {
		my $e = $ifd + 2 + $i*12;
		if ($e + 12 > length($t)) { return; }
		if (unpack($u16, substr($t, $e, 2)) != 0xB002) { next; }
		$count  = unpack($u32, substr($t, $e+4, 4));
		$offset = unpack($u32, substr($t, $e+8, 4));
		last;
	}
	if (!$count || $count % 16 || $offset + $count > length($t)) { return; }

	my $end = $eoi;
	for(my $e=$offset; $e<$offset+$count; $e+=16) {
		my $size = unpack($u32, substr($t, $e+4, 4));
		my $off  = unpack($u32, substr($t, $e+8, 4));
		if ($off == 0) {	# この画像
			substr($t, $e+4, 4) = pack($u32, $size - $removed);
			next;
		}
		# 2枚目以降はEOIより後ろにあり、JPEGで始まっているはず
		my $pos = $hdr + $off;
		if ($pos < $eoi || $pos + $size > length($d) || substr($d, $pos, 2) ne "\xFF\xD8") { return; }
		if ($end < $pos + $size) { $end = $pos + $size; }
		substr($t, $e+8, 4) = pack($u32, $off - $removed_after);
	}
	return ($end, substr($body, 0, 4) . $t);
}

################################################################################
# ■PNG
################################################################################
my %PNG_TEXT = map { $_ => 1 } qw(eXIf tEXt zTXt iTXt tIME);

sub clean_png {
	my ($d, $opt) = @_;
	my $len = length($d);
	my $out = substr($d, 0, 8);
	my $p = 8;
	my $changed;
	while(1) {
		if ($p + 12 > $len) { return (-2); }
		my ($size, $type) = unpack('Na4', substr($d, $p, 8));
		my $all = $size + 12;
		if ($p + $all > $len) { return (-2); }
		my $drop;
		if ($opt->{exif} && $PNG_TEXT{$type}) {
			$drop = 1;
		} elsif ($type eq 'iTXt' && substr($d, $p+8, 18) eq "XML:com.adobe.xmp\x00") {
			$drop = 1;
		}
		if ($drop) {
			$changed = 1;
		} else {
			$out .= substr($d, $p, $all);
		}
		$p += $all;
		if ($type eq 'IEND') { last; }
	}
	if ($p < $len) { $changed = 1; }	# IENDより後ろのデータ
	return $changed ? (0, $out) : (0);
}

################################################################################
# ■WebP
################################################################################
sub clean_webp {
	my ($d, $opt) = @_;
	my $riff = unpack('V', substr($d, 4, 4)) + 8;
	if ($riff > length($d)) { return (-2); }

	my $out = '';
	my $p = 12;
	my $changed = $riff < length($d);	# RIFFより後ろのデータ
	my $vp8x;	# 出力の中のVP8Xの位置
	my %has;
	while($p < $riff) {
		if ($p + 8 > $riff) { return (-2); }
		my ($type, $size) = unpack('a4V', substr($d, $p, 8));
		my $all = 8 + $size + ($size & 1);
		if ($p + $all > $riff) { return (-2); }
		if ($type eq 'XMP ' || ($opt->{exif} && $type eq 'EXIF')) {
			$changed = 1;
		} else {
			if ($type eq 'VP8X') { $vp8x = length($out); }
			$has{$type} = 1;
			$out .= substr($d, $p, $all);
		}
		$p += $all;
	}
	if (!$changed) { return (0); }

	# VP8Xの印を、残したチャンクに合わせる
	if (defined $vp8x) {
		my $flags = ord(substr($out, $vp8x+8, 1));
		$flags &= ~0x0C;
		if ($has{EXIF})   { $flags |= 0x08; }
		if ($has{'XMP '}) { $flags |= 0x04; }
		substr($out, $vp8x+8, 1) = chr($flags);
	}
	return (0, 'RIFF' . pack('V', length($out) + 4) . 'WEBP' . $out);
}

1;
