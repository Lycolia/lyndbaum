package Lyndbaum::BlogImage::Writer;
# ブログの画像の入れ替えと削除（docs/ogp.md の「ブログの画像」）。管理画面と旧データの取り込みで使う
#   URL を作る表示用の部分は Lyndbaum::BlogImage。公開側のページが GD や書き出しの処理を読み込まないように分けている
use strict;
use warnings;
use utf8;

use Encode qw(encode_utf8);
use File::Spec;
use Lyndbaum::BlogImage;
use Lyndbaum::Branding::Writer;
use Lyndbaum::Model::Setting;
use Lyndbaum::Thumbnail;
use Lyndbaum::Upload;

# 種類 => 置くときの拡張子
my %EXT_OF = (png => 'png', jpeg => 'jpg', webp => 'webp', gif => 'gif');

# 入れた画像（PNG、JPEG、WebP、GIF）を置き、設定を書き換える。前の画像は消す。置けなければ die する（理由の文）
#   画像として読めるかは GD で確かめる（中身の先頭だけが正しいファイルを、OGPに出さないように）
sub save {
	my ($class, $app, %args) = @_;
	my $kind = Lyndbaum::Upload->kind_of($args{filename}, $args{data}, \@Lyndbaum::Branding::Writer::IMAGE_EXTS);
	# GD の理由の文は分かりにくいので、エラーログにだけ残す
	eval { Lyndbaum::Thumbnail->load($args{data}, $kind); 1 } or do {
		warn "ブログの画像を読めませんでした: $@";
		die "「$args{filename}」を画像として読めませんでした。\n";
	};
	my $old  = $app->settings->{blog_image} // '';
	my $name = sprintf 'blog-image-%d.%s', $args{now} // time, $EXT_OF{$kind};
	Lyndbaum::Branding::Writer->write_file($app, $name, $args{data});
	Lyndbaum::Model::Setting->set($app->db, blog_image => $name);
	$app->settings->{blog_image} = $name;
	Lyndbaum::Branding::Writer->remove_file($app, $old) if $old =~ $Lyndbaum::BlogImage::NAME_RE && $old ne $name;
	return $name;
}

# 画像を消す
sub remove {
	my ($class, $app) = @_;
	my $old = $app->settings->{blog_image} // '';
	Lyndbaum::Branding::Writer->remove_file($app, $old) if $old =~ $Lyndbaum::BlogImage::NAME_RE;
	Lyndbaum::Model::Setting->set($app->db, blog_image => '');
	$app->settings->{blog_image} = '';
}

# 添付ファイルの中の画像（「フォルダ/名前」）を、ブログの画像として写す。旧データの取り込み（tools/import-adiary.pl）で使う
sub copy_attachment {
	my ($class, $app, $path, %opt) = @_;
	my $file = File::Spec->catfile($app->attachment_dir, split m{/}, $path);
	open my $fh, '<:raw', encode_utf8($file) or die "$file: $!\n";
	my $data = do { local $/; <$fh> };
	close $fh;
	return $class->save($app, filename => $path, data => $data, %opt);
}

1;
