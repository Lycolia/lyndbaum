# 通常の閲覧が、検索実行・認証・投稿用のモジュールを巻き込まないことを確かめる
use strict;
use warnings;
use utf8;
use Test::More;

use TestUtil qw(new_test_app insert_article);

my $app = new_test_app();
insert_article($app->db, id => 7, title => '公開記事', body_html => '<p>本文</p>');

for my $path ('/', '/07') {
	subtest "匿名で閲覧する $path" => sub {
		my $res = $app->handle({ REQUEST_METHOD => 'GET', PATH_INFO => $path });
		is $res->status, 200;
		like $res->body, qr{<option value="text" selected}, '検索フォームを表示する';
		for my $module (qw(
			Controller/Search Model/Search Highlight Model/Session Password
			AddressMatch Multipart Controller/Admin Media Parser Parser/Markdown
		)) {
			ok !exists $INC{"Lyndbaum/$module.pm"}, "$module は未ロード";
		}
	};
}

subtest '検索ページでは検索処理を読み込む' => sub {
	my $res = $app->handle({ REQUEST_METHOD => 'GET', PATH_INFO => '/search', QUERY_STRING => 'q=test' });
	is $res->status, 200;
	ok exists $INC{'Lyndbaum/Controller/Search.pm'};
	ok exists $INC{'Lyndbaum/Model/Search.pm'};
};

done_testing;
