use strict;
use utf8;
#-------------------------------------------------------------------------------
# 性能の予算のテスト（トップページ1回の、スケルトンの呼び出しとシステムコールの数）
#-------------------------------------------------------------------------------
# 実行: prove t/performance_budget.t
#
# 時間は揺れるので、回数を数える。値を上げるときの決まりは docs/性能の測り方.md。
# システムコールは strace で数える。strace が無ければ、その項目だけ飛ばす。
#
use FindBin;
BEGIN { push(@INC, "$FindBin::Bin/lib", "$FindBin::Bin/../lib"); }
use Test::More;
use AppTest;
use OpsTest;
use File::Temp ();

binmode(Test::More->builder->$_, ':utf8') foreach (qw(output failure_output todo_output));

my $CALL_MAX    = 25;	# 1リクエストのスケルトンの呼び出し
my $SYSCALL_MAX = 125;	# 1リクエストのシステムコール

my $app = AppTest->new()->setup()->seed();
my $dir = $app->dir;
foreach (1..3) {
	my $r = $app->post('admin', '', { %ART, title => "記事$_", body_txt => "本文\n" });
	die "edit failed" if (!AppTest::is_reload($r));
}

# トップページをログインなしでN回出す（lyndbaum.fcgiが1リクエストごとに行うことと同じ）
my $driver = File::Temp->new(SUFFIX => '.pl');
print $driver <<'DRIVER';
use lib 'lib';
use Satsuki::Base ();
my ($n, $calls_file) = @ARGV;
$0 = 'lyndbaum.cgi';
%ENV = (%ENV, REQUEST_METHOD=>'GET', REQUEST_URI=>'/', SCRIPT_NAME=>'/', DOCUMENT_URI=>'/', QUERY_STRING=>'',
	SERVER_NAME=>'localhost', HTTP_HOST=>'localhost', SERVER_PORT=>80, SERVER_PROTOCOL=>'HTTP/1.1',
	REMOTE_ADDR=>'127.0.0.1', Basepath=>'/', ModRewrite=>1);
{ package FakeRequest; sub AUTOLOAD { return; } }
open(STDOUT, '>', '/dev/null');
sub request {
	my $r = Satsuki::Base->new();
	$r->{ModRewrite} = 1;
	$r->init_for_fastcgi(bless({}, 'FakeRequest'));
	$r->start_up();
	$r->finish();
}
request() foreach (1..3);

my $calls = 0;
my $org = \&Satsuki::Base::__call;
{ no warnings 'redefine'; *Satsuki::Base::__call = sub { $calls++; return $org->(@_); }; }
request() foreach (1..$n);
open(my $fh, '>', $calls_file) || die;
print $fh $n ? $calls / $n : 0;
close($fh);
DRIVER
close($driver);

sub run_driver {
	my ($n, @prefix) = @_;
	my $out = File::Temp->new();
	system(@prefix, $^X, $driver->filename, $n, $out->filename) == 0 || die "driver failed";
	return OpsTest::read_file($out->filename);
}
sub syscalls {
	my $n   = shift;
	my $log = File::Temp->new();
	run_driver($n, 'strace', '-c', '-o', $log->filename);
	my $text = OpsTest::read_file($log->filename);
	return $text =~ /^\s*100\.00\s+\S+\s+\S+\s+(\d+)/m ? $1 : die "strace output: $text";
}

chdir($dir) || die;
mkdir('__cache');	# 無いとスケルトンをメモリに覚えない（毎回コンパイルする）
sleep(3);	# 更新された直後のディレクトリは索引に覚えないので、実際の動きに合わせる

my $n = 50;
my $calls = run_driver($n);
cmp_ok($calls, '>', 0, 'スケルトンの呼び出しを数えられる');
cmp_ok($calls, '<=', $CALL_MAX, "スケルトンの呼び出しは1リクエスト${CALL_MAX}回まで（${calls}回）");

SKIP: {
	skip('straceがありません', 1) if (system('strace -V >/dev/null 2>&1') != 0);
	skip('straceを使えません（ptraceの制限）', 1) if (system('strace -c -o /dev/null true >/dev/null 2>&1') != 0);
	my $per = (syscalls($n) - syscalls(0)) / $n;
	cmp_ok($per, '<=', $SYSCALL_MAX, "システムコールは1リクエスト${SYSCALL_MAX}回まで（${per}回）");
}
chdir('/');

done_testing();
