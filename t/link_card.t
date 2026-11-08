use strict;
use utf8;
#-------------------------------------------------------------------------------
# リンクカード（[&URL]）のテスト
#-------------------------------------------------------------------------------
# 実行: prove t/link_card.t
#
# Base::HTTPの応答を差し替えるので、外部のネットワークは要らない。
# 本番と同じパーサーとTagEscapeを通した結果を見る。
#
use FindBin;
BEGIN { push(@INC, "$FindBin::Bin/lib", "$FindBin::Bin/../lib"); }
use Test::More;
use Encode ();
use MarkdownTest qw(new_parser);
require Satsuki::Base;
require Satsuki::Base::HTTP;

binmode(Test::More->builder->$_, ':utf8') foreach (qw(output failure_output todo_output));

my $ROBJ   = Satsuki::Base->new();
my $escape = $ROBJ->loadpm('TextParser::TagEscape', 'info/allow_tags_article.txt');
$ROBJ->{CodeLib} = 'Jcode';	# 本番の設定と同じ

# 次の取得で返す応答と、取得の記録
my %RES;
my @GOT;
{
	no warnings 'redefine';
	*Satsuki::Base::HTTP::get = sub {
		my ($self, $url, $header) = @_;
		push(@GOT, { url => $url, accept => ($header || {})->{Accept}, timeout => $self->{timeout}, redirect => $self->{redirect}, max_size => $self->{max_size} });
		my $r = $RES{$url} || { status => 500 };
		$self->{url} = $r->{final} || $url;
		if ($r->{sleep}) { $r->{sleep}->(); }
		my @header = ('HTTP/1.1 ' . $r->{status}, 'Content-Type: ' . ($r->{ctype} || 'text/html; charset=UTF-8'));
		return ($r->{status}, \@header, $r->{body} ? [ $r->{body} ] : undef);
	};
}

sub bytes { return Encode::encode('UTF-8', shift); }
sub page {
	my ($head, %opt) = @_;
	return { status => 200, body => bytes("<html><head>$head</head><body><title>本文の中のタイトル</title></body></html>"), %opt };
}

# 本番と同じ流れでHTMLにする
sub render {
	my ($text, $pkey, $cards) = @_;
	my $md = new_parser();
	$md->{satsuki_obj}->{ROBJ}->{CodeLib} = 'Jcode';	# 本番の設定と同じ
	$md->{thispkey} = $pkey if (defined $pkey);
	$md->{link_cards} = $cards;
	my $html = $escape->escape(scalar $md->parse(bytes($text)));
	return Encode::decode('UTF-8', $html);
}

my $U = 'https://example.test/page';

subtest 'OGPをカードにする' => sub {
	$RES{$U} = page(q{<title>題名 - サイト</title>
		<meta property="og:title" content="OGの題名">
		<meta content="OGの説明" property="og:description">
		<meta property='og:site_name' content='サイト名'>
		<meta property="og:image" content="https://example.test/i.png?a=1&amp;b=2">
		<meta property="og:type" content="Video.Other">});
	my $h = render("[&$U]");
	like($h, qr{<a class="link-card" href="https://example\.test/page" data-og-type="video\.other">}, 'カードのリンク');
	like($h, qr{<img class="link-card-image" alt="" src="https://example\.test/i\.png\?a=1&amp;b=2">}, '画像');
	like($h, qr{<span class="link-card-title">OGの題名</span>}, 'og:titleを優先する');
	like($h, qr{<span class="link-card-desc">OGの説明</span>}, '属性の順序が逆でも読む');
	like($h, qr{<span class="link-card-site">サイト名</span>}, '単一引用符でも読む');
};

subtest 'OGPが無ければ<title>とホスト名を使う' => sub {
	$RES{$U} = page(qq{<title>\n  ただの\n  題名\n</title><meta name="description" content="metaの説明">});
	my $h = render("[&$U]");
	like($h, qr{link-card-title">ただの 題名</span>}, '<title>。改行はつめる');
	like($h, qr{link-card-desc">metaの説明</span>}, 'meta descriptionを使う');
	like($h, qr{link-card-site">example\.test</span>}, 'ホスト名を使う');
	unlike($h, qr{<img}, '画像が無ければ<img>を出さない');
	unlike($h, qr{data-og-type}, 'typeが無ければ属性を出さない');

	$RES{$U} = page('<title>題名</title>');
	unlike(render("[&$U]"), qr{link-card-desc}, '説明が無ければ出さない');
};

subtest '<head>の外とコメントの中は読まない' => sub {
	$RES{$U} = page(q{<title>本物</title>
		<!-- <meta property="og:description" content="コメント"> -->
		<script>var a = '<meta property="og:image" content="https://evil.test/x.png">';</script>});
	my $h = render("[&$U]");
	like($h, qr{link-card-title">本物<}, '先に出た<title>を使う');
	unlike($h, qr{コメント|evil\.test|本文の中}, 'コメント、スクリプト、本文を読まない');

	$RES{$U} = { status => 200, body => bytes('<html><body><title>本文の中</title></body></html>') };
	like(render("[&$U]"), qr{<a href="https://example\.test/page">https://example\.test/page</a>}, '<head>に題名が無ければ普通のリンク');
};

subtest '外部の値をエスケープする' => sub {
	$RES{$U} = page(q{<title>t</title>
		<meta property="og:title" content="<script>alert(1)</script>&quot;題">
		<meta property="og:description" content='"><img src=x onerror=alert(2)>'>
		<meta property="og:site_name" content="<b onclick=alert(3)>s</b>">
		<meta property="og:type" content='x" onclick="alert(4)'>
		<meta property="og:image" content='https://example.test/a.png" onerror="alert(5)'>});
	my $h = render("[&$U]");
	unlike($h, qr{<script|<img|<b\b|onclick="|onerror="}, 'タグや属性にならない');
	like($h, qr{link-card-desc">&quot;&gt;&lt;img src=x onerror=alert\(2\)&gt;<}, '文字として出る');
};

subtest '画像のURL' => sub {
	my %cases = (
		'/a.png'                  => 'https://example.test/a.png',
		'a.png'                   => 'https://example.test/dir/a.png',
		'//cdn.example.test/a.png'=> 'https://cdn.example.test/a.png',
		'https://x.test/a.png'    => 'https://x.test/a.png',
	);
	foreach my $img (sort keys %cases) {
		$RES{$U} = page(qq{<title>t</title><meta property="og:image" content="$img">}, final => 'https://example.test/dir/page?x=1');
		like(render("[&$U]"), qr{src="\Q$cases{$img}\E"}, "$img は絶対URLにする");
	}
	foreach my $img ('http://example.test/a.png', 'javascript:alert(1)', 'data:image/png;base64,AAAA') {
		$RES{$U} = page(qq{<title>t</title><meta property="og:image" content="$img">});
		unlike(render("[&$U]"), qr{<img}, "$img は使わない");
	}
	$RES{$U} = page(q{<title>t</title><meta property="og:image" content="/a.png">}, final => 'http://example.test/page');
	unlike(render("[&$U]"), qr{<img}, 'httpのページの相対URLはhttpになるので使わない');
};

subtest '文字コード' => sub {
	my $sjis = Encode::encode('Shift_JIS', '<title>シフトJIS題名</title><meta property="og:description" content="説明文">');
	$RES{$U} = { status => 200, ctype => 'text/html; charset=Shift_JIS', body => "<head>$sjis</head>" };
	my $h = render("[&$U]");
	like($h, qr{シフトJIS題名}, 'ヘッダの文字コードで題名を変換する');
	like($h, qr{説明文}, '説明も変換する');

	my $euc = Encode::encode('EUC-JP', '<meta charset="EUC-JP"><title>EUCの題名</title>');
	$RES{$U} = { status => 200, ctype => 'text/html', body => "<head>$euc</head>" };
	like(render("[&$U]"), qr{EUCの題名}, 'metaの文字コードで変換する');

	my $long = 'あ' x 500;
	$RES{$U} = page("<title>$long</title>");
	my ($t) = render("[&$U]") =~ /link-card-title">([^<]*)</;
	is($t, ('あ' x 300) . '…', '長い値は文字の途中で切らずに縮める');
};

subtest '失敗したら普通のリンクにする' => sub {
	my $link = qr{<a href="https://example\.test/page">https://example\.test/page</a>};
	foreach my $r (
		[ '404',       { status => 404, body => bytes('<head><title>Not Found</title></head>') } ],
		[ '接続の失敗', { status => undef } ],
		[ 'HTML以外',  { status => 200, ctype => 'image/svg+xml', body => '<head><title>t</title></head>' } ],
		[ '題名が無い', { status => 200, body => '<head></head>' } ],
	) {
		$RES{$U} = $r->[1];
		my $h = render("[&$U]");
		like($h, $link, "$r->[0]: 普通のリンク");
		unlike($h, qr{access failed|link-card}, "$r->[0]: 失敗の文字もカードも出ない");
	}
};

subtest '取得の条件' => sub {
	$RES{$U} = page('<title>t</title>');
	@GOT = ();
	render("[&$U#frag]");
	is($GOT[0]->{url}, $U, 'フラグメントは送らない');
	is($GOT[0]->{timeout}, 4, '制限時間');
	is($GOT[0]->{redirect}, 3, 'リダイレクトの回数');
	is($GOT[0]->{max_size}, 5*1024*1024, '受信の上限');
	like(render("[&$U#frag]"), qr{href="https://example\.test/page#frag"}, 'リンクにはフラグメントを残す');

	my $h = render(q{[&https://example.test/a"onclick="alert(1)]});
	unlike($h, qr{<a\b}, '引用符を含むURLはリンクにしない');
	like($h, qr{filter unkown}, 'URLとして扱えないことを出す');
	unlike(render(q{[&https://example.test/<script>alert(1)</script>]}), qr{<script}, 'タグを含むURLでもタグにならない');
};

subtest '記事ごとの取得時間の予算' => sub {
	my $md = new_parser();
	my $clock = 0;
	no warnings 'redefine';
	local *Time::HiRes::clock_gettime = sub { return $clock; };
	$RES{$U} = page('<title>t</title>', sleep => sub { $clock += 21; });

	@GOT = ();
	$md->{thispkey} = 1;
	like(scalar $md->parse("[&$U]\n\n[&$U]\n"), qr{link-card.*<a href="[^"]*">[^<]*</a>}s, '予算を超えたら次は普通のリンク');
	is(scalar(@GOT), 1, '2つ目は取得しない');

	$md->{thispkey} = 2;
	like(scalar $md->parse("[&$U]\n"), qr{link-card}, '次の記事では予算が戻る');
	is(scalar(@GOT), 2, '取得する');
	$md->{thispkey} = '';	# 使った分を次のテストへ持ち越さない
};

subtest '専用の埋め込みはカードにしない' => sub {
	@GOT = ();
	like(render('[&https://www.youtube.com/watch?v=abc]'), qr{youtube}, 'YouTube');
	like(render('[&https://gist.github.com/a/b]'), qr{<script src="https://gist\.github\.com/a/b\.js"}, 'gist');
	like(render('[&https://example.test/a.png]'), qr{<img[^>]*a\.png}, '画像');
	is(scalar(@GOT), 0, '通信しない');

	$RES{'https://github.com/Lycolia'} = page('<title>GitHubの題名</title>');
	my $h = render('[&https://github.com/Lycolia]');
	like($h, qr{link-card-title">GitHubの題名<}, 'GitHubはカードになる');
	unlike($h, qr{gist-it|<script}, 'gist-itのスクリプトを出さない');
};

subtest '記事の概要にはカードの題名だけを残す' => sub {
	require SatsukiApp::adiary;
	my $app = bless({ ROBJ => $ROBJ, blog => { desc_len => 64 } }, 'SatsukiApp::adiary');
	$RES{$U} = page(q{<title>t</title><meta property="og:title" content="カードの題名">
		<meta property="og:description" content="相手の説明"><meta property="og:site_name" content="相手のサイト">
		<meta property="og:image" content="https://example.test/i.png">});
	my %h = (text => bytes(render("前の文\n\n[&$U]\n\n後の文\n")));
	$app->set_description(\%h, '');
	my $d = Encode::decode('UTF-8', $h{description});
	like($d, qr{前の文.*カードの題名.*後の文}, '題名は残る');
	unlike($d, qr{相手の説明|相手のサイト}, '相手の説明とサイト名は入らない');
};

subtest 'RSSではタイトルだけのリンクにする' => sub {
	require SatsukiApp::adiary;
	my $app = bless({ ROBJ => $ROBJ }, 'SatsukiApp::adiary');
	$RES{$U} = page(q{<title>t</title><meta property="og:title" content="カードの題名">
		<meta property="og:description" content="相手の説明"><meta property="og:site_name" content="相手のサイト">
		<meta property="og:image" content="https://example.test/i.png"><meta property="og:type" content="article">});
	my $html = bytes(render("前の文\n\n[&$U]\n\n[&$U]\n\n後の文\n"));
	my $text = Encode::decode('UTF-8', $app->link_card_to_text($html));
	my @links = $text =~ m{(<a href="https://example\.test/page">カードの題名</a>)}g;
	is(scalar(@links), 2, 'どのカードもタイトルのリンクになる');
	unlike($text, qr{相手の説明|相手のサイト|<img|link-card}, 'カードの中身は残らない');
	like($text, qr{前の文.*後の文}s, '前後の文は残る');

	my $plain = '<a href="https://example.test/">普通のリンク</a>';
	is($app->link_card_to_text($plain), $plain, '普通のリンクは変えない');
};

#-------------------------------------------------------------------------------
# Fediverseの投稿
#-------------------------------------------------------------------------------
my $F     = 'https://fedi.test/@alice/1234';
my $NOTE  = 'https://fedi.test/users/alice/statuses/1234';
my $ACTOR = 'https://fedi.test/users/alice';
sub json { return { status => 200, ctype => 'application/activity+json; charset=utf-8', body => JSON::PP->new->utf8->encode(shift) }; }
sub fedi_page {
	return page(qq{<title>t</title><meta property="og:title" content="アリス (\@alice\@fedi.test)">
		<meta property="og:description" content="OGPの説明"><meta property="og:site_name" content="インスタンス">
		<link href='$NOTE' rel='alternate' type='application/activity+json'>});
}
sub note {
	return { id => $NOTE, type => 'Note', attributedTo => $ACTOR, published => '2026-11-07T12:36:40Z', sensitive => JSON::PP::false(),
		content => '<p>一行目<br>二行目 &amp; &lt;b&gt;</p><p><a href="https://x.test/"><span class="invisible">https://</span>x.test/</a></p><script>alert(1)</script>',
		attachment => [
			{ type => 'Document', mediaType => 'image/png', url => 'https://fedi.test/m/1.png', name => '代替"テキスト' },
			{ type => 'Document', mediaType => 'video/mp4', url => 'https://fedi.test/m/2.mp4' },
			{ type => 'Document', mediaType => 'image/jpeg', url => 'http://fedi.test/m/3.jpg' },
		], @_ };
}
sub actor { return { id => $ACTOR, type => 'Person', name => 'アリス<b>', preferredUsername => 'alice', icon => { type => 'Image', url => 'https://fedi.test/a.png' }, @_ }; }
sub fedi_set {
	my %o = @_;
	$RES{$F}     = fedi_page();
	$RES{$NOTE}  = $o{note}  || json(note());
	$RES{$ACTOR} = $o{actor} || json(actor());
	delete $RES{'https://fedi.test/api/v1/statuses/1234'};
}
require JSON::PP;

subtest 'Fediverseの投稿をカードにする' => sub {
	local $ENV{TZ} = 'Asia/Tokyo';
	fedi_set();
	@GOT = ();
	my $h = render("[&$F]");
	like($h, qr{<a class="link-card" href="https://fedi\.test/\@alice/1234" data-og-type="note" data-card="fediverse">}, 'カードのリンク');
	like($h, qr{<img class="link-card-avatar" alt="" src="https://fedi\.test/a\.png">}, 'アイコン');
	like($h, qr{<span class="link-card-title">アリス&lt;b&gt;</span>}, '表示名は文字として出す');
	like($h, qr{<span class="link-card-acct">\@alice\@fedi\.test</span>}, '@アカウント');
	like($h, qr{<span class="link-card-text">一行目\n二行目 &amp; &lt;b&gt;\n\nhttps://x\.test/</span>}, '本文は改行を残し、タグを外す');
	unlike($h, qr{<script|alert|OGPの説明|インスタンス}, 'スクリプトとOGPの値は出さない');
	like($h, qr{<span class="link-card-media"><img alt="代替&quot;テキスト" src="https://fedi\.test/m/1\.png"></span>}, '画像はhttpsのものだけ');
	like($h, qr{<time datetime="2026-11-07T21:36:40\+09:00">2026/11/07 21:36</time> ・ fedi\.test</span>}, '日時とホスト');
	is_deeply([ map { $_->{url} } @GOT ], [ $F, $NOTE, $ACTOR ], 'ページ、投稿、投稿者の順に取得する');
	like($GOT[1]->{accept}, qr{application/activity\+json}, 'ActivityPubで取得する');
};

subtest '注意書きと閲覧注意' => sub {
	fedi_set(note => json(note(summary => 'ネタバレ')));
	my $h = render("[&$F]");
	like($h, qr{<span class="link-card-text">ネタバレ</span>}, '注意書きを出す');
	unlike($h, qr{一行目|link-card-media}, '本文と画像は出さない');

	fedi_set(note => json(note(sensitive => JSON::PP::true())));
	$h = render("[&$F]");
	like($h, qr{一行目}, '閲覧注意でも本文は出す');
	unlike($h, qr{link-card-media}, '閲覧注意の画像は出さない');
};

subtest '本文の長さと画像の枚数' => sub {
	fedi_set(note => json(note(content => '<p>' . ('あ' x 600) . '</p>',
		attachment => [ map { { type => 'Image', url => "https://fedi.test/m/$_.png" } } 1..6 ])));
	my $h = render("[&$F]");
	my ($t) = $h =~ /link-card-text">([^<]*)</;
	is($t, ('あ' x 500) . '…', '本文は500文字で切る');
	my @img = $h =~ m{(src="https://fedi\.test/m/)}g;
	is(scalar(@img), 4, '画像は4枚まで');
};

subtest '他のホストの値は使わない' => sub {
	fedi_set(note => json(note(id => 'https://evil.test/users/alice/statuses/1234')));
	like(render("[&$F]"), qr{OGPの説明}, '投稿のidが違うホストならOGPのカード');

	fedi_set(note => json(note(attributedTo => 'https://evil.test/users/alice')));
	@GOT = ();
	like(render("[&$F]"), qr{OGPの説明}, '投稿者が違うホストならOGPのカード');
	ok(!grep({ $_->{url} =~ /evil/ } @GOT), '違うホストへは取得しない');

	$RES{$F} = page(q{<title>t</title><link rel="alternate" type="application/activity+json" href="https://evil.test/users/alice/statuses/1234">});
	@GOT = ();
	render("[&$F]");
	is(scalar(@GOT), 1, 'ページと違うホストのActivityPubは取得しない');
};

subtest '投稿でなければOGPのカード' => sub {
	fedi_set(note => json(actor()));
	like(render("[&$F]"), qr{<span class="link-card-desc">OGPの説明</span>}, 'Personのページ');
	fedi_set(note => { status => 200, ctype => 'application/activity+json', body => '{broken' });
	like(render("[&$F]"), qr{OGPの説明}, '壊れたJSON');
	fedi_set(note => { status => 404 });
	@GOT = ();
	like(render("[&$F]"), qr{OGPの説明}, '取得できない');
	is(scalar(@GOT), 2, '拒否でなければMastodon APIは試さない');
};

subtest 'ActivityPubを拒否されたらMastodon API' => sub {
	local $ENV{TZ} = 'Asia/Tokyo';
	my $api = 'https://fedi.test/api/v1/statuses/1234';
	fedi_set(note => { status => 401 });
	$RES{$api} = { status => 200, ctype => 'application/json; charset=utf-8', body => JSON::PP->new->utf8->encode({
		id => '1234', created_at => '2026-11-07T12:36:40.311Z', sensitive => JSON::PP::false(), spoiler_text => '',
		content => '<p>APIの本文</p>',
		account => { username => 'alice', acct => 'alice', display_name => 'アリス', avatar => 'https://fedi.test/a.png' },
		media_attachments => [ { type => 'image', url => 'https://fedi.test/m/1.png', preview_url => 'https://fedi.test/m/1s.png', description => '説明' } ],
	}) };
	@GOT = ();
	my $h = render("[&$F]");
	like($h, qr{data-card="fediverse"}, '投稿のカード');
	like($h, qr{link-card-acct">\@alice\@fedi\.test<}, 'acctにホストを足す');
	like($h, qr{link-card-text">APIの本文<}, '本文');
	like($h, qr{<img alt="説明" src="https://fedi\.test/m/1s\.png">}, 'プレビューの画像');
	like($h, qr{2026/11/07 21:36}, '日時');
	is($GOT[-1]->{url}, $api, 'APIを取得する');

	$RES{$api} = { status => 404 };
	like(render("[&$F]"), qr{OGPの説明}, 'APIも駄目ならOGPのカード');
	delete $RES{$api};
};

subtest 'Fediverseの投稿の概要とRSS' => sub {
	require SatsukiApp::adiary;
	my $app = bless({ ROBJ => $ROBJ, blog => { desc_len => 64 } }, 'SatsukiApp::adiary');
	fedi_set();
	my $html = bytes(render("前の文\n\n[&$F]\n\n後の文\n"));
	my %h = (text => $html);
	$app->set_description(\%h, '');
	my $d = Encode::decode('UTF-8', $h{description});
	like($d, qr{前の文 アリス&lt;b&gt; 後の文}, '概要には表示名だけ');

	my $text = Encode::decode('UTF-8', $app->link_card_to_text($html));
	like($text, qr{<a href="https://fedi\.test/\@alice/1234">アリス&lt;b&gt;</a>}, 'RSSは表示名のリンク');
	unlike($text, qr{一行目|<img|<time|link-card}, 'カードの中身は残らない');
};

#-------------------------------------------------------------------------------
# 前回の保存のカードを使い回す
#-------------------------------------------------------------------------------
# 保存と同じく、前回の本文（TagEscapeの後のバイト列）からカードを拾う
sub saved_cards {
	require SatsukiApp::adiary;
	my $app = bless({ ROBJ => $ROBJ }, 'SatsukiApp::adiary');
	return $app->extract_link_cards(bytes(shift));
}

subtest '前回のカードを使い、取得しない' => sub {
	my $A = 'https://example.test/a?x=1&y=2';
	$RES{$A} = page(q{<title>t</title><meta property="og:title" content="題名 &amp; &lt;記号&gt;">
		<meta property="og:description" content="説明"><meta property="og:image" content="https://example.test/i.png?a=1&amp;b=2">});
	fedi_set();
	my $src = "前の文\n\n[&$A]\n\n[&$F]\n\n後の文\n";
	my $first = render($src);
	like($first, qr{data-card="fediverse"}, '1回目はFediverseのカード');
	like($first, qr{<a class="link-card" href="https://example\.test/a\?x=1&amp;y=2">}, '1回目は&を含むURLのカード');

	my $cards = saved_cards($first);
	is(scalar(keys %$cards), 2, 'カードを2枚拾う');
	@GOT = ();
	my $second = render($src, undef, $cards);
	is(scalar(@GOT), 0, '2回目は通信しない');
	is($second, $first, '2回目も同じHTML');

	@GOT = ();
	is(render($src, undef, saved_cards($second)), $first, 'もう一度通しても変わらない');
	is(scalar(@GOT), 0, '3回目も通信しない');
};

subtest '新しいURLと、前回カードにできなかったURLは取得する' => sub {
	my $A = 'https://example.test/a';
	my $B = 'https://example.test/b';
	$RES{$A} = page('<title>Aの題名</title>');
	delete $RES{$B};
	my $cards = saved_cards(render("[&$A]\n\n[&$B]\n"));
	is(scalar(keys %$cards), 1, '普通のリンクは拾わない');

	$RES{$B} = page('<title>Bの題名</title>');
	my $C = 'https://example.test/c';
	$RES{$C} = page('<title>Cの題名</title>');
	@GOT = ();
	my $h = render("[&$A]\n\n[&$B]\n\n[&$C]\n", undef, $cards);
	is_deeply([ map { $_->{url} } @GOT ], [ $B, $C ], '前回失敗したURLと新しいURLだけ取得する');
	like($h, qr{Aの題名.*Bの題名.*Cの題名}s, 'どれもカードになる');
};

subtest '同じ保存の中では、一度取得したURLを取得しない' => sub {
	my $A = 'https://example.test/a';
	my $B = 'https://example.test/b';
	$RES{$A} = page('<title>Aの題名</title>');
	delete $RES{$B};
	my %cards;	# 保存では、見出しのIDを足すときと本文を作るときの2回パースする
	@GOT = ();
	my $first  = render("[&$A]\n\n[&$A]\n\n[&$B]\n", undef, \%cards);
	my $second = render("[&$A]\n\n[&$A]\n\n[&$B]\n", undef, \%cards);
	is_deeply([ map { $_->{url} } @GOT ], [ $A, $B ], 'どのURLも1回だけ取得する');
	is($second, $first, '2回目も同じHTML');
	like($second, qr{<a href="https://example\.test/b">https://example\.test/b</a>}, '取得できなかったURLは普通のリンクのまま');
};

subtest '前回のカードを渡さなければ取得し直す' => sub {
	my $A = 'https://example.test/a';
	$RES{$A} = page('<title>新しい題名</title>');
	@GOT = ();
	like(render("[&$A]"), qr{新しい題名}, '取得した値を使う');
	is(scalar(@GOT), 1, '取得する');
};

done_testing();
