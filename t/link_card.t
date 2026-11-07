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
		my ($self, $url) = @_;
		push(@GOT, { url => $url, timeout => $self->{timeout}, redirect => $self->{redirect}, max_size => $self->{max_size} });
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
	my ($text, $pkey) = @_;
	my $md = new_parser();
	$md->{satsuki_obj}->{ROBJ}->{CodeLib} = 'Jcode';	# 本番の設定と同じ
	$md->{thispkey} = $pkey if (defined $pkey);
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

done_testing();
