# Markdownパーサーのテスト
#   仕様は docs/markdown-syntax.md、ケースは t/markdown/*.txt
#
#   各ケースは本番と同じ設定で変換する。ただし出力を読みやすくするため、
#   見出しごとの <section> は既定で付けない。必要なケースでは「--- options: sectioning=1」を付ける
#
#   環境変数
#     MD_TEST_FILE=block_list   特定のケースファイルだけ実行する
#     MD_TEST_DUMP=1            パーサーの出力を表示する（期待値を作るとき用）
use strict;
use warnings;
use utf8;
use Test::More;

use FindBin;
use MarkdownTest qw(parse_md normalize_html load_cases);
use TestUtil ();

my @files = sort glob "$FindBin::Bin/markdown/*.txt";
@files = grep { m{/\Q$ENV{MD_TEST_FILE}\E\.txt\z} } @files if $ENV{MD_TEST_FILE};

for my $file (@files) {
	my ($group) = $file =~ m{([^/]+)\.txt\z};
	for my $case (@{ load_cases($file) }) {
		my $html = parse_md($case->{input}, %{ $case->{options} });
		diag("=== $group: $case->{name}\n$html\n") if $ENV{MD_TEST_DUMP};
		TODO: {
			local $TODO = $case->{todo};
			is normalize_html($html), normalize_html($case->{expected}), "$group: $case->{name}";
		}
	}
}

# メールアドレスの自動リンクは、収集対策として難読化して出力する
# （上のケースでは数値文字参照を文字に戻して比べているため、ここで確かめる）
unlike parse_md('<user@example.com>'), qr/user\@example\.com/, 'inline: メールアドレスは難読化して出力する';

done_testing;
