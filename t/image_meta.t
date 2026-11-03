use strict;
use utf8;
#-------------------------------------------------------------------------------
# 画像のメタ情報の削除（Satsuki::ImageMeta）と、サムネイル（Satsuki::ImageFormat）のテスト
#-------------------------------------------------------------------------------
# 実行: prove t/image_meta.t
#
use FindBin;
BEGIN { push(@INC, "$FindBin::Bin/lib", "$FindBin::Bin/../lib"); }
use Test::More;
use File::Temp ();
use Image::Magick;
use Satsuki::ImageMeta;
use Satsuki::ImageFormat;
use Satsuki::TextParser::TagPlugin::Tag_image;

binmode(Test::More->builder->$_, ':utf8') foreach (qw(output failure_output todo_output));

my $tmp = File::Temp::tempdir('image-meta-XXXXXX', TMPDIR => 1, CLEANUP => 1);

sub blob {
	my ($magick, $w, $h, $color) = @_;
	my $im = Image::Magick->new(size => "${w}x$h");
	$im->Read("xc:$color");
	my ($b) = $im->ImageToBlob(magick => $magick);
	return $b;
}
sub seg { "\xFF" . chr($_[0]) . pack('n', length($_[1]) + 2) . $_[1] }
sub has { index($_[0], $_[1]) >= 0 }
# SOSからEOIまで（画像のデータ）
sub scan {
	my $d = shift;
	my $p = 2;
	while(ord(substr($d, $p+1, 1)) != 0xDA) { $p += unpack('n', substr($d, $p+2, 2)) + 2; }
	my $e = Satsuki::ImageMeta::jpeg_find_eoi($d, $p);
	return substr($d, $p, $e - $p);
}

my $EXIF = "Exif\0\0II*\0" . pack('V', 8) . pack('v', 0) . pack('V', 0);
my $XMP  = "http://ns.adobe.com/xap/1.0/\0<x:xmpmeta xmlns:x='adobe:ns:meta/'/>";
my $XMPX = "http://ns.adobe.com/xmp/extension/\0" . ('0' x 32) . pack('NN', 10, 0) . 'original!!';
my $ICC  = "ICC_PROFILE\0\1\1" . ('i' x 50);

#-------------------------------------------------------------------------------
subtest 'JPEG' => sub {
	my $base = blob('JPEG', 40, 30, 'red');
	my $body = substr($base, 2);
	my $src  = "\xFF\xD8" . seg(0xE1, $EXIF) . seg(0xE1, $XMP) . seg(0xE1, $XMPX) . seg(0xE2, $ICC)
		. seg(0xE4, 'x' x 200) . seg(0xEE, "Adobe\0\0\0\0\0\0\1") . seg(0xFE, 'comment') . $body . 'TRAILER';

	my ($r, $out) = Satsuki::ImageMeta::clean_data($src, {});
	is($r, 0, '片付けられる');
	ok(has($out, 'Exif'), 'Exifは残る');
	ok(has($out, 'ICC_PROFILE') && has($out, "Adobe\0"), 'ICCとAdobeは残る');
	ok(!has($out, 'xap/1.0') && !has($out, 'original!!') && !has($out, 'comment') && !has($out, "\xFF\xE4"),
		'XMP、拡張XMP、APP4、コメントは消える');
	ok(!has($out, 'TRAILER'), 'MPFが無いときの末尾のデータは消える');
	is(scan($out), scan($src), '画像のデータは変わらない');

	($r, $out) = Satsuki::ImageMeta::clean_data($src, { exif => 1 });
	ok(!has($out, 'Exif') && has($out, 'ICC_PROFILE'), 'exif=>1 ではExifも消え、ICCは残る');

	($r, $out) = Satsuki::ImageMeta::clean_data("\xFF\xD8" . $body, {});
	ok(!$r && !defined $out, '消すものが無ければ書き直さない');

	my $hdr = "http://ns.adobe.com/xap/1.0/\0<x:xmpmeta xmlns:hdrgm='http://ns.adobe.com/hdr-gain-map/1.0/'/>";
	($r, $out) = Satsuki::ImageMeta::clean_data("\xFF\xD8" . seg(0xE1, $hdr) . seg(0xE4, 'x') . $body, {});
	ok(has($out, 'hdrgm'), 'ゲインマップ（hdrgm）のXMPは残る');

	# プログレッシブ（途中にDHTやSOSが挟まる）
	my $im = Image::Magick->new(size => '64x48');
	$im->Read('plasma:');
	$im->Set(interlace => 'Plane');
	my ($prog) = $im->ImageToBlob(magick => 'JPEG');
	my $src2 = "\xFF\xD8" . seg(0xE1, $XMP) . substr($prog, 2);
	($r, $out) = Satsuki::ImageMeta::clean_data($src2, {});
	is(length($out), length($prog), 'プログレッシブのJPEGも末尾まで残る');
	is(scan($out), scan($src2), 'プログレッシブの画像のデータも変わらない');

	($r) = Satsuki::ImageMeta::clean_data("\xFF\xD8\xFF\xE1\xFF\xFF", {});
	ok($r < 0, '壊れたJPEGは失敗にする');
};

#-------------------------------------------------------------------------------
subtest 'JPEGのMPF（Ultra HDRのゲインマップ）' => sub {
	my $gain = blob('JPEG', 20, 15, 'gray');
	my $body = substr(blob('JPEG', 40, 30, 'blue'), 2);

	# MPF：II、IFD（項目1つ：MPEntry）、MPEntry 2つ（16バイトずつ）
	my $mpf = sub {
		my ($size1, $size2, $off2) = @_;
		my $t = "II*\0" . pack('V', 8) . pack('v', 1) . pack('vvVV', 0xB002, 7, 32, 26) . pack('V', 0)
			. pack('VVVvv', 0x030000, $size1, 0, 0, 0) . pack('VVVvv', 0, $size2, $off2, 0, 0);
		return "MPF\0" . $t;
	};
	my $hdr = "http://ns.adobe.com/xap/1.0/\0<x hdrgm:Version='1.0'/>";
	my $junk = seg(0xE4, 'j' x 300);
	# 位置を決めるため、一度組み立てて長さを測る
	my $head = "\xFF\xD8" . seg(0xE1, $EXIF) . seg(0xE1, $hdr);
	my $mpf_len = length(seg(0xE2, $mpf->(0, 0, 0)));
	my $mp_hdr  = length($head) + 8;	# "FF E2 len len MPF\0" の後
	my $primary = length($head) + $mpf_len + length($junk) + length($body);
	my $src = $head . seg(0xE2, $mpf->($primary, length($gain), $primary - $mp_hdr)) . $junk . $body . $gain;

	my ($r, $out) = Satsuki::ImageMeta::clean_data($src, {});
	is($r, 0, '片付けられる');
	ok(!has($out, 'j' x 300), 'MPFより後ろのAPP4は消える');
	ok(has($out, $gain), 'ゲインマップの画像は残る');

	# 直したMPFを読む
	my $p = index($out, "MPF\0") + 4;
	my $t = substr($out, $p);
	my ($size1, $off1) = unpack('x4VV', substr($t, 26, 12));	# MPEntryはTIFFの先頭から26バイト目
	my ($size2, $off2) = unpack('x4VV', substr($t, 42, 12));
	is($size1, $primary - length($junk), '1枚目の大きさから消した分を引く');
	is(substr($out, $p + $off2, length($gain)), $gain, '2枚目の位置が、消した後の位置を指す');
	is($size2, length($gain), '2枚目の大きさは変わらない');

	# MPFが指す先がJPEGでなければ、何も変えない
	my $bad = $head . seg(0xE2, $mpf->($primary, length($gain), 5)) . $junk . $body . $gain;
	($r, $out) = Satsuki::ImageMeta::clean_data($bad, {});
	ok(!$r && !defined $out, 'MPFが読めなければ書き直さない');
};

#-------------------------------------------------------------------------------
subtest 'PNG' => sub {
	my $png = blob('PNG', 8, 8, 'white');
	my $chunk = sub {
		my ($type, $data) = @_;
		return pack('N', length($data)) . $type . $data . pack('N', 0);	# CRCは見ない
	};
	my $iend = index($png, 'IEND') - 4;
	my $src = substr($png, 0, $iend)
		. $chunk->('tEXt', "workflow\0{}") . $chunk->('iTXt', "XML:com.adobe.xmp\0\0\0\0\0<x/>")
		. $chunk->('eXIf', 'II*') . substr($png, $iend) . 'after';

	my ($r, $out) = Satsuki::ImageMeta::clean_data($src, {});
	is($r, 0, '片付けられる');
	ok(has($out, 'workflow') && has($out, 'eXIf'), '文字の情報とExifは残る');
	ok(!has($out, 'com.adobe.xmp') && !has($out, 'after'), 'XMPとIENDより後ろは消える');

	($r, $out) = Satsuki::ImageMeta::clean_data($src, { exif => 1 });
	ok(!has($out, 'workflow') && !has($out, 'eXIf'), 'exif=>1 では文字の情報とExifも消える');
	ok(has($out, 'IHDR') && has($out, 'IDAT') && has($out, 'IEND'), '画像のチャンクは残る');
};

#-------------------------------------------------------------------------------
subtest 'WebP' => sub {
	my $webp = blob('WEBP', 8, 8, 'white');
	my $vp8  = substr($webp, 12);
	my $chunk = sub { my ($t, $d) = @_; $t . pack('V', length($d)) . $d . (length($d) & 1 ? "\0" : '') };
	my $body = $chunk->('VP8X', chr(0x0C) . "\0\0\0" . "\7\0\0\7\0\0") . $vp8 . $chunk->('EXIF', 'II*') . $chunk->('XMP ', '<x/>');
	my $src = 'RIFF' . pack('V', length($body) + 4) . 'WEBP' . $body;

	my ($r, $out) = Satsuki::ImageMeta::clean_data($src, {});
	is($r, 0, '片付けられる');
	ok(!has($out, 'XMP ') && has($out, 'EXIF'), 'XMPは消え、EXIFは残る');
	is(unpack('V', substr($out, 4, 4)), length($out) - 8, 'RIFFの大きさを直す');
	is(ord(substr($out, 20, 1)) & 0x0C, 0x08, 'VP8XのXMPの印を外す');

	($r, $out) = Satsuki::ImageMeta::clean_data($src, { exif => 1 });
	ok(!has($out, 'EXIF'), 'exif=>1 ではEXIFも消える');
	is(ord(substr($out, 20, 1)) & 0x0C, 0, 'VP8XのEXIFの印も外す');
};

#-------------------------------------------------------------------------------
subtest 'ファイルの書き換え' => sub {
	my $file = "$tmp/a.jpg";
	open(my $fh, '>:raw', $file) || die $!;
	print $fh "\xFF\xD8" . seg(0xE1, $XMP) . substr(blob('JPEG', 4, 4, 'red'), 2);
	close($fh);
	chmod(0640, $file);
	my ($r, $saved) = Satsuki::ImageMeta::clean_file($file, {});
	is($r, 0, '書き換えられる');
	ok($saved > 0, '減ったバイト数を返す');
	is((stat($file))[2] & 07777, 0640, 'パーミッションは元のまま');
	ok(!-e "$file.meta-tmp", '一時ファイルが残らない');
	is((Satsuki::ImageMeta::clean_file("$tmp/none.jpg", {}))[0] < 0, 1, '無いファイルは失敗にする');

	open($fh, '>:raw', "$tmp/a.txt") || die $!;
	print $fh "text";
	close($fh);
	is((Satsuki::ImageMeta::clean_file("$tmp/a.txt", {}))[0], 1, '画像でないファイルは扱わない');
};

#-------------------------------------------------------------------------------
subtest 'サムネイル' => sub {
	my $src = "$tmp/photo.jpg";
	my $im = Image::Magick->new(size => '400x300');
	$im->Read('plasma:');
	$im->Write("jpeg:$src");
	# Exifの向き（6 = 時計回りに90度）を足す
	{
		open(my $fh, '<:raw', $src) || die $!;
		my $d = do { local $/; <$fh> };
		close($fh);
		my $exif = "Exif\0\0II*\0" . pack('V', 8) . pack('v', 1) . pack('vvVvv', 0x0112, 3, 1, 6, 0) . pack('V', 0);
		open($fh, '>:raw', $src) || die $!;
		print $fh "\xFF\xD8" . seg(0xE1, $exif) . substr($d, 2);
		close($fh);
	}

	is(Satsuki::ImageFormat::make_thumbnail($src, "$tmp/t.jpg", 100), 0, 'JPEGのサムネイルを作れる');
	is(join('x', Satsuki::ImageFormat::get_size("$tmp/t.jpg")), '75x100', '回転して縮める');
	my $jpg = do { open(my $fh, '<:raw', "$tmp/t.jpg"); local $/; <$fh> };
	ok(!has($jpg, 'Exif'), 'Exifを持たない');
	ok(has($jpg, "\xFF\xC2"), 'プログレッシブ（SOF2）');

	SKIP: {
		skip('ImageMagickでAVIFを書けない', 3) if !Satsuki::ImageFormat::can_write_avif();
		is(Satsuki::ImageFormat::make_thumbnail($src, "$tmp/t.avif", 100), 0, 'AVIFのサムネイルを作れる');
		is(Satsuki::ImageFormat::detect("$tmp/t.avif"), 'avif', 'AVIFで書く');
		is(join('x', Satsuki::ImageFormat::get_size("$tmp/t.avif")), '75x100', 'AVIFの大きさを読める');
	}
	is(Satsuki::ImageFormat::make_thumbnail("$tmp/none.jpg", "$tmp/x.jpg", 100), -1, '読めない画像は失敗にする');
	ok(!glob("$tmp/*.tmp"), '一時ファイルが残らない');
};

#-------------------------------------------------------------------------------
subtest '記事のサムネイルのURL' => sub {
	my $ROBJ = { Basepath => '/' };
	chdir($tmp) || die $!;
	mkdir('pub'); mkdir('pub/a'); mkdir('pub/a/.thumbnail');
	my $url = 'pub/a/.thumbnail/x.png.jpg';
	is(Satsuki::TextParser::TagPlugin::Tag_image::thumbnail_url($ROBJ, $url), $url, 'AVIFが無ければJPEGのまま');
	open(my $fh, '>', 'pub/a/.thumbnail/x.png.avif') || die $!;
	close($fh);
	is(Satsuki::TextParser::TagPlugin::Tag_image::thumbnail_url($ROBJ, $url), 'pub/a/.thumbnail/x.png.avif', 'AVIFがあればAVIFにする');
	is(Satsuki::TextParser::TagPlugin::Tag_image::thumbnail_url($ROBJ, '/pub/a/.thumbnail/x.png.jpg'), '/pub/a/.thumbnail/x.png.avif', '/で始まるURLも同じ');
	is(Satsuki::TextParser::TagPlugin::Tag_image::thumbnail_url($ROBJ, 'pub/a/x.png'), 'pub/a/x.png', 'サムネイルでなければそのまま');
	chdir($FindBin::Bin);
};

done_testing();
