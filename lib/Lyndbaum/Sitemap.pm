package Lyndbaum::Sitemap;
# サイトマップ（sitemaps.org の形。docs/feed.md の「サイトマップ」）
#   静的なファイル（pub/sitemap.xml）として書き出し、Webサーバーがそのまま返す（Lyndbaum::StaticFiles）
#   検索エンジン（Google Search Console など）に、このファイルの URL を登録する
use strict;
use warnings;
use utf8;

use Encode qw(encode_utf8);
use Lyndbaum::Feed;

# 書き出す場所。URL は Lyndbaum::URL->sitemap
#   config.json の sitemap_file で変えられる（テスト用）
my $FILE = 'pub/sitemap.xml';

# サイトマップを書き出し、書き出したファイルのパスを返す
sub write {
	my ($class, $app) = @_;
	require Lyndbaum::StaticFiles;
	return Lyndbaum::StaticFiles->write_file(Lyndbaum::StaticFiles->path_of($app, sitemap_file => $FILE), $class->xml($app));
}

# サイトマップの XML（UTF-8 のバイト列）
#   トップページと、公開している記事とコンテンツページ（下書きとゴミ箱の中は入れない）。記事は ID の順（旧システムと同じ）
#   lastmod は更新日時（UTC）。トップページは、いちばん新しい記事の更新日時
#   changefreq と priority は入れない（旧システムも入れていない。Google は使わない）
sub xml {
	my ($class, $app) = @_;
	my $rows = $app->db->selectall_arrayref(<<'SQL', { Slice => {} });
SELECT slug, updated_at FROM articles
WHERE kind IN ('post', 'page') AND status = 'published' AND deleted_at IS NULL
ORDER BY id
SQL
	my ($latest) = sort { $b <=> $a } map { $_->{updated_at} } @$rows;
	my @urls = (
		[ $app->absolute_url($app->url->top), $latest ],
		map { [ $app->absolute_url($app->url->article($_->{slug})), $_->{updated_at} ] } @$rows,
	);
	return encode_utf8(join "\n",
		'<?xml version="1.0" encoding="UTF-8"?>',
		'<urlset xmlns="http://www.sitemaps.org/schemas/sitemap/0.9">',
		(map {
			my ($loc, $lastmod) = @$_;
			join "\n", '<url>', '<loc>' . Lyndbaum::Feed::escape($loc) . '</loc>',
				(defined $lastmod ? '<lastmod>' . w3c_datetime($lastmod) . '</lastmod>' : ()), '</url>';
		} @urls),
		'</urlset>',
		'');
}

# W3C Datetime（UTC）。例：2026-10-15T03:04:05+00:00
sub w3c_datetime {
	my ($epoch) = @_;
	my ($sec, $min, $hour, $mday, $mon, $year) = gmtime $epoch;
	return sprintf '%04d-%02d-%02dT%02d:%02d:%02d+00:00', $year + 1900, $mon + 1, $mday, $hour, $min, $sec;
}

1;
