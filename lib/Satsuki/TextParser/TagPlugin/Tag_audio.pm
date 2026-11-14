use strict;
#-------------------------------------------------------------------------------
# aidio/videoタグ
#                                                (C)2013 nabe / nabe@abk.nu
#-------------------------------------------------------------------------------
package Satsuki::TextParser::TagPlugin::Tag_audio;
################################################################################
# ■MIMEタイプ定義
################################################################################
my %audio_mime = (
'wav'  => 'wave',
'wave' => 'wave',
'ogg'  => 'ogg',
'oga'  => 'ogg',
'mp3'  => 'mpeg',
'aac'  => 'aac',
'mp4'  => 'aac',
'm4a'  => 'aac'
);
my %video_mime = (
'ogg'  => 'ogg',
'ogv'  => 'ogg',
'webm' => 'webm',
'mp4'  => 'mp4',
'm4v'  => 'mp4'
);

################################################################################
# ■基本処理
################################################################################
#-------------------------------------------------------------------------------
# ●コンストラクタ
#-------------------------------------------------------------------------------
sub new {
	my $class = shift;	# 読み捨て
	my $ROBJ  = shift;	# 読み捨て
	my $tags  = shift;

	#---begin_plugin_info
	$tags->{audio}->{data} = \&audio_video;
	$tags->{video}->{data} = \&audio_video;
	#---end

	$tags->{audio}->{name} = 'audio';
	$tags->{audio}->{mime} = \%audio_mime;
	$tags->{video}->{name} = 'video';
	$tags->{video}->{mime} = \%video_mime;

	return ;
}

################################################################################
# ■タグ処理ルーチン
################################################################################
sub audio_video {
	my ($pobj, $tag, $cmd, $ary) = @_;
	my $tname = $tag->{name};
	my $width;
	my $height;

	my $ftag = $pobj->{tags}->{file};
	if ($ftag && $cmd =~ /^file:(\w+)/) {
		# [file:xxx] タグからのaliasの時
		unshift(@$ary, $1);
		my $url = $pobj->replace_link($ftag->{data}, $ary, $ftag->{argc});
		foreach(@$ary) {
			if ($_ =~ /^w(\d+)$/) { $width =$1; }
			if ($_ =~ /^h(\d+)$/) { $height=$1; }
		}
		$ary = [ $url ];
	}

	my $url0;
	my $src='';
	while(@$ary) {
		my $url = shift(@$ary);
		if ($url eq 'http' || $url eq 'https') {
			$url .= ':' . shift(@$ary);
		}
		$url0 ||= $url;
		if ($url =~ /^w(\d+)$/) { $width =$1; }
		if ($url =~ /^h(\d+)$/) { $height=$1; }

		my $mime='';
		my $url2 = $url;
		$url2 =~ tr/A-Z/a-z/;
		if ($url =~ /\.(\w+)$/ && $tag->{mime}->{$1}) {
			$mime = ' type="' . $tname . '/' . $tag->{mime}->{$1} . '"'
		}

		$src .= "<source src=\"$url\"$mime>";
	}
	if (!$src) { return''; }

	# 動画にサムネイルがあれば、サムネイルだけを出す。押すと画像ビューアー（Lythumb-viewer）で再生する
	if ($tname eq 'video' && $pobj->{image_attr} ne '') {
		my $thumb = &video_thumbnail($pobj, $url0, $width, $height);
		if ($thumb ne '') { return $thumb; }
	}

	$width  = $width  ?  " width=\"$width\""  : ' width="480"';
	$height = $height ? " height=\"$height\"" : ' height="270"';

	# 再生するまで読み込まない（ページを開いただけで動画を全部読み込まないように）
	return "<$tname$width$height controls preload=\"none\">$src(Browser not support $tname tag) <a class=\"$tname\" href=\"$url0\">$url0</a></$tname>";
}

#-------------------------------------------------------------------------------
# ●動画のサムネイル
#-------------------------------------------------------------------------------
# メディア管理の動画に、管理画面で作ったサムネイル（.thumbnail/動画名.poster.avif か .poster.jpg）があれば、
# サムネイルの画像を動画へのリンクにして返す。無ければ空（docs/仕様/動画のサムネイル.md）
# 大きさの指定が無ければ、長い辺を<video>やYouTubeの幅と同じ480pxに収める（縦長の動画が長くならないように）。
# サムネイルのファイルは480pxの2倍（長い辺960px）なので、高解像度の画面でもぼやけない
#
my $VIDEO_THUMB_SIZE = 480;

sub video_thumbnail {
	my ($pobj, $url, $width, $height) = @_;
	my $base = $url;
	$base =~ s/[?#].*//;
	if ($base !~ s|^(.*/)?([^/]+)$|$1.thumbnail/$2.poster|) { return ''; }

	# サイトの中のファイルだけを読む（外のサイトや読めないファイルなら空）。AVIFを先に見る
	require Satsuki::TextParser::TagPlugin::Tag_image;
	my ($poster, $size);
	foreach('avif', 'jpg') {
		$poster = "$base.$_";
		$size = Satsuki::TextParser::TagPlugin::Tag_image::image_size_attr($pobj->{ROBJ}, $poster);
		if ($size ne '') { last; }
	}
	if ($size eq '') { return ''; }
	if ($width || $height) {
		$size = ($width ? " width=\"$width\"" : '') . ($height ? " height=\"$height\"" : '');
	} elsif ($size =~ /width="(\d+)" height="(\d+)"/ && ($VIDEO_THUMB_SIZE < $1 || $VIDEO_THUMB_SIZE < $2)) {
		my $r = $VIDEO_THUMB_SIZE / ($1 < $2 ? $2 : $1);
		$size = ' width="' . int($1*$r + 0.5) . '" height="' . int($2*$r + 0.5) . '"';
	}

	my $attr = $pobj->{image_attr};
	$attr =~ s/%k/$pobj->{thispkey}/g;
	return "<a href=\"$url\" class=\"video-thumb\" $attr><img alt=\"\"$size src=\"$poster\"></a>";
}

1;
