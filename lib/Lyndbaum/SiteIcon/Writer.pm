package Lyndbaum::SiteIcon::Writer;
# サイトのアイコンの入れ替えと削除（docs/admin.md の「サイトのアイコン」）。管理画面だけで使う
#   URL を作る表示用の部分は Lyndbaum::SiteIcon。公開側のページが GD や書き出しの処理を読み込まないように分けている
use strict;
use warnings;
use utf8;

use Lyndbaum::Branding::Writer;
use Lyndbaum::Model::Setting;
use Lyndbaum::SiteIcon;
use Lyndbaum::Thumbnail;
use Lyndbaum::Upload;

# 入れた画像（PNG、JPEG、WebP、GIF）から書き出し、設定を書き換える。書き出せなければ die する（理由の文）
sub save {
	my ($class, $app, %args) = @_;
	my $kind = Lyndbaum::Upload->kind_of($args{filename}, $args{data}, \@Lyndbaum::Branding::Writer::IMAGE_EXTS);
	# GD の理由の文は分かりにくいので、エラーログにだけ残す
	my $files = eval { $class->make($args{data}, $kind) } // do {
		warn "サイトのアイコンを作れませんでした: $@";
		die "「$args{filename}」を画像として読めませんでした。\n";
	};
	Lyndbaum::Branding::Writer->write_file($app, $_, $files->{$_}) for sort keys %$files;
	Lyndbaum::Model::Setting->set($app->db, site_icon => $args{now} // time);
}

# 入れた画像を消して、既定のロゴに戻す
sub remove {
	my ($class, $app) = @_;
	Lyndbaum::Branding::Writer->remove_file($app, $_) for Lyndbaum::SiteIcon->file_names;
	Lyndbaum::Model::Setting->set($app->db, site_icon => '');
}


# 画像（バイト列）から、書き出すファイルの中身を作る { ファイル名 => バイト列 }
#   apple-touch-icon は、透明なところを白にする（iPhone では透明なところが黒くなるため）
sub make {
	my ($class, $data, $kind) = @_;
	my $square = _square(Lyndbaum::Thumbnail->load($data, $kind));
	return {
		'icon-32.png'          => _resize($square, 32)->png,
		'icon-192.png'         => _resize($square, 192)->png,
		'apple-touch-icon.png' => _resize($square, 180, 1)->png,
		'favicon.ico'          => $class->ico(map { _resize($square, $_)->png } 16, 32),
	};
}

# PNG（バイト列）の並びを、そのまま中に入れた ICO にする。大きさは PNG の IHDR から読む
#   ICO の中身に PNG を入れる形は、今のブラウザならどれも読める
sub ico {
	my ($class, @pngs) = @_;
	my $offset = 6 + 16 * @pngs;
	my ($entries, $images) = ('', '');
	for my $png (@pngs) {
		my ($w, $h) = unpack 'NN', substr($png, 16, 8);
		# 幅と高さは1バイト。256 は 0 と書く
		$entries .= pack 'CCCCvvVV', $w % 256, $h % 256, 0, 0, 1, 32, length $png, $offset;
		$images  .= $png;
		$offset  += length $png;
	}
	return pack('vvv', 0, 1, scalar @pngs) . $entries . $images;
}

# 真ん中を正方形に切り抜く
sub _square {
	my ($image) = @_;
	my ($w, $h) = $image->getBounds;
	return $image if $w == $h;
	my $side = $w < $h ? $w : $h;
	my $square = _canvas($side);
	$square->copy($image, 0, 0, int(($w - $side) / 2), int(($h - $side) / 2), $side, $side);
	return $square;
}

# $size 四方に縮める（拡げもする）。$opaque が真なら、透明なところを白にする
sub _resize {
	my ($image, $size, $opaque) = @_;
	my ($side) = $image->getBounds;
	my $out = _canvas($size, $opaque);
	$out->copyResampled($image, 0, 0, 0, 0, $size, $size, $side, $side);
	return $out;
}

# 透明（$opaque なら白）で塗った、$size 四方のフルカラーの画像
sub _canvas {
	my ($size, $opaque) = @_;
	my $image = GD::Image->new($size, $size, 1);
	if ($opaque) {
		$image->filledRectangle(0, 0, $size - 1, $size - 1, $image->colorAllocate(255, 255, 255));
		$image->alphaBlending(1);
	} else {
		$image->alphaBlending(0);
		$image->saveAlpha(1);
		$image->filledRectangle(0, 0, $size - 1, $size - 1, $image->colorAllocateAlpha(0, 0, 0, 127));
	}
	return $image;
}

1;
