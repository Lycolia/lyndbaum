use strict;
use warnings;
use utf8;
use Test::More;

use File::Copy qw(copy);
use File::Path qw(make_path);
use File::Spec;
use File::Temp qw(tempdir);
use Lyndbaum::SidebarCache;
use Lyndbaum::Model::Tag;
use Lyndbaum::Model::Comment;
use Lyndbaum::Model::Setting;
use AdminTest;
use TestUtil qw(new_test_app insert_article root_dir);

sub count_cache { $_[0]->selectrow_array('SELECT COUNT(*) FROM sidebar_cache') }

sub fixture {
	my $app = new_test_app();
	insert_article($app->db, id => 1, title => '<初めの記事>', published_at => 1700000000);
	insert_article($app->db, id => 2, kind => 'page', slug => 'about', title => '自己紹介');
	my ($tag) = Lyndbaum::Model::Tag->ensure_path($app->db, '親', '子');
	Lyndbaum::Model::Tag->rebuild_paths($app->db);
	$app->db->do('INSERT INTO article_tags (article_id, tag_id) VALUES (1, ?)', undef, $tag);
	Lyndbaum::Model::Comment->create($app->db, article_id => 1, status => 'public', by_admin => 0,
		author_name => '<読者>', body => 'コメント', ip => '', host => '', user_agent => '');
	return $app;
}

subtest '別のリクエストでは集計も部品の描画もしない' => sub {
	my $app = fixture();
	my $expected = Lyndbaum::SidebarCache->get($app);
	like $expected->{sidebar_tags}, qr/親/;
	like $expected->{sidebar_menu}, qr/&lt;初めの記事&gt;/, '題名をエスケープする';
	like $expected->{sidebar_menu}, qr/&lt;読者&gt;/, 'コメントの名前をエスケープする';
	my $next = Lyndbaum::App->new(root => $app->{root}, config => $app->config);
	my $cli = Lyndbaum::App->new(root => "$app->{root}/tools/..", config => $app->config);
	{
		no warnings 'redefine';
		local *Lyndbaum::View::tag_tree = sub { die 'タグを再集計した' };
		local *Lyndbaum::View::content_tree = sub { die 'ページを再集計した' };
		local *Lyndbaum::View::recent_posts = sub { die '記事を再取得した' };
		local *Lyndbaum::View::recent_comments = sub { die 'コメントを再取得した' };
		local *Lyndbaum::View::archive = sub { die '過去ログを再集計した' };
		local *Lyndbaum::SidebarBoxes::for_display = sub { die '自由欄を再変換した' };
		local *Lyndbaum::Template::render = sub { die '部品を再描画した' };
		is_deeply(Lyndbaum::SidebarCache->get($next), $expected);
		is_deeply(Lyndbaum::SidebarCache->get($cli), $expected, 'CLIとWebで同じルートのキャッシュを共有する');
	}
	my $res = $next->handle({ REQUEST_METHOD => 'GET', PATH_INFO => '/search', QUERY_STRING => 'q=test&in=source' });
	like $res->body, qr{<option value="source" selected}, '検索範囲はキャッシュせず現在の入力を使う';
};

subtest '記事・ページ・タグ・コメントの更新を反映する' => sub {
	my $app = fixture();
	my $dbh = $app->db;
	Lyndbaum::SidebarCache->get($app);
	$dbh->do(q{UPDATE articles SET title = '新しい題名', published_at = 1735689600 WHERE id = 1});
	is count_cache($dbh), 0, '直接SQLによる更新も無効化する';
	my $html = Lyndbaum::SidebarCache->get($app)->{sidebar_menu};
	like $html, qr/新しい題名/;
	unlike $html, qr/&lt;初めの記事&gt;/;
	like $html, qr/2025年01月/;
	$dbh->do(q{UPDATE tags SET name = '変更したタグ' WHERE name = '子'});
	like(Lyndbaum::SidebarCache->get($app)->{sidebar_tags}, qr/変更したタグ/, 'アプリ内の古いタグも使わない');
	$dbh->do('DELETE FROM article_tags');
	is(Lyndbaum::SidebarCache->get($app)->{sidebar_tags}, '', '最後の記事との対応を消すとタグも消える');
	$dbh->do(q{UPDATE articles SET slug = 'profile', title = 'プロフィール' WHERE id = 2});
	like(Lyndbaum::SidebarCache->get($app)->{sidebar_menu}, qr{href="/profile">プロフィール}, 'ページのURLと題名を更新する');
	Lyndbaum::Model::Comment->set_status($dbh, 1, 'held');
	unlike(Lyndbaum::SidebarCache->get($app)->{sidebar_menu}, qr/最近のコメント/, '承認の取り消しを反映する');
	Lyndbaum::Model::Comment->set_status($dbh, 1, 'public');
	like(Lyndbaum::SidebarCache->get($app)->{sidebar_menu}, qr/最近のコメント/);
	Lyndbaum::Model::Comment->delete($dbh, 1);
	unlike(Lyndbaum::SidebarCache->get($app)->{sidebar_menu}, qr/最近のコメント/);
	Lyndbaum::Model::Article->move_to_trash($dbh, [1]);
	unlike(Lyndbaum::SidebarCache->get($app)->{sidebar_menu}, qr/新しい題名/);
	Lyndbaum::Model::Article->restore($dbh, [1]);
	like(Lyndbaum::SidebarCache->get($app)->{sidebar_menu}, qr/新しい題名/);
	$dbh->do(q{UPDATE articles SET status = 'draft' WHERE id = 1});
	unlike(Lyndbaum::SidebarCache->get($app)->{sidebar_menu}, qr/新しい題名/, '非公開にした記事を残さない');
};

subtest '更新のロールバックでキャッシュも元に戻る' => sub {
	my $app = fixture();
	my $expected = Lyndbaum::SidebarCache->get($app);
	$app->db->begin_work;
	$app->db->do(q{UPDATE articles SET title = '取り消す更新' WHERE id = 1});
	is count_cache($app->db), 0;
	$app->db->rollback;
	is count_cache($app->db), 1;
	is_deeply(Lyndbaum::SidebarCache->get($app), $expected);
};

subtest 'POSTの完了時にHTMLを保存し、匿名閲覧でも同じものを使う' => sub {
	my $t = AdminTest->new;
	my ($cookie) = $t->login;
	my $csrf = $t->csrf_of($cookie);
	my $res = $t->request(POST => '/admin/sidebar', cookie => $cookie, body => [
		csrf_token => $csrf, box_title => '<お知らせ>', box_html => '<b>新しい自由欄</b><script>x</script>',
	]);
	is $res->status, 303;
	is count_cache($t->dbh), 1, '次のGETより前に再生成してある';
	my ($html) = $t->dbh->selectrow_array('SELECT menu_html FROM sidebar_cache');
	like $html, qr/&lt;お知らせ&gt;/;
	like $html, qr{<b>新しい自由欄</b>};
	unlike $html, qr{<script>}, '自由欄の許可リストを維持する';
	unlike $html, qr/csrf_token|admin-bar/, '管理者情報は保存しない';
	like $t->request(GET => '/')->body, qr{<b>新しい自由欄</b>};
};

subtest 'URL設定やテンプレート変更でも再生成する' => sub {
	my $app = fixture();
	Lyndbaum::SidebarCache->get($app);
	my $config = Lyndbaum::Config->new(%{ $app->config }, base_path => '/blog');
	my $other = Lyndbaum::App->new(root => $app->{root}, config => $config);
	like(Lyndbaum::SidebarCache->get($other)->{sidebar_menu}, qr{href="/blog/about"}, '別のbase_pathのHTMLを使わない');
	my $dir = tempdir(CLEANUP => 1);
	make_path("$dir/templates");
	# キャッシュキーに使うソースを複製し、実際のリポジトリには触れずに更新を試す
	for my $file (glob(root_dir() . '/templates/*.html'), glob(root_dir() . '/lib/Lyndbaum/*.pm'), glob(root_dir() . '/lib/Lyndbaum/Model/*.pm')) {
		my $relative = File::Spec->abs2rel($file, root_dir());
		my (undef, $parent) = File::Spec->splitpath("$dir/$relative");
		make_path($parent);
		copy($file, "$dir/$relative") or die $!;
	}
	my $copy = Lyndbaum::App->new(root => $dir, config => $app->config);
	Lyndbaum::SidebarCache->get($copy);
	open my $fh, '>>:encoding(UTF-8)', "$dir/templates/sidebar_menu.html" or die $!;
	print $fh '<p>変更したテンプレート</p>';
	close $fh;
	like(Lyndbaum::SidebarCache->get($copy)->{sidebar_menu}, qr/変更したテンプレート/);
};

done_testing;
