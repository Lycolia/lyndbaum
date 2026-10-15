# 見出しの識別子を書き足す処理
use strict;
use warnings;
use utf8;
use Test::More;

use Lyndbaum::Parser::Common;
use Lyndbaum::Parser::Markdown;

my $add = sub {
	my ($text, @ids) = @_;
	return [ Lyndbaum::Parser::Markdown->add_heading_ids($text, sub { $ids[ $_[0] ] }) ];
};

is_deeply $add->("# 一\n\n本文\n\n## 二 [#b]\n### 三", qw(a b c)), [ "# 一 [#a]\n\n本文\n\n## 二 [#b]\n### 三 [#c]", 2 ],
	'識別子の無い見出しに書き足す（ある見出しも数に入れる）';
is_deeply $add->("```\n# コメント\n```\n# 見出し", qw(a)), [ "```\n# コメント\n```\n# 見出し [#a]", 1 ], 'コードフェンスの中は見ない';
is_deeply $add->("- 項目\n\n  ## 項目の中の見出し\n> # 引用の中の見出し", qw(a b)),
	[ "- 項目\n\n  ## 項目の中の見出し [#a]\n> # 引用の中の見出し [#b]", 2 ], 'リストと引用の中の見出し';
is_deeply $add->("本文", qw(a)), [ '本文', 0 ], '見出しが無ければそのまま';

eval { $add->("  # 字下げした行は見出しではない\n# 見出し", qw(a b)) };
like $@, qr/変わります/, '見出しでない行に書き足すことになるなら止める';
eval { $add->('# 見出し', 'a b') };
like $@, qr/使えない文字/, '空白を含む識別子は書き足さない';

like(Lyndbaum::Parser::Common->new_heading_id, qr/\A[a-z][0-9a-f]{7}\z/, '新しい識別子は英字1文字と16進数7桁');
my %used = map { $_ => 1 } 1 .. 10;
is scalar(grep { !$used{ Lyndbaum::Parser::Common->new_heading_id(\%used) } } 1 .. 20), 20, '使った識別子は避ける';

done_testing;
