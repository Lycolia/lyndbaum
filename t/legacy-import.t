# 旧システムのテキストDBからの取り込み
#   t/data/adiary は、テスト用に作った小さなデータ（実データではない）
use strict;
use warnings;
use utf8;
use Test::More;

use File::Copy qw(copy);
use File::Spec;
use File::Temp qw(tempdir);

use Lyndbaum::Legacy::Importer;
use Lyndbaum::Legacy::TextDB;
use TestUtil qw(root_dir new_test_app);

my $fixture = File::Spec->catdir(root_dir(), 't', 'data', 'adiary');

subtest 'テキストDBの読み込み' => sub {
	my $records = Lyndbaum::Legacy::TextDB->read_table(File::Spec->catdir($fixture, 'db', 'test_art'));
	is scalar @$records, 4, '索引ファイルは読まない';
	is $records->[0]{title}, '最初の記事', '1行の値';
	is $records->[0]{_text}, "# 見出し\n\n本文", '複数行の値';
	is $records->[1]{_text}, '1行だけの本文', '1行で書かれた本文';
	is $records->[1]{tags}, '', '空の値';

	my $setting = Lyndbaum::Legacy::TextDB->read_record(File::Spec->catfile($fixture, 'blog', 'test', 'setting.dat'));
	is $setting->{'p:des_freetext,1:title'}, 'フリーテキスト', '記号を含むキー';
	is $setting->{'event:SETTING'}, "des_artlist\ndes_comlist", '記号を含むキーの複数行の値';
};

subtest '取り込み' => sub {
	my $app = new_test_app();
	my $dbh = $app->db;
	my $result = Lyndbaum::Legacy::Importer->run($dbh, $fixture, 'test');
	is_deeply $result, { articles => 4, rewritten => 1, image_alts => 1, heading_ids => 1, article_links => 1, tags => 4, article_tags => 2,
		comments => 3, private_comments => 2, settings => 5 }, '件数';

	my $article = sub { $dbh->selectrow_hashref('SELECT * FROM articles WHERE id = ?', undef, $_[0]) };

	my $post = $article->(1);
	is $post->{kind}, 'post';
	is $post->{slug}, '01';
	is $post->{status}, 'published';
	is $post->{published_at}, 1700000000;
	is $post->{updated_at}, 1700000100;
	is $post->{body_src}, "# 見出し [#見出し]\n\n本文", '見出しに、今の見出しのIDを識別子として書き足す';
	is $post->{body_html}, undef, '変換済みHTMLは移さない';
	is $post->{description}, '概要';
	is $post->{comments_open}, 1;

	my $draft = $article->(2);
	is $draft->{status}, 'draft';
	is $draft->{published_at}, undef, '下書きは公開日時なし';
	is $draft->{created_at}, 1700000200, '作成日時は更新日時で代える';

	my $child = $article->(3);
	is $child->{kind}, 'page', 'ctype があればコンテンツページ';
	is $child->{slug}, '親ページ/子ページ';
	is $child->{parent_id}, 4, '親が後にあっても親子関係を付ける';
	is $child->{sort_order}, 100000;
	is $child->{eyecatch}, 'posts/2023/image.png', 'アイキャッチのフォルダも付け替える（adiary/ → posts/）';
	is $child->{eyecatch_mode}, 'chosen', 'アイキャッチが決まっていれば、その画像を出す';
	is $post->{eyecatch_mode}, 'auto', '決まっていなければ、本文の最初の画像';
	is $article->(4)->{parent_id}, undef, 'upnode が 0 なら親なし';
	# tm は 2023-11-15 07:20:00（日本時間）、yyyymmdd は 2019-04-03
	is $article->(4)->{published_at}, 1554243600, '公開日は yyyymmdd、時刻は tm の時刻（日本時間）';
	is $article->(4)->{created_at}, 1700000400, '作成日時は tm';
	is $article->(4)->{body_src},
		qq{親の本文\n![図](/pub/attachments/posts/a.png) <img src="/pub/attachments/b.png"> pub/other/image/c.png\n}
		. qq{[image:S:posts/:a.jpg] [image:M:posts/:b.jpg:説明] [image:S:/pub/attachments/:c.jpg:#キャプション]\n}
		. qq{[前の記事](01) [見出し](/01#見出し) [トップ](/)},
		'添付ファイルの旧パスを書き換え（ほかのブログのパスは書き換えない）、ファイル名と同じ代替テキストを落とす。'
		. '記事へのリンク [文字](/01) は先頭の / を外す（# の付いたものとトップへのリンクはそのまま）';

	my $tags = $dbh->selectall_hashref('SELECT * FROM tags', 'id');
	is $tags->{2}{name}, '調味料', 'タグ名は末端の名前';
	is $tags->{2}{parent_id}, 3;
	is $tags->{4}{name}, '調味料', '親が違えば同じ名前';
	is $tags->{1}{parent_id}, undef, 'upnode が空なら親なし';
	is $tags->{3}{sort_order}, 20;

	is_deeply $dbh->selectcol_arrayref('SELECT tag_id FROM article_tags WHERE article_id = 1 ORDER BY tag_id'),
		[2, 4], '記事の tags 欄から対応を作る';
	is_deeply $dbh->selectcol_arrayref('SELECT ancestor FROM tag_paths WHERE descendant = 2 ORDER BY depth'),
		[2, 3, 1], '閉包テーブルを作る';

	my $comments = $dbh->selectall_hashref('SELECT * FROM comments', 'id');
	is_deeply [ sort keys %$comments ], [1, 2, 5], '非公開コメント（hidden = 1）は取り込まない';
	is $dbh->selectrow_array(q{SELECT COUNT(*) FROM comments WHERE body LIKE '%非公開%' OR author_name = '非公開の人'}), 0,
		'非公開コメントの中身はどこにも残らない';
	my $com = $comments->{1};
	is $com->{article_id}, 1;
	is $com->{num}, 1;
	is $com->{status}, 'public';
	is $com->{by_admin}, 0;
	is $com->{author_name}, '名無し';
	is $com->{body}, qq{はじめまして。\n<b>タグ</b> & "引用" '単'}, 'エスケープと <br> を原文に戻す';
	is_deeply [ @$com{qw(ip host user_agent created_at)} ], ['192.0.2.1', 'example.jp', 'TestAgent/1.0', 1700001000];
	is $comments->{2}{by_admin}, 1, 'ログインユーザーのコメントは管理者のもの';
	is $comments->{2}{body}, ">>1\nありがとうございます";
	is $comments->{5}{status}, 'held', '公開していないものは保留';
	is $comments->{5}{num}, 4, '番号は旧データのまま（飛ばした番号は詰めない）';
	is_deeply $dbh->selectall_arrayref('SELECT id, last_comment_num FROM articles ORDER BY id'), [ [1, 4], [2, 0], [3, 0], [4, 1] ],
		'最後に使った番号。非公開コメントの番号も含める（記事4のコメントは非公開の1件だけ）';
	is $dbh->selectrow_array(q{SELECT value FROM sequences WHERE name = 'articles'}), 4, '最後に使った記事のID（使い回さないため）';

	is_deeply $dbh->selectall_arrayref('SELECT key, value FROM settings ORDER BY key'),
		[ [ blog_author => 'テストの人' ], [ blog_image => '@system/blog.png' ], [ blog_title => 'テストのブログ' ], [ feed_items => 7 ], [ per_page => 3 ] ],
		'ブログの設定（空の値は取り込まない）。書いた人の名前は記事から取る';
};

subtest '空でないDBには取り込まない' => sub {
	my $app = new_test_app();
	Lyndbaum::Legacy::Importer->run($app->db, $fixture, 'test');
	eval { Lyndbaum::Legacy::Importer->run($app->db, $fixture, 'test') };
	like $@, qr/空ではありません/;
};

subtest '知らないタグ名があれば、何も取り込まずに止める' => sub {
	my $dir = tempdir(CLEANUP => 1);
	for my $sub (qw(db db/test_art db/test_tag db/test_com blog blog/test)) {
		mkdir File::Spec->catdir($dir, $sub) or die $!;
		copy($_, File::Spec->catdir($dir, $sub)) or die $!
			for glob File::Spec->catfile($fixture, $sub, '*.dat');
	}
	my $file = File::Spec->catfile($dir, 'db', 'test_art', '00002.dat');
	open my $in, '<:encoding(UTF-8)', $file or die $!;
	my $data = do { local $/; <$in> };
	close $in;
	$data =~ s/^tags=$/tags=存在しないタグ/m;
	open my $out, '>:encoding(UTF-8)', $file or die $!;
	print $out $data;
	close $out;

	my $app = new_test_app();
	eval { Lyndbaum::Legacy::Importer->run($app->db, $dir, 'test') };
	like $@, qr/タグ「存在しないタグ」がありません/;
	is $app->db->selectrow_array('SELECT COUNT(*) FROM articles'), 0, '巻き戻す';
};

done_testing;
