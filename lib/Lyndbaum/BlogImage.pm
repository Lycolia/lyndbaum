package Lyndbaum::BlogImage;
# ブログの画像（OGPで、記事に画像が無いときやトップページに出すもの。docs/ogp.md の「ブログの画像」）
#   ブログの設定の画面で、画像を入れ替えたり消したりする。入れた画像は、そのまま pub/branding/ に置く（Lyndbaum::Branding）
#   名前は blog-image-時刻.拡張子。入れ替えるとURLが変わるので、OGPを読むサービスに古い画像を使わせない
#   設定の blog_image はその名前。空なら（消したときも）出さない
use strict;
use warnings;
use utf8;

use Encode qw(encode_utf8);
use File::Spec;
use Lyndbaum::Branding;
use Lyndbaum::Model::Setting;
use Lyndbaum::Thumbnail;
use Lyndbaum::Upload;

# 種類 => 置くときの拡張子
my %EXT_OF = (png => 'png', jpeg => 'jpg', webp => 'webp', gif => 'gif');
my $NAME_RE = qr/\Ablog-image-\d+\.(?:png|jpg|webp|gif)\z/;

# 画像のURL（サイトの中のパス）。入れていなければ undef
#   書き方の違う値（添付ファイルの中のパスにしていたころの値など）は、入れていないものとする
sub url {
	my ($class, $app) = @_;
	my $name = $app->settings->{blog_image} // '';
	return $name =~ $NAME_RE ? Lyndbaum::Branding->url($name) : undef;
}

sub custom {
	my ($class, $app) = @_;
	return defined $class->url($app);
}

# 入れた画像（PNG、JPEG、WebP、GIF）を置き、設定を書き換える。前の画像は消す。置けなければ die する（理由の文）
#   画像として読めるかは GD で確かめる（中身の先頭だけが正しいファイルを、OGPに出さないように）
sub save {
	my ($class, $app, %args) = @_;
	my $kind = Lyndbaum::Upload->kind_of($args{filename}, $args{data}, \@Lyndbaum::Branding::IMAGE_EXTS);
	# GD の理由の文は分かりにくいので、エラーログにだけ残す
	eval { Lyndbaum::Thumbnail->load($args{data}, $kind); 1 } or do {
		warn "ブログの画像を読めませんでした: $@";
		die "「$args{filename}」を画像として読めませんでした。\n";
	};
	my $old  = $app->settings->{blog_image} // '';
	my $name = sprintf 'blog-image-%d.%s', $args{now} // time, $EXT_OF{$kind};
	Lyndbaum::Branding->write_file($app, $name, $args{data});
	Lyndbaum::Model::Setting->set($app->db, blog_image => $name);
	$app->settings->{blog_image} = $name;
	Lyndbaum::Branding->remove_file($app, $old) if $old =~ $NAME_RE && $old ne $name;
	return $name;
}

# 画像を消す
sub remove {
	my ($class, $app) = @_;
	my $old = $app->settings->{blog_image} // '';
	Lyndbaum::Branding->remove_file($app, $old) if $old =~ $NAME_RE;
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
