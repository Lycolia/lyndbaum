# 一覧に出す本文（Lyndbaum::Parser::Common->excerpt）
use strict;
use warnings;
use utf8;
use Test::More;

use Lyndbaum::Parser;
use Lyndbaum::Parser::Common;

my $excerpt = sub { [ Lyndbaum::Parser::Common->excerpt($_[0]) ] };

is_deeply $excerpt->("<p>前</p>\n<p>後</p>\n"), [ "<p>前</p>\n<p>後</p>\n", 0 ], '印が無ければ全文';
is_deeply $excerpt->(undef), [ '', 0 ], '未変換なら空';
is_deeply $excerpt->("<p>前</p>\n<!--more-->\n<p>後</p>\n"), [ "<p>前</p>\n", 1 ], '印より前だけ';

my $html = Lyndbaum::Parser->parse('markdown', "前\n\n# 見出し\n\n本文<br>\n\n> 引用\n\n====\n\n後\n", sectioning => 1)->{html};
my ($body, $more) = Lyndbaum::Parser::Common->excerpt($html);
ok $more;
unlike $body, qr/後/;
like $body, qr{<blockquote>.*</blockquote>\s*</section>\s*\z}s, '印の前で開いている section を閉じる';
is scalar(() = $body =~ /<section>/g), scalar(() = $body =~ m{</section>}g), '開きと閉じの数がそろう';

($body) = Lyndbaum::Parser::Common->excerpt("<ul>\n<li><p>a</p><!-- x --><img src=\"x\"><!--more--><p>b</p></li>\n</ul>\n");
is $body, "<ul>\n<li><p>a</p><!-- x --><img src=\"x\">\n</li>\n</ul>\n", '空要素とコメントは数えない';

done_testing;
