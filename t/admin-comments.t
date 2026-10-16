# 管理画面のコメントの管理と、コメントの設定
use strict;
use warnings;
use utf8;
use Test::More;

use Lyndbaum::Model::Setting;
use AdminTest;
use TestUtil qw(insert_article);

my $t   = AdminTest->new;
my $dbh = $t->dbh;
sub header { AdminTest::header(@_) }

insert_article($dbh, id => 1, title => '公開の記事');
insert_article($dbh, id => 2, title => '下書きの記事', status => 'draft');
my $insert = $dbh->prepare('INSERT INTO comments (id, article_id, num, status, author_name, body, ip, host, user_agent, created_at) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)');
$insert->execute(@$_) for
	[1, 1, 1, 'public', '公開の人', "本文 https://example.com/ <b>", '192.0.2.1', 'a.example.jp', 'UA/1', 1700000100],
	[2, 1, 2, 'held',   '保留の人', '承認待ちの本文', '192.0.2.2', '', 'UA/2', 1700000200],
	[3, 2, 1, 'public', '下書きの人', '下書きへの本文', '', '', '', 1700000300];

my ($cookie) = $t->login;
my $csrf = $t->csrf_of($cookie);
my $post = sub {
	my ($path, @body) = @_;
	return $t->request(POST => $path, cookie => $cookie, body => [ csrf_token => $csrf, @body ]);
};
my $status_of = sub { scalar $dbh->selectrow_array('SELECT status FROM comments WHERE id = ?', undef, $_[0]) };

subtest 'ログインしていなければ使えない' => sub {
	is $t->request(GET => '/admin/comments')->status, 303;
	is $t->request(GET => '/admin/settings/comments')->status, 303;
	is $t->request(POST => '/admin/comments/2', body => [ action => 'approve' ])->status, 303;
	is $status_of->(2), 'held';
};

subtest 'ダッシュボード' => sub {
	my $body = $t->request(GET => '/admin', cookie => $cookie)->body;
	like $body, qr{承認待ちのコメント</a><span class="admin-glance-count">1件</span>};
	like $body, qr{公開中のコメント</a><span class="admin-glance-count">2件</span>};
};

subtest '一覧' => sub {
	my $body = $t->request(GET => '/admin/comments', cookie => $cookie)->body;
	like $body, qr{<strong>すべて（3）</strong>};
	like $body, qr{承認待ち（1）};
	my @authors = $body =~ m{<span class="comment-author">(.*?)</span>}g;
	is_deeply \@authors, ['下書きの人', '保留の人', '公開の人'], '新しい順';
	like $body, qr{<div class="comment-text">本文 https://example.com/ &lt;b&gt;</div>}, '本文はエスケープし、URLはリンクにしない';
	like $body, qr{<a href="/01#c1">公開の記事 #1</a>}, '公開中の記事へのリンク';
	like $body, qr{下書きの記事 #1（記事は非公開）}, '非公開の記事にはリンクしない';
	like $body, qr{IP：192.0.2.1 ／ ホスト：a.example.jp ／ UA：UA/1};

	$body = $t->request(GET => '/admin/comments?status=held', cookie => $cookie)->body;
	is_deeply [ $body =~ m{<span class="comment-author">(.*?)</span>}g ], ['保留の人'], '承認待ちだけ';
	like $body, qr{value="approve">承認</button>};
	unlike $body, qr{value="hide"};
	like $body, qr{name="back" value="/admin/comments\?status=held"}, '操作の後は同じ一覧に戻る';
};

subtest '記事ごとの一覧' => sub {
	my $get = sub { $t->request(GET => $_[0], cookie => $cookie) };
	like $get->('/admin/articles')->body, qr{<td><a href="/admin/comments\?article=1" title="この記事のコメントを管理する">2</a></td>}, '記事の一覧のコメントの数から開く';

	my $body = $get->('/admin/comments?article=1')->body;
	like $body, qr{<h1>「公開の記事」のコメント</h1>};
	is_deeply [ $body =~ m{<span class="comment-author">(.*?)</span>}g ], ['保留の人', '公開の人'], 'その記事のコメントだけ';
	like $body, qr{<strong>すべて（2）</strong>.*承認待ち（1）.*公開中（1）}s, '件数もその記事だけ';
	like $body, qr{<a href="/admin/comments\?article=1&amp;status=held">承認待ち（1）</a>}, '絞り込みも同じ記事のまま';
	like $body, qr{<a href="/admin/articles/1">記事を編集</a>};
	like $body, qr{<a href="/01">公開側で見る</a>};
	like $body, qr{<a href="/admin/articles">記事の一覧へ</a>};
	like $body, qr{<a href="/admin/comments">すべての記事のコメント</a>};
	like $body, qr{name="back" value="/admin/comments\?article=1"}, '操作の後は同じ記事の一覧に戻る';

	is_deeply [ $get->('/admin/comments?article=1&status=held')->body =~ m{<span class="comment-author">(.*?)</span>}g ], ['保留の人'];
	is $get->('/admin/comments?article=99')->status, 404, '無い記事';
	is $get->('/admin/comments?article=abc')->status, 404;

	my $res = $post->('/admin/comments/2', action => 'approve', back => '/admin/comments?article=1&status=held');
	is header($res, 'Location'), '/admin/comments?article=1&status=held', '同じ記事の一覧に戻る';
	$post->('/admin/comments/2', action => 'hide');
};

subtest '承認と非表示' => sub {
	my $res = $post->('/admin/comments/2', action => 'approve', back => '/admin/comments?status=held');
	is $res->status, 303;
	is header($res, 'Location'), '/admin/comments?status=held';
	is $status_of->(2), 'public';

	$res = $post->('/admin/comments/2', action => 'hide', back => 'https://evil.example/');
	is header($res, 'Location'), '/admin/comments', '一覧以外へは戻らない';
	is $status_of->(2), 'held';

	is $t->request(POST => '/admin/comments/2', cookie => $cookie, body => [ csrf_token => 'wrong', action => 'approve' ])->status, 403, 'CSRFトークンが違う';
	is $status_of->(2), 'held';
	is $post->('/admin/comments/999', action => 'approve')->status, 404, '無いコメント';
	is $post->('/admin/comments/2', action => 'unknown')->status, 400, '知らない操作';
};

subtest '削除' => sub {
	my $res = $post->('/admin/comments/3', action => 'delete');
	is $res->status, 400, '確認のチェックが無ければ消さない';
	like $res->body, qr{確認のチェックを入れてください};
	is $status_of->(3), 'public';
	is $post->('/admin/comments/3', action => 'delete', confirm => 1)->status, 303;
	is $status_of->(3), undef, '消した';
};

subtest 'IPを拒否' => sub {
	is $post->('/admin/comments/1', action => 'block_ip')->status, 303;
	is(Lyndbaum::Model::Setting->all($dbh)->{comments_block_ips}, '192.0.2.1');
	$post->('/admin/comments/1', action => 'block_ip');
	is(Lyndbaum::Model::Setting->all($dbh)->{comments_block_ips}, '192.0.2.1', '同じIPは二重に足さない');
	my $body = $t->request(GET => '/admin/comments', cookie => $cookie)->body;
	like $body, qr{IP：192.0.2.1（拒否中）};
};

subtest '設定' => sub {
	my $body = $t->request(GET => '/admin/settings/comments', cookie => $cookie)->body;
	like $body, qr{<input type="checkbox" name="comments_enabled" value="1" checked>コメントを受け付ける}, '既定値';
	like $body, qr{<input type="checkbox" name="comments_moderate_all" value="1">};
	like $body, qr{name="comments_body_min" value="5"};
	like $body, qr{<textarea name="comments_block_ips" rows="5">192.0.2.1</textarea>};

	my %form = (
		comments_enabled => 1, comments_rate_limit => 1, comments_rate_count => 5, comments_rate_minutes => 30,
		comments_name_max => 32, comments_body_min => 3, comments_body_max => 2000, comments_body_lines => 50,
		comments_ng_words => "カジノ\r\n\r\n  バイアグラ \r\nカジノ", comments_block_ips => "192.0.2.0/24\n2001:db8::/32",
		comments_block_hosts => '.spam.example',
	);
	my $res = $post->('/admin/settings/comments', %form);
	is $res->status, 303;
	is header($res, 'Location'), '/admin/settings/comments?saved=1';
	my $s = Lyndbaum::Model::Setting->all($dbh);
	is $s->{comments_moderate_all}, 0, 'チェックが無ければ0';
	is $s->{comments_js_token}, 0;
	is $s->{comments_rate_count}, 5;
	is $s->{comments_ng_words}, "カジノ\nバイアグラ", '空行と前後の空白と重複を除く';
	is $s->{comments_block_ips}, "192.0.2.0/24\n2001:db8::/32";
	like $t->request(GET => '/admin/settings/comments?saved=1', cookie => $cookie)->body, qr{保存しました。};

	$res = $post->('/admin/settings/comments', %{ { %form, comments_body_max => 'abc', comments_block_ips => "192.0.2.0/24\nwrong", comments_block_hosts => 'a b' } });
	is $res->status, 400;
	like $res->body, qr{本文の文字数の上限は、1から100000までの整数で書いてください。};
	like $res->body, qr{拒否するIPアドレスの「wrong」は、書き方が正しくありません。};
	like $res->body, qr{拒否するホスト名の「a b」は、書き方が正しくありません。};
	like $res->body, qr{<textarea name="comments_block_ips" rows="5">192.0.2.0/24\nwrong</textarea>}, '書いた値は残す';
	is(Lyndbaum::Model::Setting->all($dbh)->{comments_body_max}, 2000, '保存しない');

	$res = $post->('/admin/settings/comments', %{ { %form, comments_body_min => 100, comments_body_max => 50 } });
	like $res->body, qr{本文の文字数の下限は、上限以下にしてください。};

	is $t->request(POST => '/admin/settings/comments', cookie => $cookie, body => [ %form ])->status, 403, 'CSRFトークンが無い';
};

done_testing;
