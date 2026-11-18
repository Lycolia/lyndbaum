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
use MarkdownTest qw(new_parser parse_md normalize_html load_cases);

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

# 見出しの識別子の書き足し（記事を保存するときに呼ぶ）。
# 見出しの探し方がパーサーとずれると、どの見出しにも書き足さなくなる
foreach my $c (
	[ "# A\n\n本文\n\n## B\n",                "# A [#ID]\n\n本文\n\n## B [#ID]\n",          '見出しに書き足す' ],
	[ "- a\n# A\n",                             "- a\n# A [#ID]\n",                             'リストの直後の見出し' ],
	[ "> a\n# A\n",                             "> a\n# A [#ID]\n",                             '引用の直後の見出し' ],
	[ "前\n===\n\n# A\n",                       "前\n===\n\n# A [#ID]\n",                       '=== の行がある記事' ],
	[ "前\n---\n\n# A\n",                       "前\n---\n\n# A [#ID]\n",                       '段落の直後に --- がある記事' ],
	[ "```\n# A\n```\n\n# B\n",                 "```\n# A\n```\n\n# B [#ID]\n",                 'コードフェンスの中の # には書き足さない' ],
	[ "~~~\n# A\n~~~\n\n# B\n",                 "~~~\n# A [#ID]\n~~~\n\n# B [#ID]\n",           '~~~ はコードフェンスにしない' ],
	[ "- a\n  ```\n  # x\n  ```\n# B\n",         "- a\n  ```\n  # x\n  ```\n# B [#ID]\n",         'リストの項目の中のコードフェンスの後の見出し' ],
	[ "- a\n  # 項目の中\n\n> # 引用\n\n# B\n",   "- a\n  # 項目の中\n\n> # 引用\n\n# B [#ID]\n",   'リストと引用の中の # には書き足さない' ],
	[ "# A\n\n  ```\n\n# B\n",                  "# A [#ID]\n\n  ```\n\n# B [#ID]\n",              '字下げした ``` はコードフェンスにしない' ],
	[ "# A\n\n - ```\n\n# B\n",                 "# A [#ID]\n\n - ```\n\n# B [#ID]\n",             '字下げしたリストの中の ``` もコードフェンスにしない' ],
	[ "# A\n\n- ```\n  code\n\n# B\n",          "# A [#ID]\n\n- ```\n  code\n\n# B [#ID]\n",      'リストの中の閉じていないコードフェンスは、リストの終わりまで' ],
	[ "# A\n\n> ```\n> code\n\n# B\n",          "# A [#ID]\n\n> ```\n> code\n\n# B [#ID]\n",      '引用の中の閉じていないコードフェンスは、引用の終わりまで' ],
	[ "```\n- a\n  # x\n```\n\n# B\n",          "```\n- a\n  # x\n```\n\n# B [#ID]\n",          'コードフェンスの中のリストの記号は数えない' ],
	[ "# A [#fixed]\n\n# B\n",                  "# A [#fixed]\n\n# B [#ID]\n",                  '識別子のある見出しはそのまま' ],
) {
	my ($in, $exp, $name) = map { Encode::encode('UTF-8', $_) } @$c;
	my $got = new_parser()->add_heading_ids($in);
	$got =~ s/\[#[a-z][0-9a-f]{7}\]/[#ID]/g;
	is(Encode::decode('UTF-8', $got), Encode::decode('UTF-8', $exp), "add_heading_ids: $c->[2]");
}

done_testing();
