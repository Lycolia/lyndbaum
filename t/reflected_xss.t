use strict;
use utf8;
#-------------------------------------------------------------------------------
# URLの値をそのまま画面に出さないことのテスト
#-------------------------------------------------------------------------------
# 実行: prove t/reflected_xss.t
#
# URLに入れたタグが、エスケープされて出ることを確かめる。
#
use FindBin;
BEGIN { push(@INC, "$FindBin::Bin/lib", "$FindBin::Bin/../lib"); }
use Test::More;
use AppTest;

binmode(Test::More->builder->$_, ':utf8') foreach (qw(output failure_output todo_output));

my $app = AppTest->new()->setup()->seed();

# PATH_INFOはデコードされて画面に届く
my $PATH = '/%3C/textarea%3E%3Cb%3Eprobe%3C/b%3E';

#-------------------------------------------------------------------------------
# システムチェック
#-------------------------------------------------------------------------------
subtest 'システムチェックの環境変数' => sub {
	my $r = $app->get('admin', "$PATH?system/check");
	is($r->{status}, 200, '画面が出る');
	like($r->{body},   qr/PATH_INFO\t\/&lt;\/textarea&gt;&lt;b&gt;probe/, 'PATH_INFOをエスケープして出す');
	unlike($r->{body}, qr/<b>probe/, 'タグのまま出さない');
};

#-------------------------------------------------------------------------------
# ENV_printの画面
#-------------------------------------------------------------------------------
subtest 'ENV_printの環境変数の一覧' => sub {
	my $file = $app->dir . '/lyndbaum.user.cgi';
	open(my $fh, '>', $file) || die "$file: $!";
	print $fh "<\$ENV_print=1>\n";
	close($fh);

	my $r = $app->get('admin', "$PATH?system/check");
	is($r->{status}, 200, '画面が出る');
	like($r->{body},   qr/PATH_INFO \/&lt;\/textarea&gt;&lt;b&gt;probe/, '個別の行をエスケープして出す');
	like($r->{body},   qr/^PATH_INFO=\/&lt;\/textarea&gt;&lt;b&gt;probe/m, '一覧もエスケープして出す');
	like($r->{body},   qr/^SERVER_NAME=localhost<br>$/m, '一覧は1行ずつ改行する');
	unlike($r->{body}, qr/<b>probe/, 'タグのまま出さない');

	unlink($file);
};

#-------------------------------------------------------------------------------
# 検索ボックス（ヘッダーのモジュール）
#-------------------------------------------------------------------------------
subtest 'deh_searchboxのallの値' => sub {
	my $r = $app->post('admin', '', { action => 'design/edit', header_ary => 'deh_searchbox' });
	cmp_ok($r->{status}, '<', 400, 'モジュールを置ける');

	# 検索で見つからないときは404だが、検索ボックスは出る
	$r = $app->get('guest', '?q=x&all=%22%3E%3Cb%3Eprobe%3C%2Fb%3E');
	like($r->{body},   qr/name="all" value="&quot;&gt;&lt;b&gt;probe/, 'エスケープして出す');
	unlike($r->{body}, qr/<b>probe/, 'タグのまま出さない');

	$r = $app->get('guest', '?q=x&all=0');
	like($r->{body},   qr/name="all" value="0"/, '普通の値はそのまま出す');
};

done_testing();
