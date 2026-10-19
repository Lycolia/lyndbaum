package Lyndbaum::Branding;
# サイトの見た目に使う画像（サイトのアイコン、ブログの画像）の置き場所。pub/branding/
#   ブログの設定の画面で入れ替えたり消したりする（Lyndbaum::SiteIcon、Lyndbaum::BlogImage）。添付ファイル（メディア）とは別に扱う
#   ここは表示用（URL を作る）。ファイルの書き出しと削除は Lyndbaum::Branding::Writer
use strict;
use warnings;
use utf8;

my $URL = '/pub/branding';

sub url {
	my ($class, $name) = @_;
	return "$URL/$name";
}

1;
