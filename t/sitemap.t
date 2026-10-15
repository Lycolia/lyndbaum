# サイトマップ（Lyndbaum::Sitemap、Lyndbaum::StaticFiles。docs/feed.md の「サイトマップ」）
use strict;
use warnings;
use utf8;
use Test::More;

use Encode qw(decode_utf8);
use File::Spec;
use Lyndbaum::App;
use Lyndbaum::Config;
use Lyndbaum::Sitemap;
use Lyndbaum::StaticFiles;
use AdminTest;
use TestUtil qw(insert_article);

my $t = AdminTest->new;
$t->{app} = Lyndbaum::App->new(root => $t->app->{root}, config => Lyndbaum::Config->new(%{ $t->app->config }, site_url => 'https://blog.example/'));
my $dbh = $t->dbh;
my $file = $t->app->config->get('sitemap_file');

insert_article($dbh, id => 2, title => '二つ目', updated_at => 1700000200);
insert_article($dbh, id => 1, title => '一つ目', updated_at => 1700000100);
insert_article($dbh, id => 3, kind => 'page', slug => '親/子 ページ', title => 'ページ', updated_at => 1700000300);
insert_article($dbh, id => 4, title => '下書き', status => 'draft', updated_at => 1800000000);
insert_article($dbh, id => 5, title => 'ゴミ箱', deleted_at => 1, updated_at => 1800000000);

subtest '中身' => sub {
	my $xml = decode_utf8(Lyndbaum::Sitemap->xml($t->app));
	like $xml, qr{\A<\?xml version="1\.0" encoding="UTF-8"\?>\n<urlset xmlns="http://www\.sitemaps\.org/schemas/sitemap/0\.9">\n};
	my @locs = $xml =~ m{<loc>([^<]+)</loc>}g;
	is_deeply \@locs, [
		'https://blog.example/',
		'https://blog.example/01',
		'https://blog.example/02',
		'https://blog.example/%E8%A6%AA/%E5%AD%90%20%E3%83%9A%E3%83%BC%E3%82%B8',
	], 'トップページと、公開している記事とコンテンツページを ID の順に（下書きとゴミ箱の中は入れない）';
	my @lastmods = $xml =~ m{<lastmod>([^<]+)</lastmod>}g;
	is_deeply \@lastmods, ['2023-11-14T22:18:20+00:00', '2023-11-14T22:15:00+00:00', '2023-11-14T22:16:40+00:00', '2023-11-14T22:18:20+00:00'],
		'更新日時（UTC）。トップページは、いちばん新しい記事の更新日時';
	unlike $xml, qr{<changefreq>|<priority>}, 'changefreq と priority は入れない';
	like $xml, qr{</urlset>\n\z};
};

subtest '書き出し' => sub {
	unlink $file;
	is_deeply(Lyndbaum::StaticFiles->write_all($t->app), [], 'RSS とサイトマップを書き出す');
	ok -f $file;
	ok -f $t->app->config->get('feed_file');

	my $broken = Lyndbaum::App->new(root => $t->app->{root}, config => Lyndbaum::Config->new(%{ $t->app->config }, site_url => undef));
	my $errors = Lyndbaum::StaticFiles->write_all($broken);
	is scalar @$errors, 2, '書き出せなかったものの理由を返す';
	like $errors->[0], qr{site_url};
};

subtest '記事を保存したら書き出す' => sub {
	local $SIG{__WARN__} = sub { warn @_ if $_[0] !~ /書き出せませんでした/ };
	unlink $file;
	my ($cookie) = $t->login;
	my $res = $t->request(POST => '/admin/articles', cookie => $cookie,
		body => [ csrf_token => $t->csrf_of($cookie), title => '新しい記事', body => '本文', status => 'published', comments_open => 1 ]);
	is $res->status, 303;
	open my $fh, '<:raw', $file or die "$file: $!";
	like decode_utf8(do { local $/; <$fh> }), qr{<loc>https://blog\.example/06</loc>}, '新しい記事が入る';
	is $t->app->url->sitemap, '/pub/sitemap.xml';
};

done_testing;
