package Lyndbaum::BlogImage;
# ブログの画像（OGPで、記事に画像が無いときやトップページに出すもの。docs/ogp.md の「ブログの画像」）
#   ブログの設定の画面で、画像を入れ替えたり消したりする。入れた画像は、そのまま pub/branding/ に置く（Lyndbaum::Branding）
#   名前は blog-image-時刻.拡張子。入れ替えるとURLが変わるので、OGPを読むサービスに古い画像を使わせない
#   設定の blog_image はその名前。空なら（消したときも）出さない
#   ここは表示用（URL を作る）。入れ替えと削除は Lyndbaum::BlogImage::Writer
use strict;
use warnings;
use utf8;

use Lyndbaum::Branding;

# 置くときの名前（Lyndbaum::BlogImage::Writer も使う）
our $NAME_RE = qr/\Ablog-image-\d+\.(?:png|jpg|webp|gif)\z/;

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

1;
