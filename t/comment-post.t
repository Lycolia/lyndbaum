# コメントの投稿（docs/comments.md の「投稿」）
use strict;
use warnings;
use utf8;
use Test::More;

use Lyndbaum::CommentToken;
use Lyndbaum::Model::Setting;
use AdminTest;
use TestUtil qw(insert_article);

# はじいた投稿の記録（warn）は、テストの出力に混ぜない
local $SIG{__WARN__} = sub { warn @_ if $_[0] !~ /コメントをはじきました/ };

my $t   = AdminTest->new;
my $dbh = $t->dbh;
sub header { AdminTest::header(@_) }

insert_article($dbh, id => 1, title => '記事');
insert_article($dbh, id => 2, title => 'コメントを閉じた記事', comments_open => 0);
insert_article($dbh, id => 3, title => '下書き', status => 'draft');
# 管理者が前に書いたコメント（この名前は、ほかの人には名乗れない）
$dbh->do(q{INSERT INTO comments (article_id, num, status, by_admin, author_name, body, created_at) VALUES (1, 1, 'public', 1, 'Lycolia Rizzim', '前のコメント', 1)});

my $token = sub { Lyndbaum::CommentToken->issue('test-secret', $_[0] // 1, time - ($_[1] // 10)) };
my $ip_count = 0;
# 投稿する。%opt：path、body（足すフォームの値）、ip、cookie
#   連投の制限に当たらないよう、指定しなければ毎回違うIPにする
sub post_comment {
	my (%opt) = @_;
	my %form = (name => '名無し', body => 'こんにちは、はじめまして。', token => $token->(), website => '', %{ $opt{body} // {} });
	return $t->request(POST => $opt{path} // '/01', body => [ %form ], ip => $opt{ip} // '192.0.2.' . ++$ip_count,
		cookie => $opt{cookie}, env => { REMOTE_HOST => $opt{host} // '', HTTP_USER_AGENT => 'TestAgent/1.0' });
}
my $last = sub { $dbh->selectrow_hashref('SELECT * FROM comments ORDER BY id DESC LIMIT 1') };
my $count = sub { scalar $dbh->selectrow_array('SELECT COUNT(*) FROM comments') };

subtest 'フォーム' => sub {
	my $body = $t->request(GET => '/01')->body;
	like $body, qr{<form class="comment-form" id="comment-form" method="post" action="/01#comment-form" data-token="v1\.1\.\d+\.[A-Za-z0-9_-]+">}, 'トークンはJavaScriptで入れる';
	like $body, qr{<input type="hidden" name="token" value="">};
	like $body, qr{<script src="/pub/assets/js/comment.js" defer></script>};
	like $body, qr{name="website"}, 'おとりの欄';
	unlike $body, qr{管理者として書き込みます};
	unlike $t->request(GET => '/02')->body, qr{comment-form}, 'コメントを閉じた記事にはフォームを出さない';

	Lyndbaum::Model::Setting->set($dbh, comments_js_token => 0);
	like $t->request(GET => '/01')->body, qr{<input type="hidden" name="token" value="v1\.1\.\d+\.}, 'JavaScriptを使わないなら、トークンをそのまま入れる';
	Lyndbaum::Model::Setting->set($dbh, comments_js_token => 1);

	Lyndbaum::Model::Setting->set($dbh, comments_enabled => 0);
	unlike $t->request(GET => '/01')->body, qr{comment-form}, '受け付けない設定ならフォームを出さない';
	Lyndbaum::Model::Setting->set($dbh, comments_enabled => 1);
};

subtest '公開される投稿' => sub {
	my $res = post_comment(body => { name => ' 名無し ', body => "  1行目\r\n2行目  " }, ip => '198.51.100.1', host => 'h.example.jp');
	is $res->status, 303;
	is header($res, 'Location'), '/01#c2', '公開されたコメントへ';
	my $c = $last->();
	is_deeply [ @$c{qw(article_id num status by_admin author_name body ip host user_agent)} ],
		[1, 2, 'public', 0, '名無し', "1行目\n2行目", '198.51.100.1', 'h.example.jp', 'TestAgent/1.0'], '前後の空白を除き、改行をLFにする';
	like $t->request(GET => '/01')->body, qr{<article class="comment-entry" id="c2">}, '記事のページに出る';
};

subtest '承認待ちになる投稿' => sub {
	my $res = post_comment(body => { body => 'ここを見てください https://spam.example/' });
	is header($res, 'Location'), '/01?comment=held#com';
	is $last->()->{status}, 'held', 'URLを含む';
	like $t->request(GET => '/01?comment=held')->body, qr{コメントは承認待ちです。};
	unlike $t->request(GET => '/01')->body, qr{spam\.example}, '公開側には出さない';

	post_comment(body => { body => 'Great post, thank you!' });
	is $last->()->{status}, 'held', '日本語を含まない';

	Lyndbaum::Model::Setting->set($dbh, comments_ng_words => "カジノ\nｂｕｙ");
	post_comment(body => { body => 'オンラインかじの、ＣＡＳＩＮＯ。BUY です' });
	is $last->()->{status}, 'held', 'NGワード（全角と半角、大文字と小文字を区別しない）';
	Lyndbaum::Model::Setting->set($dbh, comments_ng_words => '');

	Lyndbaum::Model::Setting->set($dbh, comments_moderate_all => 1);
	post_comment();
	is $last->()->{status}, 'held', '承認制';
	Lyndbaum::Model::Setting->set($dbh, comments_moderate_all => 0);

	Lyndbaum::Model::Setting->set($dbh, comments_require_japanese => 0);
	post_comment(body => { body => 'Great post, thank you!' });
	is $last->()->{status}, 'public', '日本語を求めない設定なら公開';
	Lyndbaum::Model::Setting->set($dbh, comments_require_japanese => 1);
};

subtest 'はじく投稿（理由は返さない）' => sub {
	my $before = $count->();
	my $generic = qr{コメントを投稿できませんでした。ページを開き直し、しばらくたってからもう一度試してください。};
	my %cases = (
		'トークンが無い'           => { body => { token => '' } },
		'署名が違う'               => { body => { token => $token->() . 'x' } },
		'別の記事のトークン'       => { body => { token => $token->(2) } },
		'フォームを出してすぐ'     => { body => { token => $token->(1, 1) } },
		'古すぎるフォーム'         => { body => { token => $token->(1, 2 * 24 * 60 * 60) } },
		'おとりの欄に入っている'   => { body => { website => 'https://spam.example/' } },
		'管理者の名前を名乗る'     => { body => { name => 'ｌｙｃｏｌｉａ　ｒｉｚｚｉｍ' } },
		'管理者のログイン名を名乗る' => { body => { name => 'Admin' } },
	);
	for my $name (sort keys %cases) {
		my $res = post_comment(%{ $cases{$name} });
		is $res->status, 400, $name;
		like $res->body, $generic, "$name：一般的なエラー";
	}

	Lyndbaum::Model::Setting->set($dbh, comments_block_ips => '203.0.113.0/24');
	Lyndbaum::Model::Setting->set($dbh, comments_block_hosts => '.spam.example');
	is post_comment(ip => '203.0.113.9')->status, 400, '拒否するIPアドレス';
	is post_comment(host => 'x.SPAM.example')->status, 400, '拒否するホスト名';
	Lyndbaum::Model::Setting->set($dbh, $_ => '') for qw(comments_block_ips comments_block_hosts);
	is $count->(), $before, 'どれも保存しない';

	my $res = post_comment(body => { body => 'ここに書いた本文', token => '' });
	like $res->body, qr{<textarea name="body" rows="5" required>ここに書いた本文</textarea>}, '書いた内容は残す';
};

subtest '連投の制限' => sub {
	my $ip = '192.0.2.200';
	is post_comment(ip => $ip)->status, 303 for 1 .. 3;
	is post_comment(ip => $ip)->status, 400, '10分に3回まで';
	$dbh->do('UPDATE comments SET created_at = created_at - 600 WHERE ip = ?', undef, $ip);
	is post_comment(ip => $ip)->status, 303, '期間が過ぎれば投稿できる';
	Lyndbaum::Model::Setting->set($dbh, comments_rate_limit => 0);
	is post_comment(ip => $ip)->status, 303 for 1 .. 3;
	Lyndbaum::Model::Setting->set($dbh, comments_rate_limit => 1);
};

subtest '理由を返す投稿' => sub {
	my $check = sub {
		my ($form, $message, $name) = @_;
		my $res = post_comment(body => $form);
		is $res->status, 400, $name;
		like $res->body, qr{\Q$message\E}, "$name：理由";
	};
	$check->({ name => '  ' }, '名前を書いてください。', '名前が空');
	$check->({ name => 'あ' x 33 }, '名前は32文字以内で書いてください。', '名前が長い');
	$check->({ body => "\n \n" }, '本文を書いてください。', '本文が空');
	$check->({ body => 'すごい！！！！' }, '本文は5文字以上で書いてください（空白と記号は数えません）。', '本文が短い');
	$check->({ body => 'あ' x 3001 }, '本文は3000文字以内で書いてください。', '本文が長い');
	$check->({ body => join "\n", ('あいうえお') x 101 }, '本文は100行以内で書いてください。', '行が多い');
	my $res = post_comment(body => { name => '書いた名前', body => 'すごい' });
	like $res->body, qr{name="name" value="書いた名前"}, '書いた内容は残す';
	is post_comment(body => { body => '辿り着きました！' })->status, 303, '7文字は通る';
};

subtest '記事の状態' => sub {
	is post_comment(path => '/02')->status, 403, 'コメントを閉じた記事';
	is post_comment(path => '/03', body => { token => $token->(3) })->status, 404, '下書き';
	is post_comment(path => '/0999')->status, 404, '無い記事';
	Lyndbaum::Model::Setting->set($dbh, comments_enabled => 0);
	is post_comment()->status, 403, '受け付けない設定';
	Lyndbaum::Model::Setting->set($dbh, comments_enabled => 1);
};

subtest '管理者の投稿' => sub {
	my ($cookie) = $t->login;
	my $body = $t->request(GET => '/01', cookie => $cookie)->body;
	like $body, qr{管理者として書き込みます。};
	like $body, qr{name="name" value="Lycolia Rizzim"}, '前に使った名前を入れておく';

	Lyndbaum::Model::Setting->set($dbh, comments_block_ips => '192.0.2.0/24');
	my $res = post_comment(cookie => $cookie, ip => '192.0.2.1', body => { name => 'Lycolia Rizzim', body => '了解 https://example.com/' });
	is $res->status, 303;
	my $c = $last->();
	is_deeply [ @$c{qw(status by_admin author_name)} ], ['public', 1, 'Lycolia Rizzim'], '管理者の印を付けてすぐ公開（URL、拒否するIP、本文の下限を見ない）';
	Lyndbaum::Model::Setting->set($dbh, comments_block_ips => '');
	is post_comment(cookie => $cookie, body => { token => '' })->status, 400, 'トークンは管理者にも確かめる';
	like $t->request(GET => '/01')->body, qr{<article class="comment-entry comment-admin" id="c$c->{num}">};
};

subtest '番号' => sub {
	my $max = $dbh->selectrow_array('SELECT MAX(num) FROM comments WHERE article_id = 1');
	$dbh->do('DELETE FROM comments WHERE article_id = 1 AND num = ?', undef, $max);
	post_comment();
	is $last->()->{num}, $max + 1, 'いちばん新しいコメントを消しても、その番号は使い回さない';
	is $dbh->selectrow_array('SELECT last_comment_num FROM articles WHERE id = 1'), $max + 1, '最後に使った番号を記録する';

	insert_article($dbh, id => 4, title => '番号を確かめる記事');
	post_comment(path => '/04', body => { token => $token->(4) });
	is $last->()->{num}, 1, 'コメントの無い記事は1から';
};

done_testing;
