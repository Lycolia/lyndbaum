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
use POSIX ();

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

#-------------------------------------------------------------------------------
# 空のindex
#-------------------------------------------------------------------------------
{
	$DB->create_table('emp', [ { name => 'title', type => 'text', index => 1 } ]);
	$DB->insert('emp', { title => 'a' }) for 1..2;

	# 前の版が書き込みの途中で落ちて、空になった場合
	truncate("${dir}emp/#index.dat", 0) || die $!;
	$DB->clear_cache('emp');
	is($DB->select_match_limit1('emp', 'pkey', 2)->{title}, 'a', '空のindexは読むときに作り直す');
	is(&read_index("emp/#index.dat")->[2], '000002', 'シリアル値も戻る');

	truncate("${dir}emp/#index.dat", 0) || die $!;
	$DB->clear_cache('emp');
	is($DB->insert('emp', { title => 'b' }), 3, '空のindexは書くときに作り直す');

	truncate("${dir}emp/#index.dat", 0) || die $!;
	$DB->clear_cache('emp');
	is($DB->generate_pkey('emp'), 4, 'generate_pkeyでも作り直す');

	# バックアップも空なら、作り直せない（止まらずに失敗する）
	truncate("${dir}emp/#index.dat", 0) || die $!;
	truncate("${dir}emp/#index.backup.dat", 0) || die $!;
	$DB->clear_cache('emp');
	$DB->set_noerror(1);
	my $r = eval {
		local $SIG{ALRM} = sub { die "timeout\n" };
		alarm(5);
		my $r = $DB->select_match_limit1('emp', 'pkey', 2);
		alarm(0);
		$r;
	};
	alarm(0);
	is($@, '', 'バックアップも空のとき、再帰で止まらない');
	is($r, undef, '行は返らない');
	$DB->set_noerror(0);
}

#-------------------------------------------------------------------------------
# 書き込みの失敗
#-------------------------------------------------------------------------------
SKIP: {
	skip 'rootでは書き込みを止められません', 4 if ($< == 0);
	$DB->create_table('wf', [ { name => 'title', type => 'text' } ]);
	$DB->insert('wf', { title => 'a' });

	# 次の行のファイルに書けない
	open(my $fh, '>', "${dir}wf/00002.dat") || die $!;
	close($fh);
	chmod(0444, "${dir}wf/00002.dat");
	$ROBJ->clear_error();
	is($DB->insert('wf', { title => 'b' }), 0, '行のファイルに書けなければ失敗を返す');
	$ROBJ->clear_error();
	is(scalar(@{ &read_index('wf/#index.dat') }) - 12, 1, 'indexに行を足さない');
	ok(&insert_with_timeout('wf', { title => 'c', pkey => 5 }), '失敗した後もロックが残らない');
	is($DB->select_match_limit1('wf', 'pkey', 5)->{title}, 'c', '失敗の後も書き込める');
	chmod(0644, "${dir}wf/00002.dat");
}

SKIP: {
	skip 'rootでは書き込みを止められません', 3 if ($< == 0);
	$DB->create_table('wi', [ { name => 'title', type => 'text' } ]);
	$DB->insert('wi', { title => 'a' });
	my $before = &read_index('wi/#index.dat');

	# フォルダに書けないと、indexの一時ファイルを作れない。行のファイルはすでにあるものを使う
	open(my $fh, '>', "${dir}wi/00002.dat") || die $!;
	close($fh);
	chmod(0555, "${dir}wi");
	$ROBJ->clear_error();
	is($DB->insert('wi', { title => 'b' }), 0, 'indexを書けなければ失敗を返す');
	$ROBJ->clear_error();
	chmod(0755, "${dir}wi");
	is_deeply(&read_index('wi/#index.dat'), $before, 'indexは前のまま残る');
	ok(&insert_with_timeout('wi', { title => 'c' }), '失敗の後も書き込める');
}

#-------------------------------------------------------------------------------
# indexの置き換えとロック
#-------------------------------------------------------------------------------
{
	$DB->create_table('par', [ { name => 'title', type => 'text', index => 1 } ]);
	my $n = 40;
	my @pids;
	foreach my $w (1..3) {
		my $pid = fork();
		die "fork: $!" if (!defined $pid);
		if (!$pid) {
			alarm(30);
			srand();	# 親が乱数を使った後なので、子ごとに種を変える（indexの署名が重ならないように）
			my $R = Satsuki::Base->new();
			my $D = $R->loadpm('DB_text', $dir);
			# insertとgenerate_pkeyの両方が、置き換えられたindexを正しく開き直す
			foreach my $i (1..$n) {
				my $key = $i % 2 ? undef : $D->generate_pkey('par');
				$D->insert('par', { title => "$w-$i", ($key ? (pkey => $key) : ()) }) || POSIX::_exit(1);
			}
			POSIX::_exit(0);
		}
		push(@pids, $pid);
	}
	my $fail = 0;
	foreach (@pids) { waitpid($_, 0); $fail ||= $?; }
	is($fail, 0, '同時に書いても失敗しない');

	$DB->clear_cache('par');
	my $rows = $DB->select('par', { cols => ['pkey', 'title'] });
	is(scalar(@$rows), $n*3, '同時に書いても行が失われない');
	my %titles = map { $_->{title} => 1 } @$rows;
	is(scalar(keys(%titles)), $n*3, 'どの書き込みも残る');
	my %pkeys  = map { $_->{pkey}  => 1 } @$rows;
	is(scalar(keys(%pkeys)), $n*3, 'pkeyが重ならない');
	is_deeply([ grep { /\.tmp$/ } @{ $ROBJ->search_files("${dir}par/") } ], [], '一時ファイルが残らない');
}

#-------------------------------------------------------------------------------
# pkeyを指定したinsertとシリアル値
#-------------------------------------------------------------------------------
{
	$DB->create_table('ser', [ { name => 'title', type => 'text' } ]);
	is($DB->insert('ser', { title => 'a', pkey => 100 }), 100, 'pkeyを指定して足す');
	is(&read_index('ser/#index.dat')->[2], '00000100', 'シリアル値がファイルに残る');
	is($DB->insert('ser', { title => 'b' }), 101, '次の普通のinsertは続きの番号になる');
	is($DB->insert('ser', { title => 'c', pkey => 50 }), 50, '小さいpkeyも指定できる');
	is(&read_index('ser/#index.dat')->[2], '00000101', '小さいpkeyではシリアル値を戻さない');
	is($DB->insert('ser', { title => 'd' }), 102, '続きの番号のまま');

	$DB->begin();
	is($DB->insert('ser', { title => 'e', pkey => 200 }), 200, 'トランザクションでも指定できる');
	is($DB->insert('ser', { title => 'f' }), 201, 'トランザクションの中でも続きの番号になる');
	is($DB->commit(), 0, 'コミットする');
	is(&read_index('ser/#index.dat')->[2], '00000201', 'コミットでシリアル値が残る');
}

#-------------------------------------------------------------------------------
# 行ファイルを書けなかったとき
#-------------------------------------------------------------------------------
# 行ファイルは一時ファイルに書いてから置き換えるので、書けなくても元の中身が残る。
# そのときはindexも保存せず、失敗を返す
{
	$DB->create_table('wf2', [ { name => 'title', type => 'text' }, { name => 'body', type => 'text' } ]);
	$DB->add_index('wf2', 'title');
	my $pkey = $DB->insert('wf2', { title => 'old', body => "line1\nline2" });
	my $row_file = sprintf('wf2/%05d.dat', $pkey);
	my $row      = join('', map { "$_\n" } @{ &read_index($row_file) });
	my $index    = join("\n", @{ &read_index('wf2/#index.dat') }[2..100]);	# 2行目のランダム値より後

	# 行ファイル（数字.dat）だけ書けなくする
	my $orig = \&Satsuki::Base::fwrite_atomic;
	my $deny = sub {
		my ($self, $file) = @_;
		if ($file =~ m|/\d+\.dat$|) { $self->error("File can't write '%s'", $file); return 1; }
		return &$orig(@_);
	};
	my $unchanged = sub {
		my $name = shift;
		$ROBJ->clear_error();
		is(join('', map { "$_\n" } @{ &read_index($row_file) }), $row, "$name：行ファイルは元の中身のまま");
		is(join("\n", @{ &read_index('wf2/#index.dat') }[2..100]), $index, "$name：indexも変わらない");
		my $h = $DB->select_match_limit1('wf2', 'pkey', $pkey);
		is($h->{title}, 'old',          "$name：読み直すと元のtitle");
		is($h->{body},  "line1\nline2", "$name：読み直すと元のbody");
	};

	{
		no warnings 'redefine';
		local *Satsuki::Base::fwrite_atomic = $deny;
		is($DB->update_match('wf2', { title => 'new', body => 'new body' }, 'pkey', $pkey), 0, 'updateは失敗を返す');
	}
	&$unchanged('update');
	is(&insert_with_timeout('wf2', { title => 'next' }), $pkey + 1, '失敗した後もロックが残らない');
	$index = join("\n", @{ &read_index('wf2/#index.dat') }[2..100]);

	{
		no warnings 'redefine';
		local *Satsuki::Base::fwrite_atomic = $deny;
		$DB->begin();
		$DB->update_match('wf2', { title => 'new', body => 'new body' }, 'pkey', $pkey);
		$DB->insert('wf2', { title => 'in transaction' });
		is($DB->commit(), 1, 'commitは失敗を返す');
	}
	&$unchanged('commit');
	ok(!$DB->select_match_limit1('wf2', 'title', 'in transaction'), 'commit：足した行はindexに入らない');
	is(&insert_with_timeout('wf2', { title => 'next2' }), $pkey + 2, 'commit：失敗した後もロックが残らない');

	is($DB->update_match('wf2', { title => 'new', body => 'new body' }, 'pkey', $pkey), 1, '書けるようになれば更新できる');
	is($DB->select_match_limit1('wf2', 'pkey', $pkey)->{body}, 'new body', '更新した中身を読める');
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
