use strict;
#-------------------------------------------------------------------------------
# URLフィルター
#                                                (C)2013 nabe / nabe@abk.nu
#-------------------------------------------------------------------------------
package Satsuki::TextParser::TagPlugin::Tag_url_filter;
use Time::HiRes ();
################################################################################
# ■基本処理
################################################################################
# TagEscapeのモジュール機構と連携して動作するURLフィルターです。
#
#（例）
# [&http://www.youtube.com/watch?v=njLDgvQDKdE]
#　　↓
# [filter:http://www.youtube.com/watch?v=njLDgvQDKdE]	by Satsuki.pm
#　　↓
# <module name="youtube" vid="$1">			by this plugin
#　　↓
# <iframe>-----</iframe>				by TagEscape.pm
#
#-------------------------------------------------------------------------------
# ●コンストラクタ
#-------------------------------------------------------------------------------
sub new {
	my $class = shift;	# 読み捨て
	my $ROBJ  = shift;	# 読み捨て
	my $tags  = shift;

	#---begin_plugin_info
	$tags->{'filter'}->{data} = \&filter;
	$tags->{'youtube'}->{data} = \&youtube;
	#---end

	return ;
}
################################################################################
# ■タグ処理ルーチン
################################################################################
#-------------------------------------------------------------------------------
# ●filter記法
#-------------------------------------------------------------------------------
sub filter {
	my $self = $_[0];
	my $r = &_filter(@_);
#	$self->{ROBJ}->debug($r);
	return $r;
}

#-------------------------------------------------------------------------------
# ●youtube記法
#-------------------------------------------------------------------------------
# [youtube:動画ID]、[youtube:動画ID:small]、[youtube:動画ID:large]
sub youtube {
	my ($pobj, $tag, $cmd, $ary) = @_;
	my $vid = $ary->[0];
	if ($vid !~ /^[\w\-]+$/) { return ''; }
	return &youtube_module($pobj, $vid, $ary->[1], '');
}

#-------------------------------------------------------------------------------
# ●YouTubeのモジュール
#-------------------------------------------------------------------------------
# 画像ビューアー（Lythumb-viewer）があれば、サムネイルだけを出し、押すとビューアーで再生する。
# グループ名は記事の画像と同じにして、画像と一緒にめくれるようにする（docs/仕様/動画のサムネイル.md）
# ビューアーが無ければ、今までどおりプレーヤーを埋め込む
#
sub youtube_module {
	my ($pobj, $vid, $size, $opt) = @_;
	my $w = 480;
	my $h = 270;
	if ($size eq 'small') { $w=320; $h=180; }
	if ($size eq 'large') { $w=640; $h=360; }

	my $group;
	if ($pobj->{image_attr} =~ /data-lythumb="([^"]*)"/) {
		$group = $1;
		$group =~ s/%k/$pobj->{thispkey}/g;
	}
	if (!defined $group) {
		return "<module name=\"youtube\" vid=\"$vid\" width=\"$w\" height=\"$h\" opt=\"$opt\">";
	}
	my $query = $opt ne '' ? "&$opt" : '';
	return "<module name=\"youtube-thumb\" vid=\"$vid\" width=\"$w\" height=\"$h\" query=\"$query\" group=\"$group\">";
}

sub _filter {
	my ($pobj, $tag, $cmd, $ary) = @_;
	my $ROBJ = $pobj->{ROBJ};
	my $tags = $pobj->{tags};
	my $vars = $pobj->{vars};

	my $urlf = join(':',@$ary);
	my $url  = shift(@$ary);
	if ($url =~ m|^https?$| && $ary->[0] =~ m|^//|) { $url .= ':' . shift(@$ary); }
	#-------------------------------------------------------------
	# youtube
	#-------------------------------------------------------------
	if ($url =~ m|^https?://www\.youtube\.com/watch\?v=([\w\-]+)((?:&\w+=\w+)*)|) {
		my $vid = $1;
		my $opt= $2 ? substr($2,1) : '';
		$opt =~ s/(^|&)t=(\d+)s?/${1}start=$2/g;
		return &youtube_module($pobj, $vid, $ary->[0], $opt);
	}

	#-------------------------------------------------------------
	# twitter
	#-------------------------------------------------------------
	if ($url =~ m!^https://(?:twitter|x)\.com/(\w+)/status/(\d+)$!) {
		return "<module name=\"tweet\" uid=\"$1\" status-id=\"$2\">";
	}

	#-------------------------------------------------------------
	# ニコニコ動画
	#-------------------------------------------------------------
	if ($url =~ m|^https?://www\.nicovideo\.jp/watch/(\w+)(?:\?.*)?$|) {
		my $w = 480;
		my $h = 270;
		if ($ary->[0] eq 'small') { $w=320; $h=180; }
		if ($ary->[0] eq 'large') { $w=640; $h=360; }
		return "<module name=\"nico\" vid=\"$1\" width=\"$w\" height=\"$h\">";
	}
	if ($url =~ m|^https?://www.nicovideo.jp/mylist/(\w+)(?:\?.*)?$|) {
		return "<module name=\"nico:mylist\" mid=\"$1\">";
	}
	if ($url =~ m|^https?://www.nicovideo.jp/user/(\w+)(?:\?.*)?$|) {
		return "<module name=\"nico:user\" uid=\"$1\">";
	}
	if ($url =~ m|^https?://com\.nicovideo\.jp/community/(\w+)(?:\?.*)?$|) {
		return "<module name=\"nico:community\" cid=\"$1\">";
	}

	#-------------------------------------------------------------
	# gist
	#-------------------------------------------------------------
	if ($url =~ m|^https://gist\.github\.com(/[\w\-/\.]*)|) {
		return "<module name=\"gist\" path=\"$1\">";
	}

	#-------------------------------------------------------------
	# slideshare
	#-------------------------------------------------------------
	if ($url =~ m|^https?://www\.slideshare\.net/[\w-]+/(?:[\w\-]+-)?(\w+)|) {
		my $sid = $1;
		$url =~ s/\?.*//;

		# 一応getして確認する
		while($sid =~ /[^\d]/) {
			my $http = $ROBJ->loadpm('Base::HTTP');
			my $res = $http->get($url);
			if (!ref($res)) { last; }
			foreach(@$res) {
				# https://www.slideshare.net/slideshow/embed_code/key/sqUybEjkhm2G5P
				if ($_ !~ m|https?://www\.slideshare\.net/slideshow/embed_code/key/(\w+)|) { next; }
				$sid=$1;
				last;
			}
			last;
		}
		my $w = 425;
		my $h = 355;
		if ($ary->[0] eq 'small') { $w=340; $h=290; }
		if ($ary->[0] eq 'large') { $w=595; $h=485; }
		return "<module name=\"slideshare\" sid=\"$sid\" width=\"$w\" height=\"$h\">";
	}

	#-------------------------------------------------------------
	# Speaker Deck
	#-------------------------------------------------------------
	if ($url =~ m|^https?://speakerdeck\.com/|) {
		my $sid = $1;
		$url =~ s/\?.*//;

		# getして確認する
		my $http = $ROBJ->loadpm('Base::HTTP');
		my $res = $http->get($url);
		my $id;
		my $raito;
		foreach(@$res) {
			# <div class="speakerdeck-embed" data-id="cc--90f" data-ratio="1.77777777777778"></div>
			if ($_ =~ m|class\s*=\s*"speakerdeck-embed"|) {
				if ($_ =~ m|data-id\s*=\s*"(\w+)"|)    { $id = $1; }
				if ($_ =~ m|data-ratio\s*=\s*"([\d\.]+)"|) { $raito = $1; }
				last;
			}
		}
		if (!$id) { return "[(not found)$url]"; }

		return "<module name=\"speakerdeck\" sid=\"$id\" raito=\"$raito\">";
	}

	#-------------------------------------------------------------
	# http://slide.rabbit-shocker.org/
	#-------------------------------------------------------------
	if ($url =~ m|http://slide\.rabbit-shocker\.org(/authors/\w+/[\w\-]+/)|) {
		my $path = $1;
		return "<module name=\"rabbit-shocker:slide\" path=\"$path\">";
	}


	#-------------------------------------------------------------
	# Google map
	#-------------------------------------------------------------
	# iframe embed
	# https://maps.google.co.jp/maps?output=embed&t=m&hl=ja&z=18&ll=35.689634,139.692101&q=35.689634,139.692101
	#
	while ($url =~ m!^https://www\.google\.(?:co\.jp|com)/maps/([^@]*)\@(.+)$!) {
		my $place = $1;
		my $query = $2;
		if (index('?', $query)<0 && $ary->[0] =~ /^0x/) { $query .= ':' . shift(@$ary); }

		my $opt='';
		if ($query =~ /^(-?\d+\.\d+,-?\d+\.\d+)(?:,(\d+)(?:\.\d+)?z)?(.*)/) {
			my $center = $1;
			my $query2 = $3;
			my $pin;
			$opt = " center=\"$center\" zoom=\"$2\"";
			if ($query2 =~ /!3d(-?\d+\.\d+)!4d(-?\d+\.\d+)/) {
				$pin = "$1,$2";
			}
			if ($pin && $place =~ m|^place/([^/]+)|) {
				$opt .= " q=\"$1\"";
				# $opt .= " q=\"$1\@$pin\"";
			} elsif ($pin) {
				$opt .= " q=\"$pin\"";
			}
		} else {
			last;	# unknown url type
		}
		my $w = '';
		my $h = '';
		if ($ary->[$#$ary] eq 'small') { $w=300; $h=300; }
		if ($ary->[$#$ary] eq 'large') { $w='100%; padding: 0'; $h=480; }
		return "<module name=\"google:map\"$opt width=\"$w\" height=\"$h\">";
	}

	#-------------------------------------------------------------
	# はてなブログ
	#-------------------------------------------------------------
	if ($url =~ m|^https?://\w+\.hatenablog\.com/|) {
		return "<module name=\"hatena:blog\" url=\"$url\">";
	}

	#-------------------------------------------------------------
	# その他（audio/video）
	#-------------------------------------------------------------
	if ($url =~ m{\.(?:wave?|ogg|oga|mp3|aac|m4a)}i) {
		return $pobj->parse_tag("[audio:$urlf]");
	}

	if ($url =~ m{\.(?:webm|ogv|mp4|m4v)}i) {
		return $pobj->parse_tag("[video:$urlf]");
	}

	#-------------------------------------------------------------
	# その他（画像）
	#-------------------------------------------------------------
	if ($url =~ m{\.(?:jpg|jpeg|png|gif|bmp)}i) {
		my $opt = (@$ary ? ':' : '') . join(':',@$ary);
		return $pobj->parse_tag("[img:$url$opt]");
	}

	#-------------------------------------------------------------
	# その他（URLのOGPを取得してカードにする）
	#-------------------------------------------------------------
	if ($urlf =~ m|^https?://[^\s<>"]+$|) {
		return &link_card($pobj, $urlf);
	}

	return '[(filter unkown) ' . &esc_html($urlf) . ']';
}

################################################################################
# ■リンクカード
################################################################################
# docs/仕様/機能一覧.md「リンクカード」
my $CARD_TIMEOUT  = 4;			# 接続と受信のそれぞれの制限時間（秒）
my $CARD_REDIRECT = 3;
my $CARD_MAX_SIZE = 5*1024*1024;
my $CARD_BUDGET   = 20;			# 記事1件で取得に使う時間の上限（秒）
my $CARD_TEXT_LEN = 300;		# タイトルと説明の文字数の上限

#-------------------------------------------------------------------------------
# ●カードのHTML。取得できなければ普通のリンクにする
#-------------------------------------------------------------------------------
sub link_card {
	my ($pobj, $url) = @_;
	my $eurl = &esc_html($url);
	my $link = "<a href=\"$eurl\">$eurl</a>";

	# 記事の保存が止まらないよう、記事ごとに取得の時間を制限する。パーサーは全記事の再構築で使い回される
	if ($pobj->{link_card_pkey} ne $pobj->{thispkey}) {
		$pobj->{link_card_pkey}  = $pobj->{thispkey};
		$pobj->{link_card_spent} = 0;
	}
	if ($pobj->{link_card_spent} >= $CARD_BUDGET) { return $link; }

	my $start = Time::HiRes::clock_gettime(Time::HiRes::CLOCK_MONOTONIC());
	my $ogp   = &fetch_ogp($pobj->{ROBJ}, $url);
	$pobj->{link_card_spent} += Time::HiRes::clock_gettime(Time::HiRes::CLOCK_MONOTONIC()) - $start;
	if (!$ogp) { return $link; }

	my $type  = $ogp->{type}  ne '' ? " data-og-type=\"$ogp->{type}\"" : '';
	my $image = $ogp->{image} ne '' ? '<img class="link-card-image" alt="" src="' . &esc_html($ogp->{image}) . '">' : '';
	my $title = &esc_html($ogp->{title});
	my $site  = &esc_html($ogp->{site});
	my $desc  = $ogp->{description} ne ''
		? '<span class="link-card-desc">' . &esc_html($ogp->{description}) . '</span>' : '';

	return "<a class=\"link-card\" href=\"$eurl\"$type>$image<span class=\"link-card-body\">"
	     . "<span class=\"link-card-title\">$title</span>$desc<span class=\"link-card-site\">$site</span>"
	     . "</span></a>";
}

# 外部の値をHTMLへ入れる。&は実体参照のまま残し、TagEscapeが正規化する
sub esc_html {
	my $s = shift;
	$s =~ s/</&lt;/g;
	$s =~ s/>/&gt;/g;
	$s =~ s/"/&quot;/g;
	$s =~ s/'/&#39;/g;
	return $s;
}

#-------------------------------------------------------------------------------
# ●URLを取得してOGPを返す。カードにできなければundef
#-------------------------------------------------------------------------------
sub fetch_ogp {
	my ($ROBJ, $url) = @_;

	my $http = $ROBJ->loadpm('Base::HTTP');
	$http->set_timeout($CARD_TIMEOUT);
	$http->{redirect} = $CARD_REDIRECT;
	$http->{max_size} = $CARD_MAX_SIZE;

	my $target = $url;
	$target =~ s/#.*//;	# フラグメントはサーバーへ送らない
	my ($status, $header, $res) = $http->get($target);
	if ($status != 200 || !ref($res)) { return; }

	my ($ctype) = grep { /^content-type:/i } @$header;
	if ($ctype ne '' && $ctype !~ m!\b(?:text/html|application/xhtml\+xml)\b!i) { return; }

	return &parse_ogp($ROBJ, join('', @$res), $ctype, $http->{url});
}

#-------------------------------------------------------------------------------
# ●HTMLからOGPを取り出す。タイトルが無ければundef
#-------------------------------------------------------------------------------
sub parse_ogp {
	my ($ROBJ, $html, $ctype, $base) = @_;

	# <head>の中だけを見る。コメントやスクリプトの中の文字列は拾わない
	$html =~ s/<!--.*?-->//sg;
	$html =~ s/<(script|style)\b.*?<\/\1\s*>//sgi;
	$html =~ s/<\/head\b.*//si;
	$html =~ s/<body\b.*//si;

	# metaの属性（>を含む値でも、順序や引用符が違っても読む）
	my %meta;
	my $charset = $ctype =~ /charset=["']?([\w\-]+)/i ? $1 : '';
	while ($html =~ /<meta\b((?:[^>"']++|"[^"]*"|'[^']*')*)>/gi) {
		my $attrs = $1;
		my %at;
		while ($attrs =~ /([\w:\-]+)\s*=\s*(?:"([^"]*)"|'([^']*)'|([^\s"'>]+))/g) {
			$at{lc($1)} = defined $2 ? $2 : defined $3 ? $3 : $4;
		}
		if ($charset eq '') {
			if ($at{charset} =~ /^([\w\-]+)/ || $at{content} =~ /charset=([\w\-]+)/i) { $charset = $1; }
		}
		my $key = lc($at{property} ne '' ? $at{property} : $at{name});
		if ($key ne '' && !exists $meta{$key}) { $meta{$key} = $at{content}; }
	}
	my $title = $meta{'og:title'};
	if ($title eq '' && $html =~ /<title(?:\s[^>]*)?>(.*?)<\/title\s*>/si) { $title = $1; }

	my %ogp = (
		title       => $title,
		site        => $meta{'og:site_name'},
		description => $meta{'og:description'} ne '' ? $meta{'og:description'} : $meta{description},
	);

	# 文字コードをそろえ、改行をつめ、長さを制限する
	my $jcode = $ROBJ->load_codepm_if_needs(values(%ogp));
	foreach(values(%ogp)) {
		$jcode && $jcode->from_to(\$_, $charset, $ROBJ->{SystemCode});
		$_ = &clip_text($_);
	}
	if ($ogp{title} eq '') { return; }

	if ($ogp{site} eq '' && $base =~ m|^https?://([^/:]+)|i) { $ogp{site} = $1; }
	$ogp{image} = &absolute_https_url($meta{'og:image'}, $base);
	$ogp{type}  = $meta{'og:type'} =~ /^[\w\.\-]+$/ ? lc($meta{'og:type'}) : '';
	return \%ogp;
}

# 空白をつめて長さを制限する。文字の途中で切らないよう、UTF-8として数える
sub clip_text {
	my $s = shift;
	$s =~ s/\s+/ /g;
	$s =~ s/^ //;
	$s =~ s/ $//;
	if (utf8::decode($s)) {
		my $over = length($s) > $CARD_TEXT_LEN;
		if ($over) { $s = substr($s, 0, $CARD_TEXT_LEN); }
		utf8::encode($s);
		if ($over) { $s .= '…'; }	# このファイルの文字列はバイト列なので、戻してから足す
	}
	return $s;
}

# 画像のURLを絶対URLにする。https以外は読者の環境で読めないことがあるので使わない
sub absolute_https_url {
	my ($url, $base) = @_;
	$url =~ s/^\s+//;
	$url =~ s/\s+$//;
	if ($url eq '') { return ''; }

	if ($url =~ m|^//|) {
		$url = "https:$url";
	} elsif ($url !~ /^[a-z][a-z0-9\+\.\-]*:/i) {
		if ($base !~ m|^(https?://[^/]+)([^?#]*)|i) { return ''; }
		my ($origin, $path) = ($1, $2);
		$path =~ s|[^/]*$||;
		$url = $origin . ($url =~ m|^/| ? '' : ($path eq '' ? '/' : $path)) . $url;
	}
	return $url =~ m!^https://[^\s<>"']+$!i ? $url : '';
}

1;
