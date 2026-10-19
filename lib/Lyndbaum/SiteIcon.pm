package Lyndbaum::SiteIcon;
# サイトのアイコン（favicon）。ブログの設定の画面で、画像を入れ替えたり消したりする（docs/admin.md の「サイトのアイコン」）
#   入れた画像は、真ん中を正方形に切り抜いて、大きさごとのPNGと favicon.ico にし、pub/branding/ に書き出す（Lyndbaum::Branding）
#   入れていなければ（消したときも）、既定のロゴ（pub/assets/logo/）を使う
#   /favicon.icoはWebサーバーが返す（.htaccess、docs/config samples/のnginxの見本。pub/branding/に無ければ既定のロゴ）
#   設定の site_icon は書き出した時刻。空なら既定のロゴ。URLに付けて、入れ替えたときにブラウザの古いアイコンを使わせない
#   ここは表示用（URL を作る）。入れ替えと削除は Lyndbaum::SiteIcon::Writer
use strict;
use warnings;
use utf8;

use Lyndbaum::Branding;

# 書き出すファイル => 既定のロゴ（pub/assets/ の中）
my %FILES = (
	'icon-32.png'          => 'logo/logo-32.png',
	'icon-192.png'         => 'logo/logo-192.png',
	'apple-touch-icon.png' => 'logo/logo-180.png',
	'favicon.ico'          => 'logo/favicon.ico',
);

# テンプレートに渡すURL { icon_32, icon_192, apple_touch_icon }
sub urls {
	my ($class, $app) = @_;
	my $version = $app->settings->{site_icon} // '';
	my $url_of = $version ne '' ? sub { Lyndbaum::Branding->url($_[0]) . "?v=$version" } : sub { $app->url->static($FILES{ $_[0] }) };
	return {
		icon_32          => $url_of->('icon-32.png'),
		icon_192         => $url_of->('icon-192.png'),
		apple_touch_icon => $url_of->('apple-touch-icon.png'),
	};
}

# 書き出すファイルの名前の一覧（Lyndbaum::SiteIcon::Writer が消すときに使う）
sub file_names {
	return sort keys %FILES;
}

# 入れているか（入れていなければ既定のロゴ）
sub custom {
	my ($class, $app) = @_;
	return ($app->settings->{site_icon} // '') ne '';
}

1;
