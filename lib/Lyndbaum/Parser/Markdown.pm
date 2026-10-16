package Lyndbaum::Parser::Markdown;
# Markdownパーサー。仕様は docs/markdown-syntax.md
#
# 「ブロックの解析 → インラインの解析」の2段階で処理する
#   1. 行の並びを、段落、見出し、リストなどのブロックの木にする（_parse_blocks）
#   2. ブロックごとにHTMLを出力し、その中の文章をインラインの記法として変換する（_render_*、_inline）
# 対応しない記法は、エラーにせず普通の文章として出力する
use strict;
use warnings;
use utf8;

use Lyndbaum::HTML qw(escape_html escape_text sanitize_tag strip_tags is_safe_url);
use Lyndbaum::Parser::AdiaryTag;
use Lyndbaum::Parser::Common;

# インラインの処理中に、出来上がったHTMLを一時的に置いておく印（私用領域の文字）
my ($PH_OPEN, $PH_CLOSE) = ("\x{E000}", "\x{E001}");
my $TOC_MARK = "\x{E002}TOC\x{E002}";

my $FENCE_RE = qr/\A(`{3,})[ \t]*([^`]*?)[ \t]*\z/;

# 見出しの識別子（見出しの行末の [#識別子]）。ASCII の空白と制御文字、] は使えない
my $HEADING_ID_RE = qr/[^\x00-\x20\x7F\]]+/;

sub parse {
	my ($class, $text, %context) = @_;
	my $self = bless {
		context        => \%context,
		headings       => [],
		ids            => {},
		footnotes      => {},
		footnote_order => [],
		store          => [],   # インラインの処理中に預けたHTML（入れ子の処理でも共通に使う）
	}, $class;

	$text //= '';
	$text =~ s/\r\n?/\n/g;
	my @lines = $self->_collect_footnotes([ split /\n/, $text, -1 ]);
	my $blocks = $self->_parse_blocks(\@lines);

	my $html = $context{sectioning} ? $self->_render_sections($blocks) : $self->_render_blocks($blocks, {});
	$html .= "\n" . $self->_render_footnotes if @{ $self->{footnote_order} };
	my $toc = Lyndbaum::Parser::Common->toc_html($self->{headings}, $self->{context}{article_url});
	$html =~ s/\Q$TOC_MARK\E/$toc/g;

	return { html => "$html\n", toc => $self->{headings} };
}

# 見出しの識別子の無い見出しに、識別子を書き足した原文を返す
#   $id_of->($n) は、記事の n 番目（0から）の見出しの識別子を返す関数。識別子のある見出しも数に入れる
#   戻り値は（書き足した原文, 書き足した数）
#   見出しは行を見て探す（引用やリストの中も見る。コードフェンスの中は見ない）。見出しでない行に
#   書き足すことのないよう、書き足した後の原文を変換し、見出しのID以外が変わらないことを確かめる（違えば die）
sub add_heading_ids {
	my ($class, $text, $id_of) = @_;
	my ($new, $added) = $class->_add_heading_ids($text, $id_of);
	return ($new, 0) if !$added;

	my $before = $class->parse($text, sectioning => 1);
	my $after  = $class->parse($new, sectioning => 1);
	my @from = map { $_->{id} } @{ $before->{toc} };
	my @to   = map { $_->{id} } @{ $after->{toc} };
	die "見出しの数が変わります\n" if @from != @to;
	my %map = map { escape_html($from[$_]) => escape_html($to[$_]) } 0 .. $#from;
	(my $expected = $before->{html}) =~ s/(\bid="|href="#)([^"]*)"/$1 . ($map{$2} \/\/ $2) . '"'/ge;
	die "見出しに識別子を書き足すと、見出しのID以外の出力が変わります\n" if $expected ne $after->{html};
	return ($new, $added);
}

sub _add_heading_ids {
	my ($class, $text, $id_of) = @_;
	my ($n, $added, $fence) = (0, 0);
	my @lines = split /\n/, $text, -1;
	for my $line (@lines) {
		my ($prefix, $rest) = $line =~ /\A((?:[ \t]*>)*[ \t]*(?:(?:-|\d+\.)[ \t]+)?)(.*)\z/s;
		if (defined $fence) {
			undef $fence if $rest =~ /\A\Q$fence\E`*[ \t]*\z/;
			next;
		}
		if ($rest =~ /\A(`{3,})/) {
			$fence = $1;
			next;
		}
		next if $rest !~ /\A#{1,6}[ \t]+\S/;
		my $id = $id_of->($n++);
		next if defined((_split_heading_id($rest))[1]);
		$id =~ /\A$HEADING_ID_RE\z/ or die "見出しの識別子に使えない文字があります: $id\n";
		$line =~ s/[ \t]*\z/ [#$id]/;
		$added++;
	}
	return (join("\n", @lines), $added);
}

# 見出しの文字と識別子を分ける。識別子が無ければ undef
sub _split_heading_id {
	my ($text) = @_;
	return ($1 // '', $2) if $text =~ /\A(?:(.*?)[ \t]+)?\[#($HEADING_ID_RE)\]\z/s;
	return ($text, undef);
}

#======================================================================
# ブロックの解析
#======================================================================

# 脚注の定義（[^id]: 内容）を取り出し、残りの行を返す。コードフェンスの中は見ない
sub _collect_footnotes {
	my ($self, $lines) = @_;
	my @rest;
	my $fence;
	for my $line (@$lines) {
		if (defined $fence) {
			undef $fence if $line =~ /\A[ \t]*\Q$fence\E`*[ \t]*\z/;
		} elsif ($line =~ /\A[ \t]*(`{3,})/) {
			$fence = $1;
		} elsif ($line =~ /\A\[\^([^\]\s]+)\]:[ \t]*(.*)\z/) {
			$self->{footnotes}{$1} //= { text => $2 };
			next;
		}
		push @rest, $line;
	}
	return @rest;
}

sub _parse_blocks {
	my ($self, $lines) = @_;
	my @blocks;
	my $n = @$lines;
	my $i = 0;
	my $blank = 0;   # 直前に空行があったか（リストの項目がゆるいかどうかの判定に使う）
	while ($i < $n) {
		my $line = $lines->[$i];
		my $count = @blocks;

		if ($line =~ /\A[ \t]*\z/) {
			$i++;
			$blank = 1;
			next;
		} elsif ($line =~ $FENCE_RE) {
			my ($fence, $lang) = ($1, $2);
			my $close = qr/\A`{${\ length $fence},}[ \t]*\z/;
			my @code;
			$i++;
			push @code, $lines->[$i++] while $i < $n && $lines->[$i] !~ $close;
			$i++;
			push @blocks, { type => 'code', lang => $lang, text => join '', map { "$_\n" } @code };
		} elsif ($line =~ /\A(#{1,6})[ \t]+(.*?)[ \t]*\z/) {
			push @blocks, { type => 'heading', level => length $1, text => $2 };
			$i++;
		} elsif ($line =~ /\A\[\*toc\][ \t]*\z/) {
			push @blocks, { type => 'toc' };
			$i++;
		} elsif ($line =~ /\A={4,5}[ \t]*\z/) {
			push @blocks, { type => 'more' };
			$i++;
		} elsif ($line =~ /\A-{3,}[ \t]*\z/) {
			push @blocks, { type => 'hr' };
			$i++;
		} elsif ($self->_is_table_start($lines, $i)) {
			($i, my $block) = $self->_parse_table($lines, $i);
			push @blocks, $block;
		} elsif ($line =~ /\A>/) {
			my @quoted;
			while ($i < $n && $lines->[$i] =~ /\A>[ \t]?(.*)\z/) {
				push @quoted, $1;
				$i++;
			}
			# 中に空行があるときだけ、段落を <p> で囲む（旧システムと同じ）
			my $loose = grep { /\A[ \t]*\z/ } @quoted;
			push @blocks, { type => 'quote', loose => $loose, children => $self->_parse_blocks(\@quoted) };
		} elsif (_is_list_marker($line)) {
			($i, my $block) = $self->_parse_list($lines, $i);
			push @blocks, $block;
		} elsif ($line =~ /\A<!--/) {
			# HTMLコメントは出力しない
			$i++ while $i < $n && $lines->[$i] !~ /-->/;
			$i++;
		} elsif (_is_html_block_start($line)) {
			my @html;
			push @html, $lines->[$i++] while $i < $n && $lines->[$i] !~ /\A[ \t]*\z/;
			push @blocks, { type => 'html', lines => \@html };
		} else {
			my @para = ($line);
			$i++;
			while ($i < $n && $lines->[$i] !~ /\A[ \t]*\z/ && !$self->_interrupts_paragraph($lines, $i)) {
				push @para, $lines->[$i++];
			}
			s/\A[ \t]+// for @para;
			push @blocks, { type => 'para', lines => \@para };
		}
		if (@blocks > $count) {
			$blocks[-1]{blank_before} = $blank;
			$blank = 0;
		}
	}
	return \@blocks;
}

# 段落の途中から始められるブロックか
sub _interrupts_paragraph {
	my ($self, $lines, $i) = @_;
	my $line = $lines->[$i];
	return 1 if $line =~ $FENCE_RE
		|| $line =~ /\A#{1,6}[ \t]+\S/
		|| $line =~ /\A-{3,}[ \t]*\z/
		|| $line =~ /\A>/
		|| $line =~ /\A<!--/
		|| _is_list_marker($line)
		|| _is_html_block_start($line)
		|| $self->_is_table_start($lines, $i);
	return 0;
}

sub _is_html_block_start {
	my ($line) = @_;
	my ($name) = $line =~ m{\A</?([a-zA-Z][a-zA-Z0-9]*)(?:[\s/>]|\z)} or return 0;
	return $Lyndbaum::HTML::BLOCK_TAGS{ lc $name } ? 1 : 0;
}

# リストの記号。(種類, 番号, 内容の開始位置, 内容) を返す
#   記号は - と「数字.」のみ。内容の開始位置は記号と後の空白の幅（「- 」なら2、「10. 」なら4）
#   記号の前には3つまで空白を置ける（項目の中で、内容の開始位置より少し深く字下げした入れ子のリスト）
sub _list_marker {
	my ($line) = @_;
	if ($line =~ /\A( {0,3})(-|\d{1,9}\.)([ \t]+)(.*)\z/ || $line =~ /\A( {0,3})(-|\d{1,9}\.)()\z/) {
		my ($lead, $marker, $space, $rest) = ($1, $2, $3, $4 // '');
		my $type = $marker eq '-' ? 'ul' : 'ol';
		my $width = _width($space);
		# 記号の後の空白が5つ以上なら、1つだけを区切りとみなす
		if ($width == 0 || $width > 4) {
			$rest = (' ' x ($width - 1)) . $rest if $width > 4;
			$width = 1;
		}
		my ($number) = $marker =~ /\A(\d+)/;
		return ($type, $number, length($lead) + length($marker) + $width, $rest);
	}
	return;
}

# _list_marker はリストを返すので、真偽値として使うときはこちらを使う
sub _is_list_marker {
	my @marker = _list_marker($_[0]);
	return @marker ? 1 : 0;
}

sub _parse_list {
	my ($self, $lines, $i) = @_;
	my $n = @$lines;
	my ($type, $start) = _list_marker($lines->[$i]);
	my @items;
	while ($i < $n) {
		my ($item_type, undef, $width, $first) = _list_marker($lines->[$i]);
		last if !$item_type || $item_type ne $type;

		my @content = ($first);
		my $j = $i + 1;
		while ($j < $n) {
			my $line = $lines->[$j];
			if ($line =~ /\A[ \t]*\z/) {
				# 空行の後も項目の字下げが続くなら、項目の中の空行
				my $k = $j;
				$k++ while $k < $n && $lines->[$k] =~ /\A[ \t]*\z/;
				last if $k >= $n || _indent($lines->[$k]) < $width;
				push @content, ('') x ($k - $j);
				$j = $k;
				next;
			}
			# 旧システムと同じく、次の行は内容の開始位置より浅くても項目の中とみなす
			#   2桁以上の番号の項目で、3スペースの字下げ
			#   入れ子のリストで、2スペース以上の字下げ
			my $indent = _indent($line);
			last if $indent < ($width > 3 ? 3 : $width) && !($indent >= 2 && _is_list_marker($line =~ s/\A[ \t]+//r));
			push @content, _dedent($line, $width);
			$j++;
		}
		my $item = { lines => \@content };
		push @items, $item;

		# 項目の後の空行。次も同じ種類の項目なら、空行を挟んだリスト
		my $k = $j;
		$k++ while $k < $n && $lines->[$k] =~ /\A[ \t]*\z/;
		my ($next_type) = $k < $n ? _list_marker($lines->[$k]) : ();
		if ($k > $j && $next_type && $next_type eq $type) {
			$item->{blank_after} = 1;
			$i = $k;
		} else {
			$i = $j;
		}
	}

	for my $item (@items) {
		$item->{children} = $self->_parse_blocks($item->{lines});
		# チェックボックス（- [ ] / - [x]）。] の後に空白が必要
		my $para = $item->{children}[0];
		if ($para && $para->{type} eq 'para' && $para->{lines}[0] =~ /\A\[([ xX])\][ \t]+(.*)\z/) {
			$item->{task} = $1 eq ' ' ? 'unchecked' : 'checked';
			$para->{lines}[0] = $2;
			$para->{task} = $item->{task};
		}
	}
	# CommonMark と同じく、リスト単位でゆるいかどうかを決める
	#   項目の間に空行があるか、ある項目の直接の中身（段落、コードブロックなど）の間に空行があれば、全項目の段落を <p> で囲む
	#   入れ子のリストやコードブロックの中の空行は数えない
	my $loose = grep {
		my $children = $_->{children};
		$_->{blank_after} || grep { $children->[$_]{blank_before} } 1 .. $#$children;
	} @items;
	$_->{loose} = $loose for @items;

	return ($i, { type => 'list', ordered => $type eq 'ol', start => $start, items => \@items });
}

sub _is_table_start {
	my ($self, $lines, $i) = @_;
	return 0 if $lines->[$i] !~ /\A\|/ || $i + 1 >= @$lines;
	return _is_delimiter_row($lines->[$i + 1]);
}

sub _is_delimiter_row {
	my ($line) = @_;
	return $line =~ /\A\|[ \t]*:?-+:?[ \t]*(?:\|[ \t]*:?-+:?[ \t]*)*\|?[ \t]*\z/ ? 1 : 0;
}

sub _parse_table {
	my ($self, $lines, $i) = @_;
	my $header = _split_cells($lines->[$i]);
	my @align = map { /\A:-+:\z/ ? 'c' : /\A-+:\z/ ? 'r' : '' } map { s/\s+//gr } @{ _split_cells($lines->[$i + 1]) };
	$i += 2;
	my @rows;
	while ($i < @$lines && $lines->[$i] =~ /\A\|/) {
		push @rows, _split_cells($lines->[$i]);
		$i++;
	}
	return ($i, { type => 'table', header => $header, align => \@align, rows => \@rows });
}

# 表の1行をセルに分ける（GFM と同じ）
#   エスケープしていない | で分ける。コードスパンの中でも分ける
#   \| は | に戻す。コードスパンの中でも戻す
sub _split_cells {
	my ($line) = @_;
	$line =~ s/\A\|//;
	$line =~ s/(?<!\\)\|[ \t]*\z//;
	my @cells;
	my $cell = '';
	while ($line =~ /\G(\\.?|\||[^\\|]+)/gcs) {
		my $token = $1;
		if ($token eq '|') {
			push @cells, $cell;
			$cell = '';
		} else {
			$cell .= $token eq '\\|' ? '|' : $token;
		}
	}
	push @cells, $cell;
	s/\A[ \t]+|[ \t]+\z//g for @cells;
	return \@cells;
}

sub _width {
	my ($space) = @_;
	my $width = 0;
	$width += $_ eq "\t" ? 4 - $width % 4 : 1 for split //, $space;
	return $width;
}

sub _indent {
	my ($line) = @_;
	my ($space) = $line =~ /\A([ \t]*)/;
	return _width($space);
}

# 行頭から $width 桁分の字下げを取り除く（タブは4桁として数える）
sub _dedent {
	my ($line, $width) = @_;
	my $col = 0;
	while ($col < $width && $line =~ s/\A([ \t])//) {
		$col += $1 eq "\t" ? 4 - $col % 4 : 1;
	}
	return (' ' x ($col > $width ? $col - $width : 0)) . $line;
}

#======================================================================
# ブロックの出力
#======================================================================

# 本文を <section> で囲む。見出し（#）が来るたびに次の <section> にする
sub _render_sections {
	my ($self, $blocks) = @_;
	my @groups = ([]);
	for my $block (@$blocks) {
		push @groups, [] if $block->{type} eq 'heading' && $block->{level} == 1 && @{ $groups[-1] };
		push @{ $groups[-1] }, $block;
	}
	return join "\n", map { "<section>\n" . $self->_render_blocks($_, {}) . "\n</section>" } grep { @$_ } @groups;
}

# $options
#   tight  リストの項目の中で、段落を <p> で囲まない
#   quote  引用の中で、段落を <p> で囲まない
sub _render_blocks {
	my ($self, $blocks, $options) = @_;
	my @out;
	my $previous = '';
	for my $block (@$blocks) {
		my $html = $self->_render_block($block, $options);
		next if $html eq '';
		# <p> で囲まない段落が続くときは、空行の代わりに改行を挟む
		if ($options->{quote} && $previous eq 'para' && $block->{type} eq 'para') {
			$html = "<br />\n$html";
		}
		push @out, $html;
		$previous = $block->{type};
	}
	return join "\n", @out;
}

sub _render_block {
	my ($self, $block, $options) = @_;
	my $type = $block->{type};

	if ($type eq 'para') {
		return $self->_render_paragraph($block, $options);
	}
	if ($type eq 'heading') {
		my ($text, $explicit) = _split_heading_id($block->{text});
		my $html  = $self->_inline($text);
		my $id    = Lyndbaum::Parser::Common->heading_id($html, $self->{ids}, $explicit);
		my $level = $block->{level} + 2;
		$level = 6 if $level > 6;
		push @{ $self->{headings} }, { level => $block->{level}, id => $id, html => $html };
		my $href = $self->_href_to($id);
		return qq{<h$level id="} . escape_html($id) . qq{"><a href="$href">$html</a></h$level>};
	}
	if ($type eq 'code') {
		return '<pre><code class="language-' . escape_html($block->{lang}) . '">' . escape_text($block->{text}) . '</code></pre>';
	}
	if ($type eq 'hr') {
		return '<hr />';
	}
	if ($type eq 'toc') {
		return $TOC_MARK;
	}
	if ($type eq 'more') {
		return $Lyndbaum::Parser::Common::MORE_MARK;
	}
	if ($type eq 'quote') {
		return "<blockquote>\n" . $self->_render_blocks($block->{children}, { quote => !$block->{loose} }) . "\n</blockquote>";
	}
	if ($type eq 'list') {
		return $self->_render_list($block);
	}
	if ($type eq 'table') {
		return $self->_render_table($block);
	}
	if ($type eq 'html') {
		return _render_html(join "\n", @{ $block->{lines} });
	}
	die "知らないブロックです: $type\n";
}

# HTMLブロック。Markdown は処理せず、タグを許可リストに照らし、それ以外の文字をエスケープする
sub _render_html {
	my ($html) = @_;
	$html =~ s/<!--.*?-->//gs;
	my $out = '';
	for my $part (split /(<\/?[a-zA-Z][a-zA-Z0-9]*(?:\s[^<>]*)?\/?>)/, $html) {
		my $tag = $part =~ /\A</ ? sanitize_tag($part) : undef;
		if (defined $tag) {
			$out .= $tag;
		} else {
			$part =~ s/&(?!(?:#\d+|#x[0-9a-fA-F]+|[a-zA-Z][a-zA-Z0-9]*);)/&amp;/g;
			$part =~ s/</&lt;/g;
			$part =~ s/>/&gt;/g;
			$out .= $part;
		}
	}
	return $out;
}

sub _render_paragraph {
	my ($self, $block, $options) = @_;
	my $text = join "\n", @{ $block->{lines} };

	# adiary のブロック要素のタグ（バナーなど）だけの段落は <p> で囲まない
	if ($text =~ /\A\[([^\[\]\n]+)\][ \t]*\z/) {
		my $tag = Lyndbaum::Parser::AdiaryTag->render($1, $self->{context}, sub { $self->_inline($_[0]) });
		return $tag->{html} if $tag && $tag->{block};
	}

	my $html = $self->_inline($text);
	if ($block->{task}) {
		my ($first, $rest) = split /\n/, $html, 2;
		my $checked = $block->{task} eq 'checked' ? ' checked' : '';
		$html = qq{<label><input type="checkbox"$checked>$first</label>} . (defined $rest ? "\n$rest" : '');
	}
	$html =~ s/\n/<br \/>\n/g;
	return $html if $options->{tight} || $options->{quote};
	return "<p>$html</p>";
}

sub _render_list {
	my ($self, $block) = @_;
	my $tag  = $block->{ordered} ? 'ol' : 'ul';
	my $open = $tag;
	$open .= qq{ start="$block->{start}"} if $block->{ordered} && $block->{start} != 1;
	my @items;
	for my $item (@{ $block->{items} }) {
		my $inner = $self->_render_blocks($item->{children}, { tight => !$item->{loose} });
		my $li = $item->{task} ? '<li class="task-list-item">' : '<li>';
		push @items, "$li$inner</li>";
	}
	return "<$open>\n" . join("\n", @items) . "\n</$tag>";
}

sub _render_table {
	my ($self, $block) = @_;
	my @align = @{ $block->{align} };
	my $cells = sub {
		my ($tag, $row, $use_align) = @_;
		my $out = '';
		for my $i (0 .. $#{ $block->{header} }) {
			my $class = $use_align && $align[$i] ? qq{ class="$align[$i]"} : '';
			$out .= "\t<$tag$class>" . $self->_inline($row->[$i] // '') . "</$tag>\n";
		}
		return $out;
	};
	my $html = qq{<div class="body_table"><table><thead><tr>\n} . $cells->('th', $block->{header}, 0) . "</tr></thead>\n<tbody>\n";
	$html .= "<tr>\n" . $cells->('td', $_, 1) . "</tr>\n" for @{ $block->{rows} };
	return $html . '</tbody>' . "\n</table></div>";
}

sub _render_footnotes {
	my ($self) = @_;
	my $out = qq{<div class="footnotes">\n<hr />\n<ol>\n};
	for my $note (@{ $self->{footnote_order} }) {
		my $href = $self->_href_to("fnref-$note->{number}");
		$out .= qq{<li id="fn-$note->{number}">$note->{html} <a href="$href">&#8617;</a></li>\n};
	}
	return $out . "</ol>\n</div>";
}

#======================================================================
# インラインの解析
#======================================================================

sub _inline {
	my ($self, $text) = @_;
	my $store = $self->{store};
	my $hold = sub {
		push @$store, $_[0];
		return $PH_OPEN . $#$store . $PH_CLOSE;
	};

	# 1. コードスパン（開始と同じ長さのバッククォート列で閉じる。行はまたがない）
	$text =~ s{(?<![`\\])(`+)(?!`)([^\n]*?[^`\n])\1(?!`)}{
		my $code = $2;
		$code =~ s/\A (.*) \z/$1/s if $code =~ /\A .* \z/s && $code =~ /\S/;
		$hold->('<code>' . escape_text($code) . '</code>');
	}gse;

	# 2. バックスラッシュによるエスケープ
	$text =~ s{\\([!-/:-@\[-`\x7B-~])}{ $hold->(escape_text($1)) }ge;

	# 3. HTMLコメントは出力しない
	$text =~ s{<!--.*?-->}{}gs;

	# 4. 角括弧の記法（リンク、画像、脚注、adiary のタグ）。リンク先の <URL> を先に使うため、自動リンクより前に処理する
	$text = $self->_brackets($text, $hold);

	# 5. 自動リンク（<URL>、<メールアドレス>）
	$text =~ s{<((?:https?|ftp)://[^\s<>]+)>}{
		my $url = escape_html($1);
		$hold->(qq{<a href="$url">$url</a>});
	}ge;
	$text =~ s{<(?:mailto:)?([^\s<>@]+\@[^\s<>@]+\.[^\s<>@]+)>}{ $hold->(_mail_link($1)) }ge;

	# 6. 生のHTMLのタグ。許可しないタグは文字として出す
	$text =~ s{(</?[a-zA-Z][a-zA-Z0-9]*(?:\s[^<>]*)?/?>)}{
		my $tag = sanitize_tag($1);
		defined $tag ? $hold->($tag) : $1;
	}ge;

	# 7. 残りの文字をエスケープする（文字参照はそのまま）
	$text =~ s/&(?!(?:#\d+|#x[0-9a-fA-F]+|[a-zA-Z][a-zA-Z0-9]*);)/&amp;/g;
	$text =~ s/</&lt;/g;
	$text =~ s/>/&gt;/g;

	# 8. 強調（行はまたがない）。__ の太字は対応しない
	#   * の強調は、CommonMark と同じく前後が文字でもよい（「図にない*libraries*が」）
	#   _ の強調は、前後が文字のときは強調にしない（「snake_case_name」）
	$text =~ s{\*\*(?=\S)([^\n]+?)(?<=\S)\*\*}{<strong>$1</strong>}g;
	$text =~ s{~~(?=\S)([^\n]+?)(?<=\S)~~}{<del>$1</del>}g;
	$text =~ s{(?<!\*)\*(?=[^\s*])([^*\n]*?[^\s*])\*(?!\*)}{<em>$1</em>}g;
	$text =~ s{(?<!\*)\*([^\s*])\*(?!\*)}{<em>$1</em>}g;
	$text =~ s{(?<![\p{L}\p{N}_])_(?=[^\s_])([^_\n]*?[^\s_])_(?![\p{L}\p{N}_])}{<em>$1</em>}g;
	$text =~ s{(?<![\p{L}\p{N}_])_(?=[^\s_])([^\s_])_(?![\p{L}\p{N}_])}{<em>$1</em>}g;

	# 預けておいたHTMLを戻す（入れ子になっていることがあるので、無くなるまで繰り返す）
	1 while $text =~ s/$PH_OPEN(\d+)$PH_CLOSE/$store->[$1]/g;
	return $text;
}

# 角括弧の記法を変換する。中身に角括弧を含むもの（[[image:…]] など）は内側から順に処理する
sub _brackets {
	my ($self, $text, $hold) = @_;
	$text =~ s{
		(!?)
		(\[ ((?:[^\[\]\\]|\\.|(?2))*) \])
		(?: \( [ \t]* ( <[^<>\n]*> | (?:[^\s()]|\([^\s()]*\))* ) [ \t]* \) )?
	}{
		$self->_bracket($1, $3, $4, $&, $hold);
	}gsex;
	return $text;
}

sub _bracket {
	my ($self, $bang, $inner, $url, $whole, $hold) = @_;

	if (defined $url) {
		$url =~ s/\A<(.*)>\z/$1/s;
		if ($url ne '' && is_safe_url($url)) {
			my $href = escape_html($self->_resolve_link($url));
			return $hold->(qq{<img src="$href" alt="} . escape_html($inner) . '" />') if $bang;
			return $hold->(qq{<a href="$href">} . $self->_inline($inner) . '</a>');
		}
	}
	elsif (!$bang) {
		if ($inner =~ /\A\^([^\]\s]+)\z/ && $self->{footnotes}{$1}) {
			return $hold->($self->_footnote_ref($1));
		}
		my $tag = Lyndbaum::Parser::AdiaryTag->render($inner, $self->{context}, sub { $self->_inline($_[0]) });
		return $hold->($tag->{html}) if $tag;
	}

	# [[youtube:…]] のように adiary のタグを角括弧で囲んだものは、外側の角括弧を消す（旧システムと同じ）
	if (!defined $url && !$bang && $inner =~ /\A\[([^\[\]]+)\]\z/) {
		my $tag = Lyndbaum::Parser::AdiaryTag->render($1, $self->{context}, sub { $self->_inline($_[0]) });
		return $hold->($tag->{html}) if $tag;
	}

	# 記法にならないものは文字のまま。中身に記法があれば、それは変換する
	my $rest = defined $url ? substr($whole, length("$bang\[$inner]")) : '';
	return $bang . '[' . $self->_brackets($inner, $hold) . ']' . $rest;
}

# 記事内の相対リンク（スキームも / も # も無いもの）は、記事の slug へのリンク
# （[文字](0618)、[文字](管理人について)）。記事のURLは slug と同じなので、先頭に / を付ける
#   一覧やコンテンツページの中でも同じリンク先になるよう、相対URLのままにはしない
sub _resolve_link {
	my ($self, $url) = @_;
	return $url if $url =~ m{\A(?:[a-zA-Z][a-zA-Z0-9+.-]*:|/|#|\.)};
	return ($self->{context}{base_path} // '') . "/$url";
}

sub _footnote_ref {
	my ($self, $label) = @_;
	my $note = $self->{footnotes}{$label};
	if (!$note->{number}) {
		push @{ $self->{footnote_order} }, $note;
		$note->{number} = scalar @{ $self->{footnote_order} };
		$note->{html} = $self->_inline($note->{text});
	}
	my $n = $note->{number};
	my $title = escape_html(strip_tags($note->{html}) =~ s/&amp;/&/gr =~ s/&lt;/</gr =~ s/&gt;/>/gr);
	my $href = $self->_href_to("fn-$n");
	return qq{<sup id="fnref-$n"><a href="$href" title="$title">[$n]</a></sup>};
}

# 記事の中の要素（見出し、脚注）へのリンク先。エスケープ済み
#   「記事のURL#ID」にする（一覧に本文を並べても、ほかの記事の同じIDではなく、その記事の要素へ行くように）
#   記事のURLが無ければ（context の article_url）「#ID」
sub _href_to {
	my ($self, $id) = @_;
	return escape_html(($self->{context}{article_url} // '') . "#$id");
}

# メールアドレスは、収集対策として数値文字参照にする
sub _mail_link {
	my ($address) = @_;
	my $encode = sub { join '', map { sprintf '&#%d;', ord } split //, $_[0] };
	return '<a href="' . $encode->("mailto:$address") . '">' . $encode->($address) . '</a>';
}

1;
