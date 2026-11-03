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

done_testing();
