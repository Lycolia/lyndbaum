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
# 記事の保存では、link_cardsに前回の保存のカード（URL→HTML）が入っている。そのURLは取得しない。
# 取得した結果も入れておき、同じ保存の中のもう一度のパース（見出しのIDを足すとき）では取得しない。
# 取得できずに普通のリンクにしたものも入れる（その保存の中だけ。表は保存が終わると消える）
# 再構築では、link_cardsに今のHTMLのカードが入り、link_cards_offlineが付く。表に無いURLも取得せず、普通のリンクにする
sub link_card {
	my ($pobj, $url) = @_;
	my $cards = $pobj->{link_cards};
	if (!$cards) { return &make_link_card($pobj, $url); }

	my $key = $url;
	$key =~ s/&amp;/&/g;
	if (!defined $cards->{$key}) {
		$cards->{$key} = $pobj->{link_cards_offline} ? &plain_link($url) : &make_link_card($pobj, $url);
	}
	return $cards->{$key};
}

sub plain_link {
	my $eurl = &esc_html(shift);
	return "<a href=\"$eurl\">$eurl</a>";
}

sub make_link_card {
	my ($pobj, $url) = @_;
	my $eurl = &esc_html($url);
	my $link = &plain_link($url);

	# 記事の保存が止まらないよう、記事ごとに取得の時間を制限する。パーサーは全記事の再構築で使い回される
	if ($pobj->{link_card_pkey} ne $pobj->{thispkey}) {
		$pobj->{link_card_pkey}  = $pobj->{thispkey};
		$pobj->{link_card_spent} = 0;
	}
	if ($pobj->{link_card_spent} >= $CARD_BUDGET) { return $link; }

	my $ROBJ  = $pobj->{ROBJ};
	my $start = Time::HiRes::clock_gettime(Time::HiRes::CLOCK_MONOTONIC());
	my $ogp   = &fetch_ogp($ROBJ, $url);
	my $post  = &fetch_fedi_post($ROBJ, $url, $ogp);
	$pobj->{link_card_spent} += Time::HiRes::clock_gettime(Time::HiRes::CLOCK_MONOTONIC()) - $start;
	if ($post) { return &fedi_card($ROBJ, $eurl, $post); }
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

#-------------------------------------------------------------------------------
# ●Fediverseの投稿のカード
#-------------------------------------------------------------------------------
sub fedi_card {
	my ($ROBJ, $eurl, $p) = @_;

	my $avatar = $p->{avatar} ne '' ? '<img class="link-card-avatar" alt="" src="' . &esc_html($p->{avatar}) . '">' : '';
	my $name   = &esc_text($p->{name});
	my $acct   = &esc_text($p->{acct});
	my $text   = $p->{text} ne '' ? '<span class="link-card-text">' . &esc_text($p->{text}) . '</span>' : '';
	my $media  = join('', map {
		'<img alt="' . &esc_text($_->{alt}) . '" src="' . &esc_html($_->{url}) . '">'
	} @{ $p->{media} });
	if ($media ne '') { $media = "<span class=\"link-card-media\">$media</span>"; }

	my $time = '';
	if ($p->{tm}) {
		$time = '<time datetime="' . $ROBJ->print_tmf('%Y-%m-%dT%H:%M:%S', $p->{tm}) . $p->{tz} . '">'
		      . $ROBJ->print_tmf('%Y/%m/%d %H:%M', $p->{tm}) . '</time> ・ ';
	}
	my $host = &esc_html($p->{host});

	return "<a class=\"link-card\" href=\"$eurl\" data-og-type=\"$p->{type}\" data-card=\"fediverse\"><span class=\"link-card-body\">"
	     . "<span class=\"link-card-author\">$avatar<span class=\"link-card-title\">$name</span><span class=\"link-card-acct\">$acct</span></span>"
	     . "$text$media<span class=\"link-card-site\">$time$host</span>"
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

# 実体参照を戻した文字列をHTMLへ入れる。&も文字として出す
sub esc_text {
	my $s = shift;
	$s =~ s/&/&amp;/g;
	return &esc_html($s);
}

#-------------------------------------------------------------------------------
# ●URLを取得してOGPを返す。カードにできなければundef
#-------------------------------------------------------------------------------
sub fetch_ogp {
	my ($ROBJ, $url) = @_;

	my $http = &card_http($ROBJ);

	my $target = $url;
	$target =~ s/#.*//;	# フラグメントはサーバーへ送らない
	my ($status, $header, $res) = $http->get($target);
	if ($status != 200 || !ref($res)) { return; }

	my ($ctype) = grep { /^content-type:/i } @$header;
	if ($ctype ne '' && $ctype !~ m!\b(?:text/html|application/xhtml\+xml)\b!i) { return; }

	return &parse_ogp($ROBJ, join('', @$res), $ctype, $http->{url});
}

sub card_http {
	my $ROBJ = shift;
	my $http = $ROBJ->loadpm('Base::HTTP');
	$http->set_timeout($CARD_TIMEOUT);
	$http->{redirect} = $CARD_REDIRECT;
	$http->{max_size} = $CARD_MAX_SIZE;
	return $http;
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
	# ActivityPubの表現（Fediverseの投稿のカードに使う）
	my $ap;
	while ($html =~ /<link\b((?:[^>"']++|"[^"]*"|'[^']*')*)>/gi) {
		my $attrs = $1;
		my %at;
		while ($attrs =~ /([\w:\-]+)\s*=\s*(?:"([^"]*)"|'([^']*)'|([^\s"'>]+))/g) {
			$at{lc($1)} = defined $2 ? $2 : defined $3 ? $3 : $4;
		}
		if (lc($at{rel}) ne 'alternate' || $at{type} !~ m!^application/activity\+json$!i) { next; }
		$ap = $at{href};
		$ap =~ s/&amp;/&/g;
		last;
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
	if ($ap ne '' && &url_host($ap) ne '' && &url_host($ap) eq &url_host($base) && $ap =~ m!^https://[^\s<>"']+$!i) {
		$ogp{ap} = $ap;
	}
	return \%ogp;
}

################################################################################
# ■Fediverseの投稿
################################################################################
# docs/仕様/機能一覧.md「リンクカード」
my $FEDI_TEXT_LEN  = 500;		# 本文の文字数の上限
my $FEDI_MEDIA_MAX = 4;			# 添付画像の枚数の上限
my $AP_ACCEPT = 'application/activity+json, application/ld+json; profile="https://www.w3.org/ns/activitystreams"';

#-------------------------------------------------------------------------------
# ●投稿を取得する。投稿でなければundef
#-------------------------------------------------------------------------------
# ActivityPubのNoteを取得し、拒否されたらMastodon APIを試す
sub fetch_fedi_post {
	my ($ROBJ, $url, $ogp) = @_;
	if (!$ogp || $ogp->{ap} eq '') { return; }
	my ($post, $denied) = &fetch_ap_post($ROBJ, $ogp->{ap});
	if ($post || !$denied) { return $post; }
	if ($url =~ m!^https://([^/:?#]+)/\@[\w\.\-]+(?:\@[\w\.\-]+)?/(\d+)/?(?:[?#].*)?$!) {
		return &fetch_mastodon_post($ROBJ, $1, $2);
	}
	return;
}

# JSONを取得する。2つ目の戻り値は、拒否された（401/403）かどうか
sub fetch_json {
	my ($ROBJ, $url, $accept) = @_;
	my $http = &card_http($ROBJ);
	my ($status, $header, $res) = $http->get($url, { Accept => $accept });
	if ($status == 401 || $status == 403) { return (undef, 1); }
	if ($status != 200 || !ref($res)) { return; }

	my ($ctype) = grep { /^content-type:/i } @$header;
	if ($ctype ne '' && $ctype !~ m!json!i) { return; }

	require JSON::PP;
	my $json = eval { JSON::PP->new->utf8->decode(join('', @$res)) };
	return ref($json) eq 'HASH' ? $json : undef;
}

#-------------------------------------------------------------------------------
# ●ActivityPub
#-------------------------------------------------------------------------------
sub fetch_ap_post {
	my ($ROBJ, $ap) = @_;
	my $host = &url_host($ap);

	my ($note, $denied) = &fetch_json($ROBJ, $ap, $AP_ACCEPT);
	if (!$note) { return (undef, $denied); }
	if ($note->{type} ne 'Note' && $note->{type} ne 'Question') { return; }
	if (&url_host(&ap_id($note->{id})) ne $host) { return; }	# 他のサーバーの投稿を名乗るものは使わない

	# 投稿者
	my $actor_id = &ap_actor($note->{attributedTo});
	if (&url_host($actor_id) ne $host) { return; }
	my ($actor, $denied2) = &fetch_json($ROBJ, $actor_id, $AP_ACCEPT);
	if (!$actor) { return (undef, $denied2); }
	if (&url_host(&ap_id($actor->{id})) ne $host) { return; }

	my $user = &ap_str($actor->{preferredUsername});
	my $sensitive = $note->{sensitive} ? 1 : 0;
	my @media;
	foreach (&ap_list($note->{attachment})) {
		if (ref($_) ne 'HASH') { next; }
		if ($_->{sensitive}) { $sensitive = 1; }
		my $type = &ap_str($_->{mediaType});
		if ($type ne '' ? $type !~ m!^image/!i : $_->{type} ne 'Image') { next; }
		push(@media, { url => &ap_url($_->{url}), alt => &ap_str($_->{name}) });
	}

	return &fedi_post($ROBJ, {
		type	=> lc($note->{type}),
		host	=> $host,
		name	=> &ap_str($actor->{name}) ne '' ? &ap_str($actor->{name}) : $user,
		acct	=> $user ne '' ? "\@$user\@$host" : '',
		avatar	=> &ap_url(ref($actor->{icon}) eq 'ARRAY' ? $actor->{icon}->[0] : $actor->{icon}),
		html	=> &ap_str($note->{content}),
		cw	=> &ap_str($note->{summary}),
		published => &ap_str($note->{published}),
		media	=> $sensitive ? [] : \@media,
	}, $ap);
}

# 値の取り出し。文字列でなければ空にする
sub ap_str {
	my $v = shift;
	return ref($v) ? '' : $v;
}
sub ap_list {
	my $v = shift;
	return ref($v) eq 'ARRAY' ? @$v : defined $v ? ($v) : ();
}
sub ap_id {
	my $v = shift;
	return ref($v) eq 'HASH' ? &ap_str($v->{id}) : &ap_str($v);
}
# 投稿者。配列ならPersonなどのactorを選ぶ
sub ap_actor {
	my @list = &ap_list(shift);
	foreach (@list) {
		if (!ref($_) || $_->{type} =~ /^(?:Person|Service|Application|Group|Organization)$/) { return &ap_id($_); }
	}
	return '';
}
# url（文字列、Link、Image、その配列）
sub ap_url {
	my $v = shift;
	if (ref($v) eq 'ARRAY') { $v = $v->[0]; }
	if (ref($v) eq 'HASH')  { $v = exists $v->{href} ? $v->{href} : $v->{url}; }
	if (ref($v) eq 'ARRAY') { $v = $v->[0]; }
	if (ref($v) eq 'HASH')  { $v = $v->{href}; }
	return &ap_str($v);
}

#-------------------------------------------------------------------------------
# ●Mastodon API（ActivityPubを拒否されたとき）
#-------------------------------------------------------------------------------
sub fetch_mastodon_post {
	my ($ROBJ, $host, $id) = @_;
	my $st = &fetch_json($ROBJ, "https://$host/api/v1/statuses/$id", 'application/json');
	if (!$st || ref($st->{account}) ne 'HASH' || &ap_str($st->{id}) ne $id) { return; }
	my $ac = $st->{account};

	my $acct = &ap_str($ac->{acct});
	if ($acct ne '' && $acct !~ /\@/) { $acct .= "\@$host"; }
	my @media;
	foreach (&ap_list($st->{media_attachments})) {
		if (ref($_) ne 'HASH' || $_->{type} ne 'image') { next; }
		my $u = &ap_str($_->{preview_url}) ne '' ? $_->{preview_url} : $_->{url};
		push(@media, { url => &ap_str($u), alt => &ap_str($_->{description}) });
	}

	return &fedi_post($ROBJ, {
		type	=> 'note',
		host	=> $host,
		name	=> &ap_str($ac->{display_name}) ne '' ? &ap_str($ac->{display_name}) : &ap_str($ac->{username}),
		acct	=> $acct ne '' ? "\@$acct" : '',
		avatar	=> &ap_str($ac->{avatar}),
		html	=> &ap_str($st->{content}),
		cw	=> &ap_str($st->{spoiler_text}),
		published => &ap_str($st->{created_at}),
		media	=> $st->{sensitive} ? [] : \@media,
	}, "https://$host/");
}

#-------------------------------------------------------------------------------
# ●取り出した値をカードの値にする
#-------------------------------------------------------------------------------
# JSONの文字列は文字なので、このファイルにそろえてUTF-8のバイト列にする
sub fedi_post {
	my ($ROBJ, $p, $base) = @_;
	foreach (qw(name acct avatar html cw published)) {
		utf8::encode($p->{$_}) if utf8::is_utf8($p->{$_});
	}
	foreach (@{ $p->{media} }) {
		utf8::encode($_->{url}) if utf8::is_utf8($_->{url});
		utf8::encode($_->{alt}) if utf8::is_utf8($_->{alt});
	}

	my %post = (
		type	=> $p->{type} =~ /^\w+$/ ? $p->{type} : 'note',
		host	=> $p->{host},
		name	=> &clip_text($p->{name}),
		acct	=> &clip_text($p->{acct}),
		avatar	=> &absolute_https_url($p->{avatar}, $base),
	);
	if ($post{name} eq '') { return; }

	# 注意書き（CW）があれば、本文の代わりに注意書きだけを出す
	$post{text} = $p->{cw} ne '' ? &clip_text(&html_to_text($p->{cw}))
	                             : &clip_lines(&html_to_text($p->{html}, 1), $FEDI_TEXT_LEN);

	my @media;
	foreach (@{ $p->{media} }) {
		my $url = &absolute_https_url($_->{url}, $base);
		if ($url eq '') { next; }
		push(@media, { url => $url, alt => &clip_text($_->{alt}) });
		if (@media >= $FEDI_MEDIA_MAX) { last; }
	}
	$post{media} = $p->{cw} ne '' ? [] : \@media;

	# 2026-11-07T12:36:40.311Z、2026-11-07T21:36:40+09:00
	if ($p->{published} =~ /^(\d{4})-(\d\d)-(\d\d)T(\d\d):(\d\d):(\d\d)(?:\.\d+)?(Z|([+\-])(\d\d):?(\d\d))$/i) {
		require Time::Local;
		my $tm = eval { Time::Local::timegm($6, $5, $4, $3, $2-1, $1) };
		if ($tm && uc($7) ne 'Z') { $tm -= ($8 eq '-' ? -1 : 1) * ($9*3600 + $10*60); }
		if ($tm) {
			$post{tm} = $tm;
			my @l = localtime($tm);
			my @g = gmtime($tm);
			my $off = (Time::Local::timegm(@l[0..5]) - Time::Local::timegm(@g[0..5])) / 60;
			$post{tz} = $off == 0 ? 'Z' : sprintf('%s%02d:%02d', $off < 0 ? '-' : '+', abs($off)/60, abs($off)%60);
		}
	}
	return \%post;
}

# 投稿のHTMLを文字にする。$linesなら改行を残す
sub html_to_text {
	my ($s, $lines) = @_;
	$s =~ s/<!--.*?-->//sg;
	$s =~ s/<(script|style)\b.*?<\/\1\s*>//sgi;
	if ($lines) {
		$s =~ s/[\r\n]+/ /g;
		$s =~ s/<br\b[^>]*>/\n/gi;
		$s =~ s/<\/(?:p|div|li|h\d|blockquote|pre)\s*>/\n\n/gi;
	}
	$s =~ s/<[^>]*>//g;
	$s =~ s/&#[xX]([0-9A-Fa-f]{1,6});/&chr_utf8(hex($1))/eg;
	$s =~ s/&#(\d{1,7});/&chr_utf8($1)/eg;
	my %ent = (lt => '<', gt => '>', quot => '"', apos => "'", nbsp => ' ');
	$s =~ s/&(lt|gt|quot|apos|nbsp);/$ent{$1}/g;
	$s =~ s/&amp;/&/g;
	return $s;
}
sub chr_utf8 {
	my $c = shift;
	if ($c < 0x20 && $c != 0x0a || 0x10ffff < $c || (0xd800 <= $c && $c <= 0xdfff)) { return ' '; }
	my $s = chr($c);
	utf8::encode($s);
	return $s;
}

# 改行を残して長さを制限する。行の中の空白はつめ、空行は1つにする
sub clip_lines {
	my ($s, $len) = @_;
	$s =~ s/[ \t\r\f]+/ /g;
	$s =~ s/ *\n */\n/g;
	$s =~ s/\n{3,}/\n\n/g;
	$s =~ s/^\s+//;
	$s =~ s/\s+$//;
	if (utf8::decode($s)) {
		my $over = length($s) > $len;
		if ($over) { $s = substr($s, 0, $len); $s =~ s/\s+$//; }
		utf8::encode($s);
		if ($over) { $s .= '…'; }
	}
	return $s;
}

sub url_host {
	my $url = shift;
	return $url =~ m!^https?://([^/:?#\@]+)(?::\d+)?(?:[/?#]|$)!i ? lc($1) : '';
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
