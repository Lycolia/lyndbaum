use strict;
use utf8;
#-------------------------------------------------------------------------------
# タグの無害化（TextParser::TagEscape）のテスト
#-------------------------------------------------------------------------------
# 実行: prove t/tag_escape.t
#
# URLを取る属性に javascript: などの許可していないスキームを書けないことを確かめる。
#
use FindBin;
BEGIN {
	push(@INC, "$FindBin::Bin/../lib");
	chdir("$FindBin::Bin/..");
}
use Test::More;
require Satsuki::Base;

binmode(Test::More->builder->$_, ':utf8') foreach (qw(output failure_output todo_output));

my $ROBJ = Satsuki::Base->new();
my $user = $ROBJ->loadpm('TextParser::TagEscape', 'info/allow_tags_usertext.txt');
my $art  = $ROBJ->loadpm('TextParser::TagEscape', 'info/allow_tags_article.txt');

my $DENY = qr/javascript:alert/;

foreach (
	[ $user, 'formaction', '<form><button formaction="javascript:alert(1)">x</button></form>' ],
	[ $user, 'href',       '<a href="javascript:alert(1)">x</a>' ],
	[ $user, 'action',     '<form action="javascript:alert(1)"></form>' ],
	[ $art,  'poster',     '<video poster="javascript:alert(1)" src="x.mp4"></video>' ],
	[ $art,  'ping',       '<a href="https://example.com/" ping="javascript:alert(1)">x</a>' ],
) {
	my ($e, $name, $html) = @$_;
	unlike($e->escape($html), $DENY, "$name に javascript: を書けない");
}

like($user->escape('<button formaction="https://example.com/">x</button>'),
	qr/formaction="https:\/\/example\.com\/"/, 'formaction に https: は書ける');
like($art->escape('<video poster="https://example.com/p.png" src="x.mp4"></video>'),
	qr/poster="https:\/\/example\.com\/p\.png"/, 'poster に https: は書ける');

#-------------------------------------------------------------------------------
# 文字参照で書いたスキーム
#-------------------------------------------------------------------------------
# ブラウザは文字参照を戻し、先頭の制御文字と途中のTAB、改行を捨ててからスキームを読む
foreach (
	[ $art,  '&colon;',           '<a href="javascript&colon;alert(1)">x</a>' ],
	[ $art,  '&COLON;（大文字）', '<a href="javascript&COLON;alert(1)">x</a>' ],
	[ $art,  '途中の&Tab;',       '<a href="java&Tab;script:alert(1)">x</a>' ],
	[ $art,  '途中の&NewLine;',   '<a href="java&NewLine;script:alert(1)">x</a>' ],
	[ $art,  '途中の&#9;',        '<a href="java&#9;script:alert(1)">x</a>' ],
	[ $art,  '途中の&#x0a;',      '<a href="java&#x0a;script:alert(1)">x</a>' ],
	[ $art,  '途中の&#13;',       '<a href="java&#13;script&colon;alert(1)">x</a>' ],
	[ $art,  '先頭の&#1;',        '<a href="&#1;javascript:alert(1)">x</a>' ],
	[ $art,  '先頭の&#32;',       '<a href="&#32;&#x20;javascript:alert(1)">x</a>' ],
	[ $art,  '桁の多い&#58;',     '<a href="javascript&#0000058;alert(1)">x</a>' ],
	[ $art,  'iframeのsrc',       '<iframe src="javascript&colon;alert(1)"></iframe>' ],
	[ $user, 'formのaction',      '<form action="javascript&colon;alert(1)"></form>' ],
) {
	my ($e, $name, $html) = @$_;
	my $out = $e->escape($html);
	like($out,   qr/="#javascript: is not allow"/, "$name で javascript: を書けない");
	unlike($out, qr/alert/,                        "$name の元の値は残らない");
}

# 書けていたものは、そのまま書ける
foreach (
	[ 'クエリの&amp;',           '<a href="https://example.com/?a=1&amp;b=2">x</a>' ],
	[ 'クエリの&（生）',         '<a href="https://example.com/?a=1&b=2">x</a>',  '<a href="https://example.com/?a=1&amp;b=2">x</a>' ],
	[ '相対パスのクエリ',        '<a href="?a=1&amp;b=2">x</a>' ],
	[ 'パスの中の:',             '<a href="./a&amp;b:c">x</a>' ],
	[ 'パスの中の文字参照',      '<a href="/path/&colon;x&Tab;y">x</a>' ],
	[ '文字参照で書いたhttps:',  '<a href="https&colon;//example.com/">x</a>' ],
	[ 'ASCII以外の文字参照',     '<a href="&#12354;:x">x</a>' ],
	[ 'mailto:',                 '<a href="mailto:a@example.com">x</a>' ],
) {
	my ($name, $html, $expect) = @$_;
	is($art->escape($html), $expect // $html, "$name はそのまま書ける");
}

done_testing();
