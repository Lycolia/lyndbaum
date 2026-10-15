# RSS（docs/feed.md）
use strict;
use warnings;
use utf8;
use Test::More;

use Encode qw(decode_utf8);
use File::Spec;
use File::Temp qw(tempdir);
use Lyndbaum::App;
use Lyndbaum::Config;
use Lyndbaum::Feed;
use Lyndbaum::Model::Article;
use Lyndbaum::Model::Setting;
use Lyndbaum::Model::Tag;
use TestUtil qw(new_test_app insert_article);

my $test = new_test_app();
# RSSを書き出す先（pub/）は一時ディレクトリにする
my $root = tempdir(CLEANUP => 1);
mkdir File::Spec->catdir($root, 'pub') or die $!;
# 書き出す先は既定（root の下の pub/rss.xml）を確かめるので、テスト用の feed_file は外す
my $app = Lyndbaum::App->new(root => $root, config => Lyndbaum::Config->new(%{ $test->config }, site_url => 'https://blog.example.jp/', feed_file => undef));
my $dbh = $app->db;

Lyndbaum::Model::Setting->set($dbh, blog_title       => 'テスト & ブログ');
Lyndbaum::Model::Setting->set($dbh, blog_description => '説明');
Lyndbaum::Model::Setting->set($dbh, blog_author      => '書いた人');
$dbh->do('INSERT INTO tags (id, parent_id, name, sort_order) VALUES (?, ?, ?, ?)', undef, @$_) for
	[1, undef, '料理', 1], [2, 1, '調味料', 1], [3, undef, 'Perl', 2];
Lyndbaum::Model::Tag->rebuild_paths($dbh);

# 記事1〜3は公開（3がいちばん新しい）、4は下書き、5はゴミ箱、6はコンテンツページ
insert_article($dbh, id => 1, title => '一つ目', published_at => 1700000000);
insert_article($dbh, id => 2, title => '二つ目', published_at => 1700000100);
insert_article($dbh, id => 3, title => '<三つ目> & "引用"', published_at => 1700003600, body_src => join "\n",
	'## 見出し [#h1]', '',
	'[前の記事](/02) [見出しへ](#h1) [外](https://example.com/?a=1&b=2) [メール](mailto:a@example.jp)', '',
	'![図](/pub/attachments/a.png)', '',
	'```', 'コード', '  字下げ', '```', '',
	'====', '',
	"続きの本文\x{0B}");
insert_article($dbh, id => 4, title => '下書き', status => 'draft');
insert_article($dbh, id => 5, title => 'ゴミ箱', deleted_at => time);
insert_article($dbh, id => 6, kind => 'page', slug => 'ページ', title => 'ページ');
$dbh->do('INSERT INTO article_tags (article_id, tag_id) VALUES (?, ?)', undef, @$_) for [3, 2], [3, 3];
Lyndbaum::Model::Article->rebuild_all($dbh, $app->parser_context);

my $now = 1700007200;   # 2023-11-15 00:13:20 GMT
my $rss = sub { decode_utf8(Lyndbaum::Feed->rss(Lyndbaum::App->new(root => $root, config => $app->config), now => $now)) };
my $xml = $rss->();
my @items = $xml =~ m{(<item>.*?</item>)}gs;

subtest 'チャンネル' => sub {
	like $xml, qr{\A<\?xml version="1\.0" encoding="UTF-8"\?>\n<rss version="2\.0" xmlns:atom="http://www\.w3\.org/2005/Atom" xmlns:dc="http://purl\.org/dc/elements/1\.1/">\n<channel>\n};
	like $xml, qr{<title>テスト &amp; ブログ</title>};
	like $xml, qr{<link>https://blog\.example\.jp/</link>}, 'site_url の末尾の / は重ねない';
	like $xml, qr{<description>説明</description>};
	like $xml, qr{<language>ja</language>};
	like $xml, qr{<pubDate>Tue, 14 Nov 2023 23:13:20 GMT</pubDate>\n\t<lastBuildDate>Wed, 15 Nov 2023 00:13:20 GMT</lastBuildDate>},
		'pubDate はいちばん新しい記事の公開日時、lastBuildDate は書き出した日時';
	like $xml, qr{<generator>Lyndbaum</generator>};
	like $xml, qr{<docs>https://www\.rssboard\.org/rss-specification</docs>};
	like $xml, qr{<atom:link href="https://blog\.example\.jp/pub/rss\.xml" rel="self" type="application/rss\+xml" />};
	unlike $xml, qr{<copyright>}, 'copyright は出さない';
	like $xml, qr{</channel>\n</rss>\n\z};
};

subtest '記事' => sub {
	is scalar @items, 3, '公開している普通の記事だけ（下書き、ゴミ箱、コンテンツページは載せない）';
	my $item = $items[0];
	like $item, qr{<title>&lt;三つ目&gt; &amp; &quot;引用&quot;</title>}, '新しい順';
	like $item, qr{<link>https://blog\.example\.jp/03</link>\n\t+<guid>https://blog\.example\.jp/03</guid>};
	like $item, qr{<category>Perl</category>\n\t+<category>料理::調味料</category>}, 'タグごとに分け、親を含めた名前にする';
	like $item, qr{<dc:creator>書いた人</dc:creator>};
	unlike $item, qr{<author>}, 'author はメールアドレスの欄なので使わない';
	like $item, qr{<pubDate>Tue, 14 Nov 2023 23:13:20 GMT</pubDate>};
	like $items[2], qr{<title>一つ目</title>};
	unlike $items[2], qr{<category>}, 'タグが無ければ category を出さない';
};

subtest '本文' => sub {
	my ($description) = $items[0] =~ m{<description>(.*?)</description>}s;
	unlike $description, qr{<}, 'HTMLはエスケープする（CDATAで囲まない）';
	like $description, qr{&lt;h4 id=&quot;h1&quot;&gt;}, '本文のHTML';
	like $description, qr{続きの本文}, '続きを読むの後ろも載せる';
	unlike $description, qr{more}, '続きを読むの印は取り除く';
	unlike $description, qr{\x{0B}}, 'XMLで使えない文字は取り除く';
	like $description, qr{コード\n  字下げ\n}, '本文の中身には字下げを足さない';
	unlike $description, qr{\n\t}, '本文の行の頭にタブを足さない';
	like $description, qr{href=&quot;https://blog\.example\.jp/02&quot;}, 'サイトの中のリンクは絶対URLにする';
	like $description, qr{href=&quot;https://blog\.example\.jp/03#h1&quot;}, '見出しへのリンクは記事のURLに付ける';
	like $description, qr{src=&quot;https://blog\.example\.jp/pub/attachments/a\.png&quot;}, '画像';
	like $description, qr{href=&quot;https://example\.com/\?a=1&amp;amp;b=2&quot;}, 'ほかのサイトへのリンクはそのまま';
	like $description, qr{href=&quot;mailto:a\@example\.jp&quot;};
};

subtest '設定' => sub {
	Lyndbaum::Model::Setting->set($dbh, feed_items => 2);
	my @items = $rss->() =~ m{(<item>.*?</item>)}gs;
	is scalar @items, 2, '載せる記事の数';
	Lyndbaum::Model::Setting->set($dbh, feed_items => 10);

	Lyndbaum::Model::Setting->set($dbh, blog_author => '');
	unlike $rss->(), qr{<dc:creator>}, '書いた人の名前が空なら出さない';
	Lyndbaum::Model::Setting->set($dbh, blog_author => '書いた人');

	my $no_site = Lyndbaum::App->new(root => $root, config => Lyndbaum::Config->new(%{ $test->config }));
	eval { Lyndbaum::Feed->rss($no_site) };
	like $@, qr{site_url}, 'site_url が無ければ書き出さない';
};

subtest '書き出し' => sub {
	my $file = Lyndbaum::Feed->write(Lyndbaum::App->new(root => $root, config => $app->config));
	is $file, File::Spec->catfile($root, 'pub', 'rss.xml');
	open my $fh, '<:raw', $file or die $!;
	my $written = decode_utf8(do { local $/; <$fh> });
	like $written, qr{<title>テスト &amp; ブログ</title>};
	is((stat $file)[2] & 07777, 0644, 'Webサーバーから読める');
	opendir my $dh, File::Spec->catdir($root, 'pub') or die $!;
	is_deeply [ sort grep { !/\A\.\.?\z/ } readdir $dh ], ['rss.xml'], '一時ファイルを残さない';
};

subtest '自動検出のリンク' => sub {
	my $res = Lyndbaum::App->new(root => TestUtil::root_dir(), config => $app->config)->handle({ REQUEST_METHOD => 'GET', PATH_INFO => '/' });
	like $res->body, qr{<link rel="alternate" type="application/rss\+xml" title="テスト &amp; ブログ" href="/pub/rss\.xml">};
};

done_testing;
