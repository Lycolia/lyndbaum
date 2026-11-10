use strict;
use utf8;
#-------------------------------------------------------------------------------
# lib/Satsuki だけで起動できることのテスト（CMSが無くても、別のアプリを動かせること）
#-------------------------------------------------------------------------------
# 実行: prove t/satsuki_standalone.t
#
# 一時フォルダに、何もしない小さなアプリ（SatsukiApp::mini）と起動スクリプトを置いて、CGIとして呼ぶ。
# CMS（SatsukiApp::adiary）と、CMSのフォルダ（skel/、data/、info/）は使わない。
#
# ・設定ファイル（<名前>.conf.cgi）だけで動く。アプリが無ければ、設定ファイルの出力をそのまま返す
# ・設定ファイルで、アプリと、フォームを読む前の処理（If_post_exec_pre）を指定できる
# ・コードで組み立てることもでき、そのときは <名前>.user.cgi で値を変えられる
#
use FindBin;
use Test::More;
use File::Temp ();
use File::Path ();
use IPC::Open3 ();
use Symbol ();
binmode(Test::More->builder->$_, ':utf8') foreach (qw(output failure_output todo_output));

my $LIB = "$FindBin::Bin/../lib";
my $dir = File::Temp::tempdir(CLEANUP => 1);
File::Path::make_path("$dir/lib/SatsukiApp");

sub put {
	my ($file, $text) = @_;
	open(my $fh, '>', "$dir/$file") || die "$file: $!";
	print $fh $text;
	close($fh);
}

# 何もしないアプリ。フォームの name と、設定された greeting を返す
put('lib/SatsukiApp/mini.pm', <<'PM');
use strict;
package SatsukiApp::mini;
sub new {
	my ($class, $ROBJ) = @_;
	return bless({ ROBJ => $ROBJ, greeting => 'hello' }, $class);
}
sub main {
	my $self = shift;
	my $ROBJ = $self->{ROBJ};
	my $form = $ROBJ->read_form() || {};
	$ROBJ->output("mini:$self->{greeting}:$form->{name}\n", 'text/plain');
}
1;
PM

# 起動スクリプト。終わりに、読み込んだアプリの名前をSTDERRに出す
my $HEAD = <<'CGI';
use strict;
unshift(@INC, $ENV{SATSUKI_LIB}, './lib');
require Satsuki::Base;
END { print STDERR "LOADED=" . join(',', sort grep { m|^SatsukiApp/| } keys(%INC)) . "\n"; }
my $ROBJ = Satsuki::Base->new();
CGI
put('conf.cgi', $HEAD . "\$ROBJ->start_up();\n\$ROBJ->finish();\n");
put('code.cgi', $HEAD . <<'CGI');
$ROBJ->start_up(sub {
	my $R = shift;
	$R->{Main} = $R->loadapp('mini');
});
$ROBJ->finish();
CGI

sub run {
	my ($cgi, $method, $body) = @_;
	local %ENV = (
		PATH => $ENV{PATH}, SATSUKI_LIB => $LIB,
		REQUEST_METHOD => $method, REQUEST_URI => "/$cgi", SCRIPT_NAME => "/$cgi", QUERY_STRING => '',
		SERVER_NAME => 'localhost', HTTP_HOST => 'localhost', SERVER_PORT => 80, SERVER_PROTOCOL => 'HTTP/1.1',
		REMOTE_ADDR => '127.0.0.1',
	);
	if (defined $body) {
		$ENV{CONTENT_TYPE}   = 'application/x-www-form-urlencoded';
		$ENV{CONTENT_LENGTH} = length($body);
	}
	my $err = Symbol::gensym();
	my $pid;
	{
		my $cwd = Cwd::getcwd();
		chdir($dir) || die $!;
		$pid = IPC::Open3::open3(my $in, my $out, $err, $^X, $cgi);
		chdir($cwd);
		print $in $body if (defined $body);
		close($in);
		local $/;
		my $o = <$out>;
		my $e = <$err>;
		waitpid($pid, 0);
		my ($head, $text) = split(/\r?\n\r?\n/, $o, 2);
		return { head => $head, body => $text, err => $e, loaded => ($e =~ /^LOADED=(.*)$/m)[0] };
	}
}
require Cwd;

#-------------------------------------------------------------------------------
subtest '設定ファイルだけで動く（アプリなし）' => sub {
	put('conf.conf.cgi', "conf-only-output\n");
	my $r = run('conf.cgi', 'GET');
	like($r->{body}, qr/conf-only-output/, '設定ファイルの出力がそのまま返る');
	is($r->{loaded}, '', 'アプリを1つも読み込まない');
};

subtest '設定ファイルでアプリを指定する' => sub {
	put('conf.conf.cgi', <<'CONF');
<@20>
<@#>
<$Main = loadapp('mini')>
<$Main.greeting = 'conf'>
<$If_post_exec_pre = begin>
	<$Form_options.str_max_chars = 3>
<$end>
CONF
	my $r = run('conf.cgi', 'GET');
	is($r->{body}, "mini:conf:\n", 'アプリのmainが呼ばれ、設定した値が届く');
	is($r->{loaded}, 'SatsukiApp/mini.pm', '読み込むのは指定したアプリだけ（CMSを読み込まない）');

	$r = run('conf.cgi', 'POST', 'name=abcdef');
	is($r->{body}, "mini:conf:abc\n", 'フォームを読む前の処理（If_post_exec_pre）で設定した制限が効く');

	put('conf.env.cgi', "<@20>\n<\$ENV.TZ = 'UTC'>\n");
	put('conf.conf.cgi', "<\@ENV.TZ>\n");
	$r = run('conf.cgi', 'GET');
	like($r->{body}, qr/^UTC$/m, '<名前>.env.cgi を、設定ファイルより先に読む');
};

subtest 'コードで組み立てる' => sub {
	my $r = run('code.cgi', 'GET');
	is($r->{body}, "mini:hello:\n", '渡したコードで組み立てられる');
	is($r->{loaded}, 'SatsukiApp/mini.pm', '読み込むのは指定したアプリだけ');

	put('code.user.cgi', "<\@20>\n<\$Main.greeting = 'user'>\n");
	$r = run('code.cgi', 'GET');
	is($r->{body}, "mini:user:\n", '<名前>.user.cgi で値を変えられる');

	put('code.conf.cgi', "<\@20>\n<\$Main.greeting = 'conf'>\n");
	$r = run('code.cgi', 'GET');
	is($r->{body}, "mini:user:\n", 'コードで組み立てるときは、<名前>.conf.cgi を読まない');
};

done_testing();
