use strict;
use utf8;
#-------------------------------------------------------------------------------
# JSONの生成と、Ajaxの関数のエラーのテスト
#-------------------------------------------------------------------------------
# 実行: prove t/json.t
#
use FindBin;
BEGIN { push(@INC, "$FindBin::Bin/lib", "$FindBin::Bin/../lib"); }
use Test::More;
use File::Temp ();
use JSON::PP ();
use AppTest;
use OpsTest;

binmode(Test::More->builder->$_, ':utf8') foreach (qw(output failure_output todo_output));

require Satsuki::Base;
require SatsukiApp::adiary;
my $ROBJ = Satsuki::Base->new();
my $json = JSON::PP->new->allow_nonref;

#-------------------------------------------------------------------------------
# json_encode
#-------------------------------------------------------------------------------
subtest '文字列を変えずにJSONにする' => sub {
	my %cases = (
		'バックスラッシュ' => 'C:\new\table',
		'末尾のバックスラッシュ' => 'a\\',
		'引用符'         => 'a"b',
		'\\と引用符'     => 'a\\"b',
		'タブ'           => "a\tb",
		'改行'           => "a\r\nb",
		'Backspace'      => "a\x08b",
		'Form Feed'      => "a\x0cb",
		'そのほかの制御文字' => join('', map { chr($_) } 0..0x1f),
		'DEL'            => "a\x7fb",
		'実体参照の形'   => 'a&#92;b',
	);
	foreach my $name (sort(keys(%cases))) {
		my $v = $cases{$name};
		my $s = $ROBJ->json_encode($v);
		is(eval { $json->decode($s) }, $v, $name);
	}
	is($ROBJ->json_encode("a\tb\x0c"), '"a\tb\f"', '短い書き方にする');
};

subtest '値の種類' => sub {
	is($ROBJ->json_encode('12'),   '12',   '数値');
	is($ROBJ->json_encode('1.5'),  '1.5',  '小数');
	is($ROBJ->json_encode(''),     '""',   '空');
	is($ROBJ->json_encode(\'null'), 'null', 'true/false/null');
	is($ROBJ->json_string('12'),   '"12"', 'json_stringは数字も文字列にする');
};

subtest 'generate_jsonの結果を読める' => sub {
	my $data = { title => "a\\b\x01", list => [ { name => "c\\d\x0c" } ] };
	my $r = eval { $json->decode($ROBJ->generate_json($data)) };
	is_deeply($r, $data, '元のデータに戻る');
};

#-------------------------------------------------------------------------------
# 画面が受け取るJSON
#-------------------------------------------------------------------------------
subtest '\\を含む記事とタグ' => sub {
	my $app = AppTest->new()->setup()->seed();
	my $r = $app->post('admin', '', { %ART, edit_pkey_int => 1, title => 'C:\new', body_txt => "x\\y\n", tag_ary => 'a\b' });
	ok(AppTest::is_reload($r), '保存できる');

	$r = $app->post('admin', '', { action => 'ajax_revision', now => 1 });
	is($r->{json}->{title}, 'C:\new', '今の記事の題名');
	is($r->{json}->{text}, 'x\y', '今の記事の本文');

	my $revs = $app->post('admin', '', { action => 'ajax_revision', pkey => 1 })->{json};
	my $rev  = $app->post('admin', '', { action => 'ajax_revision', rev => $revs->[0]->{pkey} })->{json};
	ok(defined $rev->{text}, '履歴の本文を読める');

	my $tags = eval { $json->decode(read_file($app->dir . '/pub/taglist.json')) };
	my @names = map { $_->{title} } @{ $tags || [] };
	ok((grep { $_ eq 'a\b' } @names), 'タグの一覧') || diag(join(',', @names));
};

subtest '数字だけの本文' => sub {
	my $app = AppTest->new()->setup()->seed();
	$app->post('admin', '', { %ART, edit_pkey_int => 1, title => 'x', body_txt => '123' });
	my $body = $app->post('admin', '', { action => 'ajax_revision', now => 1 })->{body};
	like($body, qr/"text": "123/, '本文は文字列にする');
};

#-------------------------------------------------------------------------------
# Ajaxの関数のエラー
#-------------------------------------------------------------------------------
my $lib = File::Temp::tempdir(CLEANUP => 1);
unshift(@INC, $lib);

sub put {
	my ($file, $data) = @_;
	open(my $fh, '>', $file) || die "$file: $!";
	print $fh $data;
	close($fh);
}
sub ajax_class {
	my ($class, $split) = @_;
	put("$lib/$class.pm", <<TEXT);
package $class;
use Satsuki::AutoLoader;
*do_ajax_function = \\&SatsukiApp::adiary::do_ajax_function;
sub new { return bless({ ROBJ => { Auth => { ok => 1 }, Form => {} } }, shift); }
1;
TEXT
	put("$lib/${class}_2.pm", "package $class;\n$split\n1;\n");
	require "$class.pm";
	return $class->new();
}

subtest '分割ファイルの関数のエラー' => sub {
	my $app = ajax_class('AjaxTestOk', 'sub _ajax_die { die "boom\n"; } sub _ajax_ok { return 5; } sub _ajax_call_none { $_[0]->_ajax_none2(); }');
	ok(!AjaxTestOk->can('_ajax_die'), '読み込むまでcan()は偽');
	is_deeply($app->do_ajax_function('_ajax_die'),  [ -99.9, "boom\n" ], '関数の中のエラーを返す');
	is($app->do_ajax_function('_ajax_ok'), 5, '正常なら戻り値を返す');
	is_deeply($app->do_ajax_function('_ajax_none'), [ -99.2, 'function not found: _ajax_none()' ], '無い関数');
	is($app->do_ajax_function('_ajax_call_none')->[0], -99.9, '関数の中から呼んだ関数が無いときは、呼ばれた関数の名前で報告しない');
};

subtest '分割ファイルに構文エラーがあるとき' => sub {
	my $app = ajax_class('AjaxTestBroken', 'sub _ajax_x { syntax error here ( }');
	my $r = $app->do_ajax_function('_ajax_x');
	is($r->[0], -99.9, '「関数が見つからない」にしない');
	like($r->[1], qr/\[AutoLoader\]/, '本当のエラーを返す');
};

done_testing();
