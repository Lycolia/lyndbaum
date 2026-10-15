# OGP（docs/ogp.md）
use strict;
use warnings;
use utf8;
use Test::More;

use File::Spec;
use File::Temp qw(tempdir);
use Lyndbaum::App;
use Lyndbaum::Config;
use Lyndbaum::Model::Article;
use Lyndbaum::Model::Setting;
use Lyndbaum::OGP;
use AdminTest;
use TestUtil qw(insert_article);

my $t = AdminTest->new;
$t->{app} = Lyndbaum::App->new(root => $t->app->{root}, config => Lyndbaum::Config->new(%{ $t->app->config },
	site_url => 'https://blog.example/', feed_file => File::Spec->catfile(tempdir(CLEANUP => 1), 'rss.xml')));
my $dbh = $t->dbh;
sub header { AdminTest::header(@_) }
Lyndbaum::Model::Setting->set($dbh, blog_description => 'ブログの説明');
Lyndbaum::Model::Setting->set($dbh, blog_image => '@system/blog.png');

insert_article($dbh, id => 1, title => '画像のある記事', body_src => "前置き\n\n[image:S:posts/2026/10/:a b.png:代替]\n\n![図](/pub/attachments/posts/2026/10/c.png)");
insert_article($dbh, id => 2, title => '画像の無い記事', body_src => '本文だけ');
insert_article($dbh, id => 3, title => '選んだ画像', body_src => '[image:S:posts/2026/10/:a.png]', og_image => 'posts/2026/09/x.jpg', og_image_mode => 'chosen');
insert_article($dbh, id => 4, title => '使わない', body_src => '[image:S:posts/2026/10/:a.png]', og_image_mode => 'none');
insert_article($dbh, id => 5, title => '下書き', status => 'draft');
Lyndbaum::Model::Article->rebuild_all($dbh, $t->app->parser_context);

# ページの <head> の OGP を { キー => 値 } で返す
sub ogp {
	my ($res) = @_;
	my %tags = $res->body =~ m{<meta (?:property|name)="((?:og|twitter):[^"]+)" content="([^"]*)">}g;
	return \%tags;
}

subtest '最初の画像' => sub {
	is(Lyndbaum::OGP->first_image('<p><a href="/pub/attachments/a.png" class="tag-image-S"><img src="/pub/attachments/.thumbnail/a.png.jpg"></a></p>'),
		'/pub/attachments/a.png', 'サムネイルを元の画像へのリンクで囲んでいれば、元の画像');
	is(Lyndbaum::OGP->first_image('<p><img alt="" src="/x/y.png?a=1&amp;b=2"></p><img src="/z.png">'), '/x/y.png?a=1&b=2', '最初の img。文字参照を戻す');
	is(Lyndbaum::OGP->first_image('<p><a href="/page">リンク</a> <img src="/z.png"></p>'), '/z.png', '画像でないリンクは見ない');
	is(Lyndbaum::OGP->first_image('<p>画像なし</p>'), undef);
};

subtest '記事' => sub {
	my $res = $t->request(GET => '/01');
	my $tags = ogp($res);
	is $tags->{'og:type'}, 'article';
	is $tags->{'og:url'}, 'https://blog.example/01', 'site_url の末尾の / は重ねない';
	is $tags->{'og:title'}, '画像のある記事';
	is $tags->{'og:description'}, '前置き', '記事の説明（本文の文章の頭）';
	is $tags->{'og:image'}, 'https://blog.example/pub/attachments/posts/2026/10/a%20b.png', '自動：本文の最初の画像（元の画像）を絶対URLにする';
	is $tags->{'og:site_name'}, 'テストのブログ';
	is $tags->{'og:locale'}, 'ja_JP';
	is $tags->{'twitter:card'}, 'summary_large_image', '記事の画像があれば大きなカード';
	is $tags->{'twitter:image'}, $tags->{'og:image'};
	ok !exists $tags->{'twitter:url'}, 'twitter:url は出さない（仕様に無い）';
	like $res->body, qr{<link rel="canonical" href="https://blog\.example/01">};
	like $res->body, qr{<meta name="description" content="前置き">}, 'meta description も記事の説明';

	$tags = ogp($t->request(GET => '/02'));
	is $tags->{'og:image'}, 'https://blog.example/pub/attachments/%40system/blog.png', '画像が無ければブログの画像';
	is $tags->{'twitter:card'}, 'summary';
	is ogp($t->request(GET => '/03'))->{'og:image'}, 'https://blog.example/pub/attachments/posts/2026/09/x.jpg', '選んだ画像';
	$tags = ogp($t->request(GET => '/04'));
	is $tags->{'og:image'}, 'https://blog.example/pub/attachments/%40system/blog.png', '使わない：ブログの画像';
	is $tags->{'twitter:card'}, 'summary';

	Lyndbaum::Model::Setting->set($dbh, blog_image => '');
	$tags = ogp($t->request(GET => '/02'));
	ok !exists $tags->{'og:image'}, 'ブログの画像も無ければ、og:image を出さない';
	Lyndbaum::Model::Setting->set($dbh, blog_image => '@system/blog.png');
};

subtest 'トップページ' => sub {
	my $res = $t->request(GET => '/');
	my $tags = ogp($res);
	is $tags->{'og:type'}, 'website';
	is $tags->{'og:url'}, 'https://blog.example/';
	is $tags->{'og:title'}, 'テストのブログ';
	is $tags->{'og:description'}, 'ブログの説明';
	is $tags->{'og:image'}, 'https://blog.example/pub/attachments/%40system/blog.png';
	like $res->body, qr{<meta name="description" content="ブログの説明">};
	unlike ogp($t->request(GET => '/search?q=x'))->{'og:type'} // '', qr{.}, '検索の結果には出さない';
};

subtest 'site_url が無ければリクエストのホスト名から' => sub {
	local $t->{app} = Lyndbaum::App->new(root => $t->app->{root}, config => Lyndbaum::Config->new(%{ $t->app->config }, site_url => undef));
	is ogp($t->request(GET => '/02'))->{'og:url'}, 'https://blog.example/02';
};

my ($cookie) = $t->login;
my $csrf = $t->csrf_of($cookie);
sub post {
	my ($path, %form) = @_;
	my %all = (csrf_token => $csrf, title => '題名', body => '本文', status => 'draft', comments_open => '1', %form);
	return $t->request(POST => $path, cookie => $cookie, body => [ %all ]);
}

subtest '編集の画面' => sub {
	my $res = $t->request(GET => '/admin/articles/1', cookie => $cookie);
	like $res->body, qr{<input type="radio" name="og_image_mode" value="auto" checked>}, '既定は自動';
	like $res->body, qr{data-auto="/pub/attachments/posts/2026/10/a%20b\.png"}, '自動のときの画像';
	like $res->body, qr{<img src="/pub/attachments/posts/2026/10/a%20b\.png" alt="OGPの画像">};
	like $t->request(GET => '/admin/articles/3', cookie => $cookie)->body, qr{<input type="hidden" name="og_image" value="posts/2026/09/x\.jpg">};

	my $digest = Lyndbaum::Model::Article->digest($dbh, 2);
	$res = post('/admin/articles/2', title => '画像の無い記事', og_image_mode => 'chosen', og_image => 'posts/2026/10/a.png', digest => $digest);
	is $res->status, 303;
	is_deeply $dbh->selectrow_arrayref('SELECT og_image_mode, og_image FROM articles WHERE id = 2'), ['chosen', 'posts/2026/10/a.png'];

	$res = post('/admin/articles/2', title => '画像の無い記事', og_image_mode => 'none', og_image => 'posts/2026/10/a.png', digest => Lyndbaum::Model::Article->digest($dbh, 2));
	is_deeply $dbh->selectrow_arrayref('SELECT og_image_mode, og_image FROM articles WHERE id = 2'), ['none', ''], '選んでいなければ画像は持たない';

	$res = post('/admin/articles/2', title => '画像の無い記事', og_image_mode => 'chosen', og_image => '');
	is $res->status, 400;
	like $res->body, qr{OGPの画像を選んでください。};
	$res = post('/admin/articles/2', title => '画像の無い記事', og_image_mode => 'chosen', og_image => '../etc/passwd');
	like $res->body, qr{OGPの画像のパスが正しくありません。};
};

subtest 'ブログの設定' => sub {
	my $res = $t->request(GET => '/admin/settings/blog', cookie => $cookie);
	is $res->status, 200;
	like $res->body, qr{<input type="text" name="blog_image" value="\@system/blog\.png" maxlength="300">};
	like $res->body, qr{<button type="button" class="media-field" data-target="blog_image" data-base="/admin/media">メディアから選ぶ</button>};
	my %form = (csrf_token => $csrf, blog_title => ' 新しい名前 ', blog_description => '説明', blog_author => '', blog_image => '@system/new.png', per_page => 10, feed_items => 20);
	$res = $t->request(POST => '/admin/settings/blog', cookie => $cookie, body => [ %form ]);
	is header($res, 'Location'), '/admin/settings/blog?saved=1';
	my $settings = Lyndbaum::Model::Setting->all($dbh);
	is_deeply [ @$settings{qw(blog_title blog_image per_page)} ], ['新しい名前', '@system/new.png', 10];

	$res = $t->request(POST => '/admin/settings/blog', cookie => $cookie, body => [ %{ { %form, blog_title => '', blog_image => '../x.png' } } ]);
	is $res->status, 400;
	like $res->body, qr{ブログの名前を書いてください。};
	like $res->body, qr{ブログの画像の書き方が正しくありません。};
};

done_testing;
