use strict;
#-------------------------------------------------------------------------------
# Markdown parser
#                                              (C)2014-2024 nabe / nabe@abk.nu
#-------------------------------------------------------------------------------
# [M]	is compatible to Markdown.pl.
# [GFM] is compatible to GitHub Flavored Markdown.
# [S]	is Satsuki syntax extension.
#
package Satsuki::TextParser::Markdown;
our $VERSION = '1.30';
# 見出しの識別子[#id]に使える文字（ASCIIの空白と制御文字、]以外）
my $HEADING_ID = qr/[^\x00-\x20\x7F\]]+/;
#-------------------------------------------------------------------------------
################################################################################
# Constructor
################################################################################
sub new {
	my $self = bless({}, shift);
	$self->{ROBJ} = shift;

	$self->{section_hnum} = 3;	# H3から使用する
	$self->{tab_width} = 4;		# タブの幅
	$self->{escape_spchar} = 1;	# タグではない <, > をエスケープする

	$self->{md_in_htmlblk} = 1;	# Markdown Inside HTML Blocksを許可する / PHP Markdown Extra
	$self->{sectioning}   = 1;	# sectionタグを適時挿入する
	$self->{gfm_ext}      = 1;	# GitHub Flavored Markdown拡張を使用する
	$self->{strict_list}  = 1;	# リスト開始記号が異なる時、違うブロックと判定する（標準非準拠）

	$self->{satsuki_tags}     = 0;	# satsuki記法のタグを有効にする
	$self->{satsuki_syntax_h} = 1;	# syntaxハイライトをsatsuki記法に準拠させる
	$self->{satsuki_seemore}  = 1;	# 「続きを読む」記法
	$self->{satsuki_footnote} = 0;	# (())による注釈
	$self->{satsuki_in_htmlblk}= 1;	# HTML Blocks中のsatsuki記法を許可する

	# 処理する記事ごとに設定
	$self->{thisurl}  = '';		# 記事のURL
	$self->{thispkey} = '';		# 記事のpkey = unique id = [0-9]+

	return $self;
}

################################################################################
# Main
################################################################################

# 行末記号
#	\x01	これ以上、行処理しない
#	\x02	これ以上、行処理も記法処理もしない
# 特殊記号
#	\x00	not use
#	\x03	escape character
#	\x04	for HTML comment
#
#-------------------------------------------------------------------------------
# parse
#-------------------------------------------------------------------------------
sub parse {
	my ($self, $text) = @_;

	my $sobj = $self->{satsuki_tags} && $self->{satsuki_obj};	# Satsuki parser
	$self->{sobj} = $sobj;

	# Delete special character
	$text =~ s/[\x00-\x04]//g;
	$self->save_comments($text);

	my $lines = [ split(/\n/, $text) ];
	undef $text;

	# Init internal variables
	if ( $sobj ) {
		$sobj->{thisurl}  = $self->{thisurl};
		$sobj->{thispkey} = $self->{thispkey};
	}
	$self->{sections} = [];
	$self->{ids}      = {};
	$self->{heading_ids} = [];	# 見出しのID（出現順。引用の中の見出しは除く）
	$self->{in_quote}    = 0;	# 引用の中を処理している
	$self->{in_list}     = 0;	# リストの項目の中を処理している
	$self->{in_footnote} = 0;	# 脚注の中を処理している
	$self->{footnotes}     = {};	# 脚注定義 [^id]: content
	$self->{footnote_order}= [];	# 脚注の出現順序
	$self->{footnote_refs} = {};	# 脚注ごとの参照の数
	# [S] (())の注釈の番号は、記事ごとに1から振る（パーサーは使い回されるので、ここで戻す）
	if ($self->{satsuki_footnote} && $self->{satsuki_obj}) {
		$self->{satsuki_obj}->init_footnote();
	}

	# parse main
	$lines = $self->parse_block ($lines);
	$lines = $self->parse_inline($lines);

	#-----------------------------------------
	# post process
	#-----------------------------------------
	my $all = join("\n", @$lines);
	$all =~ s|\n+\n</section>\x02|\n</section>\x02\n|g;

	# Markdown脚注の出力
	$self->output_markdown_footnotes(\$all);

	# [S] <toc>
	if ($self->{satsuki_tags} && $self->{satsuki_obj}) {
		$sobj->{sections} = $self->{sections};
		$sobj->post_process( \$all );
	}

	# [S] See More
	my $short = '';
	if ($all =~ /^((.*?)\n?<p class="seemore">.*)<!--%SeeMore%-->\x02?\n(.*)$/s ) {
		$short = $1;
		$all = $2 . "<!--%SeeMore%-->" . $3;
		if ($short =~ m|^.*<section>(.*)$|si && index($1, '</section>')<=0) {
			$short .= "\n</section>";
		}
	}

	$self->restore_comments($all, $short);
	$all   =~ s/[\x00-\x04]//g;
	$short =~ s/[\x00-\x04]//g;

	return wantarray ? ($all, $short) : $all;
}

#-------------------------------------------------------------------------------
# save comments
#-------------------------------------------------------------------------------
sub save_comments {
	my $self = shift;
	my @ary;
	foreach(@_) {
		$_ =~ s/(<!(?:--.*?--\s*)+>)/push(@ary, $1),"\x04" . $#ary . "\x04"/esg;
	}
	foreach(@ary) {
		# remove %SeeMore% in comment
		$_ =~ s/<\!--%SeeMore%-->/<\!--%SeeMore% -->/;
	}
	$self->{comments_ary} = \@ary;
}

sub restore_comments {
	my $self = shift;
	my $ary = $self->{comments_ary};
	foreach(@_) {
		$_ =~ s/\x04(\d+)\x04/$ary->[$1]/g;
	}
}

################################################################################
# Markdown Block Parser
################################################################################
sub parse_nest_block {
	return &parse_block($_[0], $_[1], 1, $_[2]);
}
sub parse_block {
	my ($self, $lines, $nest, $pmode) = @_;

	my $block_tags = qr!
		# original
		p|div|h[1-6]|blockquote|pre|table|dl|ol|ul|
		script|noscript|form|fieldset|iframe|math|ins|del|
		# append tags
		style|article|section|nav|aside|header|footer|details|
		audio|video|figure|canvas|map|
		# GFM https://github.github.com/gfm/#html-block
		address|aside|base|hr|option|source
	!x;

	# $pmode: 段落を<p>で囲むか（省略時は、入れ子のブロックで空行が無ければ囲まない）
	if (!defined $pmode) { $pmode = ($nest && !grep { $_ eq '' } @$lines) ? 0 : 1; }
	my $sectioning = $nest ? 0 : $self->{sectioning};
	my $in_section = 0;
	my $seemore    = 1;
	my $tab_width  = $self->{tab_width};

	my @p_block;

	#-----------------------------------------------------------------------
	# main loop
	#-----------------------------------------------------------------------
	my @ary;
	push(@$lines, '');
	while(@$lines) {
		my $x = shift(@$lines);

		# HTML comment only
		if ($x =~ /^\s*(?:\x04\d+\x04\s*)+$/) {
			push(@ary, "\x02");
			next;
		}

		# [M] TAB to SPACE
		$x =~ s/(.*?)\t/$1 . (' ' x ($tab_width - (length($1) % $tab_width)))/eg;

		#---------------------------------------------------------------
		# HTML block
		#---------------------------------------------------------------
		# 閉じタグで終わる行か空行の、早いほうまでをHTMLブロックとする。
		# 空行の後はMarkdownに戻るので、GFMと同じく<details>の中にMarkdownを書ける。
		# 閉じタグだけの行（</details>など）もHTMLブロックにする（段落の<p>で囲まない）。
		if (!$nest && $x =~ m!^</?($block_tags)\b[^>]*>!i) {
			$self->p_block_end(\@ary, \@p_block, $pmode);
			my $tagend = qr|</$1\s*>\s*$|;
			my $endmark = "\x02";
			if ($self->{md_in_htmlblk} && $x =~ /markdown\s*=\s*"1"/) {
				$x =~ s/\s*markdown\s*=\s*"1"//g;
				$endmark = '';
			}
			my $first=1;
			while(@$lines && $x !~ /$tagend/i) {
				push(@ary, $x . ($first ? "\x01" : $endmark));
				$first=0;
				$x = shift(@$lines);
				if ($x =~ /^\s*$/) {
					# 空行は、HTMLブロックの外として通常の処理に戻す
					unshift(@$lines, $x);
					undef $x;
					last;
				}
			}
			if (defined $x) {
				push(@ary, $x . ($endmark ? $endmark : "\x01"));
			}
			next;
		}

		#---------------------------------------------------------------
		# [GFM] Fenced code blocks
		#---------------------------------------------------------------
		if ($self->{gfm_ext} && $x =~ /^(```+|~~~+)([^`]*?)\s*$/) {
			$self->p_block_end(\@ary, \@p_block, $pmode);
			my $fence = $1;
			my ($lang,$file) = split(':', $2, 2);
			my @code;
			while(@$lines) {
				$x = shift(@$lines);
				if (substr($x,0,length($fence)) eq $fence && $x =~ /^[`~]+\s*$/) { last; }
				$self->escape_in_code($x);
				push(@code, "$x\x02");
			}

			$self->tag_escape($lang, $file);
			if ($file ne '') {
				$file = " title=\"$file\"";
			}
			my $first = shift(@code);
			push(@ary, "<pre><code class=\"language-$lang\">$first");
			push(@ary, @code);
			push(@ary, "</code></pre>\x02");
			next;
		}

		#---------------------------------------------------------------
		# Header syntax
		#---------------------------------------------------------------
		# リストと脚注の中は見出しにしない（文字のまま）
		my $no_heading = $self->{in_list} || $self->{in_footnote};

		# ==/--
		# [M] 2個以上の連なりで文末にスペース以外の文字がない
		if (!$no_heading && $x =~ /^===*\s*$/ && $#p_block == 0) {
			$x = '# '  . pop(@p_block);
		}
		if (!$no_heading && $x =~ /^---*\s*$/ && $#p_block == 0) {
			$x = '## ' . pop(@p_block);
		}

		if (!$no_heading && $x =~ /^(#+)\s+(.*?)$/) {
			$self->p_block_end(\@ary, \@p_block, $pmode);
			my $level = length($1);
			my $title = $2;
			# 見出しの識別子[#id]。IDに使い、画面には出さない（見出しの文字を変えてもIDが変わらない）
			my $fixed_id;
			if ($title =~ /^(?:(.*?)[ \t]+)?\[#($HEADING_ID)\][ \t]*$/) {
				$title    = $1;
				$fixed_id = $2;
			}
			if ($level == 1 && $sectioning && @ary) {
				push(@ary, "</section>\x02");
				push(@ary, "<section>\x02");
				$in_section=1;
			}

			# 引用の中の見出しは、目次に入れず、識別子の書き足しにも数えない（引用元の見出しで、記事の章立てではない）
			if ($self->{in_quote}) {
				my $id = defined $fixed_id ? $self->generate_link_id($fixed_id)
					: $self->generate_id_from_string($title);
				$id =~ s/"/&quot;/g;
				my $h  = $self->{section_hnum} + $level -1;
				if (6 < $h) { $h=6; }
				push(@ary, "$self->{indent}<h$h id=\"$id\"><a href=\"$self->{thisurl}#$id\">$title</a></h$h>\x01");
				push(@ary,'');
				next;
			}

			# generate section
			my $base = '';
			my $secs = $self->{sections};
			foreach(2..$level) {
				my $s = @$secs ? $secs->[$#$secs] : undef;
				if (!$s) {
					if ($base eq '') { $base='0'; }
					$s = {
						num	=> "${base}.0",
						title	=> '(none)',
						count	=> 0
					};
					push(@$secs, $s);
				}
				$base = $s->{num};
				$secs = $s->{children} ||= [];
			}
			my $count = $#$secs<0 ? 1 : $secs->[$#$secs]->{count} + 1;
			my $num   = $base . ($level>1 ? '.' : '') . $count;
			my $id    = defined $fixed_id ? $self->generate_link_id($fixed_id)
				  : $self->generate_id_from_string($title, 'p' . $num);
			push(@{ $self->{heading_ids} }, $id);
			my $id_attr = $id;
			$id_attr =~ s/"/&quot;/g;

			# save section information
			my $sec = {
				id	=> $id_attr,
				num	=> $num,
				number  => undef,
				title	=> $self->parse_oneline($title),
				count	=> $count
			};
			push(@$secs, $sec);

			# output html
			my $h  = $self->{section_hnum} + $level -1;
			if (6 < $h) { $h=6; }
			push(@ary, "$self->{indent}<h$h id=\"$id_attr\"><a href=\"$self->{thisurl}#$id_attr\">$title</a></h$h>\x01");
			push(@ary,'');
			next;
		}

		#---------------------------------------------------------------
		# [S] Satsuki macro
		#---------------------------------------------------------------
		if ($self->{satsuki_tags} && $self->{satsuki_obj}) {
			if ($x =~ m!(.*?)\[\*toc(\d*)(?:|:(.*?))\](.*)!) {
				if ($1 ne '') { push(@ary,$1); }
				push(@ary,'',"<toc>depth=$2:$3</toc>\x01");
				if ($3 ne '') { push(@ary,$4); }
				next;
			}
		}

		#===============================================================
		# paragraph
		#===============================================================
		my $blank = !@p_block;
		if ($x =~ /^\s*$/) { $x=''; }

		# blank line
		if ($x eq '') {
			$self->p_block_end(\@ary, \@p_block, $pmode);
			push(@ary, $x);
			next;
		}

		#---------------------------------------------------------------
		# list block
		#---------------------------------------------------------------
		if ($x =~ /^ ? ? ?(\*|\+|\-|\d+\.) /) {
			$self->p_block_end(\@ary, \@p_block, $pmode);
			my $ulol = length($1)<2 ? 'ul' : 'ol';
			my $mark = $self->{strict_list} ? $1 : undef;
			# 番号付きリストは、書いた番号から始める
			my $start = ($ulol eq 'ol' && $1 != 1) ? ' start="' . ($1+0) . '"' : '';
			$mark = ($mark =~ /^\d+\./) ? '0' : $mark;
			my @list=($x);
			my $blank=0;
			while(@$lines) {
				$x = shift(@$lines);
				if ($x ne '' && ord(substr($x, -1)) < 4) { last; }
				# 空行が続く時は、次の空行でない行で判定する（項目内のコードフェンスの中の連続した空行など）
				if ($blank && $x eq '') {
					push(@list, $x);
					next;
				}
				if ($blank && $x !~ /^ ? ?(\*|\+|\-|\d+\.) |^ /) { last; }
				if ($blank && $1 && $mark) {	# リストの開始文字判定
					my $m = $1;
					$m = ($m =~ /^\d+\./) ? '0' : $m;
					if ($mark ne $m) { last; }
				}
				push(@list, $x);
				$blank = ($x eq '');
			}
			unshift(@$lines, $x);
			if ($list[$#list] eq '') { pop(@list); }
			# 2つ目からの空行はリストの後に戻す
			while (@list && $list[$#list] eq '') { unshift(@$lines, pop(@list)); }

			# listの構成
			push(@ary, "<$ulol$start>\x01");
			my @ul;
			my $li = [];
			my $blank=0;
			my $ul_indent = -1;
			my %p;
			my %li_indent;
			while(@list) {
				$x = shift(@list);
				if ($x =~ /^( ? ?)(\*|\+|\-|\d+\.)( +)(.*)$/
				 && ($ul_indent == -1 || length($1) == $ul_indent)) {
					if (@$li) {
						push(@ul, $li);
					}
					$li = [$4];
					$ul_indent = length($1);
					# 項目内容の開始位置（記号の幅 + 空白。空白5つ以上は1つとみなす）
					$li_indent{$li} = length($2) + (length($3) > 4 ? 1 : length($3));
					if ($blank) { $p{$li} = 1; }
					$blank=0;
					next;
				} elsif ( $x eq '' )  {
					$blank=1;
					$p{$li} = 1;
				} else {
					$blank=0;
					for(my $i=0; $i<$ul_indent; $i++) {
						# そのブロックのインデント除去
						if (ord($x) != 0x20) { next; }
						$x = substr($x,1);
					}
				}
				push(@$li, $x);
			}
			if (@$li) { push(@ul, $li); }

			# [GFM] checkbox list
			# 項目には task-list-item クラスを付ける（リストの記号を消すため。GitHubと同じクラス名）
			my %task;
			if ($self->{gfm_ext}) {
				foreach my $li (@ul) {
					# [GFM] [ ] / [x] / [X] の後に空白が必要。チェックボックスの記号は表示しない
					if ($li->[0] =~ /^\[([ xX])\](?: +(.*)|$)/) {
						my $checked = $1 ne ' ';
						$li->[0] = '<label><input type="checkbox"'
							 . ($checked ? ' checked>' : '>')
							 . $2 . '</label>';
						$task{$li} = 1;
					}
				}
			}

			# nest
			foreach my $li (@ul) {
				my $li_tag = $task{$li} ? '<li class="task-list-item">' : '<li>';
				# 先頭が>の項目は、1行でも引用としてブロック処理する
				if ($#$li == 0 && $li->[0] !~ /^ ? ? ?>/) {
					push(@ary, $p{$li} ? "$li_tag<p>$li->[0]</p></li>" : "$li_tag$li->[0]</li>");
					next;
				}
				# 項目の内容の開始位置（記号の幅。「- 」は2、「1. 」は3、「10. 」は4）まで先頭スペースを除去する
				# ※これより多く除去すると、入れ子の内側の段で子の項目が親と同じ段になる
				my $n = $li_indent{$li} || 2;
				foreach(@$li) {
					$_ =~ s/^ {1,$n}//;
				}

				# 入れ子のリストやコードフェンスの中の空行では、項目を<p>で囲まない
				$self->{in_list}++;
				my $blk = $self->parse_nest_block( $li, $self->is_loose_item($li) );
				$self->{in_list}--;
				if ($blk->[$#$blk] eq '') { pop(@$blk); }
				$blk->[0] = $li_tag . $blk->[0];
				$blk->[$#$blk] .= '</li>';
				push(@ary, @$blk);
			}
			push(@ary, "</$ulol>\x01");
			next;
		}

		#---------------------------------------------------------------
		# [M] blockquote
		#---------------------------------------------------------------
		if ($x =~ /^ ? ? ?>/) {
			$self->p_block_end(\@ary, \@p_block, $pmode);
			push(@ary, '<blockquote>');
			my $p = 0;
			my @block;
			while(@$lines && $x ne '') {
				$x =~ s/^ ? ? ?>\s?(.*)$/$1/;	# [M] '>'後の除去するスペースは1つまで
				if ($x ne '' || $block[$#block] ne '') {
					push(@block, $x);
				}
				$x = shift(@$lines);
			}
			# [M] 入れ子処理する
			$self->{in_quote}++;
			my $blk = $self->parse_nest_block( \@block );
			$self->{in_quote}--;
			push(@ary, @$blk);
			push(@ary, '</blockquote>');
			next;
		}

		#---------------------------------------------------------------
		# [M] コードブロック
		#---------------------------------------------------------------
		if ($blank && $x =~ /^    (.*)/) {
			$self->p_block_end(\@ary, \@p_block, $pmode);
			my @code = ($x);
			while(@$lines && (substr($lines->[0],0,4) eq '    ' || $lines->[0] =~ /^\s*$/)) {
				push(@code, shift(@$lines));
			}
			# 最後の空行を無視
			while (@code && $code[$#code] =~ /^\s*$/) {
				unshift(@$lines, pop(@code));
			}
			foreach(@code) {
				$x = substr($_, 4);
				$self->escape_in_code($x);
				$_ = "$x\x02";
			}
			my $first = shift(@code);
			push(@ary, "<pre><code>$first\x02");
			push(@ary, @code);
			push(@ary, "</code></pre>\x02");
			next;
		}

		#---------------------------------------------------------------
		# [GFM] テーブル
		#---------------------------------------------------------------
		# [GFM] 段落の途中からでも始められる（リスト項目内のテキストの直後など）。
		# その場合は誤検出を避けるため、2行目が区切り行（|-|:-:|など）であることを厳密に確認する
		if ($self->{gfm_ext}
		 && $x =~ /^\s*\|/
		 && $lines->[0] =~ /^\s*|(?:\s*:?\-{3,}:?\s*\|)+\s*$/
		 && ($blank || $lines->[0] =~ /^\s*\|?\s*:?-+:?\s*(?:\|\s*:?-+:?\s*)*\|?\s*$/)
		) {
			my @buf = ($x);
			while(@$lines && $lines->[0] =~ /\|/) {
				push(@buf, shift(@$lines));
			}
			my @tbl = @buf;	# copy

			my @th = $self->split_table_row(shift(@tbl));	# 1行目
			my @hr = $self->split_table_row(shift(@tbl));	# 2行目
			my $err = ($#th > $#hr);			# [GFM] カラム数不一致
			my @class;
			foreach(@hr) {
				if ($#class >= $#th) { next; }		# [GFM] thの分しか読み込まない
				if ($_ !~ /^(:)?-*(:)?/) { $err=1; last; }

				my $c;
				if ($1 && $2) {
					$c = 'c';
				} elsif ($1) {
					$c = 'l';
				} elsif ($2) {
					$c = 'r';
				}
				push(@class, $c);
			}

			# 書式が正しくない時は無効
			if ($err) {
				shift(@buf);
				unshift(@$lines, @buf);
			} else {
				# テーブル展開
				$self->p_block_end(\@ary, \@p_block, $pmode);
				push(@ary, "<div class=\"body_table\"><table><thead><tr>\x02");
				push(@ary, "\t<th>" . join("</th>\n\t<th>", @th) . "</th>");
				push(@ary, "</tr></thead>\x02");
				if (@tbl) { push(@ary, "<tbody>\x02"); }
				foreach(@tbl) {
					my @cols = $self->split_table_row($_);
					push(@ary, "<tr>\x02");
					foreach(@class) {
						my $t = shift(@cols);
						my $c = $_ ? " class=\"$_\"" : '';
						push(@ary, "\t<td$c>$t</td>");
					}
					push(@ary, "</tr>\x02");
				}
				if (@tbl) { push(@ary, "</tbody>\x02"); }
				push(@ary, "</table></div>\x02");
				next;
			}
		}

		#---------------------------------------------------------------
		# 続きを読む記法
		#---------------------------------------------------------------
		if ($blank && $seemore && $self->{satsuki_seemore} && ($x eq '====' || $x eq '=====')) {
			$self->p_block_end(\@ary, \@p_block, $pmode);
			push(@ary, <<TEXT);
<p class="seemore"><a class="seemore" href="$self->{thisurl}">$self->{seemore_msg}</a></p><!--%SeeMore%-->\x02
TEXT
			chomp($ary[$#ary]);
			$seemore=0;
			next;
		}

		#---------------------------------------------------------------
		# <hr />
		#---------------------------------------------------------------
		my $y = $x;
		$y =~ s/\s//g;
		if ($y =~ /^\*\*\*\**$|^----*$|^____*$/) {
			$self->p_block_end(\@ary, \@p_block, $pmode);
			push(@ary, "<hr />\x01");
			next;
		}

		#---------------------------------------------------------------
		# [MD Extra] 脚注定義 [^id]: content
		#---------------------------------------------------------------
		if ($x =~ /^\[\^([^\]]+)\]:\s*(.*)$/) {
			$self->p_block_end(\@ary, \@p_block, $pmode);
			my $fn_id   = $1;
			my $content = $2;

			# 複数行の脚注内容を収集（インデントされた行）
			# [GFM] 空行を挟んでも、次の行がインデントされていれば脚注の続き（次の段落）
			while(@$lines) {
				if ($lines->[0] =~ /^(    |\t)(.*)$/) {
					$content .= "\n" . $2;
					shift(@$lines);
					next;
				}
				my $i = 0;
				while($i <= $#$lines && $lines->[$i] =~ /^\s*$/) { $i++; }
				if (!$i || $i > $#$lines || $lines->[$i] !~ /^(    |\t)/) { last; }
				$content .= "\n" x $i;
				splice(@$lines, 0, $i);
			}

			# 脚注を保存
			$self->{footnotes}{$fn_id} = $content;

			# 次が空行なら除去する
			if (@$lines && $lines->[0] eq '') { shift(@$lines); }
			next;
		}

		#---------------------------------------------------------------
		# 通常文字
		#---------------------------------------------------------------
		$x =~ s/^ ? ? ?//;	# [M] 手前スペース3つまで削除
		push(@p_block, $x);	# 段落ブロック

	}
	while(@ary && $ary[$#ary] eq '') { pop(@ary); }

	# sectioning
	if ($sectioning && grep { $_ =~ /[^\s]/ } @ary) {
		unshift(@ary, "<section>\x02");
		push(@ary, "</section>\x02");
	}
	return \@ary;
}

#-------------------------------------------------------------------------------
# [GFM] テーブルの行をセルに分ける
#-------------------------------------------------------------------------------
# \とその次の1文字はまとめて読む（\\|の|は区切り、\|はセルの中の|）。
# \|はコードスパンの中でも|にする。行頭と行末の|と、セルの前後の空白は除く。
#-------------------------------------------------------------------------------
# リストの項目の段落を<p>で囲むか
#-------------------------------------------------------------------------------
# 項目の直下のブロックの間の空行と、項目の最後の空行（次の項目との間）だけを数える。
# 入れ子のリストやコードフェンスの中の空行は数えない。
# $linesは、項目の内容の開始位置までインデントを除いた行。
sub is_loose_item {
	my ($self, $lines) = @_;
	my $fence;
	my $in_list;
	my $mark;
	for(my $i=0; $i<=$#$lines; $i++) {
		my $x = $lines->[$i];
		# [GFM] コードフェンス（判定はparse_blockと同じ）
		if (defined $fence) {
			if (substr($x,0,length($fence)) eq $fence && $x =~ /^[`~]+\s*$/) { undef $fence; }
			next;
		}
		if ($self->{gfm_ext} && $x =~ /^(```+|~~~+)([^`]*?)\s*$/) {
			$fence   = $1;
			$in_list = 0;
			next;
		}
		if ($x ne '') {
			if (!$in_list && $x =~ /^ ? ? ?(\*|\+|\-|\d+\.) /) {
				$in_list = 1;
				$mark = ($1 =~ /^\d+\./) ? '0' : $1;
			}
			next;
		}

		# 空行
		my $j = $i+1;
		while($j<=$#$lines && $lines->[$j] eq '') { $j++; }
		if ($j > $#$lines) { return 1; }
		# 入れ子のリストの続き（判定はリストの行の収集と同じ）
		if ($in_list && $lines->[$j] =~ /^ ? ?(\*|\+|\-|\d+\.) |^ /) {
			# リストの開始文字が異なる時は、別のリスト
			if ($1 && $self->{strict_list}) {
				my $m = ($1 =~ /^\d+\./) ? '0' : $1;
				if ($m ne $mark) { return 1; }
			}
			$i = $j-1;
			next;
		}
		return 1;
	}
	return 0;
}

sub split_table_row {
	my ($self, $line) = @_;
	$line =~ s/^\s*\|?//;
	my @cells = ('');
	my $sep = 0;	# 最後が区切りの|だったか
	while ($line =~ /\G(\\\||\\.|\||[^\\|]+|\\)/g) {
		if ($1 eq '|') {
			push(@cells, '');
			$sep = 1;
			next;
		}
		$cells[$#cells] .= $1 eq '\\|' ? '|' : $1;
		if ($1 =~ /\S/) { $sep = 0; }
	}
	if ($sep) { pop(@cells); }
	foreach(@cells) { $_ =~ s/^\s+|\s+$//g; }
	return @cells;
}

sub p_block_end {
	my $self = shift;
	my $ary  = shift;
	my $blk  = shift;
	my $pmode= shift;
	if (!@$blk) { return; }

	my $line = ($pmode ? '<p>' : '') . shift(@$blk);
	foreach my $x (@$blk) {
		# 改行はbr変換する
		push(@$ary, $line . '<br />');
		$line = $x;
	}
	# \> によるエスケープ
	$line =~ s/\\>/&gt;/g;

	push(@$ary, $line . ($pmode ? '</p>' : ''));
	@$blk = ();
}

################################################################################
# Markdown Inline Parser
################################################################################
sub parse_oneline {
	my ($self, $text) = @_;
	my $lines = $self->parse_inline( [$text] );
	return $lines->[0];
}

sub parse_inline {
	my ($self, $lines) = @_;

	# 強調タグ処理避け
	sub escape_special_char {
		my $s = shift;
		$s =~ s/([\*\~\`_])/"\x03". ord($1) ."\x03"/eg;
		return $s;
	}

	# Satsuki parser obj
	my $satsuki = $self->{satsuki_obj};

	# [S] 画像タグはキャプションが無ければ <figure> で囲まない。
	# 画像は段落の中に出力されるため、<p> の中に <figure> が入るとHTMLとして不正になる。
	# （このパーサーの処理中だけ有効。他の記法やテーマ向けの出力は変えない）
	my $tag_opt = $satsuki || {};
	local $tag_opt->{image_no_figure} = 1;

	# 注釈
	my @footnote;
	my %note_hash;

	foreach(@$lines) {
		if (substr($_,-1) eq "\x02") {
			# [S] (())の注釈の一覧は、節の終わり（</section>）の前に出す。
			#     一覧の中の注の文も、このあとの記法の処理を通すので、ここで読み飛ばさない
			if (!@footnote || $_ ne "</section>\x02") { next; }
			my $ary = $satsuki->output_footnote(undef, \@footnote, \%note_hash);
			$_ = join('', @$ary) . "</section>\x01";
			# 番号の「*1」は、強調の記法にしない
			$_ =~ s/>\*(\d+)</>\x0342\x03$1</g;
		}

		# エスケープ処理
		# [M] コードスパンの中のバックスラッシュは文字のまま（コードスパンは次で処理する）
		$_ =~ s{((?<!`)(`+)(?!`).+?(?<!`)\2(?!`))|\\([\\`'\*_\[\]\(\)>#\+\-\.\~!])}{
			defined $1 ? $1 : "\x03" . ord($3) . "\x03"
		}eg;

		# inline code
		# 開始と同じ長さのバッククォート列で閉じる。中身には長さの異なるバッククォートを含められる
		$_ =~ s|(?<!`)(`+)(?!`)(.+?)(?<!`)\1(?!`)|
			my $s = $2;
			# 前後が共に空白なら1つずつ除去する（空白のみの場合は除く）
			if ($s =~ /[^ ]/ && $s =~ /^ (.*) $/) { $s = $1; }
			$self->escape_in_code($s);
			$s =~ s/([\\`'\*_\{\}\[\]\(\)>#\+\-\.\~!])/"\x03" . ord($1) . "\x03"/eg;
			"<code>$s</code>";
		|eg;

		# 注釈処理 ((xxxx))
		# 注釈の中には、対になった ( ) を1段だけ書ける（リンクの記法を注釈の最後に書いても、そこで閉じない）
		if ($self->{satsuki_footnote}) {
			$_ =~ s/\(\(((?:[^()]++|\([^()]*\))*)\)\)/ $self->satsuki_footnote_ref($satsuki->footnote($1, \@footnote, \%note_hash)) /eg;
		}

		# 直接リンク記法 - [text](<https://example.com/hoge_(fuga)>)を処理できる方式
		# リンクの文字には対応の取れた[]を含められる（[a [b] c](URL)）
		$_ =~ s{(!?)\[((?:[^\[\]]++|\[(?2)\])*)\]\(<([^>]+)>(?:\s*("[^\"]*"|'[^\']*')\s*)?\)}
		{
			my $is_img= $1;
			my $text  = $2;
			my $url   = $3;
			my $title = substr($4,1);
			chop($title);

			$self->tag_escape($url, $title);
			if ($title ne '') { $title = " title=\"$title\""; }
			$is_img ? "<img src=\"$url\" alt=\"$text\"$title />"
				: "<a href=\"$url\"$title" . $self->image_link_attr($url) . ">$text</a>";
		}eg;

		# 直接リンク記法 - [text](https://example.com/hoge_\(fuga\))を処理できる方式
		# リンク先には対応の取れた()を含められる（https://example.com/a_(b_(c))）
		$_ =~ s{(!?)\[((?:[^\[\]]++|\[(?2)\])*)\]\(((?:[^\(\)\"\']|\((?3)\))*?)(?:\s*("[^\"]*"|'[^\']*')\s*)?\)}
		{
			my $is_img= $1;
			my $text  = $2;
			my $url   = $3;
			my $title = substr($4,1);
			chop($title);

			# <URL>形式の場合は<>を除去
			if ($url =~ /<(.+)>/) {
				$url = $1;
			}

			$self->tag_escape($url, $title);
			if ($title ne '') { $title = " title=\"$title\""; }
			$is_img ? "<img src=\"$url\" alt=\"$text\"$title />"
				: "<a href=\"$url\"$title" . $self->image_link_attr($url) . ">$text</a>";
		}eg;

		# 自動リンク記法
		$_ =~ s!<((?:https?|ftp):[^'"> ]+)>!<a href="$1">$1</a>!ig;

		# 自動リンク記法のメールアドレス展開
		$_ =~ s|<(?:mailto:)?([\w\.\-\+]+\@[a-z0-9\-]+(?:\.[a-z0-9\-]+)*\.[a-z]+)>|
			my $mail = $1;
			$self->un_escape($mail);
			my $mailto = $self->encode_email('mailto:');
			$mail = $self->encode_email($mail);
			"<a href=\"$mailto$mail\">$mail</a>";
		|eg;

		# [MD Extra] 脚注参照 [^id]
		$_ =~ s{\[\^([^\]]+)\]}{
			my $fn_id = $1;
			if (exists $self->{footnotes}{$fn_id}) {
				# 出現順序を記録
				if (!grep { $_ eq $fn_id } @{$self->{footnote_order}}) {
					push(@{$self->{footnote_order}}, $fn_id);
				}
				my $num = 1 + (grep { $_ eq $fn_id } @{$self->{footnote_order}} ? 0 : 0);
				for my $i (0..$#{$self->{footnote_order}}) {
					if ($self->{footnote_order}[$i] eq $fn_id) { $num = $i + 1; last; }
				}
				my $id = "fn-$fn_id";
				# [GFM] 2回目以降の参照はfnref-id-2, fnref-id-3…
				my $n = ++$self->{footnote_refs}{$fn_id};
				my $ref_id = "fnref-$fn_id" . ($n > 1 ? "-$n" : '');
				"<sup id=\"$ref_id\"><a href=\"$self->{thisurl}#$id\">[$num]</a></sup>";
			} else {
				"[^$fn_id]";
			}
		}eg;

		# [S] さつき記法のタグ処理
		if ($self->{satsuki_tags}) {
			$_ = $satsuki->parse_tag( $_, \&escape_special_char );
			$satsuki->un_escape( $_ );
		}

		# タグ中の文字を処理しないようにエスケープ
		# <a href="http://example.com/_hoge_">_hoge_</a>
		$_ =~ s!(<\w(?:"[^\"]*"|'[^\"]*'|[^>])*>)!&escape_special_char($1)!eg;

		# 強調
		# 記号の内側が空白で始まる・終わるものは強調にしない（2 * 3 * 4、*.txt と *.md）。
		# 閉じていない**は文字のまま
		$_ =~ s|\*\*(?=\S)(.+?)(?<=\S)\*\*|<strong>$1</strong>|g;
		$_ =~ s|  __(.*?)__  |<strong>$1</strong>|xg;
		$_ =~ s|(?<!\*)\*(?=[^\s\*])([^\*]*?[^\s\*])\*(?!\*)|<em>$1</em>|g;
		$_ =~ s|(?<!\*)\*([^\s\*])\*(?!\*)|<em>$1</em>|g;

		if ($self->{gfm_ext}) {
			# [GFM] 前後が文字（日本語を含む）のときは強調にしない（snake_case_name、図にない_libraries_が）。
			# 文字かどうかを見るため、この処理だけ文字列に戻す
			my $decoded = utf8::decode($_);
			$_ =~ s#(?<![\p{L}\p{N}_])_(?=[^\s_])([^_]*?[^\s_])_(?![\p{L}\p{N}_])#<em>$1</em>#g;
			$_ =~ s#(?<![\p{L}\p{N}_])_([^\s_])_(?![\p{L}\p{N}_])#<em>$1</em>#g;
			if ($decoded) { utf8::encode($_); }
		} else {
			$_ =~ s|_( [^_]*)_ |<em>$1</em>|xg;				# [M]
		}

		# [GFM] Strikethrough
		if ($self->{gfm_ext}) {
			$_ =~ s|~~(.*?)~~|<del>$1</del>|xg;
		}

		# 画像ビューアーで開くテキストリンクは、リンクの文字をキャプションにする
		# 強調などを処理した後の文字を使うため、ここで付ける
		$self->add_image_link_caption($_);

		# escape special charactor "<" ">"
		# HTMLに無いタグ名（<M>、<x86 Panther Lake>など）は文字として表示する
		if ($self->{escape_spchar}) {
			$_ =~ s!(.*?)(</[\w\-]+>|<[\w\-]+(?:\s+[\w\-]+(?:\s*=\s*(?:[^\s\"]+|"[^\"]*"))?)*\s*/?>|$)!
				my $t   = $1;
				my $tag = $2;
				my ($name) = $tag =~ m|^</?([\w\-]+)|;
				unless ($name eq '' || $self->is_html_tag_name($name)) {
					$t  .= $tag;
					$tag = '';
				}
				$t =~ s/</&lt;/g;
				$t =~ s/>/&gt;/g;
				$t . $tag;
			!eg;
		}

		# [S] ブロック要素（バナー、キャプション付きの画像）だけの段落は<p>で囲まない
		$_ =~ s!^<p>(<(div|figure)\b.*</\2>)</p>$!$1!;
	}

	#---------------------------------------------------
	# エスケープを戻す
	#---------------------------------------------------
	$self->un_escape(@$lines);

	return $lines;
}

#-------------------------------------------------------------------------------
# [S] (())の注釈の、本文に出す番号のリンク
#-------------------------------------------------------------------------------
# このあとの記法の処理を通さない（「*1」が強調にならず、title の中の記法がタグにならない）。
# title には注の原文が入るので、リンクの記法は文字だけにする
sub satsuki_footnote_ref {
	my ($self, $ref) = @_;
	$ref =~ s{title="([^"]*)"}{
		my $t = $1;
		$t =~ s/!?\[([^\]]*)\]\([^)]*\)/$1/g;
		"title=\"$t\"";
	}e;
	# タグの「>」はエスケープしない（後の処理が、閉じていないタグの「<」を文字にするため）
	$ref =~ s/([\\`'\*_\{\}\[\]\(\)#\+\-\.\~!])/"\x03" . ord($1) . "\x03"/eg;
	return $ref;
}

# エスケープを戻す
sub un_escape {
	my $self = shift;
	foreach(@_) {
		$_ =~ s/\x03(\d+)\x03/chr($1)/eg;
	}
	return $_[0];
}

################################################################################
# Subroutine
################################################################################
#-------------------------------------------------------------------------------
# ●コードブロック中のエスケープ
#-------------------------------------------------------------------------------
sub escape_in_code {
	my $self = shift;
	$self->restore_comments(@_);
	foreach(@_) {
		$_ =~ s/&/&amp;/g;
		$_ =~ s/</&lt;/g;
		$_ =~ s/>/&gt;/g;
	}
	return $_[0];
}

#-------------------------------------------------------------------------------
# ●HTMLのタグ名か
#-------------------------------------------------------------------------------
# 許可するかどうかは、この後のタグの除去（info/allow_tags_*.txt）で決める。
# ここではHTMLのタグとして書かれたものか、文字として書かれたものかだけを見分ける。
my %HTML_TAG_NAMES = map { $_ => 1 } qw(
	a abbr address area article aside audio b base bdi bdo blockquote body br button
	canvas caption center cite code col colgroup command data datalist dd del details dfn
	dialog div dl dt em embed fieldset figcaption figure font footer form
	h1 h2 h3 h4 h5 h6 head header hgroup hr html i iframe img input ins kbd keygen
	label legend li link main map mark math menu meta meter nav noscript object ol
	optgroup option output p param picture pre progress q rp rt ruby s samp script
	search section select slot small source span strike strong style sub summary sup
	table tbody td template textarea tfoot th thead time title tr track tt u ul var
	video wbr
	svg path g circle ellipse line polygon polyline rect text tspan defs use symbol
	toc module
);
sub is_html_tag_name {
	my $self = shift;
	my $name = lc(shift);
	# カスタム要素（amp-adなど）は名前に-を含む
	return $HTML_TAG_NAMES{$name} || index($name, '-') > 0;
}

#-------------------------------------------------------------------------------
# ●タグのエスケープ
#-------------------------------------------------------------------------------
sub tag_escape {
	my $self = shift;
	$self->restore_comments(@_);
	foreach(@_) {
		# $_ =~ s/&/&amp;/g;
		$_ =~ s/</&lt;/g;
		$_ =~ s/>/&gt;/g;
		$_ =~ s/"/&quot;/g;
	}
	return $_[0];
}

#-------------------------------------------------------------------------------
# ●画像へのリンクを画像ビューアーで開く属性
#-------------------------------------------------------------------------------
# サイト内の画像を指すリンクには、[image:...]と同じ属性（image_attr）を付け、
# テキストのリンクでも画像ビューアー（Lythumb-viewer）で開けるようにする。
# 外部のURL（スキームや//の付いたもの）は対象外。拡張子だけでは画像か判定しきれず、
# 直リンクを禁止しているサイトもあるため
#
sub image_link_attr {
	my $self = shift;
	my $url  = shift;
	my $attr = $self->{image_attr};
	if ($attr eq '') { return ''; }
	if ($url =~ m!^(?:[A-Za-z][A-Za-z0-9+.\-]*:|//)!) { return ''; }
	my $path = $url;
	$path =~ s/[?#].*//s;
	if ($path !~ /\.(?:jpe?g|png|gif|webp|avif|bmp)$/i) { return ''; }
	$attr =~ s/%k/$self->{thispkey}/g;
	return ' ' . $attr;
}

#-------------------------------------------------------------------------------
# ●画像ビューアーで開くリンクに、リンクの文字のキャプションを付ける
#-------------------------------------------------------------------------------
# Lythumb-viewerは data-caption、無ければ中の<img>のaltをキャプションにする。
# data-caption="" だとaltが使われなくなるので、文字の無いリンク（画像だけのリンク）には付けない
#
sub add_image_link_caption {
	my $self = shift;
	$_[0] =~ s{(<a\s(?:"[^"]*"|[^>"])*\bdata-lythumb="[^"]*"(?:"[^"]*"|[^>"])*)>(.*?)</a>}{
		my $tag  = $1;
		my $text = $2;
		my $cap  = $text;
		$cap =~ s/<(?:"[^"]*"|[^>"])*>//g;
		$cap =~ s/^\s+|\s+$//g;
		if ($cap ne '' && $tag !~ /\sdata-caption=/) {
			$cap =~ s/"/&quot;/g;
			$cap =~ s/</&lt;/g;
			$cap =~ s/>/&gt;/g;
			$tag .= " data-caption=\"$cap\"";
		}
		"$tag>$text</a>";
	}eg;
	return $_[0];
}

#-------------------------------------------------------------------------------
# ●Markdown脚注の出力
#-------------------------------------------------------------------------------
sub output_markdown_footnotes {
	my $self = shift;
	my $text_ref = shift;
	my $order = $self->{footnote_order};
	if (!@$order) { return; }

	my $footnotes = $self->{footnotes};
	my @out;
	push(@out, '<div class="footnotes">');
	push(@out, '<hr />');
	push(@out, '<ol>');

	foreach my $fn_id (@$order) {
		# [GFM] 参照ごとに戻るリンクを付ける。2つ目からは番号を付ける
		my $count = $self->{footnote_refs}{$fn_id} || 1;
		my $backref = join(' ', map {
			my $ref_id = "fnref-$fn_id" . ($_ > 1 ? "-$_" : '');
			"<a href=\"$self->{thisurl}#$ref_id\">&#8617;" . ($_ > 1 ? "<sup>$_</sup>" : '') . '</a>';
		} 1..$count);

		my $content = $footnotes->{$fn_id};
		my $parsed;
		if ($content =~ /\n\s*\n/) {
			# [GFM] 複数の段落は、本文と同じくブロックとして処理し、戻るリンクは最後の段落に入れる
			$self->{in_footnote}++;
			my $blk = $self->parse_nest_block([ split(/\n/, $content) ]);
			$self->{in_footnote}--;
			$parsed = $self->parse_inline([ grep { $_ ne '' } @$blk ]);
			if ($parsed->[$#$parsed] !~ s|</p>([\x01\x02]*)$| $backref</p>$1|) {
				push(@$parsed, $backref);
			}
		} else {
			$parsed = $self->parse_inline([ split(/\n/, $content) ]);
			# 本文の段落と同じく、改行はbr変換する
			$_ .= '<br />' foreach @$parsed[0 .. $#$parsed-1];
			$parsed->[$#$parsed] .= " $backref";
		}
		$content = join("\n", @$parsed);
		my $id = "fn-$fn_id";
		push(@out, "<li id=\"$id\">$content</li>");
	}

	push(@out, '</ol>');
	push(@out, '</div>');

	$$text_ref .= "\n" . join("\n", @out);
}

#-------------------------------------------------------------------------------
# ●メールアドレス難読化エンコード
#-------------------------------------------------------------------------------
sub encode_email {
	my $self = shift;
	my $str  = shift;
	$str =~ s[(.)][
		my $r = int(rand(10));
		if (!$r) { $1; }
		if ($r<5) { '&#'  . ord($1) .';'; }
		     else { '&#x' . sprintf('%X',ord($1)) .';'; }
	]eg;
	return $str;
}

#-------------------------------------------------------------------------------
# ●ラベル等からidを生成
#-------------------------------------------------------------------------------
sub generate_id_from_string {
	my $self  = shift;
	my $label = shift;
	my $default = shift || 'id';
	$label =~ tr/A-Z/a-z/;
	$label =~ s/[^\w\-\.\x80-\xff]+/-/g;
	return $self->generate_link_id($label eq '' ? $default : $label);
}

sub generate_link_id {
	my $self  = shift;
	my $base  = shift;
	my $ids   = $self->{ids};

	my $id = $base;
	my $i  = 1;
	while($ids->{$id}) {
		$id = $base . "-" . (++$i);
	}
	$ids->{$id} = 1;
	return $id;
}

#-------------------------------------------------------------------------------
# ●識別子の無い見出しに、新しい識別子[#id]を書き足す
#-------------------------------------------------------------------------------
# 見出しの文字を変えてもIDが変わらないよう、記事の保存時に呼ぶ。識別子はnew_heading_idで作る。
# 見出しは行を見て探す（引用とリストとコードフェンスの中は見ない）。
# 書き足す前と後で、見出しのID以外の変換結果が同じになる時だけ書き足し、違えば元の原文を返す。
sub add_heading_ids {
	my $self  = shift;
	my $text  = shift;
	my @before = $self->parse($text);
	my @from   = @{ $self->{heading_ids} };
	if (!@from) { return $text; }
	my %used   = %{ $self->{ids} };

	my $n = 0;
	my $added = 0;
	my $fence;
	my $quote;
	my $list;
	my $blank;
	my @lines = split(/\n/, $text, -1);
	foreach(@lines) {
		# 引用は空行まで続く（>の無い行も引用の中）。
		# リストは、空行の後に字下げの無い行が来るまで続く（字下げの無い行も、空行の前なら項目の続き）。
		if ($_ =~ /^\s*$/) {
			undef $quote;
			$blank = 1;
		} else {
			if (/^ ? ? ?>/) { $quote = 1; }
			if (/^\s*(?:[\*\+\-]|\d+\.) +/) { $list = 1; }
			elsif ($blank && /^\S/) { undef $list; }
			undef $blank;
		}
		# 引用の>とリストの記号を除く
		my $rest = $_;
		$rest =~ s/^(?: ? ? ?>\s?|\s*(?:[\*\+\-]|\d+\.) +)*\s*//;
		if (defined $fence) {
			if ($rest =~ /^\Q$fence\E[`~]*\s*$/) { undef $fence; }
			next;
		}
		if ($rest =~ /^(```+|~~~+)/) {
			$fence = $1;
			next;
		}
		if ($quote || $list) { next; }	# 引用とリストの中の#は見出しにならない
		if ($_ !~ /^#+\s+(.*?)$/) { next; }
		my $title = $1;
		$n++;
		if ($title =~ /^(?:(.*?)[ \t]+)?\[#$HEADING_ID\][ \t]*$/) { next; }	# 識別子がある
		my $id = $self->new_heading_id(\%used);
		$used{$id} = 1;
		$_ =~ s/[ \t]*$/ [#$id]/;
		$added++;
	}
	if (!$added || $n != @from) { return $text; }

	my $new   = join("\n", @lines);
	my @after = $self->parse($new);
	my @to    = @{ $self->{heading_ids} };
	if (@from != @to) { return $text; }

	# 書き足す前の出力の見出しのIDを、書き足した後のIDに置き換えて比べる
	# （記事の中から見出しへのリンクがあれば、置き換えた方と変わらない方で違いが出て、書き足さない）
	my %map;
	foreach(0..$#from) {
		my ($x, $y) = ($from[$_], $to[$_]);
		$x =~ s/"/&quot;/g;
		$y =~ s/"/&quot;/g;
		$map{$x} = $y;
	}
	foreach(0..1) {
		$before[$_] =~ s/(\bid="|\bhref="(?:\Q$self->{thisurl}\E)?#)([^"]*)"/$1 . (exists $map{$2} ? $map{$2} : $2) . '"'/eg;
		if ($before[$_] ne $after[$_]) { return $text; }
	}
	return $new;
}

#-------------------------------------------------------------------------------
# ●新しい見出しの識別子
#-------------------------------------------------------------------------------
# 英字1文字と16進数7桁（l7a712f2など）。$usedにあるものは避ける
sub new_heading_id {
	my $self = shift;
	my $used = shift || {};
	while (1) {
		my $id = chr(ord('a') + int(rand(26))) . sprintf('%07x', int(rand(0x10000000)));
		if (!$used->{$id}) { return $id; }
	}
}

#-------------------------------------------------------------------------------
# ●Markdownの記法を除去してプレーンテキストにする
#-------------------------------------------------------------------------------
sub strip_markdown {
	my $self = shift;
	my $text = shift;
	$text =~ s/\n/ /g;
	# 画像 ![alt](url) → alt
	$text =~ s/!\[([^\]]*)\]\([^\)]*\)/$1/g;
	# リンク [text](url) → text
	$text =~ s/\[([^\]]*)\]\([^\)]*\)/$1/g;
	# 参照リンク [text][ref] → text
	$text =~ s/\[([^\]]*)\]\[[^\]]*\]/$1/g;
	# 太字
	$text =~ s/\*\*(.*?)\*\*/$1/g;
	$text =~ s/__(.*?)__/$1/g;
	# 斜体
	$text =~ s/\*([^\*]*)\*/$1/g;
	$text =~ s/_([^_]*)_/$1/g;
	# 取り消し線
	$text =~ s/~~(.*?)~~/$1/g;
	# インラインコード
	$text =~ s/`+([^`]+?)`+/$1/g;
	# 脚注参照
	$text =~ s/\[\^[^\]]+\]//g;
	return $text;
}

1;
