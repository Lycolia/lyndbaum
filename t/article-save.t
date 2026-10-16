# 記事の保存（Lyndbaum::ArticleForm、Lyndbaum::Model::Article->save）
use strict;
use warnings;
use utf8;
use Test::More;

use Lyndbaum::ArticleForm;
use Lyndbaum::Date qw(parse_input_date);
use Lyndbaum::Model::Article;
use Lyndbaum::Model::Tag;
use Lyndbaum::Parser::Common;
use TestUtil qw(new_test_app insert_article);

my $app = new_test_app();
my $dbh = $app->db;
my %context = $app->parser_context;

# フォームの値を読む。値を配列にすると、同じ名前で複数送ったことになる（タグ）
sub form {
	my (%f) = @_;
	my %all = (title => '題名', body => '本文', status => 'draft', published_at => '', comments_open => '1', %f);
	my $tags = Lyndbaum::Model::Tag->all($dbh);
	return Lyndbaum::ArticleForm->parse(
		values     => sub { my $v = $all{ $_[0] }; ref $v ? @$v : defined $v ? ($v) : () },
		tag_exists => sub { Lyndbaum::Model::Tag->find_by_path($tags, @_) },
	);
}
sub save {
	my ($v, %opt) = @_;
	return Lyndbaum::Model::Article->save($dbh, $v, context => \%context, %opt);
}
sub tag_names {
	my ($id) = @_;
	my $tags = Lyndbaum::Model::Tag->all($dbh);
	return [ sort map { $tags->{$_}{full_name} } @{ Lyndbaum::Model::Article->tag_ids_of($dbh, $id)->{$id} // [] } ];
}

subtest 'フォーム' => sub {
	$dbh->do(q{INSERT INTO tags (id, parent_id, name) VALUES (100, NULL, '既存')});
	my ($v, $errors) = form(title => '  題名  ', body => "一行目\r\n二行目\r\n", tag => ['既存', ' 既存 '], new_tag => [' 料理 :: 調味料 ', 'Perl', '', '既存'],
		published_at => '2026-10-14T21:05', comments_open => undef, keep_updated => '1', digest => 'a' x 64);
	is_deeply $errors, [];
	is $v->{title}, '題名', '前後の空白を除く';
	is $v->{body_src}, "一行目\n二行目\n", '改行を LF にそろえる';
	is_deeply $v->{tags}, [ ['既存'], ['料理', '調味料'], ['Perl'] ], '今あるタグと新しいタグ。重なりは除く';
	is_deeply $v->{tag_chips}, [ { name => '既存', new => 0 }, { name => '料理::調味料', new => 1 }, { name => 'Perl', new => 1 } ],
		'フォームに戻す札';
	is $v->{published_at}, parse_input_date('2026-10-14T21:05');
	is $v->{status}, 'draft';
	is $v->{comments_open}, 0, 'チェックが無ければ受け付けない';
	is $v->{keep_updated}, 1;
	is $v->{digest}, 'a' x 64;

	(undef, $errors) = form(title => ' ', tag => ['無いタグ'], new_tag => ['料理::', '::a', 'a,b'], published_at => '2026-02-30T00:00');
	is_deeply [ map { $_->{key} } @$errors ], [qw(title tags tags tags tags published_at)];
	like $errors->[1]{message}, qr{タグ「無いタグ」はありません。}, '新しいタグとして送られなければ、無いタグは作らない';
	(undef, $errors) = form(title => 'あ' x 201);
	is_deeply [ map { $_->{key} } @$errors ], ['title'], '題名は200文字まで';
	$dbh->do('DELETE FROM tags');
};

subtest '説明（一覧に出す要約）' => sub {
	my $summary = sub { Lyndbaum::Parser::Common->summary($_[0]) };
	is $summary->("<h3>見出し</h3>\n<p>一行目<br>\n二行目 &lt;b&gt; &amp;</p>"), '見出し 一行目 二行目 <b> &', 'タグを除き、文字参照を戻し、空白をまとめる';
	is $summary->('<p>' . ('あ' x 64) . '</p>'), 'あ' x 64, '64文字までならそのまま';
	is $summary->('<p>' . ('あ' x 65) . '</p>'), ('あ' x 64) . '...', '長ければ64文字で切って ... を付ける';
	is $summary->("<p>前</p>\n<!--more-->\n<p>後</p>"), '前 後', '続きを読むの印は除く';
};

subtest '新しい記事' => sub {
	insert_article($dbh, id => 7, title => '前からある記事');
	my ($v) = form(title => '新しい記事', body => "# 見出し\n\n本文", new_tag => ['料理::調味料', 'Perl']);
	my $r = save($v, now => 1000);
	is_deeply $r, { id => 8, slug => '08' }, 'IDはいちばん大きいID + 1、slug は「0 + ID」';
	my $a = $dbh->selectrow_hashref('SELECT * FROM articles WHERE id = 8');
	is $a->{kind}, 'post';
	is $a->{status}, 'draft';
	is $a->{published_at}, undef, '下書きで公開日時が空なら、空のまま';
	is_deeply [ @$a{qw(created_at updated_at)} ], [1000, 1000];
	like $a->{body_src}, qr{\A# 見出し \[#[a-z][0-9a-f]{7}\]\n\n本文\z}, '識別子の無い見出しに識別子を付ける';
	like $a->{body_html}, qr{<h3 id="[a-z][0-9a-f]{7}">}, '本文を変換する';
	is $a->{description}, '見出し 本文', '説明は本文から作る';
	ok $dbh->selectrow_array('SELECT COUNT(*) FROM article_search WHERE article_id = 8'), '検索用のテキスト';
	is_deeply tag_names(8), ['Perl', '料理::調味料'], '無いタグは親から作る';
	is $dbh->selectrow_array('SELECT COUNT(*) FROM tag_paths WHERE descendant = (SELECT id FROM tags WHERE name = ?)', undef, '調味料'), 2,
		'閉包テーブルを作り直す';
	is $dbh->selectrow_array('SELECT COUNT(*) FROM revisions'), 0, '新しい記事には履歴を残さない';
};

subtest '書き換え' => sub {
	my $before = $dbh->selectrow_hashref('SELECT * FROM articles WHERE id = 8');
	my ($v) = form(title => '新しい記事', body => $before->{body_src}, tag => ['Perl'], status => 'published',
		digest => Lyndbaum::Model::Article->digest($dbh, 8));
	my $r = save($v, id => 8, now => 2000);
	is_deeply $r, { id => 8, slug => '08' };
	my $a = $dbh->selectrow_hashref('SELECT * FROM articles WHERE id = 8');
	is $a->{status}, 'published';
	is $a->{published_at}, 2000, '公開するときに公開日時が空なら、今の時刻';
	is $a->{created_at}, 1000;
	is $a->{body_src}, $before->{body_src}, '識別子のある見出しはそのまま';
	is_deeply tag_names(8), ['Perl'], 'タグを付け替える';
	is $dbh->selectrow_array('SELECT COUNT(*) FROM tags'), 3, 'あるタグは作らない（最上位のタグを含む）';
	is $dbh->selectrow_array('SELECT COUNT(*) FROM revisions'), 0, '題名と本文が同じなら履歴を残さない';

	($v) = form(title => '直した題名', body => '直した本文', status => 'published', published_at => '2026-01-02T03:04');
	save($v, id => 8, now => 3000);
	$a = $dbh->selectrow_hashref('SELECT * FROM articles WHERE id = 8');
	is $a->{published_at}, parse_input_date('2026-01-02T03:04'), '公開日時を直せる';
	is_deeply $dbh->selectrow_arrayref('SELECT title, body_src, saved_at, created_at FROM revisions WHERE article_id = 8'),
		['新しい記事', $before->{body_src}, 2000, 3000], '保存する前の版を履歴に残す';
};

subtest 'ほかの画面で先に保存されていたら保存しない' => sub {
	my $digest = Lyndbaum::Model::Article->digest($dbh, 8);
	$dbh->do(q{UPDATE articles SET title = '別のタブで直した' WHERE id = 8});
	my ($v) = form(title => '古い画面から', digest => $digest);
	my $r = save($v, id => 8, now => 4000);
	ok $r->{conflict}, '開いたときの更新日時と違う';
	is $r->{conflict}{title}, '別のタブで直した', '今の記事を返す';
	is $dbh->selectrow_array('SELECT title FROM articles WHERE id = 8'), '別のタブで直した', '書き換えない';

	($v) = form(title => '今の画面から', digest => Lyndbaum::Model::Article->digest($dbh, 8));
	ok !save($v, id => 8, now => 5000)->{conflict}, '要約が同じなら保存する';
};

subtest '更新日時を変えない' => sub {
	my $before = $dbh->selectrow_hashref('SELECT updated_at FROM articles WHERE id = 8');
	my $digest = Lyndbaum::Model::Article->digest($dbh, 8);
	my ($v) = form(title => '誤字を直した', keep_updated => '1', digest => $digest);
	ok !save($v, id => 8, now => 6000)->{conflict};
	is $dbh->selectrow_array('SELECT updated_at FROM articles WHERE id = 8'), $before->{updated_at}, '更新日時はそのまま';
	is $dbh->selectrow_array('SELECT title FROM articles WHERE id = 8'), '誤字を直した';
	isnt(Lyndbaum::Model::Article->digest($dbh, 8), $digest, '更新日時が同じでも、中身が変われば要約が変わる');

	my ($new) = form(title => '新しい記事でも', keep_updated => '1');
	my $r = save($new, now => 7000);
	is $dbh->selectrow_array('SELECT updated_at FROM articles WHERE id = ?', undef, $r->{id}), 7000, '新しい記事には効かない';
};

subtest 'コンテンツページ' => sub {
	my $page = sub {
		my (%f) = @_;
		my $id = delete $f{id};
		my ($v, $errors) = Lyndbaum::ArticleForm->parse(
			values     => sub { my $x = { title => 'ページ', body => '本文', status => 'published', %f }->{ $_[0] }; defined $x ? ($x) : () },
			tag_exists => sub { 1 },
			page       => 1,
		);
		return (undef, [ map { $_->{message} } @$errors ]) if @$errors;
		my $r = save($v, id => $id);
		return ($r, $r->{errors} // []);
	};
	my ($top) = $page->(page_name => 'about');
	is $dbh->selectrow_array('SELECT slug FROM articles WHERE id = ?', undef, $top->{id}), 'about', '親が無ければ名前が slug';
	is $dbh->selectrow_array('SELECT kind FROM articles WHERE id = ?', undef, $top->{id}), 'page';
	my ($child) = $page->(page_name => '署名', parent_id => $top->{id});
	my ($grandchild) = $page->(page_name => '孫', parent_id => $child->{id});
	is $grandchild->{slug}, 'about/署名/孫', '「親の slug/名前」';
	my ($second) = $page->(page_name => '二つ目', parent_id => $top->{id});
	my $orders = $dbh->selectcol_arrayref('SELECT sort_order FROM articles WHERE id IN (?, ?) ORDER BY id', undef, $child->{id}, $second->{id});
	is $orders->[1], $orders->[0] + 1, '並び順が空なら、同じ親のいちばん後ろ';

	$page->(id => $top->{id}, page_name => 'profile');
	is_deeply $dbh->selectcol_arrayref('SELECT slug FROM articles WHERE id IN (?, ?, ?) ORDER BY id', undef, $top->{id}, $child->{id}, $grandchild->{id}),
		['profile', 'profile/署名', 'profile/署名/孫'], '名前を変えると、子孫の slug も付け替える';
	$page->(id => $grandchild->{id}, page_name => '孫', parent_id => $second->{id});
	is $dbh->selectrow_array('SELECT slug FROM articles WHERE id = ?', undef, $grandchild->{id}), 'profile/二つ目/孫', '親を変える';

	my (undef, $errors) = $page->(id => $top->{id}, page_name => 'profile', parent_id => $second->{id});
	like $errors->[0], qr{自分の子孫のページを親にはできません}, '子孫を親にはできない';
	(undef, $errors) = $page->(page_name => '0123');
	like $errors->[0], qr{0で始められません};
	(undef, $errors) = $page->(page_name => 'Admin');
	like $errors->[0], qr{管理画面などが使う};
	(undef, $errors) = $page->(page_name => '署名', parent_id => $top->{id});
	like $errors->[0], qr{URL「/profile/署名」は、「ページ」が使っています。}, 'slug はぶつけられない';
	(undef, $errors) = $page->(page_name => 'a/b');
	like $errors->[0], qr{使えません}, '名前に / は使えない';
	(undef, $errors) = $page->(page_name => 'x', parent_id => 99999);
	like $errors->[0], qr{親のページがありません};
};

subtest '見出しと目次のリンクには記事のURLを付ける' => sub {
	my ($v) = form(body => "# 見出し\n\n[*toc]", status => 'published');
	my $post = save($v);
	my $html = $dbh->selectrow_array('SELECT body_html FROM articles WHERE id = ?', undef, $post->{id});
	like $html, qr{<h3 id="([^"]+)"><a href="/0$post->{id}#\1">見出し</a></h3>}, '記事は /0ID#見出しのID';
	like $html, qr{<li><a href="/0$post->{id}#[^"]+">見出し</a></li>}, '目次も';

	my $page = sub {
		my (%f) = @_;
		my $id = delete $f{id};
		my ($v) = Lyndbaum::ArticleForm->parse(
			values     => sub { my $x = { title => 'ページ', body => "# 見出し", status => 'published', %f }->{ $_[0] }; defined $x ? ($x) : () },
			tag_exists => sub { 1 },
			page       => 1,
		);
		return save($v, id => $id);
	};
	my $parent = $page->(page_name => 'docs');
	my $child  = $page->(page_name => '使い方', parent_id => $parent->{id});
	my $body_of = sub { $dbh->selectrow_array('SELECT body_html FROM articles WHERE id = ?', undef, $_[0]) };
	like $body_of->($child->{id}), qr{<a href="/docs/%E4%BD%BF%E3%81%84%E6%96%B9#[^"]+">}, 'ページは slug のURL（Lyndbaum::URL->article と同じ形）';
	$page->(id => $parent->{id}, page_name => 'manual');
	like $body_of->($parent->{id}), qr{<a href="/manual#[^"]+">}, '名前を変えたページ';
	like $body_of->($child->{id}), qr{<a href="/manual/%E4%BD%BF%E3%81%84%E6%96%B9#[^"]+">}, '子孫の本文も変換し直す';
};

subtest 'ゴミ箱' => sub {
	my $parent = $dbh->selectrow_hashref(q{SELECT id FROM articles WHERE slug = 'profile'});
	my $child  = $dbh->selectrow_hashref(q{SELECT id FROM articles WHERE slug = 'profile/署名'});
	my ($count, $errors) = Lyndbaum::Model::Article->move_to_trash($dbh, [ $parent->{id} ]);
	is $count, 0;
	like $errors->[0], qr{子ページがあるので、ゴミ箱へ移せません}, '子ページのあるページは移せない';

	my ($r) = save((form(title => '消す記事'))[0]);
	$dbh->do(q{INSERT INTO comments (article_id, num, author_name, body, created_at) VALUES (?, 1, 'a', 'b', 1)}, undef, $r->{id});
	($count) = Lyndbaum::Model::Article->move_to_trash($dbh, [ $r->{id} ], now => 100);
	is $count, 1;
	is $dbh->selectrow_array('SELECT deleted_at FROM articles WHERE id = ?', undef, $r->{id}), 100;
	is(Lyndbaum::Model::Article->find_for_admin($dbh, $r->{id}), undef, '編集の対象から外れる');
	is_deeply [ map { $_->{id} } @{ Lyndbaum::Model::Article->list_trash($dbh) } ], [ $r->{id} ];
	is(Lyndbaum::Model::Article->restore($dbh, [ $r->{id} ]), 1, '戻す');
	is $dbh->selectrow_array('SELECT COUNT(*) FROM comments WHERE article_id = ?', undef, $r->{id}), 1, 'コメントもそのまま';

	Lyndbaum::Model::Article->move_to_trash($dbh, [ $r->{id} ]);
	($count) = Lyndbaum::Model::Article->purge($dbh, [ $r->{id} ]);
	is $count, 1, '完全に削除';
	is $dbh->selectrow_array('SELECT COUNT(*) FROM comments WHERE article_id = ?', undef, $r->{id}), 0, 'コメントも消える';
	my ($next) = save((form(title => '次の記事'))[0]);
	is $next->{id}, $r->{id} + 1, '完全に削除した記事のIDは使い回さない';

	# 親と子を一緒に消すときは、子から消す。親だけなら消さない
	my $grand = $dbh->selectrow_hashref(q{SELECT id FROM articles WHERE slug = 'profile/二つ目/孫'});
	my $second = $dbh->selectrow_hashref(q{SELECT id FROM articles WHERE slug = 'profile/二つ目'});
	Lyndbaum::Model::Article->move_to_trash($dbh, [ $grand->{id}, $second->{id} ]);
	($count, $errors) = Lyndbaum::Model::Article->purge($dbh, [ $second->{id} ]);
	is $count, 0;
	like $errors->[0], qr{子ページがあるので、完全に削除できません}, '子ページのあるページは消さない';
	($count, $errors) = Lyndbaum::Model::Article->purge($dbh, undef);
	is $count, 2, 'ゴミ箱を空にする（子から消す）';
	is_deeply $errors, [];
};

subtest '更新履歴' => sub {
	my ($r) = save((form(title => '履歴の記事', body => '版0'))[0], now => 0);
	my $edit = sub {
		my ($body, $now, %opt) = @_;
		save((form(title => '履歴の記事', body => $body))[0], id => $r->{id}, now => $now, %opt);
	};
	my $revs = sub { $dbh->selectall_arrayref('SELECT body_src, saved_at, created_at FROM revisions WHERE article_id = ? ORDER BY id', undef, $r->{id}) };

	$edit->('版1', 10_000);
	is_deeply $revs->(), [ ['版0', 0, 10_000] ], '保存する前の版。saved_at は版が保存された日時、created_at は履歴に加えた日時';
	$edit->('版2', 10_000 + 3 * 3600 - 1);
	is scalar @{ $revs->() }, 1, '前に履歴を残してから3時間の中なら残さない（続けた保存を1つの版にまとめる）';
	$edit->('版3', 10_000 + 3 * 3600);
	is_deeply $revs->()->[-1], ['版2', 10_000 + 3 * 3600 - 1, 10_000 + 3 * 3600], '3時間たてば残す';
	$edit->('版4', 30_000, revision_interval => 0);
	is scalar @{ $revs->() }, 3, '間隔が0なら、変わるたびに残す';

	$edit->('版5', 40_000, revision_interval => 0, revision_max => 2);
	is_deeply [ map { $_->[0] } @{ $revs->() } ], ['版3', '版4'], '件数を超えたら古いものから消す';
	$edit->('版6', 50_000, revision_interval => 0, revision_max => 0);
	is scalar @{ $revs->() }, 3, '件数が0なら制限しない';

	my $list = Lyndbaum::Model::Article->revisions($dbh, $r->{id});
	is_deeply [ map { $_->{length} } @$list ], [2, 2, 2], '一覧は新しい順で、本文の文字数を付ける';
	is(Lyndbaum::Model::Article->revision($dbh, $r->{id}, $list->[0]{id})->{body_src}, '版5');
	is(Lyndbaum::Model::Article->revision($dbh, $r->{id} + 1000, $list->[0]{id}), undef, 'ほかの記事の履歴は取れない');
};

done_testing;
