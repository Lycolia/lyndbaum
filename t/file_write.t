use strict;
use utf8;
#-------------------------------------------------------------------------------
# ファイルの書き込みのテスト
#-------------------------------------------------------------------------------
# 実行: prove t/file_write.t
#
use FindBin;
BEGIN { push(@INC, "$FindBin::Bin/../lib"); }
use Test::More;
use File::Temp ();
use POSIX ();

binmode(Test::More->builder->$_, ':utf8') foreach (qw(output failure_output todo_output));

require Satsuki::Base;
my $ROBJ = Satsuki::Base->new();
my $dir  = File::Temp::tempdir(CLEANUP => 1);

sub slurp {
	my $file = shift;
	open(my $fh, '<', $file) || die "$file: $!";
	local $/;
	return scalar(<$fh>);
}
sub is_root { return $< == 0; }

#-------------------------------------------------------------------------------
# fwrite_lines
#-------------------------------------------------------------------------------
subtest 'fwrite_linesは書き込みのエラーを返す' => sub {
	plan skip_all => '/dev/full がありません' if (!-w '/dev/full');
	is($ROBJ->fwrite_lines('/dev/full', "x\n"), 1, 'ディスクがいっぱいなら失敗を返す');
	$ROBJ->clear_error();
	is($ROBJ->fwrite_lines("$dir/ok.txt", "x\n"), 0, '書ければ成功を返す');
	is(slurp("$dir/ok.txt"), "x\n", '中身が入る');
};

#-------------------------------------------------------------------------------
# fwrite_atomic
#-------------------------------------------------------------------------------
subtest 'fwrite_atomicは書き終えてから置き換える' => sub {
	my $file = "$dir/atomic.txt";
	is($ROBJ->fwrite_atomic($file, ["a\n", "b\n"]), 0, '新しいファイルを作る');
	is(slurp($file), "a\nb\n", '中身が入る');

	chmod(0640, $file);
	my $before = (stat($file))[1];
	open(my $old, '<', $file) || die $!;
	is($ROBJ->fwrite_atomic($file, "c\n"), 0, '書き直す');
	is(slurp($file), "c\n", '新しい中身になる');
	is(scalar(<$old>), "a\n", '読んでいる途中の人には前の中身が見える');
	close($old);
	isnt((stat($file))[1], $before, '別のファイルに置き換わる');
	is((stat($file))[2] & 07777, 0640, 'パーミッションを引き継ぐ');
	is_deeply([ grep { /\.tmp$/ } @{ $ROBJ->search_files("$dir/") } ], [], '一時ファイルが残らない');

	SKIP: {
		skip 'rootでは書き込みを止められません', 3 if (is_root());
		my $sub = "$dir/readonly";
		mkdir($sub) || die $!;
		$ROBJ->fwrite_atomic("$sub/f.txt", "keep\n");
		chmod(0555, $sub);
		is($ROBJ->fwrite_atomic("$sub/f.txt", "new\n"), 1, '一時ファイルを作れなければ失敗を返す');
		$ROBJ->clear_error();
		is(slurp("$sub/f.txt"), "keep\n", '元のファイルは変わらない');
		is_deeply([ grep { /\.tmp$/ } @{ $ROBJ->search_files("$sub/") } ], [], '一時ファイルが残らない');
		chmod(0755, $sub);
	}
};

#-------------------------------------------------------------------------------
# 置き換えとロック
#-------------------------------------------------------------------------------
subtest 'ロックを待っている間に置き換わったら、新しいファイルを読む' => sub {
	my $file = "$dir/lock.txt";
	$ROBJ->fwrite_atomic($file, "old\n");
	my ($fh, $lines) = $ROBJ->fedit_readlines($file);
	is($lines->[0], "old\n", '編集用に読める');

	pipe(my $rd, my $wr) || die $!;
	my $pid = fork();
	die "fork: $!" if (!defined $pid);
	if (!$pid) {
		close($rd);
		alarm(10);
		close($fh);	# 親のロックは親のfhにあるので、閉じても親のロックは消えない（flockは開いたものに付く）
		my ($fh2, $l) = Satsuki::Base->new()->fedit_readlines($file);
		print $wr $l->[0];
		close($wr);
		POSIX::_exit(0);
	}
	close($wr);
	select(undef, undef, undef, 0.3);	# 子がロック待ちになるまで
	is($ROBJ->fedit_replace($fh, $file, "new\n"), 0, 'ロックを持ったまま置き換える');
	my $got = <$rd>;
	waitpid($pid, 0);
	is($got, "new\n", '待っていた側は新しい中身を読む');
};

subtest '開けないファイルを編集しようとしたら、エラーにして戻る' => sub {
	my $file = "$dir/cant_open";	# フォルダはrootでもO_RDWRで開けない
	mkdir($file) || die $!;
	$ROBJ->clear_error();

	my ($fh, $lines);
	my $ok = eval {
		local $SIG{ALRM} = sub { die "timeout\n" };
		alarm(3);
		($fh, $lines) = $ROBJ->fedit_readlines($file);
		alarm(0);
		1;
	};
	alarm(0);
	ok($ok, '戻ってくる');
	is_deeply($lines, [], '中身は空');
	is(scalar(@{$ROBJ->{Error}}), 1, 'エラーは1件');
	$ROBJ->fedit_exit($fh);
	$ROBJ->clear_error();
};

#-------------------------------------------------------------------------------
# umask
#-------------------------------------------------------------------------------
subtest 'wwwのプロセスでも、ほかの人が書けるファイルを作らない' => sub {
	my $bak = umask(022);
	my $cwd = Cwd::getcwd();
	chdir("$FindBin::Bin/..") || die $!;
	my $r = Satsuki::Base->new();
	$r->{UID} = 33;
	$r->setup_main();
	chdir($cwd);
	is(sprintf('%03o', umask()), '002', 'グループまで書ける');

	umask(002);
	my $file = "$dir/mode.txt";
	$ROBJ->fwrite_lines($file, "x\n");
	is((stat($file))[2] & 07777, 0664, 'ファイルは664');
	$ROBJ->fwrite_atomic("$dir/mode2.txt", "x\n");
	is((stat("$dir/mode2.txt"))[2] & 07777, 0664, 'fwrite_atomicで作っても664');
	$ROBJ->mkdir("$dir/mode_dir");
	is((stat("$dir/mode_dir"))[2] & 07777, 0775, 'フォルダは775');
	umask($bak);
};

done_testing();
