package Lyndbaum::Feed;
# RSS 2.0（docs/feed.md）
#   静的なファイル（pub/rss.xml）として書き出し、Webサーバーがそのまま返す
#   記事を保存したとき、再構築したときなどに書き出し直す
use strict;
use warnings;
use utf8;

use Encode qw(encode_utf8);
use URI;
use Lyndbaum::Model::Article;
use Lyndbaum::View;

my $RSS_DOCS = 'https://www.rssboard.org/rss-specification';

# 書き出す場所。URLは Lyndbaum::URL->feed
#   config.json の feed_file で変えられる（テストで、リポジトリの pub/rss.xml を書き換えないようにするため）
my $FILE = 'pub/rss.xml';

# RSSを書き出し、書き出したファイルのパスを返す（Lyndbaum::StaticFiles）
sub write {
	my ($class, $app, %opt) = @_;
	require Lyndbaum::StaticFiles;
	return Lyndbaum::StaticFiles->write_file(Lyndbaum::StaticFiles->path_of($app, feed_file => $FILE), $class->rss($app, %opt));
}

# RSSのXML（UTF-8のバイト列）を返す。%opt の now は生成した時刻（テスト用）
sub rss {
	my ($class, $app, %opt) = @_;
	my $settings = $app->settings;
	my $abs      = sub { $app->absolute_url($_[0]) };
	my $articles = Lyndbaum::View->articles($app,
		Lyndbaum::Model::Article->list_public_posts($app->db, limit => $settings->{feed_items}));

	my @channel = (
		_element(title       => $settings->{blog_title}),
		_element(link        => $abs->($app->url->top)),
		_element(description => $settings->{blog_description}),
		_element(language    => 'ja'),
		(@$articles ? _element(pubDate => rfc822($articles->[0]{published_at})) : ()),
		_element(lastBuildDate => rfc822($opt{now} // time)),
		_element(generator   => 'Lyndbaum'),
		_element(docs        => $RSS_DOCS),
		sprintf('<atom:link href="%s" rel="self" type="application/rss+xml" />', escape($abs->($app->url->feed))),
		map { $class->_item($app, $_) } @$articles,
	);
	return encode_utf8(join "\n",
		'<?xml version="1.0" encoding="UTF-8"?>',
		'<rss version="2.0" xmlns:atom="http://www.w3.org/2005/Atom" xmlns:dc="http://purl.org/dc/elements/1.1/">',
		'<channel>',
		# 字下げは要素の先頭にだけ付ける（本文の中の改行の後ろに付けると、<pre> などの中身が変わる）
		(map { "\t$_" } @channel),
		'</channel>',
		'</rss>',
		'');
}

sub _item {
	my ($class, $app, $article) = @_;
	my $url    = $app->absolute_url($article->{url});
	my $author = $app->settings->{blog_author};
	my @lines = (
		_element(title => $article->{title}),
		_element(link  => $url),
		_element(guid  => $url),
		(map { _element(category => $_->{full_name}) } @{ $article->{tags} }),
		(defined $author && $author ne '' ? _element('dc:creator' => $author) : ()),
		_element(pubDate => rfc822($article->{published_at})),
		_element(description => absolutize(Lyndbaum::View->body($app, $article), $url)),
	);
	return ('<item>', (map { "\t$_" } @lines), '</item>');
}

sub _element {
	my ($name, $text) = @_;
	return sprintf '<%s>%s</%s>', $name, escape($text // ''), $name;
}

# XMLのエスケープ。XML 1.0で使えない文字（制御文字など）は取り除く
#   本文のHTMLもCDATAで囲まずにエスケープする（CDATAは中に ]]> があると壊れるため）
my %ESCAPE = ('&' => '&amp;', '<' => '&lt;', '>' => '&gt;', '"' => '&quot;', "'" => '&#39;');
sub escape {
	my ($text) = @_;
	$text =~ s/[^\x09\x0A\x0D\x20-\x{D7FF}\x{E000}-\x{FFFD}\x{10000}-\x{10FFFF}]//g;
	$text =~ s/([&<>"'])/$ESCAPE{$1}/g;
	return $text;
}

# 本文のHTMLの中の相対URL（href、src、poster）を、記事のURLをもとに絶対URLにする
#   リーダーは記事のページの外で本文を表示するため。本文はパーサーの出力なので、属性の値は " で囲まれている
sub absolutize {
	my ($html, $base) = @_;
	$html =~ s{(\s(?:href|src|poster)=")([^"]*)(")}{$1 . _absolute($2, $base) . $3}ge;
	return $html;
}

sub _absolute {
	my ($value, $base) = @_;
	return $value if $value =~ /\A[A-Za-z][A-Za-z0-9+.-]*:/;   # すでに絶対URL（http:、mailto: など）
	# 属性の値はHTMLのエスケープ済み（&amp; など）。URI は & を区切りとして扱わないので、そのまま渡してよい
	return URI->new_abs($value, $base)->as_string;
}

# RFC 822 の日時（RSS 2.0 の pubDate）。ロケールに左右されないよう、曜日と月の名前は自前で持つ
my @DAYS   = qw(Sun Mon Tue Wed Thu Fri Sat);
my @MONTHS = qw(Jan Feb Mar Apr May Jun Jul Aug Sep Oct Nov Dec);
sub rfc822 {
	my ($epoch) = @_;
	my ($sec, $min, $hour, $mday, $mon, $year, $wday) = gmtime $epoch;
	return sprintf '%s, %02d %s %04d %02d:%02d:%02d GMT', $DAYS[$wday], $mday, $MONTHS[$mon], $year + 1900, $hour, $min, $sec;
}

1;
