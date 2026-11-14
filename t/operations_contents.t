use strict;
use utf8;
#-------------------------------------------------------------------------------
# 固定ページの親子とパーマリンクのテスト
#-------------------------------------------------------------------------------
# 実行: prove t/operations_contents.t
#
# パーマリンクは、親があれば「親のパーマリンク/名前」、なければ「名前」。名前に/は使えない。
# 公開中のページの親は、いつも公開中（親を非公開にすると子も非公開になる）。
# 子のある固定ページは、子と一緒でなければゴミ箱へ移せない。
#
use FindBin;
BEGIN { push(@INC, "$FindBin::Bin/lib", "$FindBin::Bin/../lib"); }
use Test::More;
use AppTest;
use OpsTest;

binmode(Test::More->builder->$_, ':utf8') foreach (qw(output failure_output todo_output));

# 記事の番号が1から始まるよう、seed()はしない
my $app = AppTest->new()->setup();
my $dir = $app->dir;

# 固定ページ（公開していないものも）: pkey => { link_key, upnode, enable }
sub pages {
	require Satsuki::Base;
	my $ROBJ = Satsuki::Base->new();
	my $DB   = $ROBJ->loadpm('DB_text', "$dir/data/db/");
	return { map { $_->{pkey} => $_ } @{ $DB->select_match('art', '-ctype', '') } };
}
sub link_keys {
	my $p = pages();
	return { map { $_ => $p->{$_}->{link_key} } keys(%$p) };
}
sub comment_keys {
	require Satsuki::Base;
	my $ROBJ = Satsuki::Base->new();
	my $DB   = $ROBJ->loadpm('DB_text', "$dir/data/db/");
	return { map { $_->{a_pkey} => $_->{a_elink_key} } @{ $DB->select_match('com') } };
}
sub page {	# 固定ページを書く・直す
	my %f = @_;
	return $app->post('admin', '', { %ART, page => 1, body_txt => "本文\n", %f });
}
sub save_tree {	# 表示順の保存（pkey,upnode,priority,名前）
	return $app->post('admin', 'contents_edit', [ action => 'contents_edit', map { (contents_txt_ary => $_) } @_ ]);
}

#-------------------------------------------------------------------------------
# 編集画面
#-------------------------------------------------------------------------------
subtest '編集画面：パーマリンクは親のパス/名前' => sub {
	ok(AppTest::is_reload(page(title => 'A', link_key_txt => 'a')), 'Aを書ける');
	ok(AppTest::is_reload(page(title => 'B', link_key_txt => 'b', upnode => 1)), 'Aの子Bを書ける');
	ok(AppTest::is_reload(page(title => 'C', link_key_txt => 'c', upnode => 2)), 'Bの子Cを書ける');
	ok(AppTest::is_reload(page(title => 'E', link_key_txt => 'e', upnode => 2, enable => 0)), 'Bの子Eを非公開で書ける');
	is_deeply(link_keys(), { 1 => 'a', 2 => 'a/b', 3 => 'a/b/c', 4 => 'a/b/e' }, '親のパスの後ろに名前が付く');

	my $r = page(title => 'F', link_key_txt => 'x/f', upnode => 1);
	ok(!AppTest::is_reload($r), '名前に/は使えない');
	like(body($r), qr{パーマリンクの名前に文字「/」は使えません}, 'エラーの文言');
	ok(!exists pages()->{5}, '保存されない');

	$r = page(edit_pkey_int => 1, title => 'A', link_key_txt => 'a', upnode => 3);
	ok(!AppTest::is_reload($r), '子孫を親にできない');
	like(body($r), qr{このページと、その子孫のページは親にできません}, 'エラーの文言');
	$r = page(edit_pkey_int => 1, title => 'A', link_key_txt => 'a', upnode => 1);
	ok(!AppTest::is_reload($r), '自分を親にできない');
	is(pages()->{1}->{upnode}, 0, '親は変わらない');

	$r = page(edit_pkey_int => 2, title => 'B', link_key_txt => 'a', upnode => 0);
	ok(AppTest::is_reload($r), '根で重なる名前は、数字を付けて保存する（今までどおり）');
	is(pages()->{2}->{link_key}, 'a2', '「a2」になる');
	ok(AppTest::is_reload(page(edit_pkey_int => 2, title => 'B', link_key_txt => 'b', upnode => 1)), 'Aの子に戻せる');
	is_deeply(link_keys(), { 1 => 'a', 2 => 'a/b', 3 => 'a/b/c', 4 => 'a/b/e' }, '子孫も戻る');
};

subtest '編集画面：親のパーマリンクを変えると子孫も変わる' => sub {
	$app->post('admin', '', { action => 'comment_post', a_pkey => 3, comment_txt => 'Cへのコメント', name => 'admin' });
	is(comment_keys()->{3}, 'a/b/c', 'コメントは記事のパーマリンクを持つ');

	ok(AppTest::is_reload(page(edit_pkey_int => 1, title => 'A', link_key_txt => 'x')), 'Aの名前を変えられる');
	is_deeply(link_keys(), { 1 => 'x', 2 => 'x/b', 3 => 'x/b/c', 4 => 'x/b/e' }, '子と孫（非公開のものも）が変わる');
	is(comment_keys()->{3}, 'x/b/c', 'コメントのパーマリンクも変わる');
	is($app->get('guest', '/x/b/c')->{status}, 200, '新しいURLで出る');
	is($app->get('guest', '/a/b/c')->{status}, 404, '古いURLは出ない');
};

subtest '編集画面：子のあるページはブログ記事にできない' => sub {
	my $r = $app->post('admin', '', { %ART, edit_pkey_int => 2, title => 'B', body_txt => "本文\n" });
	ok(!AppTest::is_reload($r), '保存できない');
	like(body($r), qr{子の固定ページがあるので、ブログ記事にはできません}, 'エラーの文言');
	is(pages()->{2}->{ctype}, 'page', '固定ページのまま');
};

#-------------------------------------------------------------------------------
# 公開と非公開
#-------------------------------------------------------------------------------
subtest '親を非公開にすると子も非公開になる' => sub {
	ok(AppTest::is_reload(page(edit_pkey_int => 2, title => 'B', link_key_txt => 'b', upnode => 1, enable => 0)), 'Bを非公開にできる');
	my $p = pages();
	is($p->{3}->{enable}, 0, '子のCも非公開になる');
	is($app->get('guest', '/x/b/c')->{status}, 404, 'Cは出ない');

	my $r = page(edit_pkey_int => 3, title => 'C', link_key_txt => 'c', upnode => 2);
	ok(!AppTest::is_reload($r), '親が非公開なら、子は公開できない');
	like(body($r), qr{親の固定ページが非公開なので、公開できません}, 'エラーの文言');
	ok(AppTest::is_reload(page(edit_pkey_int => 3, title => 'C', link_key_txt => 'c', upnode => 2, enable => 0)), '非公開のままなら保存できる');
	is(pages()->{3}->{upnode}, 2, '非公開の親のまま');

	$r = $app->post('admin', 'artlist', [ action => 'articles_edit', mode => 'enable', pkey_ary => 3 ]);
	like(body($r), qr{「C」の親の固定ページが非公開なので、公開できません}, '一覧で子だけ公開しようとすると、メッセージが出る');
	is(pages()->{3}->{enable}, 0, '子だけは公開されない');

	$app->post('admin', 'artlist', [ action => 'articles_edit', mode => 'enable', pkey_ary => 2, pkey_ary => 3 ]);
	$p = pages();
	is_deeply([ $p->{2}->{enable}, $p->{3}->{enable} ], [ 1, 1 ], '親と一緒なら公開できる');

	$app->post('admin', 'artlist', [ action => 'articles_edit', mode => 'disable', pkey_ary => 1 ]);
	$p = pages();
	is_deeply([ map { $p->{$_}->{enable} } 1..3 ], [ 0, 0, 0 ], '一覧でAを非公開にすると、子孫も非公開になる');
	$app->post('admin', 'artlist', [ action => 'articles_edit', mode => 'enable', pkey_ary => 1, pkey_ary => 2, pkey_ary => 3 ]);
	$p = pages();
	is_deeply([ map { $p->{$_}->{enable} } 1..3 ], [ 1, 1, 1 ], 'まとめて公開に戻せる');

	ok(AppTest::is_reload(page(edit_pkey_int => 1, title => 'A', link_key_txt => 'x', draft => 1)), 'Aを下書きにできる');
	$p = pages();
	is_deeply([ map { $p->{$_}->{enable} } 1..3 ], [ 0, 0, 0 ], '下書きにしても、子孫は非公開になる');
	ok(AppTest::is_reload(page(edit_pkey_int => 1, title => 'A', link_key_txt => 'x')), 'Aを公開に戻す');
	$app->post('admin', 'artlist', [ action => 'articles_edit', mode => 'enable', pkey_ary => 2, pkey_ary => 3 ]);
};

#-------------------------------------------------------------------------------
# 表示順の画面
#-------------------------------------------------------------------------------
subtest '表示順の保存：名前だけを送る' => sub {
	# 今：1 x、2 x/b、3 x/b/c、4 x/b/e（非公開）
	my $r = save_tree('1,0,10,x', '2,1,20,bb', '3,2,30,c');
	ok(AppTest::is_reload($r), '保存できる');
	is_deeply(link_keys(), { 1 => 'x', 2 => 'x/bb', 3 => 'x/bb/c', 4 => 'x/bb/e' }, '名前を変えると、子孫（ツリーに出ない非公開のものも）が変わる');

	$r = save_tree('1,0,10,x', '2,0,20,bb', '3,2,30,c');
	is_deeply(link_keys(), { 1 => 'x', 2 => 'bb', 3 => 'bb/c', 4 => 'bb/e' }, '根へ動かすと、親のパスが外れる');
	$r = save_tree('1,0,10,x', '2,1,20,bb', '3,2,30,c');
	is_deeply(link_keys(), { 1 => 'x', 2 => 'x/bb', 3 => 'x/bb/c', 4 => 'x/bb/e' }, 'Aの下に戻すと、親のパスが付く');

	foreach (['hoge/c', '/を含む'], ['..', '..'], ['', '空']) {
		my ($name, $label) = @$_;
		$r = save_tree('1,0,10,x', '2,1,20,bb', "3,2,30,$name");
		like(body($r), qr{「C」のパーマリンクは保存しませんでした}, "$label：メッセージが出る");
		is(link_keys()->{3}, 'x/bb/c', "$label：変わらない");
	}
	$r = save_tree('1,0,10,x', '2,1,20,bb', '3,1,30,bb');
	like(body($r), qr{パーマリンク「x/bb」は、ほかで使われています}, '重なると、メッセージが出る');
	is_deeply([ link_keys()->{3}, pages()->{3}->{upnode} ], [ 'x/bb/c', 2 ], '重なると、親もパーマリンクも変わらない');

	$r = save_tree('1,3,10,x', '2,1,20,bb', '3,2,30,c');
	like(body($r), qr{固定ページのツリーが正しくないので、保存しませんでした}, '親を辿って自分に戻るものは保存しない');
	is(pages()->{1}->{upnode}, 0, '変わらない');
};

#-------------------------------------------------------------------------------
# ゴミ箱
#-------------------------------------------------------------------------------
subtest '子のあるページはゴミ箱へ移せない' => sub {
	my $r = $app->post('admin', 'artlist', [ action => 'articles_edit', mode => 'delete', pkey_ary => 2 ]);
	like(body($r), qr{「B」には子の固定ページがあるので、ゴミ箱へ移せません}, 'メッセージが出る');
	ok(pages()->{2}, '移らない');

	$r = $app->post('admin', '', { action => 'delete', delete_pkey_ary => 2, title => 'B' });
	ok(!AppTest::is_reload($r), '編集画面の削除でも移せない');
	ok(pages()->{2}, '移らない');

	$app->post('admin', 'artlist', [ action => 'articles_edit', mode => 'delete', pkey_ary => 2, pkey_ary => 3, pkey_ary => 4 ]);
	my $p = pages();
	ok(!$p->{2} && !$p->{3} && !$p->{4}, '子孫と一緒なら移せる');

	$r = $app->post('admin', '', { action => 'trash', mode => 'restore', pkey_ary => 3 });
	like(body($r), qr{「C」の親の固定ページがないので、ゴミ箱から戻せません}, '親のない子は戻せない');
	ok(!pages()->{3}, '戻らない');

	ok(AppTest::is_reload(page(edit_pkey_int => 1, title => 'A', link_key_txt => 'y')), 'ゴミ箱にある間に、Aの名前を変える');
	$app->post('admin', '', [ action => 'trash', mode => 'restore', pkey_ary => 3, pkey_ary => 2 ]);
	$p = pages();
	is_deeply([ map { $p->{$_} && $p->{$_}->{link_key} } 2, 3 ], [ 'y/bb', 'y/bb/c' ], '親と一緒なら戻せる。パーマリンクは今の親から作る');
};

done_testing();
