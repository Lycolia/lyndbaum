use strict;
#-------------------------------------------------------------------------------
# テキストDBのテーブル操作のテスト
#-------------------------------------------------------------------------------
# 実行: prove t/db_text.t
#
use FindBin;
BEGIN { push(@INC, "$FindBin::Bin/../lib"); }
use Test::More;
use File::Temp ();

require Satsuki::Base;
my $ROBJ = Satsuki::Base->new();
my $dir  = File::Temp::tempdir(CLEANUP => 1) . '/';
my $DB   = $ROBJ->loadpm('DB_text', $dir);

is($DB->create_table('old_art', [ { name => 'title', type => 'text' } ]), 0, 'テーブルを作る');
ok($DB->insert('old_art', { title => 'abc' }), '行を足す');

#-------------------------------------------------------------------------------
# rename_table
#-------------------------------------------------------------------------------
is($DB->rename_table('old_art', 'art'), 0, '名前を変える');
ok(!$DB->find_table('old_art'), '元の名前のテーブルは無くなる');
ok( $DB->find_table('art'), '新しい名前のテーブルがある');
is($DB->select_match_limit1('art', 'title', 'abc')->{title}, 'abc', '行はそのまま残る');

is($DB->rename_table('none', 'none2'), 1, '無いテーブルは変えられない');

$DB->create_table('other', [ { name => 'title', type => 'text' } ]);
is($DB->rename_table('other', 'art'), 2, '同じ名前のテーブルがあれば変えない');
ok($DB->find_table('other'), '変えなかったテーブルは残る');
is($DB->select_match_limit1('art', 'title', 'abc')->{title}, 'abc', '先にあったテーブルも壊さない');

#-------------------------------------------------------------------------------
# add_index
#-------------------------------------------------------------------------------
{
	$DB->create_table('idx', [ { name => 'title', type => 'text' }, { name => 'num', type => 'int' } ]);
	$DB->insert('idx', { title => 'abc', num => 2 });
	$DB->insert('idx', { title => 'def', num => 1 });

	is($DB->add_index('idx', 'title'), 0, 'indexを足す');
	my $lines = &read_index("idx/#index.dat");
	is($lines->[11], "pkey\ttitle", 'indexのカラムに足される');
	is($lines->[12], "1\tabc", '1行目の値がindexに入る');
	is($lines->[13], "2\tdef", '2行目の値がindexに入る');
	is(&read_index("idx/#index.backup.dat")->[11], "pkey\ttitle", 'バックアップにも足される');

	is($DB->add_index('idx', 'title'), 0, '既にindexのカラムでも失敗しない');
	is($DB->add_index('idx', 'none'), 8, '無いカラムには足せない');
	ok($DB->insert('idx', { title => 'ghi' }), '失敗した後もロックが残らない');
	is($DB->select_match_limit1('idx', 'title', 'ghi', '*cols', 'num')->{num}, undef, '足した後も検索できる');
	is($DB->select_match_limit1('idx', 'title', 'abc')->{num}, 2, 'index外のカラムも読める');
}

#-------------------------------------------------------------------------------
# add_column
#-------------------------------------------------------------------------------
{
	$DB->create_table('col', [ { name => 'title', type => 'text' } ]);
	$DB->insert('col', { title => 'abc' });

	is($DB->add_column('col', { name => 'num', type => 'int', default => '5', index_tdb => 1 }), 0, '既定値とindex_tdbを付けて足す');
	my $lines = &read_index("col/#index.dat");
	is($lines->[10], "5\t\t", '既定値がindexの見出しに入る（カラムは名前順で、num、pkey、title）');
	is($lines->[11], "pkey\tnum", 'index_tdbでindexになる');
	is($lines->[12], "1\t5", '既存の行のindexに既定値が入る');
	is($DB->select_match_limit1('col', 'title', 'abc')->{num}, 5, '既存の行のファイルに既定値が入る');
	my $pkey = $DB->insert('col', { title => 'def' });
	is($DB->select_match_limit1('col', 'pkey', $pkey)->{num}, 5, '新しい行にも既定値が入る');

	is($DB->add_column('col', { name => 'req', type => 'text', not_null => 1 }), 0, 'not_nullを付けて足す');
	is(&read_index("col/#index.dat")->[9], "pkey\treq", 'NOT NULLのカラムになる');
	$DB->set_noerror(1);
	ok(!$DB->insert('col', { title => 'ghi' }), 'NOT NULLのカラムを渡さないと足せない');
	$DB->set_noerror(0);

	is($DB->add_column('col', { name => 'bad', type => 'none' }), 10, '型が違えば足せない');
	is($DB->add_column('col', { name => '', type => 'text' }), 8, '名前が無ければ足せない');
	ok($DB->insert('col', { title => 'jkl', req => 'x' }), '失敗した後もロックが残らない');
	unlike(&read_index("col/#index.dat")->[3], qr/bad/, '失敗したカラムは残らない');
}

#-------------------------------------------------------------------------------
# drop_column
#-------------------------------------------------------------------------------
{
	$DB->create_table('drop', [
		{ name => 'title', type => 'text' },
		{ name => 'who',   type => 'text', index => 1, not_null => 1 },
		{ name => 'num',   type => 'int' },
	]);
	$DB->insert('drop', { title => 'abc', who => 'me', num => 1 });
	$DB->add_column('drop', { name => 'def', type => 'text', default => 'x' });

	is($DB->drop_column('drop', 'who'), 0, 'indexとNOT NULLのカラムを消す');
	is($DB->drop_column('drop', 'def'), 0, '既定値のカラムを消す');
	foreach my $f ('drop/#index.dat', 'drop/#index.backup.dat') {
		my $lines = &read_index($f);
		is($lines->[3], "num\tpkey\ttitle", "$f のカラムの一覧から消える");
		is($lines->[11], 'pkey', "$f のindexから消える");
		is($lines->[10], "\t\t", "$f の既定値から消える");
	}
	is($DB->drop_column('drop', 'none'), 9, '無いカラムは消せない');

	my $row = $DB->select_match_limit1('drop', 'title', 'abc');
	ok(!exists($row->{who}), '行の値が消える');
	is($row->{num}, 1, 'ほかのカラムは残る');
	my $pkey = $DB->insert('drop', { title => 'new' });
	ok($pkey, 'NOT NULLのカラムを消した後は、無くても入れられる');
	is($DB->update_match('drop', { num => 2 }, 'pkey', $pkey), 1, '消した後も更新できる');
}

#-------------------------------------------------------------------------------
# NOT NULL
#-------------------------------------------------------------------------------
{
	$DB->create_table('nn', [ { name => 'title', type => 'text', not_null => 1 }, { name => 'flag', type => 'flag', not_null => 1 } ]);
	$DB->set_noerror(1);
	ok(!$DB->insert('nn', { flag => 1 }), '挿入でNOT NULLのカラムを渡さないと足せない');
	ok(!$DB->insert('nn', { title => '', flag => 1 }), '挿入でNOT NULLのカラムに空文字を渡すと足せない');
	my $pkey = $DB->insert('nn', { title => 'abc', flag => 0 });
	ok($pkey, '0は空ではないので足せる');
	ok(!$DB->update_match('nn', { title => '' }, 'pkey', $pkey), '更新でNOT NULLのカラムを空文字にできない');
	ok(!$DB->update_match('nn', { title => undef }, 'pkey', $pkey), '更新でNOT NULLのカラムをundefにできない');
	$DB->set_noerror(0);
	is($DB->update_match('nn', { flag => 1 }, 'pkey', $pkey), 1, '更新で渡さなかったNOT NULLのカラムは確かめない');
	is($DB->select_match_limit1('nn', 'pkey', $pkey)->{title}, 'abc', '拒んだ更新は書かれない');
}

#-------------------------------------------------------------------------------
# update_match の式
#-------------------------------------------------------------------------------
{
	$DB->create_table('ex', [ { name => 'num', type => 'int' } ]);
	my $pkey = $DB->insert('ex', { num => 1 });
	is($DB->update_match('ex', { '*num' => 'num+1' }, 'pkey', $pkey), 1, '式で更新する');
	is($DB->select_match_limit1('ex', 'pkey', $pkey)->{num}, 2, '式の結果が入る');

	$DB->set_noerror(1);
	ok(!$DB->update_match('ex', { '*num' => 'foo(1)' }, 'pkey', $pkey), '関数の呼び出しは拒む');
	ok(&insert_with_timeout('ex', { num => 3 }), '関数の呼び出しで拒んだ後もロックが残らない');
	ok(!$DB->update_match('ex', { '*num' => 'num+' }, 'pkey', $pkey), '書き方の誤った式は拒む');
	ok(&insert_with_timeout('ex', { num => 4 }), '式の誤りで拒んだ後もロックが残らない');
	ok(!$DB->update_match('ex', { '*pkey' => 'pkey+1' }, 'pkey', $pkey), 'pkeyは書き換えられない');
	ok(&insert_with_timeout('ex', { num => 5 }), 'pkeyで拒んだ後もロックが残らない');
	$DB->set_noerror(0);
	is($DB->select_match_limit1('ex', 'pkey', $pkey)->{num}, 2, '拒んだ更新は書かれない');
}

#-------------------------------------------------------------------------------
# index_rebuild
#-------------------------------------------------------------------------------
{
	$DB->create_table('rb', [ { name => 'title', type => 'text', index => 1 } ]);
	$DB->insert('rb', { title => 'a' }) for 1..3;

	unlink("${dir}rb/#index.dat") || die $!;
	$DB->clear_cache('rb');
	is($DB->insert('rb', { title => 'b' }), 4, 'indexを作り直した後は、最大のpkeyの次を振る');
	is(&read_index("rb/#index.dat")->[2], '000004', 'シリアル値は振った最大値');
	is($DB->select_match_limit1('rb', 'title', 'a', '*sort', 'pkey')->{pkey}, 1, '既存の行がindexに戻る');

	unlink("${dir}rb/#index.dat") || die $!;
	$DB->clear_cache('rb');
	is($DB->generate_pkey('rb'), 5, 'generate_pkeyで作り直したときも、最大のpkeyの次を振る');
}

# ロックが残っていると、同じプロセスでも書き込みが止まるので、時間を切る
sub insert_with_timeout {
	my ($table, $h) = @_;
	my $r = eval {
		local $SIG{ALRM} = sub { die "timeout\n" };
		alarm(5);
		my $r = $DB->insert($table, $h);
		alarm(0);
		$r;
	};
	alarm(0);
	return $r;
}

sub read_index {
	my $file = shift;
	open(my $fh, '<', "$dir$file") || die "$dir$file: $!";
	my @lines = map { s/\n$//r } <$fh>;
	close($fh);
	return \@lines;
}

done_testing();
