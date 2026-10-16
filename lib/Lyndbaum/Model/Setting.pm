package Lyndbaum::Model::Setting;
# 管理画面から変えるブログの設定（settings テーブル）
use strict;
use warnings;
use utf8;

use Lyndbaum::CommentSettings;
use Lyndbaum::EditorSettings;

my %DEFAULT = (
	blog_title       => 'Lyndbaum',
	blog_description => '',
	blog_author      => '',   # 書いた人の名前（RSSに出す）。空なら出さない
	per_page         => 5,
	feed_items       => 10,   # RSSに載せる記事の数
	blog_image       => '',   # ブログの画像（OGP。添付ファイルの中のパス）。Lyndbaum::BlogSettings
	sidebar_boxes    => '[]', # サイドバーの自由欄（JSON）。Lyndbaum::SidebarBoxes
	Lyndbaum::CommentSettings->defaults,
	Lyndbaum::EditorSettings->defaults,
);

# 既定値に、DBにある値を重ねて返す
sub all {
	my ($class, $dbh) = @_;
	my %settings = %DEFAULT;
	my $rows = $dbh->selectall_arrayref('SELECT key, value FROM settings');
	$settings{ $_->[0] } = $_->[1] for @$rows;
	return \%settings;
}

sub set {
	my ($class, $dbh, $key, $value) = @_;
	$dbh->do('INSERT OR REPLACE INTO settings (key, value) VALUES (?, ?)', undef, $key, $value);
}

1;
