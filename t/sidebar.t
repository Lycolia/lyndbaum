# 公開側のサイドバー：自由欄、最近の記事、過去ログ（docs/admin.md の「サイドバーの自由欄」）
use strict;
use warnings;
use utf8;
use Test::More;

use Lyndbaum::HTML qw(sanitize_html);
use Lyndbaum::Model::Setting;
use Lyndbaum::SidebarBoxes;
use AdminTest;
use TestUtil qw(insert_article);

my $t = AdminTest->new;
my $dbh = $t->dbh;
sub header { AdminTest::header(@_) }

# 2025-12-31 15:30 UTC は日本時間で 2026-01-01
insert_article($dbh, id => 1, title => '去年の記事', published_at => 1735689600 - 9 * 3600 + 3600);   # 2025-01-01 01:00 JST
insert_article($dbh, id => 2, title => '年越しの記事', published_at => 1767195000);                  # 2026-01-01 00:30 JST
insert_article($dbh, id => 3, title => '新しい記事', published_at => 1780000000);                    # 2026-05-28 JST
insert_article($dbh, id => 4, title => '下書き', status => 'draft');
insert_article($dbh, id => 10, kind => 'page', slug => 'about', title => 'このサイトについて', published_at => 1780000100);

subtest 'HTMLを許可リストに通す' => sub {
	is sanitize_html('<p>a & b &amp; <b>太字</p>'), '<p>a &amp; b &amp; <b>太字</b></p>', '閉じていないタグを閉じる。裸の & を直す';
	is sanitize_html('<script>alert(1)</script>'), '&lt;script&gt;alert(1)&lt;/script&gt;', '許可しないタグは文字にする';
	is sanitize_html('<img src="https://x.example/c.cgi" onerror="x" width="315">'), '<img src="https://x.example/c.cgi" width="315">', '許可しない属性は消す';
	is sanitize_html('<a href="javascript:x">l</a>'), '<a>l</a>', '安全でないURLは消す';
	is sanitize_html('前</div>後<!-- メモ -->'), '前後', '対応の無い閉じタグとコメントは消す';
	is sanitize_html('<ul><li>x'), '<ul><li>x</li></ul>';
	is sanitize_html('1 < 2 > 0'), '1 &lt; 2 &gt; 0';
};

subtest '欄の確かめ' => sub {
	my ($boxes, $errors) = Lyndbaum::SidebarBoxes->parse_form([' Information ', '', '', 'カウンター'], ["紹介\r\n", '', '中身だけ', '']);
	is_deeply $boxes, [ { title => 'Information', html => '紹介' }, { title => '', html => '中身だけ' }, { title => 'カウンター', html => '' } ],
		'題名も中身も空の欄は捨てる';
	is_deeply $errors, ['2番目の欄の題名を書いてください。'];
	is_deeply(Lyndbaum::SidebarBoxes->decode('壊れた値'), [], '壊れた値は空');
};

my ($cookie) = $t->login;
my $csrf = $t->csrf_of($cookie);

subtest '管理画面' => sub {
	my $res = $t->request(GET => '/admin/sidebar', cookie => $cookie);
	is $res->status, 200;
	like $res->body, qr{<legend>新しい欄</legend>}, '空の欄を1つ出す';
	$res = $t->request(POST => '/admin/sidebar', cookie => $cookie, body => [
		csrf_token => $csrf,
		box_title => 'Information', box_html => '<p>雑記帳です。</p><script>x</script>',
		box_title => 'カウンター',  box_html => '<img src="https://counter.example/c.cgi" alt="">',
		box_title => '',            box_html => '',
	]);
	is header($res, 'Location'), '/admin/sidebar?saved=1';
	is_deeply(Lyndbaum::SidebarBoxes->decode(Lyndbaum::Model::Setting->all($dbh)->{sidebar_boxes}), [
		{ title => 'Information', html => '<p>雑記帳です。</p><script>x</script>' },
		{ title => 'カウンター', html => '<img src="https://counter.example/c.cgi" alt="">' },
	], '書いたまま保存する');

	$res = $t->request(POST => '/admin/sidebar', cookie => $cookie, body => [ csrf_token => $csrf, box_title => '', box_html => '中身' ]);
	is $res->status, 400;
	like $res->body, qr{1番目の欄の題名を書いてください。};
	like $res->body, qr{<textarea name="box_html" rows="6">中身</textarea>}, '書いた値を残す';

	is $t->request(POST => '/admin/sidebar', cookie => $cookie, body => [ box_title => 'x', box_html => 'y' ])->status, 403, 'CSRFトークンが無ければ断る';
};

subtest '公開側' => sub {
	my $body = $t->request(GET => '/')->body;
	my ($left)  = $body =~ m{<aside class="site-sidebar sidebar-left">(.*?)</aside>}s;
	my ($right) = $body =~ m{<aside class="site-sidebar sidebar-right">(.*?)</aside>}s;
	like $left, qr{<h2>検索</h2>}, '左は検索とタグ';
	like $right, qr{<h2>コンテンツ</h2>.*<h2>Information</h2>.*<h2>カウンター</h2>.*<h2>最近の記事</h2>.*<h2>過去ログ</h2>}s, '右の並び';
	like $right, qr{<div class="sidebar-box-body"><p>雑記帳です。</p>&lt;script&gt;x&lt;/script&gt;</div>}, '自由欄は許可リストに通して出す';

	my @posts = $right =~ m{<ul class="recent-posts">(.*?)</ul>}s;
	is_deeply [ $posts[0] =~ m{<a href="[^"]*">([^<]*)</a>}g ], ['新しい記事', '年越しの記事', '去年の記事'], '最近の記事：新しい順。下書きとコンテンツページは出さない';

	my ($archive) = $right =~ m{<ul class="archive">(.*)</ul>}s;
	like $archive, qr{<details open>\s*<summary><a href="/search\?d=2026">2026年</a> <span class="count">\(2\)</span></summary>}, 'いちばん新しい年は開く。コンテンツページは数えない（旧システムと同じ）';
	like $archive, qr{<a href="/search\?d=202605">2026年05月</a> <span class="count">\(1\)</span>.*<a href="/search\?d=202601">2026年01月</a> <span class="count">\(1\)</span>}s, '月は新しい順。日本時間で数える';
	like $archive, qr{<details>\s*<summary><a href="/search\?d=2025">2025年</a> <span class="count">\(1\)</span></summary>}, 'ほかの年は閉じる';
};

done_testing;
