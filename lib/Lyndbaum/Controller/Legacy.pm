package Lyndbaum::Controller::Legacy;
# 旧システムのURLからの転送。対応は docs/legacy-urls.md を参照
#   ページ送り /?p=2                      → /?page=2
#   タグ      /?t=言語::C%23.NET          → /search?t=言語::C%23.NET
#   検索      /?q=語&all=1&t=…&t=…&d=…    → /search?q=語&in=source&t=…&t=…&d=…
# 記事とコンテンツページのURLは旧システムと同じなので、転送しない
use strict;
use warnings;
use utf8;


# トップページへの旧形式のクエリ（t, d, q, all, p）を転送する。旧形式でなければ undef
#   タグ、日付、検索語のどれかがあれば検索へ。ページ送りだけならトップページへ
#   旧システムの all は検索の範囲。0 か無しならタイトル、1 なら全文（旧システムは原文を探していたので、原文にする）
sub redirect_query {
	my ($class, $app, $req) = @_;
	my @tags = $req->params('t');
	my $page = $req->param('p');
	my $q    = $req->param('q') // '';
	my $d    = $req->param('d') // '';
	return undef if !@tags && !defined $page && $q eq '' && $d eq '';

	$page = defined $page && $page =~ /\A[1-9]\d{0,8}\z/ && $page > 1 ? $page : undef;
	return $app->redirect($app->url->top(page => $page)) if !@tags && $q eq '' && $d eq '';
	return $app->redirect($app->url->search(
		q    => $q,
		in   => $q eq '' ? undef : ($req->param('all') // '') eq '1' ? 'source' : 'title',
		t    => [ map { [ split /::/, $_ ] } @tags ],
		d    => $d,
		page => $page,
	));
}

1;
