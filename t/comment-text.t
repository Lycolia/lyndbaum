# コメントの本文の表示（Lyndbaum::CommentText）
use strict;
use warnings;
use utf8;
use Test::More;

use Lyndbaum::CommentText;
use TestUtil ();

my $html = sub { Lyndbaum::CommentText->to_html($_[0]) };
my $REL = 'rel="nofollow ugc noopener noreferrer"';

is $html->(qq{<b>太字</b> & "引用"\n2行目}), qq{&lt;b&gt;太字&lt;/b&gt; &amp; "引用"\n2行目}, 'エスケープする。改行はそのまま';
is $html->('>>12 ありがとう'), '<a href="#c12">&gt;&gt;12</a> ありがとう', '>>N は #cN へのリンク';
is $html->('>> 1 と >1'), '&gt;&gt; 1 と &gt;1', '>> の直後が数字でなければ文字のまま';
is $html->('見て https://example.com/a?b=1&c=2 です'),
	qq{見て <a href="https://example.com/a?b=1&amp;c=2" $REL>https://example.com/a?b=1&amp;c=2</a> です}, 'URL はリンク';
is $html->('http://example.com/は便利'), qq{<a href="http://example.com/" $REL>http://example.com/</a>は便利}, '日本語の手前で切る';
is $html->('（https://example.com/）'), qq{（<a href="https://example.com/" $REL>https://example.com/</a>）}, '全角の括弧';
is $html->('(https://example.com/) https://example.com/a.'),
	qq{(<a href="https://example.com/" $REL>https://example.com/</a>) <a href="https://example.com/a" $REL>https://example.com/a</a>.},
	'対になっていない閉じ括弧と末尾の句読点は含めない';
is $html->('https://ja.wikipedia.org/wiki/A_(B)'),
	qq{<a href="https://ja.wikipedia.org/wiki/A_(B)" $REL>https://ja.wikipedia.org/wiki/A_(B)</a>}, '対になった括弧は含める';
is $html->('javascript:alert(1) ftp://example.com/'), 'javascript:alert(1) ftp://example.com/', 'http(s) 以外はリンクにしない';
is $html->(q{https://example.com/"onmouseover="x}),
	qq{<a href="https://example.com/" $REL>https://example.com/</a>"onmouseover="x}, '引用符は URL に含めない';

done_testing;
