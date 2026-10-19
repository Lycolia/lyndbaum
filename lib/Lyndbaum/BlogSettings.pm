package Lyndbaum::BlogSettings;
# ブログの設定の項目（settingsテーブルに保存する）
#   項目の書き方は Lyndbaum::SettingsForm。既定値は Lyndbaum::Model::Setting
#   サイトのアイコンとブログの画像は、同じ画面の別のフォームで入れ替える（Lyndbaum::SiteIcon、Lyndbaum::BlogImage）
use strict;
use warnings;
use utf8;

use Lyndbaum::SettingsForm;

our @FIELDS = (
	{ key => 'blog_title',       type => 'text', required => 1, max => 100, label => 'ブログの名前' },
	{ key => 'blog_description', type => 'text', max => 300, label => 'ブログの説明',
	  help => 'ページの上と、トップページの説明（meta description、OGP）に出します。' },
	{ key => 'blog_author',      type => 'text', max => 100, label => '書いた人の名前', help => 'RSSに出します。空なら出しません。' },
	{ key => 'per_page',         type => 'int', min => 1, max => 100, label => '1ページに出す記事の数' },
	{ key => 'feed_items',       type => 'int', min => 1, max => 100, label => 'RSSに載せる記事の数' },
);

sub fields { \@FIELDS }

sub parse_form {
	my ($class, $get) = @_;
	return Lyndbaum::SettingsForm->parse(\@FIELDS, $get);
}

1;
