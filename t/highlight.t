# 検索語の強調表示と抜粋
use strict;
use warnings;
use utf8;
use Test::More;

use Lyndbaum::Highlight;

subtest '強調表示' => sub {
	is(Lyndbaum::Highlight->mark('ＰＥＲＬとPerl', ['perl']), '<mark>ＰＥＲＬ</mark>と<mark>Perl</mark>', '全角、大文字も当てて、元の文字のまま出す');
	is(Lyndbaum::Highlight->mark('a<b>&c', ['b']), 'a&lt;<mark>b</mark>&gt;&amp;c', 'エスケープする');
	is(Lyndbaum::Highlight->mark('㍻の話', ['平']), '<mark>㍻</mark>の話', '複数の文字に正規化される文字は、その文字ごと囲む');
	is(Lyndbaum::Highlight->mark('abcd', ['bc', 'cd']), 'a<mark>bcd</mark>', '重なる範囲はまとめる');
	is(Lyndbaum::Highlight->mark('abc', []), 'abc', '検索語なし');
};

subtest '抜粋' => sub {
	my $text = ('あ' x 50) . 'Perl' . ('い' x 50) . "\n\n" . 'nginx' . ('う' x 5);
	is_deeply(Lyndbaum::Highlight->snippets($text, ['perl', 'nginx'], around => 5), [
		'…あああああ<mark>Perl</mark>いいいいい…',
		'…いいいい <mark>nginx</mark>ううううう',
	], '当たった箇所の前後。空白はまとめる');
	is_deeply(Lyndbaum::Highlight->snippets('a-a-a', ['a'], around => 2), ['<mark>a</mark>-<mark>a</mark>-<mark>a</mark>'], '近い箇所はつなげる');
	is(scalar @{ Lyndbaum::Highlight->snippets(join('y' x 20, ('x') x 5), ['x'], around => 2, max => 3) }, 3, '抜粋の数の上限');
	is_deeply(Lyndbaum::Highlight->snippets('abc', ['z']), [], '当たらなければ空');
};

subtest '当たった行' => sub {
	my ($lines, $omitted) = Lyndbaum::Highlight->lines("a\n[link](https://example.com/)\nb\nexample\nexample", ['example'], max => 2);
	is_deeply $lines, [
		{ number => 2, html => '[link](https://<mark>example</mark>.com/)' },
		{ number => 4, html => '<mark>example</mark>' },
	], '行番号つき';
	is $omitted, 1, '上限を超えた行の数';

	($lines) = Lyndbaum::Highlight->lines(('a' x 100) . 'X' . ('b' x 100), ['x'], width => 40);
	is $lines->[0]{html}, '…' . ('a' x 10) . '<mark>X</mark>' . ('b' x 29) . '…', '長い行は当たった箇所の前後だけ';
};

done_testing;
