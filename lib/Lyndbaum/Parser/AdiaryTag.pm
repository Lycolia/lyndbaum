package Lyndbaum::Parser::AdiaryTag;
# adiary 独自のタグ（[image:…] など）。記法をまたいで使えるよう、Markdown とは分けておく
#
#   [image:サイズ:フォルダ/:ファイル名:代替テキスト(:#キャプション)]
#   [file:種類:フォルダ/:ファイル名:説明]
#   [youtube:動画ID]
#   [&URL]                       YouTube、ニコニコ動画は埋め込み、それ以外はリンク
#   [info:文章] [warn:文章] [error:文章]
#
# 知らないタグは undef を返し、呼ぶ側で普通の文章として出す
use strict;
use warnings;
use utf8;

use Lyndbaum::HTML qw(escape_html escape_text is_safe_url);

my $EMBED_SIZE = 'width="480" height="270"';

# バナーのアイコン（Material Icons と同じ図形）
my %BANNER_ICON = (
	info  => 'M11 7h2v2h-2zm0 4h2v6h-2zm1-9C6.48 2 2 6.48 2 12s4.48 10 10 10 10-4.48 10-10S17.52 2 12 2m0 18c-4.41 0-8-3.59-8-8s3.59-8 8-8 8 3.59 8 8-3.59 8-8 8',
	warn  => 'M12 5.99 19.53 19H4.47zM12 2 1 21h22zm1 14h-2v2h2zm0-6h-2v4h2z',
	error => 'M12 2C6.47 2 2 6.47 2 12s4.47 10 10 10 10-4.47 10-10S17.53 2 12 2m0 18c-4.41 0-8-3.59-8-8s3.59-8 8-8 8 3.59 8 8-3.59 8-8 8m3.59-13L12 10.59 8.41 7 7 8.41 10.59 12 7 15.59 8.41 17 12 13.41 15.59 17 17 15.59 13.41 12 17 8.41z',
);

# タグの中身（角括弧の内側）を変換する
#   戻り値 { html => HTML, block => ブロック要素か } または undef（知らないタグ）
#   $inline は文章を変換する関数（バナーの文章に使う）
sub render {
	my ($class, $inner, $context, $inline) = @_;
	if ($inner =~ /\A&(.+)\z/s) {
		return _url_embed($1, $context);
	}
	my ($name, $args) = $inner =~ /\A([a-z]+):(.*)\z/s or return undef;
	return _image($args, $context)               if $name eq 'image';
	return _file($args, $context)                if $name eq 'file';
	return _youtube($args)                       if $name eq 'youtube';
	return _banner($name, $args, $inline)        if $BANNER_ICON{$name};
	return undef;
}

# 添付ファイルのURL。フォルダ名とファイル名はパーセントエンコードする（空白や括弧を含むことがある）
sub _attachment_url {
	my ($context, $dir, $file) = @_;
	my $path = join '/', map { _escape_path($_) } split m{/}, "$dir$file", -1;
	return ($context->{attachment_path} // '/pub/attachments/') . $path;
}

sub _escape_path {
	my ($segment) = @_;
	my $bytes = $segment;
	utf8::encode($bytes);
	$bytes =~ s/([^A-Za-z0-9\-._~!\$&'()*+,;=:@])/sprintf '%%%02X', ord $1/eg;
	return $bytes;
}

sub _image {
	my ($args, $context) = @_;
	my ($size, $dir, $file, @rest) = split /:/, $args, -1;
	return undef if !defined $file || $size !~ /\A[A-Za-z]*\z/ || $dir !~ m{\A(?:[^/]+/)*\z} || $file eq '';

	my @captions = map { substr $_, 1 } grep { /\A#/ } @rest;
	my $alt = join ':', grep { !/\A#/ } @rest;

	my $url       = _attachment_url($context, $dir, $file);
	my $thumbnail = $size eq 'L' ? $url : _attachment_url($context, "$dir.thumbnail/", "$file.jpg");
	my $html = sprintf '<a href="%s" class="tag-image-%s" title="%s" data-lythumb="k%s"><img alt="%s" src="%s"></a>',
		escape_html($url), escape_html($size), escape_html($alt), escape_html($context->{article_id} // ''),
		escape_html($alt), escape_html($thumbnail);
	return { html => $html, block => 0 } if !@captions;
	return {
		html  => '<figure>' . $html . '<figcaption>' . escape_text(join ' ', @captions) . '</figcaption></figure>',
		block => 1,
	};
}

sub _file {
	my ($args, $context) = @_;
	my ($type, $dir, $file, @rest) = split /:/, $args, -1;
	return undef if !defined $file || $dir !~ m{\A(?:[^/]+/)*\z} || $file eq '';
	my $url  = escape_html(_attachment_url($context, $dir, $file));
	my $text = escape_text(@rest ? join(':', @rest) : $file);
	if ($type eq 'mp4' || $type eq 'webm') {
		return {
			html  => qq{<video $EMBED_SIZE controls><source src="$url" type="video/$type"><a class="video" href="$url">$text</a></video>},
			block => 0,
		};
	}
	return { html => qq{<a href="$url">$text</a>}, block => 0 };
}

sub _youtube {
	my ($id, $start) = @_;
	return undef if $id !~ /\A[\w-]+\z/;
	my $src = "https://www.youtube.com/embed/$id" . (defined $start ? "?start=$start" : '');
	return {
		html  => qq{<iframe class="youtube-player" $EMBED_SIZE src="$src" frameborder="0" allowfullscreen></iframe>},
		block => 0,
	};
}

sub _url_embed {
	my ($url, $context) = @_;
	return undef if $url !~ m{\Ahttps?://\S+\z} || !is_safe_url($url);

	if ($url =~ m{\Ahttps?://(?:www\.|m\.)?youtube\.com/watch\?(\S*)}) {
		my %q = map { split /=/, $_, 2 } grep { /=/ } split /&/, $1;
		my ($start) = ($q{t} // '') =~ /\A(\d+)s?\z/;
		return _youtube($q{v}, $start) if $q{v};
	}
	if ($url =~ m{\Ahttps?://youtu\.be/([\w-]+)(?:\?t=(\d+))?}) {
		return _youtube($1, $2);
	}
	if ($url =~ m{\Ahttps?://(?:www\.|sp\.)?nicovideo\.jp/watch/((?:sm|so|nm)\d+)}) {
		return {
			html  => qq{<iframe class="niconico nico-video" $EMBED_SIZE src="https://embed.nicovideo.jp/watch/$1" frameborder="0" scrolling="no" allowfullscreen></iframe>},
			block => 0,
		};
	}
	my $title = $context->{url_title} ? $context->{url_title}->($url) : undef;
	return {
		html  => '<a href="' . escape_html($url) . '">' . escape_text(defined $title && $title ne '' ? $title : $url) . '</a>',
		block => 0,
	};
}

sub _banner {
	my ($type, $text, $inline) = @_;
	my $icon = $BANNER_ICON{$type};
	return {
		html => qq{<div class="notice_banner $type">    <div><svg width="25" viewBox="0 0 24 24" aria-label="fontSize small"><path d="$icon"></path></svg></div>    <div class="message">}
			. $inline->($text) . '</div></div>',
		block => 1,
	};
}

1;
