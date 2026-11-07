use strict;
use utf8;
#-------------------------------------------------------------------------------
# スケルトンの探索のテスト（常駐時に、追加や削除、上書きを見落とさないこと）
#-------------------------------------------------------------------------------
# 実行: prove t/skeleton_lookup.t
#
use FindBin;
BEGIN { push(@INC, "$FindBin::Bin/../lib"); chdir("$FindBin::Bin/.."); }
use Test::More;
use File::Temp ();
use File::Path ();
require Satsuki::Base;
binmode(Test::More->builder->$_, ':utf8') foreach (qw(output failure_output todo_output));

my $root = File::Temp::tempdir(CLEANUP => 1);
my ($low, $high) = ("$root/low/", "$root/high/");
File::Path::make_path("${low}_sub", $high);

sub put   { open(my $fh, '>', $_[0]) || die "$_[0]: $!"; print $fh "x"; close($fh); }
# 古い時刻にする。呼ぶたびに別の時刻にする（同じ時刻へ戻すと「変更なし」と区別できない）
my $age_tm = time() - 100000;
sub age   { my $t = ($age_tm += 10); utime($t, $t, $_) foreach @_; }
# 1リクエスト分のオブジェクト
sub req {
	my $r = Satsuki::Base->new();
	$r->{SkeletonExt} = '.html';
	$r->regist_skeleton($low, 0);
	$r->regist_skeleton($high, 10);
	return $r;
}
sub find { return scalar req()->check_skeleton(@_); }

put("${low}a.html");
put("${low}_sub/b.html");
age($low, "${low}_sub", $high);

is(find('a'),      "${low}a.html",      '見つかる');
is(find('_sub/b'), "${low}_sub/b.html", 'サブディレクトリも見つかる');
is(find('none'),   undef,               '無ければ無い');

subtest '常駐中に上位へ置いた上書きを、次のリクエストから使う（下位の索引が残っていても）' => sub {
	find('_sub/b');
	File::Path::make_path("${high}_sub");
	put("${high}_sub/b.html");
	is(find('_sub/b'), "${high}_sub/b.html", '上書きを使う');
	unlink("${high}_sub/b.html");
	is(find('_sub/b'), "${low}_sub/b.html", '消すと元に戻る');
	rmdir("${high}_sub");
	is(find('_sub/b'), "${low}_sub/b.html", 'ディレクトリごと消しても元に戻る');
};

subtest '更新時刻の古いディレクトリにも、追加と削除が反映される' => sub {
	age($low);
	find('a');
	put("${low}c.html");
	is(find('c'), "${low}c.html", '追加');
	unlink("${low}c.html");
	is(find('c'), undef, '削除');
};

subtest '更新された直後のディレクトリは、同じ時刻のまま次の変更が入っても見落とさない' => sub {
	put("${low}k.html");
	my $tm = time();
	utime($tm, $tm, $high);
	is(find('k'), "${low}k.html", '上書きの無いうちは下を使う');

	# 時刻の細かさが粗いファイルシステムでは、変更しても更新時刻が変わらないことがある
	put("${high}k.html");
	utime($tm, $tm, $high);
	is(find('k'), "${high}k.html", '上書きを使う');

	unlink("${low}k.html", "${high}k.html");
	age($low, $high);
};

subtest '同じリクエストの中では確かめ直さず、次のリクエストで反映する' => sub {
	put("${low}a.html");
	age($low);
	find('a');	# 索引を作る
	my $r = req();
	is(scalar $r->check_skeleton('a'), "${low}a.html", '索引から');
	unlink("${low}a.html");
	age($low);
	is(scalar $r->check_skeleton('a'), "${low}a.html", '同じリクエストでは前の結果のまま');
	is(find('a'), undef, '次のリクエストで反映');
};

subtest '場所の登録が変わると、覚えた結果を使わない' => sub {
	put("${low}g.html");
	put("${high}g.html");
	age($low, $high);
	my $r = Satsuki::Base->new();
	$r->{SkeletonExt} = '.html';
	$r->regist_skeleton($low, 0);
	is(scalar $r->check_skeleton('g'), "${low}g.html", '下の場所だけ');
	$r->regist_skeleton($high, 10);
	is(scalar $r->check_skeleton('g'), "${high}g.html", '上の場所を足す');
	$r->delete_skeleton(10);
	is(scalar $r->check_skeleton('g'), "${low}g.html", '上の場所を外す');
	unlink("${low}g.html", "${high}g.html");
	age($low, $high);
};

subtest '相対の指定は、呼び出し元ごとに探す' => sub {
	File::Path::make_path("${low}_sub2");
	put("${low}_sub/h.html");
	put("${low}_sub2/h.html");
	age($low, "${low}_sub", "${low}_sub2");
	my $r = req();
	$r->{CurrentSkel} = '_sub/x';
	is(scalar $r->check_skeleton('./h'), "${low}_sub/h.html", '_sub/ から');
	$r->{CurrentSkel} = '_sub2/x';
	is(scalar $r->check_skeleton('./h'), "${low}_sub2/h.html", '_sub2/ から');
};

subtest 'レベルの指定を守る' => sub {
	put("${low}e.html");
	put("${high}e.html");
	age($low, $high);
	is(find('e'),    "${high}e.html", '高いレベルを優先');
	is(find('e', 5), "${low}e.html",  'レベルより上は見ない');
};

subtest 'POSTでは実物を見る（同じリクエストの中で書き出したものを使う）' => sub {
	my $r = req();
	$r->{POST} = 1;
	is(scalar $r->check_skeleton('f'), undef, 'まだ無い');
	put("${low}f.html");
	is(scalar $r->check_skeleton('f'), "${low}f.html", '書き出した直後から見える');
};

done_testing();
