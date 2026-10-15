package Lyndbaum::Highlight;
# 検索語の強調表示と、検索結果に出す抜粋
#
#   検索語は正規化済み（Lyndbaum::Parser::Common::normalize_for_search）のものを受け取る
#   文章は1文字ずつ正規化して検索語と比べ、当たった箇所を元の文字の範囲に戻す
#   （元の文章の大文字・全角などはそのまま表示する）
#
# 戻り値のHTMLはここでエスケープする。<mark> 以外のタグは出さない
use strict;
use warnings;
use utf8;

use Unicode::Normalize qw(NFKC);
use Lyndbaum::HTML qw(escape_html);

# 文章全体を、検索語を <mark> で囲んだHTMLにする
sub mark {
	my ($class, $text, $words) = @_;
	return _mark($text, _ranges($text, $words), 0, length $text);
}

# 当たった箇所の前後を抜き出す（本文の範囲の検索結果に出す）
#   %opt
#     around  当たった箇所の前後に出す文字数（既定は 40）。抜粋1つはこの4倍までの長さにする
#     max     抜粋の数の上限（既定は 3）
#   戻り値は抜粋のHTMLの配列。当たらなければ空
sub snippets {
	my ($class, $text, $words, %opt) = @_;
	my $around = $opt{around} // 40;
	my $max    = $opt{max} // 3;
	$text =~ s/\s+/ /g;
	$text =~ s/\A | \z//g;
	my $ranges = _ranges($text, $words);

	# 当たった箇所の前後をまとめ、重なるものはつなげる（つなげた長さが around の4倍を超えるなら分ける）
	my @windows;
	for my $r (@$ranges) {
		my ($from, $to) = ($r->[0] - $around, $r->[1] + $around);
		$from = 0 if $from < 0;
		$to = length $text if $to > length $text;
		if (@windows && $from <= $windows[-1][1] && $to - $windows[-1][0] <= $around * 4) {
			$windows[-1][1] = $to if $to > $windows[-1][1];
		} else {
			last if @windows >= $max;
			push @windows, [ $from, $to ];
		}
	}
	return [ map {
		my ($from, $to) = @$_;
		($from > 0 ? '…' : '') . _mark($text, $ranges, $from, $to) . ($to < length $text ? '…' : '');
	} @windows ];
}

# 当たった行を行番号つきで抜き出す（原文の範囲の検索結果に出す）
#   %opt
#     max     行の数の上限（既定は 5）
#     width   長い行は、最初に当たった箇所の前後をこの文字数まで出す（既定は 160）
#   戻り値は [ { number => 行番号, html => 行のHTML }, ... ] と、上限を超えて省いた行の数
sub lines {
	my ($class, $text, $words, %opt) = @_;
	my $max   = $opt{max} // 5;
	my $width = $opt{width} // 160;
	my (@lines, $omitted);
	my $number = 0;
	for my $line (split /\r?\n/, $text, -1) {
		$number++;
		my $ranges = _ranges($line, $words);
		next if !@$ranges;
		if (@lines >= $max) {
			$omitted++;
			next;
		}
		my ($from, $to) = (0, length $line);
		if ($to > $width) {
			$from = $ranges->[0][0] - int($width / 4);
			$from = 0 if $from < 0;
			$to = $from + $width;
			$to = length $line if $to > length $line;
		}
		push @lines, {
			number => $number,
			html   => ($from > 0 ? '…' : '') . _mark($line, $ranges, $from, $to) . ($to < length $line ? '…' : ''),
		};
	}
	return (\@lines, $omitted // 0);
}

# 検索語が当たった範囲 [開始, 終了) の一覧（元の文章の文字位置。重なりはまとめる）
sub _ranges {
	my ($text, $words) = @_;
	return [] if !@$words || $text eq '';

	# 1文字ずつ正規化し、正規化後の位置から元の位置を引けるようにする
	my ($normalized, @origin) = ('');
	my @chars = split //, $text;
	for my $i (0 .. $#chars) {
		my $n = lc NFKC($chars[$i]);
		$normalized .= $n;
		push @origin, ($i) x length $n;
	}

	my @ranges;
	for my $word (grep { $_ ne '' } @$words) {
		my $pos = 0;
		while ((my $found = index $normalized, $word, $pos) >= 0) {
			my $end = $found + length $word;
			# 終わりは、当たった最後の文字の元の文字の直後（1文字が複数の文字に正規化されたときは、その文字ごと含める）
			push @ranges, [ $origin[$found], $origin[$end - 1] + 1 ];
			$pos = $end;
		}
	}
	my @merged;
	for my $r (sort { $a->[0] <=> $b->[0] } @ranges) {
		if (@merged && $r->[0] <= $merged[-1][1]) {
			$merged[-1][1] = $r->[1] if $r->[1] > $merged[-1][1];
		} else {
			push @merged, [@$r];
		}
	}
	return \@merged;
}

# 文章の [$from, $to) を、当たった範囲を <mark> で囲んでHTMLにする
sub _mark {
	my ($text, $ranges, $from, $to) = @_;
	my ($html, $pos) = ('', $from);
	for my $r (@$ranges) {
		my ($s, $e) = @$r;
		next if $e <= $from;
		last if $s >= $to;
		$s = $from if $s < $from;
		$e = $to if $e > $to;
		$html .= escape_html(substr $text, $pos, $s - $pos) . '<mark>' . escape_html(substr $text, $s, $e - $s) . '</mark>';
		$pos = $e;
	}
	return $html . escape_html(substr $text, $pos, $to - $pos);
}

1;
