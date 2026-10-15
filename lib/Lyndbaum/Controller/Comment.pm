package Lyndbaum::Controller::Comment;
# コメントの投稿（記事のURLへのPOST）。決まりは docs/comments.md の「投稿」
#
#   はじくもの      理由を返さず、一般的なエラーだけを出す（何が引っかかったかをボットに教えないため）
#   理由を返すもの  長さの決まり。書いた内容は消さずにフォームへ戻す
#   承認待ち        URL、NGワード、日本語を含まない、承認制
#   管理者（ログイン中）のコメントは、トークン以外の確認をせず、すぐ公開して管理者の印を付ける
use strict;
use warnings;
use utf8;

use Lyndbaum::CommentPolicy;
use Lyndbaum::CommentToken;
use Lyndbaum::Controller::Article;
use Lyndbaum::Model::Article;
use Lyndbaum::Model::Comment;

# 理由を返さずにはじいたときの知らせ
my $REJECTED = 'コメントを投稿できませんでした。ページを開き直し、しばらくたってからもう一度試してください。';

sub create {
	my ($class, $app, $req, $slug) = @_;
	my $dbh = $app->db;
	my $article = Lyndbaum::Model::Article->find_public_by_slug($dbh, $slug) or return $app->not_found;
	my $settings = $app->settings;
	my $secret   = $app->config->get('secret_key');

	my $name = Lyndbaum::CommentPolicy->normalize($req->body_param('name'));
	my $body = Lyndbaum::CommentPolicy->normalize($req->body_param('body'));
	my $back = sub {
		my (%form) = @_;
		return Lyndbaum::Controller::Article->render_article($app, $req, $article, name => $name, body => $body, %form);
	};

	return $back->(status => 403, errors => ['この記事には、コメントを書けません。'])
		if !$settings->{comments_enabled} || !$article->{comments_open} || !defined $secret || $secret eq '';

	my $admin = $app->admin_session($req) ? 1 : 0;
	my $ip    = $req->remote_addr;

	# はじくもの（トークンとおとりの欄は、管理者にも確かめる）
	my $reason;
	$reason = 'token' if !Lyndbaum::CommentToken->verify($secret, $req->body_param('token'), $article->{id});
	$reason //= 'honeypot' if ($req->body_param('website') // '') ne '';
	if (!$admin) {
		$reason //= Lyndbaum::CommentPolicy->reject_reason($settings,
			ip           => $ip,
			host         => $req->remote_host,
			name         => $name,
			admin_names  => [ ($app->admin_login // ()), @{ Lyndbaum::Model::Comment->admin_names($dbh) } ],
			recent_count => Lyndbaum::Model::Comment->count_recent_by_ip($dbh, $ip, time - $settings->{comments_rate_minutes} * 60),
		);
	}
	if ($reason) {
		warn "コメントをはじきました（$reason）: 記事 $article->{id}、IP $ip\n";
		return $back->(status => 400, errors => [$REJECTED]);
	}

	# 理由を返すもの
	my $errors = Lyndbaum::CommentPolicy->length_errors($settings, $name, $body, admin => $admin);
	return $back->(status => 400, errors => $errors) if @$errors;

	my $hold = $admin ? [] : Lyndbaum::CommentPolicy->hold_reasons($settings, $name, $body);
	my $status = @$hold ? 'held' : 'public';
	my $num = Lyndbaum::Model::Comment->create($dbh,
		article_id  => $article->{id},
		status      => $status,
		by_admin    => $admin,
		author_name => $name,
		body        => $body,
		ip          => $ip,
		host        => $req->remote_host,
		user_agent  => $req->user_agent,
	);
	my $url = $app->url->article($article->{slug});
	return $app->redirect($status eq 'public' ? "$url#c$num" : "$url?comment=held#com", 303);
}

1;
