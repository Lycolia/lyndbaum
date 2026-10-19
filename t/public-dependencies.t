# 通常の閲覧が、検索実行・認証・投稿用のモジュールを巻き込まないことを確かめる
#   書き出し用のモジュール（サイトのアイコンやブログの画像の入れ替え、RSS とサイトマップ、アップロード）も読み込まない
#   CGI は毎回すべてを読み込み直すので、読み込むものが増えると表示が遅くなる
use strict;
use warnings;
use utf8;
use Test::More;

use TestUtil qw(new_test_app insert_article);

my $app = new_test_app();
insert_article($app->db, id => 7, title => '公開記事', body_html => '<p>本文<img src="/pub/attachments/a.png"></p>');   # OGP の画像を絶対 URL にする

for my $path ('/', '/07') {
	subtest "匿名で閲覧する $path" => sub {
		my $res = $app->handle({ REQUEST_METHOD => 'GET', PATH_INFO => $path });
		is $res->status, 200;
		like $res->body, qr{<option value="text" selected}, '検索フォームを表示する';
		for my $module (qw(
			Controller/Search Model/Search Highlight Model/Session Password
			AddressMatch Multipart Controller/Admin Media Parser Parser/Markdown
			SiteIcon/Writer BlogImage/Writer Branding/Writer StaticFiles Feed Sitemap Upload Thumbnail
		)) {
			ok !exists $INC{"Lyndbaum/$module.pm"}, "$module は未ロード";
		}
		# 標準ライブラリやサーバーのモジュールも、読み込みに時間のかかるものは要るときだけ読み込む
		#   URI と HTML::Entities は、OGP の画像の URL がふだんの形でないときだけ（Lyndbaum::OGP）
		#   POSIX も読み込まない（Lyndbaum::View の切り上げ）が、Test::More が読み込むので、ここでは確かめられない
		for my $module (qw(URI HTML/Entities)) {
			ok !exists $INC{"$module.pm"}, "$module は未ロード";
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
