# 管理画面の記事の管理（docs/admin.md の「記事の管理」）
use strict;
use warnings;
use utf8;
use Test::More;

use File::Spec;
use File::Temp qw(tempdir);
use JSON::PP ();
use Lyndbaum::App;
use Lyndbaum::Config;
use Lyndbaum::Model::Article;
use AdminTest;
use TestUtil qw(insert_article);

# RSSを書けなかったときの記録（warn）は、テストの出力に混ぜない
local $SIG{__WARN__} = sub { warn @_ if $_[0] !~ /RSSかサイトマップを書き出せませんでした/ };

my $t = AdminTest->new;
# RSSは一時ディレクトリに書き出す
my $feed = File::Spec->catfile(tempdir(CLEANUP => 1), 'rss.xml');
$t->{app} = Lyndbaum::App->new(root => $t->app->{root},
	config => Lyndbaum::Config->new(%{ $t->app->config }, site_url => 'https://blog.example', feed_file => $feed));
my $dbh = $t->dbh;
sub header { AdminTest::header(@_) }

insert_article($dbh, id => 1, title => '公開した記事', published_at => 1700000000);
insert_article($dbh, id => 2, title => '書きかけ', status => 'draft', published_at => undef);
insert_article($dbh, id => 3, kind => 'page', slug => 'ページ', title => 'ページ', published_at => 1600000000);
insert_article($dbh, id => 4, title => 'ゴミ箱の記事', deleted_at => 1);
Lyndbaum::Model::Article->rebuild_all($dbh, $t->app->parser_context);   # 検索用のテキストを作る

my ($cookie) = $t->login;
my $csrf = $t->csrf_of($cookie);
sub get  { $t->request(GET => $_[0], cookie => $cookie) }
# 値を配列にすると、同じ名前で複数送る（タグ）
sub post {
	my ($path, %form) = @_;
	my %all = (csrf_token => $csrf, title => '題名', body => '本文', published_at => '', comments_open => '1', status => 'draft', %form);
	my @body = map { my $k = $_; ref $all{$k} ? (map { ($k, $_) } @{ $all{$k} }) : ($k, $all{$k}) } sort keys %all;
	return $t->request(POST => $path, cookie => $cookie, body => \@body);
}
sub digest { Lyndbaum::Model::Article->digest($dbh, $_[0]) }

subtest 'ログインしていなければ使えない' => sub {
	is $t->request(GET => '/admin/articles')->status, 303;
	is $t->request(GET => '/admin/articles/1')->status, 303;
	is $t->request(POST => '/admin/articles', body => [ title => 'x' ])->status, 303;
	is $t->request(POST => '/admin/articles', cookie => $cookie, body => [ title => 'x' ])->status, 403, 'CSRFトークンが無い';
	is $t->request(POST => '/admin/rebuild', cookie => $cookie)->status, 403;
};

subtest '一覧' => sub {
	my $res = get('/admin/articles');
	is $res->status, 200;
	is header($res, 'Cache-Control'), 'no-store';
	my $body = $res->body;
	like $body, qr{<h1>記事</h1>};
	like $body, qr{すべて（2）.*下書き（1）.*公開中（1）}s, 'ゴミ箱の中とコンテンツページは数えない';
	like $body, qr{書きかけ.*公開した記事}s, '下書き（公開日時の無いもの）が先、あとは新しい順';
	unlike $body, qr{ゴミ箱の記事};
	unlike $body, qr{<a href="/admin/articles/3">}, 'コンテンツページは出さない';
	like $body, qr{<a href="/admin/articles/1">公開した記事</a>};
	like $body, qr{<a href="/01">見る</a>}, '公開側のURL';
	like $body, qr{<input type="hidden" name="kind" value="post">}, 'ゴミ箱へ移した後は記事の一覧へ戻る';

	$body = get('/admin/articles?status=draft')->body;
	like $body, qr{書きかけ};
	unlike $body, qr{公開した記事};
	$body = get('/admin/articles?q=%E5%85%AC%E9%96%8B')->body;   # 公開
	like $body, qr{公開した記事};
	unlike $body, qr{書きかけ}, '題名で探す';
	is get('/admin/articles?page=2')->status, 404;
};

subtest 'ページの一覧' => sub {
	my $body = get('/admin/articles?kind=page')->body;
	like $body, qr{<h1>ページ</h1>};
	like $body, qr{すべて（1）.*下書き（0）.*公開中（1）}s, 'コンテンツページだけを数える';
	like $body, qr{<a href="/admin/articles/3">ページ</a>};
	unlike $body, qr{公開した記事|書きかけ}, '記事は出さない';
	like $body, qr{<a href="/%E3%83%9A%E3%83%BC%E3%82%B8">見る</a>}, '公開側のURL';
	like $body, qr{<a href="/admin/articles/new\?kind=page">新しいページを作る</a>};
	like $body, qr{<a href="/admin/articles\?kind=page&amp;status=draft">下書き（0）</a>}, '絞り込みも同じ種類のまま';
	like $body, qr{<input type="hidden" name="kind" value="page">\s*<input type="search" name="q"}, '探すときも同じ種類のまま';
	like $body, qr{<input type="hidden" name="kind" value="page">\s*<table}, 'ゴミ箱へ移した後はページの一覧へ戻る';
	unlike get('/admin/articles?kind=page&q=%E3%81%AA%E3%81%84')->body, qr{<a href="/admin/articles/3">}, '題名で探す';
	is get('/admin/articles?kind=other')->status, 200, '知らない種類は記事の一覧';
	like get('/admin/articles/3')->body, qr{<a href="/admin/articles\?kind=page" class="is-current" aria-current="page">ページの一覧</a>}, 'ページの編集では、左のナビはページの一覧';
	like get('/admin/articles/1')->body, qr{<a href="/admin/articles" class="is-current" aria-current="page">記事の一覧</a>}, '記事の編集では、記事の一覧';
};

subtest '新しい記事' => sub {
	my $res = get('/admin/articles/new');
	is $res->status, 200;
	like $res->body, qr{<form class="admin-form article-edit" method="post" action="/admin/articles">};
	like $res->body, qr{<input type="checkbox" name="comments_open" value="1" checked>}, 'コメントは受け付けるのが既定';
	unlike $res->body, qr{name="keep_updated"}, '新しい記事には「更新日時を変えない」を出さない';
	my @buttons = $res->body =~ m{<button type="submit" name="status" value="(\w+)"}g;
	is_deeply \@buttons, [qw(draft published)], 'Enter で送ったときは下書き（最初のボタン）';
	like $res->body, qr{value="published" class="button-primary" data-confirm="この記事を公開しますか？">公開する</button>}, '公開するときは確かめる';

	$res = post('/admin/articles', title => '新しい記事', body => "## 見出し\n\n本文", new_tag => ['料理::調味料']);
	is $res->status, 303;
	is header($res, 'Location'), '/admin/articles/5?saved=1', 'IDはいちばん大きいID + 1';
	my $a = $dbh->selectrow_hashref('SELECT * FROM articles WHERE id = 5');
	is $a->{status}, 'draft';
	is $a->{slug}, '05';

	$res = get('/admin/articles/5?saved=1');
	like $res->body, qr{保存しました。<a href="/05">記事を見る</a>};
	like $res->body, qr{<li class="tag-chip">\s*<input type="hidden" name="tag" value="料理::調味料">}, '付けたタグの札';
	like $res->body, qr{data-tags="\[\{&quot;count&quot;:0,&quot;name&quot;:&quot;料理&quot;\},\{&quot;count&quot;:1,&quot;name&quot;:&quot;料理::調味料&quot;\}\]"},
		'タグの候補と、使っている記事の数';
	like $res->body, qr{<option value="料理">料理</option><option value="料理::調味料">　調味料</option>}, '一覧から選ぶ（木の順に字下げ）';
	like $res->body, qr{<input type="hidden" name="digest" value="[0-9a-f]{64}">};
	like $res->body, qr{<input type="checkbox" name="keep_updated" value="1">更新日時を変えない};
};

subtest '入力の誤り' => sub {
	my $res = post('/admin/articles', title => '', body => "書いた本文\n", tag => ['料理', '無いタグ'], new_tag => ['新しいタグ']);
	is $res->status, 400;
	like $res->body, qr{題名を書いてください。};
	like $res->body, qr{タグ「無いタグ」はありません。}, '新しいタグとして送られなければ、無いタグは作らない';
	like $res->body, qr{<textarea name="body" rows="25" class="admin-body">書いた本文\n</textarea>}, '書いた内容は消さない';
	like $res->body, qr{name="tag" value="無いタグ"};
	like $res->body, qr{<li class="tag-chip tag-chip-new">\s*<input type="hidden" name="new_tag" value="新しいタグ"><span class="tag-chip-mark">新</span>};
	is $dbh->selectrow_array(q{SELECT COUNT(*) FROM tags WHERE name IN ('無いタグ', '新しいタグ')}), 0, 'タグも作らない';
	is $dbh->selectrow_array('SELECT COUNT(*) FROM articles'), 5, '保存しない';
};

subtest '下書きは管理者にだけ見える' => sub {
	my $res = get('/05');
	is $res->status, 200;
	like $res->body, qr{下書きです。管理者にだけ見えています。<a href="/admin/articles/5">編集する</a>};
	like $res->body, qr{<meta name="robots" content="noindex, nofollow">};
	is header($res, 'Cache-Control'), 'no-store';
	unlike $res->body, qr{comment-form}, 'コメントのフォームは出さない';
	is $t->request(GET => '/05')->status, 404, 'ログインしていなければ見えない';
	unlike get('/01')->body, qr{下書きです}, '公開した記事';
};

subtest '公開する' => sub {
	unlink $feed;
	my $res = post('/admin/articles/5', title => '新しい記事', body => '本文', status => 'published', digest => digest(5));
	is $res->status, 303;
	is header($res, 'Location'), '/admin/articles/5?saved=1';
	is $dbh->selectrow_array('SELECT status FROM articles WHERE id = 5'), 'published';
	ok -f $feed, 'RSSを書き出す';
	is $t->request(GET => '/05')->status, 200, '誰でも見られる';

	my @buttons = get('/admin/articles/5')->body =~ m{<button type="submit" name="status" value="(\w+)"[^>]*>([^<]+)}g;
	is_deeply \@buttons, [ published => '更新', draft => '下書きに戻す' ], '公開中なら、Enter で送ったときは公開のまま';
};

subtest 'ほかの画面で先に保存されていたら' => sub {
	my $res = post('/admin/articles/5', title => '古い画面から', body => '古い本文', status => 'published', digest => '0' x 64);
	is $res->status, 409;
	like $res->as_cgi, qr{\AStatus: 409 Conflict\r\n}, '状態の文言';
	like $res->body, qr{ほかの画面で先に保存されています};
	like $res->body, qr{name="title" value="古い画面から"}, '書いた内容は消さない';
	my $now = digest(5);
	like $res->body, qr{name="digest" value="$now"}, 'もう一度保存すれば上書きになる';
	is $dbh->selectrow_array('SELECT title FROM articles WHERE id = 5'), '新しい記事';
};

subtest 'RSSを書き出せなくても保存する' => sub {
	my $broken = Lyndbaum::Config->new(%{ $t->app->config }, site_url => undef);
	local $t->{app} = Lyndbaum::App->new(root => $t->app->{root}, config => $broken);
	my $res = post('/admin/articles/5', title => '題名を直した', status => 'published', digest => digest(5));
	is header($res, 'Location'), '/admin/articles/5?feed=failed&saved=1';
	is $dbh->selectrow_array('SELECT title FROM articles WHERE id = 5'), '題名を直した';
	like get('/admin/articles/5?feed=failed&saved=1')->body, qr{RSSかサイトマップを書き出せませんでした};
};

subtest '再構築' => sub {
	$dbh->do('UPDATE articles SET body_html = NULL');
	unlink $feed;
	my $res = $t->request(POST => '/admin/rebuild', cookie => $cookie, body => [ csrf_token => $csrf ]);
	is $res->status, 303;
	is header($res, 'Location'), '/admin?rebuilt=5', 'ゴミ箱の中の記事も変換する';
	is $dbh->selectrow_array('SELECT COUNT(*) FROM articles WHERE body_html IS NULL'), 0;
	ok -f $feed, 'RSSも書き出す';
	like get('/admin?rebuilt=5')->body, qr{5件の記事の本文を変換し直しました。};
};

subtest 'ページ' => sub {
	my $res = get('/admin/articles/new?kind=page');
	like $res->body, qr{<h1>新しいページ</h1>};
	like $res->body, qr{<input type="hidden" name="kind" value="page">};
	like $res->body, qr{<option value="3">ページ</option>}, '親に選べるページ';

	$res = post('/admin/articles', kind => 'page', title => '子', page_name => '子', parent_id => 3, sort_order => '');
	is $res->status, 303;
	my ($id) = header($res, 'Location') =~ m{/admin/articles/(\d+)};
	is $dbh->selectrow_array('SELECT slug FROM articles WHERE id = ?', undef, $id), 'ページ/子';
	$res = get("/admin/articles/$id");
	like $res->body, qr{<h1>ページの編集</h1>};
	like $res->body, qr{<option value="3" selected>ページ</option>};
	like $res->body, qr{name="page_name" value="子"};
	unlike get('/admin/articles/3')->body, qr{<option value="3"}, '自分は親に選べない';
	unlike get('/admin/articles/3')->body, qr{<option value="$id"}, '子孫も親に選べない';

	$res = post('/admin/articles', kind => 'page', title => '同じ', page_name => '子', parent_id => 3);
	is $res->status, 400;
	like $res->body, qr{URL「/ページ/子」は、「子」が使っています。};
	like $res->body, qr{name="page_name" value="子"}, '書いた内容は消さない';
};

subtest '更新履歴' => sub {
	unlike get('/admin/articles/new')->body, qr{class="revisions"}, '新しい記事には履歴の欄を出さない';
	like get('/admin/articles/3')->body, qr{<summary>履歴（0件）</summary>.*この記事の履歴はまだありません}s;

	my $res = post('/admin/articles/3', kind => 'page', title => 'ページ', body => '新しい本文', page_name => 'ページ', status => 'published', digest => digest(3));
	is $res->status, 303;
	my $body = get('/admin/articles/3')->body;
	like $body, qr{<summary>履歴（1件）</summary>};
	my ($url) = $body =~ m{<button type="button" class="revision-item" data-url="([^"]+)">};
	like $url, qr{\A/admin/articles/3/revisions/\d+\z};

	$res = get($url);
	is $res->status, 200;
	is $res->content_type, 'application/json';
	is header($res, 'Cache-Control'), 'no-store';
	my $rev = JSON::PP->new->decode($res->body);
	is $rev->{title}, 'ページ';
	is $rev->{body}, '', '保存する前の本文';
	like $rev->{saved}, qr{\A\d{4}-\d\d-\d\d \d\d:\d\d\z};
	is $t->request(GET => $url)->status, 303, 'ログインしていなければ取れない';
	(my $other = $url) =~ s{/articles/3/}{/articles/1/};
	is get($other)->status, 404, 'ほかの記事の履歴としては取れない';
};

subtest '編集の設定' => sub {
	my $res = get('/admin/settings/editor');
	is $res->status, 200;
	like $res->body, qr{<h1>編集の設定</h1>};
	like $res->body, qr{<form class="admin-form" method="post" action="/admin/settings/editor">};
	like $res->body, qr{name="revision_interval" value="180"};
	like $res->body, qr{name="revision_max" value="120"};
	like $res->body, qr{name="thumbnail_size" value="240"};

	$res = $t->request(POST => '/admin/settings/editor', cookie => $cookie,
		body => [ csrf_token => $csrf, revision_interval => '0', revision_max => '10', thumbnail_size => '240' ]);
	is header($res, 'Location'), '/admin/settings/editor?saved=1';
	is $t->app->settings->{revision_max}, 10;
	is $t->request(POST => '/admin/settings/editor', cookie => $cookie,
		body => [ csrf_token => $csrf, revision_interval => '-1', revision_max => '10', thumbnail_size => '240' ])->status, 400;
	is get('/admin/settings/unknown')->status, 404;
};

subtest 'ゴミ箱へ移す' => sub {
	my $res = get('/admin/articles/1');
	like $res->body, qr{<button type="submit" class="publish-box-trash" formaction="/admin/articles/1/trash" formnovalidate data-confirm="[^"]+">ゴミ箱へ移動</button>};
	my @buttons = $res->body =~ m{<button type="submit"([^>]*)>}g;
	unlike $buttons[0], qr{formaction}, 'Enter で送ったときにゴミ箱へ移さない';

	unlink $feed;
	$res = $t->request(POST => '/admin/articles/1/trash', cookie => $cookie, body => [ csrf_token => $csrf ]);
	is $res->status, 303;
	is header($res, 'Location'), '/admin/articles?trashed=1';
	ok -f $feed, 'RSSを書き出し直す';
	ok $dbh->selectrow_array('SELECT deleted_at FROM articles WHERE id = 1');
	is $t->request(GET => '/01')->status, 404, '公開側には出ない';
	like get('/admin/articles?trashed=1')->body, qr{1件の記事をゴミ箱へ移しました。};

	$res = $t->request(POST => '/admin/articles/trash', cookie => $cookie, body => [ csrf_token => $csrf, id => 2, id => 5 ]);
	is header($res, 'Location'), '/admin/articles?trashed=2', '一覧から選んで移す';

	$res = $t->request(POST => '/admin/articles/trash', cookie => $cookie, body => [ csrf_token => $csrf, id => 3 ]);
	is $res->status, 409;
	like $res->body, qr{「ページ」には子ページがあるので、ゴミ箱へ移せません。};
};

subtest 'ゴミ箱' => sub {
	my $res = get('/admin/trash');
	is $res->status, 200;
	like $res->body, qr{題名を直した.*書きかけ.*公開した記事.*ゴミ箱の記事}s, '削除した日時の新しい順';
	like $res->body, qr{<input type="checkbox" name="id" value="1" id="trash-1">};

	$res = $t->request(POST => '/admin/trash', cookie => $cookie, body => [ csrf_token => $csrf, mode => 'restore', id => 1 ]);
	is header($res, 'Location'), '/admin/trash?count=1&done=restore';
	is $t->request(GET => '/01')->status, 200, '戻すと公開側に出る';
	like get('/admin/trash?count=1&done=restore')->body, qr{1件の記事を戻しました。};

	$res = $t->request(POST => '/admin/trash', cookie => $cookie, body => [ csrf_token => $csrf, mode => 'purge', id => 2 ]);
	is header($res, 'Location'), '/admin/trash?count=1&done=purge';
	is $dbh->selectrow_array('SELECT COUNT(*) FROM articles WHERE id = 2'), 0, '完全に削除';

	$res = $t->request(POST => '/admin/trash', cookie => $cookie, body => [ csrf_token => $csrf, mode => 'purge_all' ]);
	is header($res, 'Location'), '/admin/trash?count=2&done=purge_all';
	like get('/admin/trash')->body, qr{ゴミ箱は空です。};

	is $t->request(POST => '/admin/trash', cookie => $cookie, body => [ csrf_token => $csrf, mode => 'x' ])->status, 400;
	is $t->request(POST => '/admin/trash', cookie => $cookie, body => [ mode => 'purge_all' ])->status, 403, 'CSRFトークンが無い';
};

subtest '無い記事' => sub {
	is get('/admin/articles/99')->status, 404;
	$dbh->do('UPDATE articles SET deleted_at = 1 WHERE id = 1');
	is get('/admin/articles/1')->status, 404, 'ゴミ箱の中の記事';
	is $t->request(POST => '/admin/articles/1/trash', cookie => $cookie, body => [ csrf_token => $csrf ])->status, 404;
	is post('/admin/articles/99')->status, 404;
};

done_testing;
