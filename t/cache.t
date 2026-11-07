use strict;
use utf8;
#-------------------------------------------------------------------------------
# 常駐しているとき（FastCGI）のキャッシュのテスト
#-------------------------------------------------------------------------------
# 実行: prove t/cache.t
#
use FindBin;
BEGIN { push(@INC, "$FindBin::Bin/../lib"); chdir("$FindBin::Bin/.."); }
use Test::More;
use File::Temp ();
use Time::HiRes ();

binmode(Test::More->builder->$_, ':utf8') foreach (qw(output failure_output todo_output));

require Satsuki::Base;
require Satsuki::DB::text;
my $dir = File::Temp::tempdir(CLEANUP => 1);

sub put {
	my ($file, $data) = @_;
	open(my $fh, '>', $file) || die "$file: $!";
	binmode($fh);
	print $fh $data;
	close($fh);
}

#-------------------------------------------------------------------------------
# ファイルのキャッシュ
#-------------------------------------------------------------------------------
subtest '同じ秒に同じ大きさで書き直されても、新しい内容を読む' => sub {
	my $file = "$dir/same_sec.dat";
	my $tm   = time();

	put($file, "enable=0\n");
	Time::HiRes::utime($tm + 0.1, $tm + 0.1, $file);
	is(Satsuki::Base->new()->fread_hash_cached($file)->{enable}, '0', '初めの内容');

	put($file, "enable=1\n");
	Time::HiRes::utime($tm + 0.2, $tm + 0.2, $file);
	is(Satsuki::Base->new()->fread_hash_cached($file)->{enable}, '1', '書き直した内容');
};

subtest '変わっていなければキャッシュを使う' => sub {
	my $file = "$dir/cached.dat";
	my $tm   = time();

	put($file, "a=1\n");
	Time::HiRes::utime($tm + 0.1, $tm + 0.1, $file);
	is(Satsuki::Base->new()->fread_hash_cached($file)->{a}, '1', '初めの内容');

	put($file, "a=2\n");
	Time::HiRes::utime($tm + 0.1, $tm + 0.1, $file);
	is(Satsuki::Base->new()->fread_hash_cached($file)->{a}, '1', '時刻も大きさも同じならキャッシュ');
};

#-------------------------------------------------------------------------------
# テキストDBの関数のキャッシュ
#-------------------------------------------------------------------------------
subtest 'コンパイルした関数のキャッシュには上限がある' => sub {
	my $db = Satsuki::DB::text->new(Satsuki::Base->new(), "$dir/db/");
	my $first = 'sub { "first" }';
	my $func  = $db->eval_and_cache($first);
	is(&$func(), 'first', '関数を返す');
	is($db->eval_and_cache($first), $func, '同じものはキャッシュを使う');

	foreach (1..1000) {
		my $f = $db->eval_and_cache("sub { $_ }");
		if (&$f() != $_) { fail("関数${_}の値"); }
	}
	isnt($db->eval_and_cache($first), $func, '上限を超えたら捨てている');
};

#-------------------------------------------------------------------------------
# テンプレートのキャッシュ
#-------------------------------------------------------------------------------
# 1回のリクエストを別のプロセスで動かす（メモリのキャッシュを使わず、ファイルを読ませる）
sub request {
	my ($src, $cache_dir) = @_;
	my $pid = open(my $pipe, '-|') // die "fork: $!";
	if (!$pid) {
		my $ROBJ = Satsuki::Base->new();
		$ROBJ->{__cache_dir} = $cache_dir;
		my $out = eval { $ROBJ->_call($src) };
		print $@ ? "die: $@" : ($out // 'undef');
		exit(0);
	}
	local $/;
	my $r = <$pipe>;
	close($pipe);
	return $r;
}

subtest '壊れたテンプレートのキャッシュは作り直す' => sub {
	my $cache_dir = "$dir/cache/";
	mkdir($cache_dir) || die $!;
	my $src = "$dir/skel.html";
	put($src, "<\$x=1>hello <\@x>\n");

	is(request($src, $cache_dir), "hello 1\n", 'キャッシュがないとき');
	my ($cache) = glob("$cache_dir*.cache");
	ok($cache, 'キャッシュを保存する');
	is_deeply([ glob("$cache_dir*.tmp") ], [], '一時ファイルが残らない');

	my $all = do { open(my $fh, '<', $cache) || die $!; binmode($fh); local $/; <$fh> };
	is(request($src, $cache_dir), "hello 1\n", 'キャッシュを使ったとき');

	my @recs = split(/(?<=\0)/, $all);
	my %broken = (
		'0バイト'             => '',
		'ヘッダーの途中で切れた' => substr($all, 0, 10),
		'行数の前で切れた'     => join('', @recs[0..3]),
		'行数の後で切れた'     => join('', @recs[0..4]),
		'関数の途中で切れた'   => substr($all, 0, length($all) - 3),
		'デリミタの直前で切れた' => substr($all, 0, length($all) - 1),
		'余分なデータがある'   => $all . "junk\0",
	);
	foreach my $name (sort(keys(%broken))) {
		put($cache, $broken{$name});
		is(request($src, $cache_dir), "hello 1\n", "$name：ページを出せる");
		is(-s $cache, length($all), "$name：キャッシュを作り直す");
	}
};

#-------------------------------------------------------------------------------
# プラグインの設定（load_plgsetの項目名の索引）
#-------------------------------------------------------------------------------
subtest 'プラグインの設定は、変更と追加と削除をすぐ読める' => sub {
	require SatsukiApp::adiary;
	my $blog = { 'p:mod:a' => 1, 'p:mod,1:a' => 2, 'other' => 3, 'p:mod:x:y' => 4 };
	my $v = bless({ blog => $blog, ROBJ => Satsuki::Base->new() }, 'SatsukiApp::adiary');

	is_deeply($v->load_plgset('mod'),   { a => 1, 'x:y' => 4 }, 'そのプラグインの項目だけ');
	is_deeply($v->load_plgset('mod,1'), { a => 2 }, '複数置いたモジュールは別');
	is_deeply($v->load_plgset('none'),  {}, '無ければ空');
	is($v->load_plgset('mod', 'a'), 1, '項目を指定して読む');

	$v->update_plgset('mod', 'a', 10);
	is($v->load_plgset('mod')->{a}, 10, '変更');
	$v->update_plgset('mod', 'b', 20);
	is($v->load_plgset('mod')->{b}, 20, '追加');
	$v->update_plgset('mod', { c => 30 });
	is($v->load_plgset('mod')->{c}, 30, 'ハッシュで追加');
	$v->update_blogset($blog, 'p:mod:d', 40);
	is($v->load_plgset('mod')->{d}, 40, 'ブログの設定の変更から追加');
	$v->update_plgset('mod', 'b', undef);
	ok(!defined $v->load_plgset('mod')->{b}, 'undefで消す');

	$v->load_plgset('mod')->{a} = 99;
	is($v->load_plgset('mod')->{a}, 10, '戻り値を書き換えても設定は変わらない');

	$v->{blog} = { 'p:mod:z' => 5 };
	is_deeply($v->load_plgset('mod'), { z => 5 }, 'ブログの設定を差し替えると、そちらを読む');
};

#-------------------------------------------------------------------------------
# URIエンコード
#-------------------------------------------------------------------------------
subtest 'encode_uricomの結果は、1文字ずつ変換したときと同じ' => sub {
	my $r = Satsuki::Base->new();
	my $old = sub { my $x = shift; $x =~ s/([^\w!\(\)\*\-\.\~\/:])/'%' . unpack('H2',$1)/eg; return $x; };
	my $ng = 0;
	foreach (0..255) {
		my $x = chr($_);
		my $e = $old->($x);
		$r->encode_uricom($x);
		if ($x ne $e) { $ng++; }
	}
	is($ng, 0, 'すべてのバイト');

	my $wide = "\x{3042}a b";
	my $e = $old->($wide);
	$r->encode_uricom($wide);
	is($wide, $e, '文字列（バイト列でないもの）');
	my $x = '日本語 a/b';
	is($r->encode_uricom($x), $old->('日本語 a/b'), '戻り値');
};

done_testing();
