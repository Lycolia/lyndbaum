use strict;
use utf8;
#-------------------------------------------------------------------------------
# Markdownパーサーのテスト
#-------------------------------------------------------------------------------
# 仕様: docs/markdown-syntax.md
# 実行: prove -Ilib t/markdown.t
#
# 各ケースは本番と同じ設定で変換する。ただし出力を読みやすくするため、
# sectioning（<section>の挿入）は既定で無効にする。
# 必要なケースでは「--- options: sectioning=1」で有効にする。
#
# 環境変数
#   MD_TEST_FILE=block_list   特定のケースファイルだけ実行
#   MD_TEST_DUMP=1            今のパーサーの出力を表示（期待値を作るとき用）
#
use FindBin;
use lib "$FindBin::Bin/lib";
# 本体の lib は末尾に追加する（-I で別のパーサーを指定して比べられるように）
BEGIN { push(@INC, "$FindBin::Bin/../lib"); }
use Test::More;
use Encode ();
use MarkdownTest qw(parse_md normalize_html load_cases);

binmode(Test::More->builder->$_, ':utf8') for qw(output failure_output todo_output);

my $dir   = "$FindBin::Bin/markdown";
my @files = sort glob("$dir/*.txt");
if ($ENV{MD_TEST_FILE}) {
	@files = grep { m|/\Q$ENV{MD_TEST_FILE}\E\.txt$| } @files;
}

foreach my $file (@files) {
	(my $group = $file) =~ s|.*/||;
	$group =~ s/\.txt$//;
	foreach my $c (@{ load_cases($file) }) {
		# パーサーはバイト列（UTF-8）を扱う
		my $input = Encode::encode('UTF-8', $c->{input});
		my %opt   = (sectioning => 0, %{ $c->{options} });
		my $out   = Encode::decode('UTF-8', parse_md($input, %opt));

		if ($ENV{MD_TEST_DUMP}) {
			diag("=== $group: $c->{name}\n$out\n");
		}
		my $got = normalize_html($out);
		my $exp = normalize_html($c->{expected});
	  TODO: {
		local $TODO = $c->{todo};
		is($got, $exp, "$group: $c->{name}");
	  }
	}
}

# メールアドレスの自動リンクは、収集対策として難読化して出力する
# （上のケースでは数値文字参照を文字に戻して比較しているため、ここで確認する）
unlike(parse_md('<user@example.com>'), qr/user\@example\.com/, 'inline: メールアドレスは難読化して出力する');

done_testing();
