# ブログの設定の「<head>に入れるHTML」（head_html。Lyndbaum::BlogSettings、templates/layout.html）
use strict;
use warnings;
use utf8;
use Test::More;

use Lyndbaum::Model::Setting;
use AdminTest;

my $t = AdminTest->new;
my $dbh = $t->dbh;
my ($cookie) = $t->login;
my $csrf = $t->csrf_of($cookie);

my $script = qq{<!-- 解析 -->\n<script>\n  var _paq = window._paq || [];\n  if (1 < 2 && "a") _paq.push(['trackPageView']);\n</script>};

subtest '保存' => sub {
	my %form = (csrf_token => $csrf, blog_title => 'ブログ', blog_description => '', blog_author => '', per_page => 5, feed_items => 10);
	my $res = $t->request(POST => '/admin/settings/blog', cookie => $cookie, body => [ %form, head_html => "\r\n\r\n" . ($script =~ s/\n/\r\n/gr) . "\r\n  \r\n" ]);
	is $res->status, 303;
	is(Lyndbaum::Model::Setting->all($dbh)->{head_html}, $script, '改行は LF にそろえ、前後の空白行は除く');

	$res = $t->request(GET => '/admin/settings/blog', cookie => $cookie);
	like $res->body, qr{<textarea name="head_html"[^>]*>\Q&lt;!-- 解析 --&gt;\E}, '設定の画面ではエスケープして出す';
	unlike $res->body, qr{\Q$script\E}, '管理画面の <head> には入れない';

	$res = $t->request(POST => '/admin/settings/blog', cookie => $cookie, body => [ %form, head_html => 'x' x 10001 ]);
	is $res->status, 400;
	like $res->body, qr{&lt;head&gt;に入れるHTMLは10000文字までにしてください。};
	is(Lyndbaum::Model::Setting->all($dbh)->{head_html}, $script, '保存できなければ変えない');
};

subtest '公開側のページ' => sub {
	my $res = $t->request(GET => '/');
	is $res->status, 200;
	like $res->body, qr{\Q$script\E\n</head>}, '</head> の前にそのまま出す';

	Lyndbaum::Model::Setting->set($dbh, head_html => '');
	$res = $t->request(GET => '/');
	like $res->body, qr{type="application/rss\+xml"[^>]*>\n</head>}, '空なら何も出さない';
};

done_testing;
