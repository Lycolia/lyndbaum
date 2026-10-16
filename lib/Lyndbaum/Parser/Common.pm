package Lyndbaum::Parser::Common;
# 記法をまたいで使う部品：見出しのID、目次、続きを読む、検索用テキストの抽出
use strict;
use warnings;
use utf8;

use Lyndbaum::HTML qw(escape_html strip_tags);

# 続きを読むの印。パーサーはこの印を出力し、表示するときにここで分ける
our $MORE_MARK = '<!--more-->';

# 見出しの文字（HTML）からIDを作る（旧システムと同じ規則）
#   タグ、文字参照、ASCII の記号と空白が続くところは - 1つにし、英字は小文字にする（「C#」→「c-」）
#   ただし - . _ は残す（「sort -r」→「sort--r」、「Node.js」→「node.js」）。全角の記号や絵文字もそのまま残す
#   同じIDがすでにあれば、-2、-3 … を付ける。$used はこの記事で使ったIDの表
#   $explicit は見出しに書いた識別子（[#識別子]）。あればそれを使う
sub heading_id {
	my ($class, $html, $used, $explicit) = @_;
	my $id = $explicit // lc $html;
	if (!defined $explicit) {
		$id =~ s/(?:<[^>]*>|&[#\w]+;|[\x00-\x2C\x2F\x3A-\x40\x5B-\x5E\x60\x7B-\x7F])+/-/g;
		$id = '-' if $id eq '';
	}
	if ($used->{$id}++) {
		my $n = $used->{$id};
		$n++ while $used->{"$id-$n"};
		$used->{"$id-$n"} = 1;
		$id = "$id-$n";
	}
	return $id;
}

# 新しい見出しの識別子。英字1文字と16進数7桁（l7a712f2 など）。$used にあるものは避ける
sub new_heading_id {
	my ($class, $used) = @_;
	while (1) {
		my $id = chr(ord('a') + int rand 26) . sprintf '%07x', int rand 0x10000000;
		return $id if !$used || !$used->{$id};
	}
}

# 目次のHTML
#   $headings は [{ level => 1〜6, id => ID, html => 見出しの文字 }, ...]
#   $url は記事のURL（リンクを「記事のURL#ID」にする。一覧に本文を並べても、その記事の見出しへ行くように）
#   見出しの並びを、より浅い見出しを親とする木にしてから出力する
#   1段目は # の見出し。段を飛ばした見出し（# の無い ##、## の直後の #### など）は目次に入れない（旧システムと同じ）
sub toc_html {
	my ($class, $headings, $url) = @_;
	my $root = { level => 0, children => [] };
	my @stack = ($root);
	for my $h (@$headings) {
		pop @stack while $stack[-1]{level} >= $h->{level};
		if ($h->{level} > $stack[-1]{level} + 1) {
			$stack[-1]{skipped} = 1;   # 子が無くても空の <ul> を出す（旧システムと同じ）
			next;
		}
		my $node = { %$h, children => [] };
		push @{ $stack[-1]{children} }, $node;
		push @stack, $node;
	}
	return @{ $root->{children} } ? _toc_list($root->{children}, $url // '', 0, ' class="toc"') : qq{<ul class="toc"></ul>\n};
}

sub _toc_list {
	my ($nodes, $url, $depth, $attr) = @_;
	my $indent = "\t" x $depth;
	my $out = "$indent<ul" . ($attr // '') . ">\n";
	for my $node (@$nodes) {
		$out .= "$indent\t<li><a href=\"" . escape_html("$url#$node->{id}") . "\">" . $node->{html} . "</a>";
		$out .= "\n" . _toc_list($node->{children}, $url, $depth + 1) . "$indent\t" if @{ $node->{children} } || $node->{skipped};
		$out .= "</li>\n";
	}
	return "$out$indent</ul>\n";
}

# 続きを読むの印より前と後に分ける。印が無ければ後は undef
sub split_more {
	my ($class, $html) = @_;
	my ($before, $after) = split /\Q$MORE_MARK\E/, $html, 2;
	return ($before, $after);
}

# 一覧に出す本文。続きを読むの印より前を返し、印の前で閉じていないタグ（<section> など）は閉じる
#   印が無ければ全文。戻り値は (HTML, 続きがあるか)
my %VOID_TAGS = map { $_ => 1 } qw(area br col embed hr img input link meta source track wbr);
sub excerpt {
	my ($class, $html) = @_;
	my ($before, $after) = $class->split_more($html // '');
	return ($before // '', 0) if !defined $after;
	my @open;
	# 本文の < は文字参照になっているので、タグだけを拾える。コメントは飛ばす
	for my $tag ($before =~ m{<!--.*?-->|<(/?[a-zA-Z][a-zA-Z0-9]*)}gs) {
		next if !defined $tag;
		my $name = lc $tag;
		if ($name =~ s{\A/}{}) {
			next if !grep { $_ eq $name } @open;
			1 while pop(@open) ne $name;
		} elsif (!$VOID_TAGS{$name}) {
			push @open, $name;
		}
	}
	$before =~ s/\s*\z/\n/;
	return ($before . join('', map { "</$_>\n" } reverse @open), 1);
}

# 検索用のテキスト（範囲が「本文」のとき）。タイトルと、本文のHTMLからタグを除いたもの
# 画像の代替テキストも含める（画面には出ないが、画像の説明で記事を探せるように）
# Unicode NFKC で正規化して小文字にする。検索語にも同じ正規化をかけてから比べる
sub search_text {
	my ($class, $title, $html) = @_;
	$html //= '';
	my @alts = grep { $_ ne '' } $html =~ /<img\b[^>]*?\balt="([^"]*)"/g;
	my $text = join "\n", $title // '', plain_text($html), map { _unescape($_) } @alts;
	return normalize_for_search($text);
}

# 本文のHTMLから文章だけを取り出す。段落や項目などの区切りは改行にする（前後の文章がつながらないように）
sub plain_text {
	my ($html) = @_;
	$html =~ s{<br\s*/?>|</(?:p|li|h[1-6]|pre|div|td|th|tr|blockquote|figcaption|dt|dd|section|figure)>}{\n}gi;
	return _unescape(strip_tags($html));
}

# 記事の説明（一覧に出す要約）。本文の文章の先頭 $SUMMARY_LENGTH 文字。長ければ ... を付ける（旧システムと同じ）
#   空白と改行は1つの空白にまとめる。本文を変換するときに作り、articles.description に入れる
our $SUMMARY_LENGTH = 64;
sub summary {
	my ($class, $html) = @_;
	my $text = plain_text(($html // '') =~ s/\Q$MORE_MARK\E//gr);
	$text =~ s/\s+/ /g;
	$text =~ s/\A | \z//g;
	return length $text > $SUMMARY_LENGTH ? substr($text, 0, $SUMMARY_LENGTH) . '...' : $text;
}

# 範囲が「原文」のときの検索用のテキスト。タイトルと原文そのもの
sub search_source {
	my ($class, $title, $source) = @_;
	return normalize_for_search(join "\n", $title // '', $source // '');
}

sub normalize_for_search {
	my ($text) = @_;
	require Unicode::Normalize;
	$text = lc Unicode::Normalize::NFKC($text);
	$text =~ s/[ \t]+/ /g;
	$text =~ s/\s*\n\s*/\n/g;
	return $text;
}

sub _unescape {
	my ($text) = @_;
	$text =~ s/&#x([0-9a-fA-F]+);/chr(hex $1)/eg;
	$text =~ s/&#(\d+);/chr($1)/eg;
	$text =~ s/&lt;/</g;
	$text =~ s/&gt;/>/g;
	$text =~ s/&quot;/"/g;
	$text =~ s/&amp;/&/g;
	return $text;
}

1;
