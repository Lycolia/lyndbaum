# [&URL] のページのタイトルの取得（Lyndbaum::UrlTitle）
use strict;
use warnings;
use utf8;
use Test::More;

use Encode qw(encode);
use Lyndbaum::Parser;
use Lyndbaum::UrlTitle;
use TestUtil qw(new_test_app);

# 取得に失敗したときの記録（warn）は、テストの出力に混ぜない
local $SIG{__WARN__} = sub { warn @_ if $_[0] !~ /ページのタイトルを取得できませんでした/ };

my $app = new_test_app();
my $dbh = $app->db;
my %context = $app->parser_context;

sub html {
	my ($body, %opt) = @_;
	return { success => 1, status => 200, headers => { 'content-type' => $opt{type} // 'text/html; charset=UTF-8' }, content => $body };
}

subtest 'タイトルを取り出す' => sub {
	is Lyndbaum::UrlTitle::title_of(html(encode('UTF-8', "<html><head><title>\n  題名 &amp; 説明\n</title>"))), '題名 & 説明',
		'文字参照を戻し、空白をまとめる';
	is Lyndbaum::UrlTitle::title_of(html(encode('Shift_JIS', '<title>日本語</title>'), type => 'text/html; charset=Shift_JIS')), '日本語',
		'Content-Type の charset';
	is Lyndbaum::UrlTitle::title_of(html(encode('EUC-JP', '<meta charset="EUC-JP"><title>日本語</title>'), type => 'text/html')), '日本語',
		'meta の charset';
	is Lyndbaum::UrlTitle::title_of(html('<title>x</title>', type => 'application/pdf')), undef, 'HTMLでない';
	is Lyndbaum::UrlTitle::title_of(html('<title> </title>')), undef, '空のタイトル';
	is Lyndbaum::UrlTitle::title_of({ success => 0, status => 404, headers => {} }), undef, '取得に失敗';
	is length Lyndbaum::UrlTitle::title_of(html('<title>' . ('a' x 300) . '</title>')), 201, '200文字で切る';
};

subtest '保存のときに取得する' => sub {
	my @fetched;
	my %pages = (
		'https://example.com/a' => html(encode('UTF-8', '<title>ページA</title>')),
		'https://example.com/b' => { success => 0, status => 500, headers => {} },
	);
	my $fetch = sub { push @fetched, $_[0]; $pages{ $_[0] } };
	my $text = "[&https://example.com/a] [&https://example.com/a] [&https://example.com/b]\n\n[&https://www.youtube.com/watch?v=abc]";
	is(Lyndbaum::UrlTitle->fetch_missing($dbh, $text, context => \%context, fetch => $fetch, now => 1000), 2);
	is_deeply \@fetched, ['https://example.com/a', 'https://example.com/b'], '同じURLは1回だけ。埋め込みにするURLは取りに行かない';
	is_deeply $dbh->selectall_arrayref('SELECT url, title, ok FROM url_cache ORDER BY url'),
		[ ['https://example.com/a', 'ページA', 1], ['https://example.com/b', undef, 0] ];
	like(Lyndbaum::Parser->parse('markdown', $text, %context)->{html}, qr{<a href="https://example\.com/a">ページA</a>}, '変換するとリンクの文字になる');

	@fetched = ();
	Lyndbaum::UrlTitle->fetch_missing($dbh, $text, context => \%context, fetch => $fetch, now => 2000);
	is_deeply \@fetched, [], '取得したものと、失敗してから1日たっていないものは取りに行かない';
	Lyndbaum::UrlTitle->fetch_missing($dbh, $text, context => \%context, fetch => $fetch, now => 1000 + 24 * 60 * 60 + 1);
	is_deeply \@fetched, ['https://example.com/b'], '失敗してから1日たてば取り直す';
};

done_testing;
