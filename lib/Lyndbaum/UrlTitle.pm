package Lyndbaum::UrlTitle;
# [&URL] のリンクの文字にする、外部のページのタイトル
#   変換の途中では外へ取りに行かず（CLAUDE.md の「パーサーの方針」）、記事を保存するときに取得して url_cache に入れる
#   変換するときは url_cache を読むだけ（Lyndbaum::App->parser_context の url_title）
use strict;
use warnings;
use utf8;

use Encode qw(find_encoding);
use HTML::Entities qw(decode_entities);
use HTTP::Tiny;
use Lyndbaum::Parser;

my $TIMEOUT   = 5;            # 1件の取得の待ち時間（秒）
my $MAX_SIZE  = 1024 * 1024;  # 読むのは1MBまで
my $MAX_URLS  = 10;           # 1回の保存で取りに行く数
my $RETRY     = 24 * 60 * 60; # 取得に失敗したURLを取り直すまでの秒数
my $MAX_TITLE = 200;

# 本文の [&URL] のうち、まだタイトルを持っていないURLのタイトルを取得して url_cache に入れる
#   取得したURLの数を返す。取得に失敗しても die しない（リンクの文字がURLのままになるだけ）
#   %opt
#     syntax   本文の記法
#     context  変換の設定（Lyndbaum::App->parser_context）
#     fetch    URLを受け取り、HTTP::Tiny->get と同じ形の応答を返す関数（テスト用）
#     agent    User-Agent
#     now      今の時刻（テスト用）
sub fetch_missing {
	my ($class, $dbh, $text, %opt) = @_;
	my $now = $opt{now} // time;

	# 変換して、パーサーがタイトルを求めたURLを集める（埋め込みにするURLは求めないので、取りに行かない）
	my (@urls, %seen);
	Lyndbaum::Parser->parse($opt{syntax} // 'markdown', $text, %{ $opt{context} // {} },
		url_title => sub { push @urls, $_[0] if !$seen{ $_[0] }++; undef });

	my $fetch = $opt{fetch} // do {
		my $http = HTTP::Tiny->new(timeout => $TIMEOUT, max_size => $MAX_SIZE, agent => $opt{agent} // 'Lyndbaum', verify_SSL => 1);
		sub { $http->get($_[0]) };
	};
	my $count = 0;
	for my $url (@urls) {
		last if $count >= $MAX_URLS;
		my $cached = $dbh->selectrow_hashref('SELECT ok, fetched_at FROM url_cache WHERE url = ?', undef, $url);
		next if $cached && ($cached->{ok} || $cached->{fetched_at} > $now - $RETRY);
		my $title = eval { title_of($fetch->($url)) };
		warn "ページのタイトルを取得できませんでした: $url: $@" if $@;
		$dbh->do('INSERT OR REPLACE INTO url_cache (url, title, fetched_at, ok) VALUES (?, ?, ?, ?)', undef,
			$url, $title, $now, defined $title ? 1 : 0);
		$count++;
	}
	return $count;
}

# HTTP::Tiny の応答から、ページのタイトルを取り出す。HTMLでないか、タイトルが無ければ undef
sub title_of {
	my ($res) = @_;
	return undef if !$res->{success};
	my $type = $res->{headers}{'content-type'} // '';
	$type = join ',', @$type if ref $type;
	return undef if $type !~ m{\A\s*(?:text/html|application/xhtml\+xml)}i;

	my $bytes = $res->{content} // '';
	my ($raw) = $bytes =~ m{<title[^>]*>(.*?)</title\s*>}is or return undef;
	my $charset = ($type =~ /charset\s*=\s*["']?([\w.:-]+)/i)[0]
		// ($bytes =~ /<meta[^>]+charset\s*=\s*["']?([\w.:-]+)/i)[0]
		// 'UTF-8';
	my $encoding = find_encoding($charset) // find_encoding('UTF-8');
	my $title = decode_entities($encoding->decode($raw));
	$title =~ s/\s+/ /g;
	$title =~ s/\A | \z//g;
	$title =~ s/[\x00-\x1F\x7F]//g;
	return undef if $title eq '';
	return length $title > $MAX_TITLE ? substr($title, 0, $MAX_TITLE) . '…' : $title;
}

1;
