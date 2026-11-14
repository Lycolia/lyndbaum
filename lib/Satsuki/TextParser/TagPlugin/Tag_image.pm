use strict;
#-------------------------------------------------------------------------------
# 画像記法プラグイン
#                                                   (C)2015 nabe / nabe@abk.nu
#-------------------------------------------------------------------------------
package Satsuki::TextParser::TagPlugin::Tag_image;
use Satsuki::ImageFormat ();
################################################################################
# ■基本処理
################################################################################
# ●使い方
#   通常の記法プラグインと違い、オプション部（文字コード部）に image と
# 指定することで使用する。
#
#（設定例）
#	img       = 画像, image, 1, http://image.xxx.jp/image/$1_small.jpg
#	img#large = 画像, image, 1, http://image.xxx.jp/image/$1_large.jpg
#	img#link  = 画像, image, 1, http://image.xxx.jp/image/$1.jpg
#　large などのサイズ違いを指定する際は、引数の数を同一にすること。
#  $11 引数から、最初に出てくる "." の手前までに置換。
#
# としたとき
# [img:test]
#  → <a href="http://image.xxx.jp/image/test.jpg" class="img" title="test">
#	<img alt="test" src="http://image.xxx.jp/image/test_large.jpg"></a>
#
# [img:test:small]
#  → <a href="http://image.xxx.jp/image/test.jpg" class="img small" title="test">
#	<img alt="test" src="http://image.xxx.jp/image/test_small.jpg"></a>
#
# [img:test:てすと]
#  → <a href="http://image.xxx.jp/image/test.jpg" class="img" title="てすと">
#	<img alt="てすと" src="http://image.xxx.jp/image/test_small.jpg"></a>
#
# 「タグ名#textlink」があると、画像を出さずにテキストのリンクにする。
# 残りの引数がリンクの文字で、無ければファイル名（最後のURLの引数）を出す。
#（設定例）
#	image:T          = 画像へのリンク, image, 2, ${image}$1$2
#	image:T#textlink = 画像へのリンク, image, 2, ${image}$1$2
# [image:T:dir/:a.png:この写真]
#  → <a href="pub/attachments/dir/a.png" class="tag-image-T">この写真</a>
#
#-------------------------------------------------------------------------------
# ●コンストラクタ
#-------------------------------------------------------------------------------
sub new {
	my $class = shift;	# 読み捨て
	my $ROBJ  = shift;	# 読み捨て
	my $tags  = shift;

	#---begin_plugin_info
	$tags->{'&image'} = \&image;
	#---end

	return ;
}
################################################################################
# ■タグ処理ルーチン
################################################################################
#-------------------------------------------------------------------------------
# ●image記法
#-------------------------------------------------------------------------------
sub image {
	my ($pobj, $tag, $cmd, $ary) = @_;
	my $tags = $pobj->{tags};
	my $ROBJ = $pobj->{ROBJ};

	# mode チェック
	my $tag_name = $tag->{name};
	my $argc     = $tag->{argc};
	my $mode     = $ary->[ ($argc || 1) ];
	if (exists $tags->{"$tag_name#$mode"}) {	# [tag:～:large] 等の指定がある
		$tag  = $tags->{"$tag_name#$mode"};
		$mode = undef;
		splice(@$ary, $argc || 1, 1);	# モード指定部を削除
	}

	#  構成
	my $url  = $tag->{data};
	my $link = (exists $tags->{"$tag_name#link"}) ? $tags->{"$tag_name#link"}->{data} : $url;

	# http/httpsの特殊処理
	if ($ary->[0] =~ /^https?$/i && $ary->[1] =~ m|^//|) {
		my $p = shift(@$ary);
		$ary->[0] = $p . ':' . $ary->[0];
	}

	# テキストのリンクにするか。リンクの文字が無いときに出すファイル名を、URL生成で引数が消える前に取っておく
	my $textlink = exists $tags->{"$tag_name#textlink"};
	my $filename_arg = $ary->[ ($argc || 1) - 1 ];

	# URL生成
	{
		my @ary2 = @$ary;
		$url  = $pobj->replace_link($url,   $ary,  $argc);
		$link = $pobj->replace_link($link, \@ary2, $argc);
	}
	$url = &thumbnail_url($ROBJ, $url);

	if ($textlink) {
		return &text_link($pobj, $tag, $ary, $link, $filename_arg);
	}

	# 画像サイズ
	my $size;
	{
		my @ary2;
		my ($w,$h);
		foreach(@$ary) {
			if ($_ =~ /^\s*w(\d+)\s*$/) { $w=" width=\"$1\"";  next; }
			if ($_ =~ /^\s*h(\d+)\s*$/) { $h=" height=\"$1\""; next; }
			push(@ary2, $_);
		}
		$size=$w . $h;
		$ary = \@ary2;
	}
	# 大きさの指定が無ければ、画像のファイルから読んで書く。
	# 読み込む前に場所を空けておき、読み込んだときにページがずれないようにする（CLS）
	if ($size eq '') {
		$size = &image_size_attr($ROBJ, $url);
	}

	# Captionあり？
	my $caption;
	for(my $i=0; $i<=$#$ary; $i++) {
		if ($ary->[$i] =~ /\#/) {
			$caption = $i;
			last;
		}
	}
	if (defined $caption) {		# 1番目（0）の引数がキャプションのこともある
		my $cap = substr(join(':', splice(@$ary,$caption)),1);
		$caption = "<figcaption>$cap</figcaption>";
	}

	# 属性値。titleはaltと同じく、残りの引数をすべてつないだもの（代替テキストに:を含められる）
	my @rest = @$ary;
	while(@rest && $rest[0] =~ /^(?:title|class|target)=/) { shift(@rest); }
	my $name = join(':', @rest);
	$ROBJ->tag_escape($name);
	my %tag2 = %$tag;
	$tag2{title} = $name;
	my $attr = $pobj->make_attr($ary, \%tag2, exists($tags->{"$tag_name#ext"}) ? '' : 'image');
	   $name = $pobj->make_name($ary, $name);
	# 代替テキストが無ければtitleも空にする（タグ名を出さない）
	if ($name eq '') { $attr =~ s/title="[^"]*"/title=""/; }

	# ファイル名と$nameが同じ場合、それは初期値で無価値なものなので、altやtitleを空文字にする
	$link =~ /([^\/]+)$/;
	my $filename = $1;
	if ($filename eq $name) {
		$name = '';
		$attr =~ s/title="[^"]*"/title=""/;
	}

	my $tag = "<a href=\"$link\"$attr><img alt=\"$name\"$size src=\"$url\"></a>";
	# キャプションが無ければ <figure> で囲まない（Markdownパーサーが指定する）
	if (!$caption && $pobj->{image_no_figure}) { return $tag; }

	return "<figure>$tag$caption</figure>";
}

#-------------------------------------------------------------------------------
# ●画像へのテキストのリンク
#-------------------------------------------------------------------------------
# 画像の大きさは読まず、<figure>でも囲まない。#はキャプションの印にせず、リンクの文字に含める。
# titleはリンクの文字と同じで余計なので付けない
#
sub text_link {
	my ($pobj, $tag, $ary, $link, $filename) = @_;
	my $ROBJ = $pobj->{ROBJ};

	my @rest = @$ary;
	while(@rest && $rest[0] =~ /^(?:title|class|target)=/) { shift(@rest); }
	my $text = join(':', @rest);
	if ($text eq '') { $text = $filename; }
	$ROBJ->tag_escape($text);

	my $attr = $pobj->make_attr($ary, $tag, 'image');
	$attr =~ s/ title="[^"]*"//;
	return "<a href=\"$link\"$attr>$text</a>";
}

#-------------------------------------------------------------------------------
# ●メディア管理のサムネイルの形式
#-------------------------------------------------------------------------------
# 記法の設定（image:S）はJPEGのサムネイル（.thumbnail/元の名前.jpg）を指す。
# AVIFのサムネイル（.avif）があれば、そちらにする（SatsukiApp::adiary の thumbnail_ext）
#
sub thumbnail_url {
	my ($ROBJ, $url) = @_;
	if ($url !~ m|/\.thumbnail/[^/]+\.jpg$|) { return $url; }
	my $file = &local_file($ROBJ, $url);
	if ($file eq '') { return $url; }
	$file =~ s/\.jpg$/.avif/;
	if (-e $file) { $url =~ s/\.jpg$/.avif/; }
	return $url;
}

#-------------------------------------------------------------------------------
# ●画像のファイルの大きさを width、height の属性にする
#-------------------------------------------------------------------------------
# このサイトの中の画像だけを読む。読めなければ空
# 記法を変換する時点のURLは、サイトの置き場所からの相対（pub/attachments/…）。/で始まるならBasepathを外す
# ※記事を保存、再構築したときのファイルの大きさを書くので、サムネイルを作り直したら記事も作り直す
#
sub image_size_attr {
	my ($ROBJ, $url) = @_;
	my $file = &local_file($ROBJ, $url);
	if ($file eq '') { return ''; }

	my ($w, $h) = Satsuki::ImageFormat::get_size($file);
	return $w ? " width=\"$w\" height=\"$h\"" : '';
}

# URLを、このサイトの中のファイルのパスにする。外のサイトや、サイトの外を指すなら空
sub local_file {
	my ($ROBJ, $url) = @_;
	if ($url =~ m|^[A-Za-z][\w+.\-]*:| || $url =~ m|^//|) { return ''; }	# 外のサイト

	my $file = $url;
	if ($file =~ m|^/|) {
		my $base = $ROBJ->{Basepath};
		if ($base eq '' || index($file, $base) != 0) { return ''; }
		$file = substr($file, length($base));
	}
	$file =~ s/[?#].*//;
	$file =~ s/%([0-9A-Fa-f]{2})/chr(hex($1))/eg;
	if ($file =~ m|^/| || $file =~ m!(?:^|/)\.\.(?:/|$)!) { return ''; }
	return $file;
}

1;
