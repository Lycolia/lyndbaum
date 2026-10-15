use strict;
use warnings;
use utf8;
use Test::More;

use File::Spec;
use File::Temp qw(tempdir);

use Lyndbaum::Template;
use TestUtil ();

my $t = Lyndbaum::Template->new;
sub render { $t->render_string(@_) }

subtest '値を出す' => sub {
	is render('こんにちは、{{ name }}さん', { name => '太郎' }), 'こんにちは、太郎さん';
	is render('{{ a.b.c }}', { a => { b => { c => 'x' } } }), 'x', '入れ子';
	is render('{{ list.1 }}', { list => [qw(a b)] }), 'b', '配列の添字';
	is render('[{{ none }}][{{ a.none.x }}]', { a => {} }), '[][]', '無い値は空';
	is render('{{ zero }}', { zero => 0 }), '0', '0 は出す';
};

subtest '既定でエスケープする' => sub {
	is render('{{ v }}', { v => q{<a href="x">'&'</a>} }), '&lt;a href=&quot;x&quot;&gt;&#39;&amp;&#39;&lt;/a&gt;';
	is render('{{ raw v }}', { v => '<b>太字</b>' }), '<b>太字</b>', 'raw はエスケープしない';
};

subtest 'if' => sub {
	my $src = '{{# if v }}真{{# else }}偽{{/ if }}';
	is render($src, { v => 1 }), '真';
	is render($src, { v => 0 }), '偽';
	is render($src, { v => '' }), '偽';
	is render($src, { v => [] }), '偽', '空の配列は偽';
	is render($src, { v => [0] }), '真';
	is render('{{# if not v }}無い{{/ if }}', {}), '無い', 'not';
};

subtest 'for' => sub {
	my $src = '{{# for x in list }}{{ loop.number }}:{{ x.name }}{{# if not loop.last }},{{/ if }}{{/ for }}';
	is render($src, { list => [ { name => 'a' }, { name => 'b' } ] }), '1:a,2:b';
	is render($src, { list => [] }), '', '空';
	is render($src, {}), '', '無い';
	is render('{{# for x in list }}{{ title }}{{/ for }}', { list => [1], title => '外' }), '外', '外側の値も見える';
	is render('{{# for a in o }}{{# for b in i }}{{ a }}{{ b }}{{ loop.index }} {{/ for }}{{/ for }}',
		{ o => [1, 2], i => [qw(x y)] }), '1x0 1y1 2x0 2y1 ', '入れ子';
};

subtest 'ブロックの印だけの行は除く' => sub {
	my $src = <<'T';
<ul>
  {{# for x in list }}
  <li>{{ x }}</li>
  {{/ for }}
</ul>
{{! コメント }}
T
	is render($src, { list => [1, 2] }), "<ul>\n  <li>1</li>\n  <li>2</li>\n</ul>\n";
	is render("a {{# if v }}b{{/ if }} c\n", { v => 1 }), "a b c\n", '行の途中では除かない';
};

subtest '部品の読み込み' => sub {
	my $dir = tempdir(CLEANUP => 1);
	my $write = sub {
		my ($name, $body) = @_;
		open my $fh, '>:encoding(UTF-8)', File::Spec->catfile($dir, "$name.html") or die $!;
		print $fh $body;
		close $fh;
	};
	$write->(page => "<h1>{{ title }}</h1>\n{{> footer }}\n");
	$write->(footer => "<footer>{{ title }}のフッター</footer>\n");
	$write->(loop => "{{> loop }}");

	my $t = Lyndbaum::Template->new(dir => $dir);
	is $t->render('page', { title => '題' }), "<h1>題</h1>\n<footer>題のフッター</footer>\n";
	eval { $t->render('loop') };
	like $@, qr/深すぎます/, '循環は止める';
	eval { $t->render('../etc/passwd') };
	like $@, qr/テンプレート名が不正です/, 'ディレクトリの外は読まない';
};

subtest '構文の誤りは行番号つきで止める' => sub {
	my $error = sub { eval { render($_[0], {}) }; $@ };
	like $error->("a\n{{# if v }}\nb\n"), qr/2 行目: \{\{# if \}\} が閉じていません/;
	like $error->("{{/ if }}"), qr/対応する開始のない/;
	like $error->("{{# if a }}{{/ for }}"), qr/対応する開始のない/;
	like $error->("{{# else }}"), qr/if のない else/;
	like $error->("a\nb\n{{ a-b }}"), qr/3 行目: 式が不正です/;
	like $error->("{{# if a }}\n  {{# if b }}\n{{ a-b }}"), qr/3 行目/, '除いた行も数える';
	like $error->("{{ a\n}}\n{{ a-b }}"), qr/3 行目/, 'タグの中の改行も数える';
	like $error->("{{# while x }}{{/ while }}"), qr/知らないブロック/;
	like $error->("{{ a"), qr/閉じていない/;
};

done_testing;
