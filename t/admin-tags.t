# 管理画面のタグの管理（docs/admin.md の「タグの管理」）
use strict;
use warnings;
use utf8;
use Test::More;

use File::Spec;
use File::Temp qw(tempdir);
use JSON::PP ();
use Lyndbaum::App;
use Lyndbaum::Config;
use Lyndbaum::Model::Tag;
use AdminTest;
use TestUtil qw(insert_article);

my $t = AdminTest->new;
my $feed = File::Spec->catfile(tempdir(CLEANUP => 1), 'rss.xml');
$t->{app} = Lyndbaum::App->new(root => $t->app->{root},
	config => Lyndbaum::Config->new(%{ $t->app->config }, site_url => 'https://blog.example', feed_file => $feed));
my $dbh = $t->dbh;
sub header { AdminTest::header(@_) }

# タグ：料理(1) > 調味料(2)、料理 > 食材(3)、言語(4)、空(5)。記事1に「調味料」、ゴミ箱の記事2に「言語」
$dbh->do('INSERT INTO tags (id, parent_id, name, sort_order) VALUES (?, ?, ?, ?)', undef, @$_) for
	[1, undef, '料理', 10], [2, 1, '調味料', 10], [3, 1, '食材', 20], [4, undef, '言語', 20], [5, undef, '空', 30];
Lyndbaum::Model::Tag->rebuild_paths($dbh);
insert_article($dbh, id => 1, title => '記事');
insert_article($dbh, id => 2, title => 'ゴミ箱の記事', deleted_at => 1);
$dbh->do('INSERT INTO article_tags (article_id, tag_id) VALUES (?, ?)', undef, @$_) for [1, 2], [2, 4];

# 今のタグの木（画面が送る形）。%change で ID ごとに値を変える
sub tree {
	my (%change) = @_;
	my $rows = $dbh->selectall_arrayref('SELECT id, name, parent_id, sort_order FROM tags ORDER BY id', { Slice => {} });
	return [ map { +{ %$_, deleted => 0, %{ $change{ $_->{id} } // {} } } } @$rows ];
}
# 理由をつないだ文（空なら書き込んだ）
sub save_tree { join "\n", @{ Lyndbaum::Model::Tag->save_tree($dbh, tree(@_)) } }

subtest '確かめる' => sub {
	like save_tree(2 => { name => '食材', parent_id => 1 }), qr{同じ親の中に「食材」が2つあります}, '同じ親の中で同じ名前';
	like save_tree(1 => { parent_id => 2 }), qr{自分自身か自分の子孫}, '子孫を親にする';
	like save_tree(2 => { name => ' ' }), qr{名前が空};
	like save_tree(2 => { name => 'a::b' }), qr{「::」と「,」は使えません};
	like save_tree(2 => { deleted => 1 }), qr{記事に付いているので消せません}, '記事が付いているタグ';
	like save_tree(4 => { deleted => 1 }), qr{ゴミ箱の中の記事を含む}, 'ゴミ箱の中の記事が付いているタグ';
	like save_tree(1 => { deleted => 1 }), qr{子のタグがあるので消せません};
	like save_tree(3 => { parent_id => 5 }, 5 => { deleted => 1 }), qr{消すタグを親にはできません};
	my $rows = tree();
	pop @$rows;
	like(join("\n", @{ Lyndbaum::Model::Tag->save_tree($dbh, $rows) }), qr{タグの一覧が正しくありません}, 'タグが欠けている');
	is $dbh->selectrow_array('SELECT name FROM tags WHERE id = 2'), '調味料', '確かめられなければ書き込まない';
};

subtest '書き込む' => sub {
	is save_tree(2 => { name => '食材' }, 3 => { name => '調味料' }), '', '名前を入れ替える（一意の索引にぶつからない）';
	is_deeply $dbh->selectcol_arrayref('SELECT name FROM tags WHERE id IN (2, 3) ORDER BY id'), ['食材', '調味料'];
	is save_tree(3 => { parent_id => 4, sort_order => 5 }), '', '親を付け替える';
	is_deeply $dbh->selectcol_arrayref('SELECT ancestor FROM tag_paths WHERE descendant = 3 ORDER BY depth'), [3, 4], '閉包テーブルを作り直す';
	is save_tree(3 => { parent_id => 5 }), '';
	is save_tree(3 => { deleted => 1 }, 5 => { deleted => 1 }), '', '親と子を一緒に消す';
	is $dbh->selectrow_array('SELECT COUNT(*) FROM tags WHERE id IN (3, 5)'), 0;
	$dbh->do(q{INSERT INTO tags (id, parent_id, name, sort_order) VALUES (3, 1, '食材2', 20), (5, NULL, '空', 30)});
	Lyndbaum::Model::Tag->rebuild_paths($dbh);
};

my ($cookie) = $t->login;
my $csrf = $t->csrf_of($cookie);
sub post {
	my (%form) = @_;
	return $t->request(POST => '/admin/tags', cookie => $cookie, body => [ csrf_token => $csrf, %form ]);
}

subtest '画面' => sub {
	is $t->request(GET => '/admin/tags')->status, 303, 'ログインしていなければ使えない';
	my $res = $t->request(GET => '/admin/tags', cookie => $cookie);
	is $res->status, 200;
	my ($json) = $res->body =~ m{<form class="tag-admin" method="post" action="/admin/tags" data-tags="([^"]*)">};
	$json =~ s/&quot;/"/g;
	my %tag = map { $_->{id} => $_ } @{ JSON::PP->new->decode($json) };
	is_deeply [ @{ $tag{2} }{qw(name parent_id count)} ], ['食材', 1, 1], '名前、親、記事の数';
	ok $tag{4}{in_use}, 'ゴミ箱の中の記事が付いていれば、消せない印';
	is $tag{4}{count}, 0, '記事の数にはゴミ箱の中を数えない';
	ok !$tag{5}{in_use};
	like $res->body, qr{<script src="/pub/assets/js/admin-tags.js" defer></script>};
};

subtest '保存' => sub {
	my $digest = Lyndbaum::Model::Tag->digest($dbh);
	unlink $feed;
	my $res = post(digest => $digest, tree => JSON::PP->new->encode(tree(5 => { name => '空っぽ' })));
	is $res->status, 303;
	is header($res, 'Location'), '/admin/tags?saved=1';
	is $dbh->selectrow_array('SELECT name FROM tags WHERE id = 5'), '空っぽ';
	ok -f $feed, 'RSSを書き出し直す（タグの名前が出るため）';

	$res = post(digest => $digest, tree => JSON::PP->new->encode(tree(5 => { name => '古い画面' })));
	is $res->status, 409, 'ほかの画面で先に変わっていたら保存しない';
	like $res->body, qr{ほかの画面};

	$res = post(digest => Lyndbaum::Model::Tag->digest($dbh), tree => JSON::PP->new->encode(tree(5 => { name => '' }, 2 => { name => '直した' })));
	is $res->status, 400;
	like $res->body, qr{名前が空です};
	like $res->body, qr{&quot;name&quot;:&quot;直した&quot;}, '送られた木のまま出し直す';

	is post(digest => Lyndbaum::Model::Tag->digest($dbh), tree => '{')->status, 400, 'JSONでない';
	is $t->request(POST => '/admin/tags', cookie => $cookie, body => [ tree => '[]' ])->status, 403, 'CSRFトークンが無い';
};

done_testing;
