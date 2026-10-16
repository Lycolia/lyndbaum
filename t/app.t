use strict;
use warnings;
use utf8;
use Test::More;

use Encode qw(encode_utf8);
use Lyndbaum::Model::Article;
use Lyndbaum::Model::Setting;
use Lyndbaum::Model::Tag;
use TestUtil qw(new_test_app insert_article);

my $app = new_test_app();
my $dbh = $app->db;

# テスト用のデータ
#   タグ：料理 > 食材 > 調味料、料理 > 調味料、言語 > C#.NET
#   記事：1〜3 は公開、4 は下書き、5 はゴミ箱、6 は「C#.NET」
#   コンテンツ：親ページ > 子ページ
Lyndbaum::Model::Setting->set($dbh, blog_title => 'テストのブログ');
Lyndbaum::Model::Setting->set($dbh, per_page   => 2);
$dbh->do('INSERT INTO tags (id, parent_id, name, sort_order) VALUES (?, ?, ?, ?)', undef, @$_) for
	[1, undef, '料理', 1], [2, 1, '食材', 1], [3, 2, '調味料', 1], [4, 1, '調味料', 2],
	[5, undef, '言語', 2], [6, 5, 'C#.NET', 1];
Lyndbaum::Model::Tag->rebuild_paths($dbh);

insert_article($dbh, id => 1, title => '<b>題名</b>', body_src => "# 見出し\n\n本文 & **続き**\n\n====\n\n後半", published_at => 1700000000);
insert_article($dbh, id => 2, title => '二つ目', published_at => 1700000100);
insert_article($dbh, id => 3, title => '三つ目', published_at => 1700000200);
insert_article($dbh, id => 4, title => '下書き', status => 'draft');
insert_article($dbh, id => 5, title => 'ゴミ箱', deleted_at => time);
insert_article($dbh, id => 6, title => 'C#の記事', published_at => 1600000000);
insert_article($dbh, id => 10, kind => 'page', slug => '親ページ', title => '親ページ');
insert_article($dbh, id => 11, kind => 'page', slug => '親ページ/子ページ', title => '子ページ', parent_id => 10);
$dbh->do('INSERT INTO article_tags (article_id, tag_id) VALUES (?, ?)', undef, @$_) for
	[1, 3], [2, 4], [4, 3], [5, 3], [6, 6], [11, 3];
Lyndbaum::Model::Article->rebuild_all($dbh, $app->parser_context);
# コメント：記事1に公開2件（2件目は管理者）と保留1件、下書き（記事4）に公開1件
$dbh->do('INSERT INTO comments (id, article_id, num, status, by_admin, author_name, body, created_at) VALUES (?, ?, ?, ?, ?, ?, ?, ?)', undef, @$_) for
	[1, 1, 1, 'public', 0, '<i>名無し</i>', "はじめまして\nhttps://example.com/ を見ました", 1700001000],
	[2, 1, 3, 'public', 1, '管理人', '>>1 ありがとうございます', 1700003000],
	[3, 1, 2, 'held',   0, '保留の人', '承認待ちのコメント', 1700002000],
	[4, 4, 1, 'public', 0, '下書きの人', '下書きへのコメント', 1700004000];

sub get {
	my ($path, $query) = @_;
	# 1リクエストごとにアプリを作り直す（設定などを使い回さないため）
	# CGIの環境変数はバイト列で届くので、UTF-8にして渡す
	my $app = Lyndbaum::App->new(root => $app->{root}, config => $app->config);
	return $app->handle({
		REQUEST_METHOD => 'GET',
		PATH_INFO      => encode_utf8($path),
		QUERY_STRING   => $query // '',
	});
}

sub location {
	my ($res) = @_;
	my %headers = @{ $res->{headers} };
	return $headers{Location};
}

subtest 'トップページ' => sub {
	my $res = get('/');
	is $res->status, 200;
	like $res->body, qr{<title>テストのブログ</title>}, 'ブログ名';
	like $res->body, qr{三つ目.*二つ目}s, '新しい順';
	my ($main) = $res->body =~ m{<main.*?</main>}s;   # サイドバーの「最近のコメント」を除く
	unlike $main, qr{<b>題名</b>|&lt;b&gt;題名}, '2件で次のページへ';
	unlike $res->body, qr{親ページ</a></h2>}, 'コンテンツページは一覧に出さない';
	like $res->body, qr{href="/\?page=2"}, '次のページへのリンク';

	my $page2 = get('/', 'page=2');
	is $page2->status, 200;
	like $page2->body, qr{&lt;b&gt;題名&lt;/b&gt;}, '2ページ目';
	like $page2->body, qr{rel="prev" href="/"}, '前のページは page を付けない';

	is get('/', 'page=3')->status, 404, '範囲外のページ';
	is get('/', 'page=abc')->status, 404, '数字でないページ';
};

subtest '記事' => sub {
	my $res = get('/01');
	is $res->status, 200;
	like $res->body, qr{<title>&lt;b&gt;題名&lt;/b&gt; - テストのブログ</title>}, 'タイトルをエスケープする';
	like $res->body, qr{<section>\s*<h3 id="見出し"><a href="#見出し">見出し</a></h3>}, '本文をMarkdownとして変換する';
	like $res->body, qr{<p>本文 &amp; <strong>続き</strong></p>\s*<p>後半</p>}s, '続きを読むの印は記事のページでは出さない';
	like $dbh->selectrow_array('SELECT text FROM article_search WHERE article_id = 1'), qr/本文 & 続き/, '検索用テキストを保存する';

	my $html = $dbh->selectrow_array('SELECT body_html FROM articles WHERE id = 1');
	$dbh->do(q{UPDATE articles SET body_html = '<p>古いHTML</p>' WHERE id = 1});
	like get('/01')->body, qr{<p>古いHTML</p>}, '表示のときには変換し直さない';
	$dbh->do('UPDATE articles SET body_html = ? WHERE id = 1', undef, $html);
	like $res->body, qr{<time datetime="2023-11-15T07:13:20\+09:00">2023-11-15 07:13</time>}, '日本時間で表示する';
	like $res->body, qr{href="/search\?t=%E6%96%99%E7%90%86::%E9%A3%9F%E6%9D%90::%E8%AA%BF%E5%91%B3%E6%96%99">料理::食材::調味料</a>}, 'タグはタグで絞り込んだ検索へのリンク';

	is get('/04')->status, 404, '下書き';
	is get('/05')->status, 404, 'ゴミ箱';
	is get('/1')->status, 404, '0 の無い記事ID';
	is get('/0999')->status, 404, '存在しない';
};

subtest 'コンテンツページ' => sub {
	my $res = get('/親ページ/子ページ');
	is $res->status, 200;
	like $res->body, qr{<h1 class="article-title">子ページ</h1>};
	unlike $res->body, qr{<time}, '日付は出さない';
	is get('/親ページ/')->status, 404, '末尾の / は付けない';
	is get('/存在しない')->status, 404;

	insert_article($dbh, id => 12, kind => 'page', slug => 'pub', title => 'pub');
	insert_article($dbh, id => 13, kind => 'page', slug => 'pub/a', title => 'pub/a');
	insert_article($dbh, id => 14, kind => 'page', slug => 'public', title => 'public');
	is get('/pub')->status, 404, 'pub と pub/… は静的なファイルの置き場所なので、slug に使えない';
	is get('/pub/a')->status, 404;
	is get('/public')->status, 200, 'pub で始まるだけの slug は使える';
	$dbh->do('DELETE FROM articles WHERE id IN (12, 13, 14)');
};

subtest 'コメント' => sub {
	my $body = get('/01')->body;
	like $body, qr{<h2 class="comments-title">コメント（2件）</h2>}, '件数は公開中のものだけ';
	like $body, qr{<article class="comment-entry" id="c1">.*?<span class="comment-author">&lt;i&gt;名無し&lt;/i&gt;</span>}s, '番号の id、名前をエスケープする';
	like $body, qr{<div class="comment-text">はじめまして\n<a href="https://example.com/" rel="nofollow ugc noopener noreferrer">https://example.com/</a> を見ました</div>}, '本文の URL はリンク';
	like $body, qr{<article class="comment-entry comment-admin" id="c3">.*?<span class="comment-badge">管理者</span>}s, '管理者のコメント';
	like $body, qr{<a href="#c1">&gt;&gt;1</a> ありがとうございます}, '>>N は #cN へのリンク';
	unlike $body, qr{承認待ち}, '保留のコメントは出さない';
	like $body, qr{<a class="comment-num" href="#c1">1</a>.*<a class="comment-num" href="#c3">3</a>}s, '番号の順';
	my $empty = get('/02')->body;
	unlike $empty, qr{<article class="comment}, 'コメントが無い記事';
	like $empty, qr{<h2 class="comments-title">コメント（0件）</h2>.*<form class="comment-form"}s, 'コメントが無くても、受け付けるならフォームを出す';
};

subtest 'サイドバー' => sub {
	my $body = get('/')->body;
	like $body, qr{<a href="/%E8%A6%AA%E3%83%9A%E3%83%BC%E3%82%B8">親ページ</a>\s*<ul>\s*<li><a href="/%E8%A6%AA[^"]+">子ページ</a>}, 'コンテンツの木';
	like $body, qr{>料理</a> <span class="count">\(3\)</span>}, '親のタグの件数は子孫を含み、非公開を除く';
	like $body, qr{>C#.NET</a>}, 'タグの名前';
	my ($recent) = $body =~ m{<h2>最近のコメント</h2>(.*?)</ul>}s;
	is_deeply [ $recent =~ m{<li><a href="([^"]+)">}g ], ['/01#c3', '/01#c1'], '最近のコメントは新しい順。保留と非公開の記事のものは出さない';
	like $recent, qr{<a href="/01#c3">&lt;b&gt;題名&lt;/b&gt;</a> <span class="comment-author" title="2023-11-15 08:03">管理人</span>}, '記事の題名と名前';
};

subtest 'タグで絞り込んだ検索' => sub {
	my $res = get('/search', 't=%E6%96%99%E7%90%86');
	is $res->status, 200;
	like $res->body, qr{<title>料理 - テストのブログ</title>}, '題名はタグの名前';
	like $res->body, qr{<p>3 件</p>}, '子孫のタグの記事とコンテンツページを含む';
	like $res->body, qr{二つ目}, '1ページ目';
	like get('/search', 't=%E6%96%99%E7%90%86::%E9%A3%9F%E6%9D%90::%E8%AA%BF%E5%91%B3%E6%96%99')->body, qr{<p>2 件</p>};

	is get('/search', 't=%E8%A8%80%E8%AA%9E::C%23.NET')->status, 200, '記号を含むタグ名';
	is get('/search', 't=%E8%AA%BF%E5%91%B3%E6%96%99')->status, 404, '親を省いた名前では探さない';
	is get('/search', 't=%E6%96%99%E7%90%86&page=3')->status, 404, '範囲外のページ';
	is get('/tags/料理')->status, 404, '/tags/ は使わない';
};

subtest '旧URLからの転送' => sub {
	my $res = get('/', '&p=2');
	is $res->status, 301, 'ページ送り';
	is location($res), '/?page=2';
	is location(get('/', 'p=1')), '/', '1ページ目';

	$res = get('/', '&t=%E8%A8%80%E8%AA%9E::C%23.NET');
	is $res->status, 301, 'タグ1つ';
	is location($res), '/search?t=%E8%A8%80%E8%AA%9E::C%23.NET';
	is location(get('/', 't=%E6%96%99%E7%90%86%3A%3A%E9%A3%9F%E6%9D%90&p=2')),
		'/search?t=%E6%96%99%E7%90%86::%E9%A3%9F%E6%9D%90&page=2', 'タグとページ送り（:: がエンコードされていても可）';
	is location(get('/', '&t=a&t=b%3A%3Ac')), '/search?t=a&t=b::c', '複数のタグ';
	is location(get('/', 't=')), '/search?t=', 'タグなし';
	is location(get('/', '&d=202606&p=2')), '/search?d=202606&page=2', '年月';
	is location(get('/', 'q=a%20b&all=1')), '/search?q=a%20b&in=source', '全文（旧システムは原文を探していた）';
	is location(get('/', 'all=0&q=a&t=x&d=2026')), '/search?q=a&in=title&t=x&d=2026', 'タイトル';
	is location(get('/', 'q=a')), '/search?q=a&in=title', 'all が無ければタイトル';
	is get('/no/such/path')->status, 404;
};

subtest '検索' => sub {
	Lyndbaum::Model::Setting->set($dbh, per_page => 10);   # 当たった記事を1ページに収める
	# 検索だけで使う記事。タグなし、2017-07-14
	insert_article($dbh, id => 7, title => 'Perlの話', published_at => 1500000000,
		body_src => "PERL と ｎｇｉｎｘ の [リンク](https://example.com/foo) [image:S:a/:b.png:画像の説明] 100% 確実");
	Lyndbaum::Model::Article->rebuild_all($dbh, $app->parser_context);   # 検索用テキストは変換のときに作る

	# 当たった記事の題名（新しい順）か、200以外ならステータス
	my $search = sub {
		my $res = get('/search', $_[0]);
		return $res->status if $res->status != 200;
		return [ map { s{</?mark>}{}gr } $res->body =~ m{<h2 class="summary-title"><a href="[^"]*">(.*?)</a>}g ];
	};
	# 検索条件の欄（サイドバーを含めない）
	my $body = sub { my ($section) = get('/search', $_[0])->body =~ m{(<section class="search-conditions">.*?</section>)}s; $section // '' };

	unlike $body->(''), qr{件</p>}, '条件が無ければフォームだけ';
	is_deeply $search->('q=%E6%9C%AC%E6%96%87'), ['&lt;b&gt;題名&lt;/b&gt;'], '本文';
	is_deeply $search->('q=perl%E3%80%80NGINX'), ['Perlの話'], '大文字と小文字、全角と半角を区別しない。全角空白で区切った語はすべてを含む';
	is_deeply $search->('q=perl%20ruby'), [], 'すべての語を含むものだけ';
	is_deeply $search->('q=%E9%A1%8C%E5%90%8D&in=title'), ['&lt;b&gt;題名&lt;/b&gt;'], 'タイトル';
	is_deeply $search->('q=%E6%9C%AC%E6%96%87&in=title'), [], 'タイトルに無い語';
	is_deeply $search->('q=example.com'), [], '本文はURLを含まない';
	is_deeply $search->('q=example.com&in=source'), ['Perlの話'], '原文はURLを含む';
	is_deeply $search->('q=**%E7%B6%9A%E3%81%8D&in=source'), ['&lt;b&gt;題名&lt;/b&gt;'], '原文は記法を含む';
	is_deeply $search->('q=%E7%94%BB%E5%83%8F%E3%81%AE%E8%AA%AC%E6%98%8E'), ['Perlの話'], '本文は画像の代替テキストを含む';
	is_deeply $search->('q=0%25'), ['Perlの話'], '% は文字として探す';
	is_deeply $search->('q=_'), [], '_ は文字として探す';

	is_deeply $search->('t=%E6%96%99%E7%90%86'), ['子ページ', '二つ目', '&lt;b&gt;題名&lt;/b&gt;'], 'タグ（子孫を含む）';
	is_deeply $search->('t=%E6%96%99%E7%90%86&t=%E6%96%99%E7%90%86%3A%3A%E9%A3%9F%E6%9D%90'), ['子ページ', '&lt;b&gt;題名&lt;/b&gt;'], '複数のタグはすべてが付いたもの';
	is_deeply $search->('t='), ['親ページ', '三つ目', 'Perlの話'], 'タグなし';
	is $search->('t=%E5%AD%98%E5%9C%A8%E3%81%97%E3%81%AA%E3%81%84'), 404, '存在しないタグ';
	is_deeply $search->('d=2023'), ['三つ目', '二つ目', '&lt;b&gt;題名&lt;/b&gt;'], '年';
	is_deeply $search->('d=201707'), ['Perlの話'], '年月';
	unlike $body->('d=abc'), qr{件</p>}, '不正な年月は無視する';

	my $facet = $body->('t=%E6%96%99%E7%90%86');
	like $facet, qr{>料理::食材</a> <span class="count">\(2\)</span>}, 'タグの候補と件数（子孫を含む）';
	like $facet, qr{>料理::調味料</a> <span class="count">\(1\)</span>};
	unlike $facet, qr{>料理</a> <span class="count">}, '選んだタグは候補に出さない';
	like $facet, qr{>2023年</a> <span class="count">\(2\)</span>}, '年の候補（子ページは今年）';
	like $body->('t='), qr{>2017年</a>}, 'タグなしの記事の年';
	like $body->('d=2023'), qr{>11月</a> <span class="count">\(3\)</span>}, '年を選んだら月の候補';
	like $body->('q=perl'), qr{>\(タグなし\)</a> <span class="count">\(1\)</span>}, 'タグなしの候補';
	like $body->('t=%E6%96%99%E7%90%86&d=2023'), qr{href="/search\?d=2023"[^>]*>×}, '選んだ条件を外すリンク';

	my $result = get('/search', 'q=nginx')->body;
	like $result, qr{<a href="/07"><mark>Perl</mark>の話</a>|<a href="/07">Perlの話</a>}, '題名';
	like $result, qr{<p class="search-snippet">PERL と <mark>ｎｇｉｎｘ</mark> の リンク.*?</p>}s, '本文の範囲は抜粋。当たった語を強調する';
	like get('/search', 'q=perl')->body, qr{<a href="/07"><mark>Perl</mark>の話</a>}, '題名も強調する';
	like get('/search', 'q=example.com&in=source')->body,
		qr{<li><span class="search-line-number">1</span><code>.*?\[リンク\]\(https://<mark>example.com</mark>/foo\).*?</code></li>}, '原文の範囲は当たった行';
	unlike get('/search', 't=')->body, qr{<mark>}, '検索語が無ければ強調しない';

	is get('/search', 'q=perl&page=2')->status, 404, '範囲外のページ';
	Lyndbaum::Model::Setting->set($dbh, per_page => 2);
};

subtest '画像の拡大表示とコードの色付け（Fancybox、Prism.js）' => sub {
	my $body = get('/01')->body;
	like $body, qr{<link rel="stylesheet" href="/pub/assets/js/extlib/fancybox/jquery\.fancybox\.min\.css">};
	like $body, qr{<link rel="stylesheet" href="/pub/assets/js/extlib/prismjs/prism\.css">};
	like $body, qr{<script src="/pub/assets/js/extlib/prismjs/prism-core\.min\.js" data-manual defer></script>}, 'Prism は自動では動かさない';
	my @scripts = $body =~ m{<script src="/pub/assets/js/([^"]+)"[^>]*defer></script>}g;
	is_deeply [ @scripts[0 .. 7] ], [ qw(
		extlib/prismjs/prism-core.min.js extlib/fancybox/jquery-3.2.1.min.js extlib/fancybox/jquery.fancybox.min.js
		extlib/prismjs/prism-autoloader.min.js extlib/prismjs/prism-line-numbers.min.js extlib/prismjs/prism-toolbar.min.js
		extlib/prismjs/prism-copy-to-clipboard.min.js article.js
	) ], 'defer なので、この順に動く（Prism の本体が先、article.js が最後）';
};

subtest '404はHTMLで返す' => sub {
	my $res = get('/no/such/path');
	is $res->content_type, 'text/html';
	like $res->body, qr{ページが見つかりません};
};

subtest 'パスはREQUEST_URIから、クエリはQUERY_STRINGから取る' => sub {
	my $app = Lyndbaum::App->new(root => $app->{root}, config => $app->config);
	my $res = $app->handle({ REQUEST_METHOD => 'GET', REQUEST_URI => '/search?t=%E6%96%99%E7%90%86', QUERY_STRING => 't=%E8%A8%80%E8%AA%9E' });
	is $res->status, 200, 'パスはREQUEST_URIの ? より前を使う';
	like $res->body, qr{<title>言語 - }, 'クエリはQUERY_STRINGを使う';

	$res = $app->handle({ REQUEST_METHOD => 'GET', REQUEST_URI => '/search?t=%E6%96%99%E7%90%86' });
	unlike $res->body, qr{<title>料理 - }, 'QUERY_STRINGが無ければ、REQUEST_URIのクエリは使わない';
};

done_testing;
