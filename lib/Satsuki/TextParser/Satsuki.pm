use strict;
#-------------------------------------------------------------------------------
# さつき記法のタグ（[image:...]など）の処理
#                                             (C)2006-2019 nabe / nabe@abk
#-------------------------------------------------------------------------------
# 4.22で標準記法（ブロック、見出し、段落、リスト、表など）の処理を削除した。
# Markdownパーサー（Markdown.pm）が、タグ、脚注（(())）、目次の処理に使う。
#-------------------------------------------------------------------------------
package Satsuki::TextParser::Satsuki;

use Satsuki::AutoLoader;
our $VERSION = '2.30';
#-------------------------------------------------------------------------------
# \x00-\x03は内部で使用するため、処理の過程で除去されます。
#	\x00 文字列の一時退避用
#	\x01 インデント抑止用、処理済マークング（グローバル使用）
#	\x02 各処理プロセス内でのみ使用
#	\x03 未使用（プラグイン用）
#-------------------------------------------------------------------------------
my $TAG_PLUGIN_CLASS = 'TextParser::TagPlugin::Tag_';
my $CSS_CLASS_PREFIX = 'tag-';
my $INFO_BEGIN_MARK = '#---begin_plugin_info';
my $INFO_END_MARK   = '#---end';
################################################################################
# ■基本処理
################################################################################
#-------------------------------------------------------------------------------
# ●【コンストラクタ】
#-------------------------------------------------------------------------------
# 引数のキャッシュファイルは省略しても動作します。
# 第２引数はプラグインdir
sub new {
	my $self = bless({}, shift);
	$self->{ROBJ} = shift;
	$self->{plugin_cache_file} = shift;

	$self->{indent} = '';		# indent all line
	$self->{image_attr}  = '';	# image link attribute for image viewer

	$self->{vars} = {};		# 内部自由変数

	$self->init_tags();
	$self->load_plugins(@_);

	# 処理する記事ごとに設定
	$self->{thisurl}  = '';		# 記事のURL
	$self->{thispkey} = '';		# 記事のpkey = unique id = [0-9]+

	return $self;
}

################################################################################
# ■記法タグの処理
################################################################################
#---------------------------------------------------------------------
# ○タグのパースと処理
#---------------------------------------------------------------------
sub parse_tag {
	my $self = shift;
	my $this = shift;
	my $post_process = shift;	# markdown記法で使用

	# [[ ]] タグを先行処理
	my $count=0;
	while ($this =~ /(.*?)(\[\[)(.*?)\]\](.*)/s || $this =~ /(.*?)(\[)((?:\\\[|\\\]|[^\[\]])+)\](.*)/s) {
		my $p0  = $1;
		my $cmd = $3;
		my $p1  = $4;
		$cmd = $self->special_command( $cmd, {verb => ($2 eq '[[')} );
		$cmd =~ s/\(/&#40;/g;
		$cmd =~ s/\[/&#91;/g;
		$cmd =~ s/\]/&#93;/g;
		$cmd =~ s/:/&#58;/g;
		if ($post_process) { $cmd = &$post_process($cmd); }
		# imageタグの前後に空の<p></p>を入れてる要因。これを外すと画像と同じ段落に文字列を入れたときに崩れる
		$this = $p0 . $cmd . $p1;
		$count++;
		if ($count>99) { last; }
	}
	return $this;
}

#---------------------------------------------------------------------
# ○コマンドの処理
#---------------------------------------------------------------------
sub special_command {
	my $self     = shift;
	my $cmd_line = shift;
	my $opt  = shift || {};
	my $tags = $self->{tags};
	my $orig = $cmd_line;

	# 特殊コマンド処理
	# [&http://youtube.com/] → [filter:http://youtube.com]
	$cmd_line =~ s/^&([^#].*)$/filter:$1/g;

	# 自由変数置換
	if ($cmd_line =~ /^\$(.*)$/) {
		$cmd_line = $self->{vars}->{$1};
		$cmd_line =~ s/\$/&#36;/g;
		return $cmd_line;
	}

	# cmd:arg1:arg2 ... のパース
	if (!$opt->{verb}) {
		$cmd_line =~ s/\\([\[\]])/$1/g;
		$cmd_line =~ s/\\:/\x00/g;
	}

	my @cmd = map { s/\x00/:/g; $_ } split(':', $cmd_line);
	my $cmd = shift(@cmd);
	while (exists $tags->{ "$cmd:$cmd[0]" } && @cmd) {	# 連結コマンド
		$cmd = $cmd . ':' . shift(@cmd);
	}

	if (exists $tags->{ $cmd }) {
		my $tag = $self->load_tag($cmd);
		# verb環境？
		if ($opt->{verb}) {
			@cmd = ( join(':', @cmd) );
		}
		# alias 処理
		my $real_cmd = $cmd;
		if ($tag->{alias}) {
			$real_cmd = $tag->{alias};
			$tag      = $self->load_tag($real_cmd);
		}
		# 引数指定あり？
		my $arg_cmd = $real_cmd . '##' . ($#cmd +1);
		if (exists $tags->{ $arg_cmd }) {
			$tag = $tags->{ $arg_cmd };
		} else {
			my $x = $#cmd + 1;
			$x=0;
			foreach(@cmd) {
				if ($_ =~ /[\x80-\xff]/) { last }
				if (substr($_,-1) eq ' ') {	# 最後がスペースの引数
					chop($_);
					last;
				}
				$x++;
			}
			my $arg_cmd = $real_cmd . '#' . $x;
			if (exists $tags->{ $arg_cmd }) { $tag = $tags->{ $arg_cmd }; }
		}

		# 置換処理呼び出し
		my $data   = $tag->{data};
		my $option = $self->load_tag("&$tag->{option}");	# 特殊オプション？

		if (ref($option)) {		# 特殊オプションによる置換
			return &$option($self, $tag, $cmd, \@cmd);
		} elsif (ref($data)) {		# CODE ref のときは指定の専用ルーチンコール
			return &$data($self, $tag, $cmd, \@cmd);
		} elsif($tag->{html}) {		# HTML置換タグ
			return $self->html_tag($tag, \@cmd);
		} elsif($data) {		# それ以外のときは汎用検索置換ルーチンへ
			return $self->search($tag, $cmd, \@cmd);
		}
	}
	# 未知のコマンド
	return $opt->{verb} ? "[[$orig]]" : "[$orig]";
}

sub load_tag {
	my $self = shift;
	my $cmd = shift;
	my $tag = $self->{tags}->{$cmd};
	if (ref($tag) eq 'CODE') { return $tag; }
	if ($tag->{plugin}) {
		$self->eval_load_plugin( $tag->{plugin} );
	}
	return $self->{tags}->{$cmd};
}

#-------------------------------------------------------------------------------
# ●記法タグルーチン
#-------------------------------------------------------------------------------
#---------------------------------------------------------------------
# ●htmlタグ置換
#---------------------------------------------------------------------
sub html_tag {
	my ($self, $tag, $ary) = @_;
	my ($name, $class) = split('\.', $tag->{html});
	if ($class ne '') { $class=" class=\"$class\""; }
	if (!@$ary) { return "<$name$class$tag->{attribute}></$name>"; }
	return "<$name$class$tag->{attribute}>" . join(':', @$ary) . "</$name>";
}

#---------------------------------------------------------------------
# ●汎用リンク置換（記法タグ）
#---------------------------------------------------------------------
sub search {
	my ($self, $tag, $cmd, $ary) = @_;
	my $ROBJ = $self->{ROBJ};

	# Query 構成
	my $code = $tag->{option};
	my $argc = $tag->{argc};
	my $url  = $tag->{data};

	my @argv = splice(@$ary, 0, $argc);
	if ($#$ary>=0 && $tag->{replace_html}) {
		# タグそのままのとき、最後を連結。
		# 2引数 [color:red:xxx:yyy] を "red" / "xxx:yyy" にする
		$argv[$argc-1] .= ':' . join(':', @$ary);
		@$ary = ();
	}

	# リンク置換。添付ファイルは、名前を省いたらファイル名を出す
	my $name = $tag->{name} eq 'file' ? $argv[$#argv] : join(':', @argv);
	$url = $self->replace_link($url, \@argv, $argc, $code);

	# タグそのまま
	if ($tag->{replace_html}) {
		$url =~ s/&quot;/"/g;
		return $url;
	}

	# リンク構成
	my $class = $self->make_attr($ary, $tag, 'http');
	   $name  = $self->make_name($ary, $name);

	return "<a href=\"$url\"$class>$name</a>";
}

#---------------------------------------------------------------------
# ●link文字列の置換処理
#---------------------------------------------------------------------
sub replace_link {
	my $self = shift;
	my ($url, $ary, $argc, $code) = @_;
	my $ROBJ = $self->{ROBJ};
	my $rep  = $self->{vars};

	my @argv = splice(@$ary, 0, $argc);
	unshift(@argv, join(':', @argv));	# for $0/#0
	$url =~ s/\#(\d)/$argv[$1]/g;		# 文字コード変換前

	if ($code eq 'ASCII' || $code !~ /[A-Z]/) { $code=''; }
	my $jcode = $code ? $ROBJ->load_codepm() : undef;

	foreach(@argv) {
		if ($jcode) { $jcode->from_to(\$_, $ROBJ->{SystemCode}, $code); }
		$self->encode_uricom($_);
	}
	$url =~ s/\$(\d)/$argv[$1]/g;		# 文字コード変換後
	$url =~ s/\$\{(\w+)\}/$rep->{$1}/g;	# 任意データ置換
	return $url;
}

#---------------------------------------------------------------------
# ●replace_varsのみ (for Tag-Plugin)
#---------------------------------------------------------------------
sub replace_vars {
	my $self = shift;
	my $url = shift;
	my $h = $self->{vars};
	$url =~ s/\$\{(\w+)\}/$h->{$1}/g;	# 任意データ置換
	return $url;
}

################################################################################
# ■脚注
################################################################################
#---------------------------------------------------------------------
# ○脚注表記
#---------------------------------------------------------------------
sub init_footnote {
	my $self = shift;
	$self->{footnote_no} = 0;
}
sub footnote {
	my $self = shift;
	my $note = shift;
	my $buf  = shift;
	my $hash = shift || {};

	# 同じ内容は、同じfootnoteを参照する
	# 一覧から戻る先（id）は最初の参照だけに付ける（2回目からも付けると、同じidが重なる）
	my $number;
	my $name;
	my $id_attr = '';
	my $name_base = 'fn';
	if (exists $hash->{$note}) {	# 同じ内容注釈がある
		$number = $hash->{$note};
		$name   = "$name_base$number";
	} else {
		$hash->{$note} = $number = (++ $self->{footnote_no});
		$name   = "$name_base$number";
		$id_attr = " id=\"fnt-$name\"";
		push(@$buf, <<HTML);
	<p class="footnote"><a href="$self->{thisurl}#fnt-$name" id="fn-$name">*$number</a> : $note</p>
HTML
	}
	$self->tag_delete($note);
	$note =~ s/"/&quot;/g;

	return "<span class=\"footnote\"><a title=\"$note\" href=\"$self->{thisurl}#fn-$name\"$id_attr>*$number</a></span>";
}

#---------------------------------------------------------------------
# ○脚注表記の出力
#---------------------------------------------------------------------
sub output_footnote {
	my $self = shift;
	my $out  = shift || [];
	my $buf  = shift;
	my $hash = shift || {};
	my $indent = $self->{indent};
	if (@$buf) {
		push(@$out, "$indent<footer>\n");
		foreach(@$buf) {
			push(@$out, "$indent$_");
		}
		push(@$out, "$indent</footer>\n");
	}
	@$buf  = ();
	%$hash = ();
	return $out;	# used by Markdown.pm
}

################################################################################
# ■ポストプロセス
################################################################################
sub post_process {
	my $self = shift;
	my $rtxt = shift;

	# エスケープした文字を復元
	$self->un_escape( $$rtxt );

	# 目次の処理
	$$rtxt =~ s|<toc>(.*?)</toc>|$self->post_toc($1)|eg;
}

sub post_toc {
	my $self = shift;
	my $arg  = shift;
	my $opt  = {};
	foreach(split(':', $arg)) {
		if ($_ =~ /^(\w+)=(.*)$/) {
			$opt->{$1} = $2;
			next;
		}
		$opt->{$_}=1;
	}
	my $c = $self->normalize_class_string( $opt->{class} );
	$opt->{class} = $self->chain_class("toc", $c, exists($opt->{none}) ? 'none' : '');

	my $secs = $self->{sections};
	my $toc  = $self->generate_toc($secs, $opt, $opt->{depth});
	if ($toc eq '') { return "\n"; }

	# 普通の箇条書きと見分けられるよう、「目次」の見出しを付けて<nav>で囲む
	return "<nav class=\"toc-box\" aria-label=\"目次\">\n<div class=\"toc-title\">目次</div>\n$toc\n</nav>\n";
}

sub generate_toc {
	my $self  = shift;
	my $secs  = shift;
	my $opt   = shift;
	my $depth = shift;
	my $level = shift || 0;

	my $tab = "\t" x $level;
	my $out = $level ? "$tab<ul>\n" : "<ul class=\"$opt->{class}\">\n";

	# 段を飛ばした見出しは、飛ばした段（IDの無い仮の項目）を除いて1つ上の段に繰り上げる
	my @items = $self->toc_items($secs);

	# 目次に入る見出しが無ければ、空の<ul>は出さない
	if (!@items) { return ''; }

	foreach(@items) {
		my $subs = $_->{children};
		my $num  = $_->{number};
		if ($num ne '') { $num .= ' '; }
		my $link = "<a href=\"$self->{thisurl}#$_->{id}\">$num$_->{title}</a>";
		if (!$subs || !@$subs) {
			$out .= "$tab\t<li>$link</li>\n";
			next;
		}

		$out .= "$tab\t<li>$link\n";
		if ($depth eq '' || 1<$depth) {
			my $d = $depth eq '' ? '' : $depth-1;
			$out .=	$self->generate_toc($subs, $opt, $d, $level+1);
		}
		$out .= "</li>\n";
	}
	$out .= "$tab</ul>";
	return $out;
}

sub toc_items {
	my $self = shift;
	my $secs = shift || [];
	return map { $_->{id} eq '' ? $self->toc_items($_->{children}) : $_ } @$secs;
}

################################################################################
# ■記法タグのロードルーチン
################################################################################
#-------------------------------------------------------------------------------
# ●記法タグの初期化
#-------------------------------------------------------------------------------
sub init_tags {
	my $self = shift;
	$self->{tags} = {};
}

#-------------------------------------------------------------------------------
# ●プラグインをロードする
#-------------------------------------------------------------------------------
sub load_plugins {
	my $self = shift;
	my $ROBJ = $self->{ROBJ};
	my $dir = shift;

	if (!$dir) {
		$INC{'Satsuki/TextParser/Satsuki.pm'} =~ m|(.*/)\w+\.\w+|;
		$dir=$1 . "TagPlugin/";
	}

	my $cfile = $self->{plugin_cache_file};
	my $x = $ROBJ->get_lastmodified($cfile);
	my $y = $ROBJ->get_lastmodified_in_dir($dir);
	if ($x < $y) {
		return $self->generate_plugin_cache($cfile, $dir);
	}
	my $h = $ROBJ->fread_hash_cached($cfile);
	foreach(keys(%$h)) {
		$self->{tags}->{$_} = { plugin => $h->{$_} };
	}
}

sub generate_plugin_cache {
	my $self = shift;
	my $cfile= shift;
	my $dir  = shift;
	my $ROBJ = $self->{ROBJ};

	my $files = $ROBJ->search_files($dir, {ext => '.pm'});
	map { s/^Tag_(\w+)\.pm$/$1/ } @$files;

	# キャッシュファイルが設定されてない場合は全ロードして戻る
	if ($cfile eq '') {
		foreach(@$files) {
			$self->eval_load_plugin($_);
			next;
		}
		return;
	}

	# キャッシュの生成
	my %h = ('::FileVersion' => 1);
	foreach my $f (@$files) {
		my $lines = $ROBJ->fread_lines("${dir}Tag_$f.pm");
		my $in_info;
		foreach(@$lines) {
			$_ =~ s/^\s*//;
			$_ =~ s/[\r\n]*$//;
			if (!$in_info) {
				if ($_ eq $INFO_BEGIN_MARK) { $in_info=1; }
				next;
			}
			if ($_ eq $INFO_END_MARK) { last; }
			#
			# プラグイン情報のパース
			#	$tags->{asin}
			if ($_ !~ /^\$tags->\{("|'|)?([^\}\"\']+)\1\}/) { next; }
			$h{$2} = $f;
			$self->{tags}->{$2} = { plugin => $f };
		}
	}
	# キャッシュに保存
	$ROBJ->fwrite_hash($cfile, \%h);
}


#-------------------------------------------------------------------------------
# ●タグ定義のロード
#-------------------------------------------------------------------------------
# タグデータ構造
# $tag = $tags{tag_name};
#	$tag{data}   = tag data
#	$tag{argc}   = argments for url data
#	$tag{option} = tag option
# (search only)
#	$tag{name}   = tag name
#	$tag{title}  = title
#	$tag{class}  = html style sheet class
# (alias or html tag)
#	$tag{alias}  = alias to
#	$tag{html}   = html tag
sub load_tagdata {
	my ($self, $data, $allow_load) = @_;
	my $ROBJ = $self->{ROBJ};
	my $file;
	if (!ref($data)) {
		$file = $data;
		if (!-r $file) { return; }
		$data = $ROBJ->fread_lines_cached( $file, {DelCR => 1} );
	}

	# 現在の設定ロード
	my $basepath = $ROBJ->{Basepath};
	my $tags   = $self->{tags};
	my @load_files;
	while(@$data) {
		my $line = shift(@$data);
		chomp($line);
		if (ord($line) == 0x23) { next; }		# 先頭'#'はコメント
		#---------------------------------------------------------------
		# プラグインロード？
		#---------------------------------------------------------------
		if ($line =~ /^plugin\s+(\w+)/i) {
			$self->eval_load_plugin($1);
			next;
		}
		#---------------------------------------------------------------
		# 他のファイルをロード
		#---------------------------------------------------------------
		if ($line =~ /^load\s+([\w\/\.]+)/i) {
			if ($allow_load) { push(@load_files, $ROBJ->get_relative_path($file, $1)); }
			next;
		}
		#---------------------------------------------------------------
		# マクロ定義（標準記法の機能だったので、空行までを読み飛ばす）
		#---------------------------------------------------------------
		if ($line =~ /^\*(.+?)\s*$/) {
			while (@$data) {
				my $x = shift(@$data);
				chomp($x);
				if ($x =~ /^\s*$/) { last; }
			}
			next;
		}
		#---------------------------------------------------------------
		# タグ定義
		#---------------------------------------------------------------
		if ($line !~ /^([\w\-\+#:]+)\s*=\s*(.*?)\s*$/s) { next; }	# '=' のない行は無視
		my $tag   = $1;
		my $value = $2;
		$tag =~ s/[\"\']//g;
		my @ary = split(':', $tag);
		if ($#ary > 1) {	# : が２つ以上ある
			my $cmd = shift(@ary); pop(@ary);
			while (@ary) {
				$cmd .= ':' . shift(@ary);
				$tags->{$cmd} ||= {};
			}
		}

		# タグ定義処理
		my $tag_hash = $tags->{$tag} ||= {};

		if (substr($value,0,1) eq '>') {	# alias
			$tag_hash->{alias} = substr($value, 1);

		} elsif (substr($value,0,5) eq 'html:') { # HTMLタグ置換
			my $tag = substr($value, 5);
			$tag =~ s/>/&gt;/g;
			$tag =~ s/</&lt;/g;
			($tag_hash->{html}, $tag_hash->{attribute}) = split(/\s+/, $tag, 2);
			if ($tag_hash->{attribute} ne '') {
				$tag_hash->{attribute} = ' ' . $tag_hash->{attribute};
			}
		} elsif (substr($value,0,5) eq 'text:') { # text置換
			my $text = substr($value, 5);
			$text =~ s/^\s*(.*?)\s*$/$1/g;
			$tag_hash->{data} = $text;
			$tag_hash->{argc} = 9;
			$tag_hash->{replace_html} = 1;

		} elsif (substr($value,0,7) eq 'plugin:') { # プラグイン設定
			my $plg = substr($value, 7);
			if ($plg =~ /[^\w]/) { next; }
			$tag_hash->{plugin} = $plg;
		} else {
			if (substr($value,0,1) eq '<') {	# HTML置換
				$value = "$tag,ASCII,9," . $value;
			}
			# タグの（リンク）クラス
			my $class =$tag;
			$class =~ s/#.*//;
			$tag_hash->{name} = $class;
			$class =~ s/[^A-Za-z0-9 ]/-/g;
			$tag_hash->{class} = "$CSS_CLASS_PREFIX$class";
			# タイトルなど
			my ($title, $option, $url) = split(/\s*,\s*/, $value, 3);
			$self->tag_escape( $title, $option );
			if ($url =~ /^(\d+)\s*,\s*(.*)$/) {	# 受け取り引数指定
				$tag_hash->{argc} = $1;
				$url = $2;
			} else {
				$tag_hash->{argc} = 1;
				$url .= '$1';
			}
			$url =~ s/\"/&quot;/g;
			if ($title  ne '') { $tag_hash->{title}  = $title;  }
			if ($option ne '') { $tag_hash->{option} = $option; }
			if ($url eq 'block:') {	# block要素ならば、空行が出るまで読み込み
				$url = '';
				while(@$data) {
					my $add = shift(@$data);
					chomp($add);
					# $add =~ s/^\s*(.*?)\s*\n?$/$1/;	# 前後の空白除去
					if ($add eq '') { last; }
					$url .= $add;
				}
			}
			if ($url ne '') {
				if (substr($url,0,1) eq '<') {	# HTML置換
					$tag_hash->{replace_html}=1;
				}
				if ($url =~ /^html:(.*)/) {	# HTML置換
					$tag_hash->{replace_html}=1;
					$url = $1;
				}
				$tag_hash->{data} = $url;
			}
		}
	}
	# 他のファイルロード（エラーなし）
	foreach(@load_files) {
		$self->load_tagdata( $_ );
	}
}

#-------------------------------------------------------------------------------
# ●プラグインのロード
#-------------------------------------------------------------------------------
sub eval_load_plugin {
	my $self = shift;
	my $ROBJ = $self->{ROBJ};
	my $file = shift;
	$file =~ s/[^\w]//g;
	# $ROBJ->debug("load tag plugin '$file'");
	eval{ $ROBJ->loadpm("${TAG_PLUGIN_CLASS}$file", $self->{tags}); };
	if ($@) { $ROBJ->error('[plugin load failed] %s', $@); }
}

################################################################################
# ■内部サブルーチン
################################################################################
#-------------------------------------------------------------------------------
# ●タグエスケープ
#-------------------------------------------------------------------------------
sub tag_escape {
	my $self=shift;
	my $ROBJ = $self->{ROBJ};
	return $ROBJ->tag_escape(@_);
}

#-------------------------------------------------------------------------------
# ●タグの除去
#-------------------------------------------------------------------------------
sub tag_delete {
	my $self=shift;
	foreach(@_) {
		$_ =~ s/<\/.*?>//sg;
		$_ =~ s/<\w([^>"']|[=\s]".*?"|[=\s]'.*?')*?>//sg;
	}
}

#-------------------------------------------------------------------------------
# ●エスケープした文字の復元
#-------------------------------------------------------------------------------
sub un_escape {
	my $self=shift;
	foreach(@_) {	# ( ) [ ] { } | * ^ ~: = + - を復元
		$_ =~ s/&#(36|40|41|91|93|123|125|124|58|42|94|126|61|43|45);/chr($1)/eg;
	}
	return $_[0];
}

#-------------------------------------------------------------------------------
# ●classの結合処理
#-------------------------------------------------------------------------------
sub chain_class {
	my $self = shift;
	my $class='';
	foreach(@_) {
		if ($_ eq '') { next; }
		$class .= $_ . ' ';
	}
	chop($class);
	return $class;
}

#-------------------------------------------------------------------------------
# ●class名の正規化
#-------------------------------------------------------------------------------
sub normalize_class_string {
	my $self  = shift;
	my $class = shift;
	$class =~ tr/A-Z/a-z/;
	$class =~ s/[^a-z0-9 ]+/-/g;
	$class =~ s/  +/ /g;
	$class =~ s/(^| )[\-\d]+/$1/g;
	return $class;
}

#-------------------------------------------------------------------------------
# ●URIエンコード
#-------------------------------------------------------------------------------
sub encode_uri {
	my $self=shift;
	return $self->{ROBJ}->encode_uri(@_);
}
sub encode_uricom {
	my $self=shift;
	return $self->{ROBJ}->encode_uricom(@_);
}

#-------------------------------------------------------------------------------
# ●class/titleの設定
#-------------------------------------------------------------------------------
sub make_attr {
	my $self = shift;
	my ($ary, $tag, $type) = @_;

	# target/class/rel 設定, type未定義のとき初期値なし(mailto:等)
	my $class;
	my $title = $tag->{title} || $tag->{name};
	my $target='';
	while(1) {
		my $x = $ary->[0];
		if ($x =~ /^title=\s*(.*?)\s*$/)  { shift(@$ary); $title = $1; next; }
		if ($x =~ /^class=\s*(.*?)\s*$/)  { shift(@$ary); $class = $1; next; }
		if ($x =~ /^target=\s*(.*?)\s*$/) { shift(@$ary); $target= $1; next; }
		last;
	}
	$class =~ s/[^\w\s:\-]//g;
	$self->tag_escape($title);
	$target =~ s/[^\w\-]//g;

	my $attr='';
	if ($class ne '' || $tag->{class} ne '') {
		my $sp = ($class ne '' && $tag->{class} ne '') ? ' ' : '';
		$attr  =" class=\"$tag->{class}$sp$class\"";
	}
	if ($title  ne '') { $attr .= " title=\"$title\""; }
	if ($target ne '') { $attr .=" target=\"$target\""; }
	if ($type eq 'image' && $self->{image_attr} ne '') {
		my $at = $self->{image_attr};
		$at =~ s/%k/$self->{thispkey}/g;
		$attr .= ' ' . $at;
	}

	# 属性文字列を返す
	return $attr;
}
#--------------------------------------
# name の設定
#--------------------------------------
sub make_name {
	my $self=shift;
	my ($ary, $name) = @_;
	my $x = join(':', @$ary);
	return ($x eq '' ?  $name : $x);
}

1;
