# 段を飛ばしたために目次に入らない見出しの警告
use strict;
use warnings;
use utf8;
use Test::More;

use Lyndbaum::Parser::Markdown;

my $warnings = sub { Lyndbaum::Parser::Markdown->parse($_[0], sectioning => 1)->{warnings} };

is_deeply $warnings->("[*toc]\n\n# 一\n\n## 二\n\n### 三"), [], '段を飛ばしていなければ無い';
is_deeply $warnings->("[*toc]\n\n## bbb\n\n## ccc"), [
	'見出し「bbb」（##）の前に # の見出しが無いため、目次に入りません',
	'見出し「ccc」（##）の前に # の見出しが無いため、目次に入りません',
], '# の無い ##';
is_deeply $warnings->("[*toc]\n\n# aa\n\n## bbb\n\n#### ccc\n\n## ddd"), [
	'見出し「ccc」（####）は、「bbb」（##）から段を飛ばしているため、目次に入りません',
], '## の直後の ####（次の ## は目次に入る）';
is_deeply $warnings->("[*toc]\n\n## A &amp; *B*"), [
	'見出し「A & B」（##）の前に # の見出しが無いため、目次に入りません',
], '見出しの名前は、タグを除いて文字参照を戻した文字（画面でエスケープする）';
is_deeply $warnings->("## bbb\n\n## ccc"), [], '目次を置いていなければ警告しない';

done_testing;
