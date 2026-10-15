package MarkdownTest;
# Markdownパーサーのテスト用の部品
use strict;
use warnings;
use utf8;

use Exporter 'import';
our @EXPORT_OK = qw(parse_md normalize_html load_cases);

use Lyndbaum::Parser;

# テストでの変換の設定。記事IDは 1、添付ファイルの置き場所は /attachments/
my %CONTEXT = (
	article_id      => 1,
	attachment_path => '/attachments/',
	sectioning      => 0,
);

sub parse_md {
	my ($text, %options) = @_;
	return Lyndbaum::Parser->parse('markdown', $text, %CONTEXT, %options)->{html};
}

# HTMLの正規化（比較用）
#   タグの前後の改行と字下げを無視する。<pre> の中身はそのまま比べる
#   数値文字参照は文字に戻す（メールアドレスの難読化を比べられるように）
sub normalize_html {
	my ($html) = @_;
	$html =~ s/&#x([0-9a-fA-F]+);/chr(hex($1))/eg;
	$html =~ s/&#(\d+);/chr($1)/eg;
	my @parts = split /(<pre\b.*?<\/pre>)/s, $html;
	for (@parts) {
		next if /\A<pre\b/;
		s/[ \t]*\n[ \t]*/\n/g;
		s/>\n+/>/g;
		s/\n+</</g;
		s/\n+/ /g;
	}
	my $result = join '', @parts;
	$result =~ s/\A\s+|\s+\z//g;
	return $result;
}

# テストケースの読み込み
#
#   === ケース名
#   （ここから --- input までの行は無視されるので、コメントを書ける）
#   --- options: sectioning=1                    （省略可）
#   --- todo: 理由                                （省略可。まだ満たせないもの）
#   --- input
#   Markdown
#   --- expected
#   HTML
sub load_cases {
	my ($file) = @_;
	open my $fh, '<:encoding(UTF-8)', $file or die "$file: $!\n";
	my @cases;
	my ($case, $section);
	while (my $line = <$fh>) {
		if ($line =~ /\A=== (.*?)\s*\z/) {
			$case = { name => $1, input => '', expected => '', options => {} };
			push @cases, $case;
			$section = undef;
			next;
		}
		next if !$case;
		if ($line =~ /\A--- options:\s*(.*?)\s*\z/) {
			for my $pair (split /\s+/, $1) {
				my ($key, $value) = split /=/, $pair, 2;
				$case->{options}{$key} = $value;
			}
			next;
		}
		if ($line =~ /\A--- todo:\s*(.*?)\s*\z/) {
			$case->{todo} = $1;
			next;
		}
		if ($line =~ /\A--- (input|expected)\s*\z/) {
			$section = $1;
			next;
		}
		$case->{$section} .= $line if $section;
	}
	close $fh;
	for (@cases) {
		$_->{input}    =~ s/\n\z//;
		$_->{expected} =~ s/\n\z//;
	}
	return \@cases;
}

1;
