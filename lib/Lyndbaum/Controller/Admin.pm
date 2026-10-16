package Lyndbaum::Controller::Admin;
# 管理画面のログイン、ログアウト、ダッシュボードと、管理画面のコントローラで共通の処理
#
# POSTはすべて、Origin（無ければReferer）がこのサイトであることを確かめる
# ログイン後のPOSTは、さらにセッションごとのCSRFトークン（フォームのcsrf_token）を確かめる
#   ほかの管理画面のコントローラは、最初に authorize を呼ぶ
use strict;
use warnings;
use utf8;

use Lyndbaum::Model::Admin;
use Lyndbaum::Model::Article;
use Lyndbaum::Model::Comment;
use Lyndbaum::Model::Session;
use Lyndbaum::Password;

# ログインしていればセッションを返す。そうでなければ (undef, 返す応答)
#   %opt
#     post  真ならPOSTとして、同じサイトからか、CSRFトークンが合うかも確かめる
sub authorize {
	my ($class, $app, $req, %opt) = @_;
	my $session = $app->admin_session($req) or return (undef, $class->_to_login($app));
	return (undef, $class->forbidden($app)) if $opt{post} && !$class->_valid_post($req, $session);
	return ($session);
}

sub dashboard {
	my ($class, $app, $req) = @_;
	my ($session, $res) = $class->authorize($app, $req);
	return $res if !$session;
	my ($rebuilt) = ($req->param('rebuilt') // '') =~ /\A(\d+)\z/;   # 再構築した記事の数（Lyndbaum::Controller::AdminArticle->rebuild）
	return $app->render_admin('admin_dashboard', {
		title          => 'ダッシュボード',
		comment_counts => Lyndbaum::Model::Comment->count_by_status($app->db),
		article_counts => Lyndbaum::Model::Article->count_by_status($app->db, 'post'),
		page_counts    => Lyndbaum::Model::Article->count_by_status($app->db, 'page'),
		trash_count    => Lyndbaum::Model::Article->count_trash($app->db),
		rebuilt        => $rebuilt,
		feed_failed    => ($req->param('feed') // '') eq 'failed',
	}, session => $session);
}

sub login_form {
	my ($class, $app, $req) = @_;
	return $app->redirect($app->url->admin, 303) if $app->admin_session($req);
	return $app->render_admin('admin_login', { title => 'ログイン' });
}

sub login {
	my ($class, $app, $req) = @_;
	return $class->forbidden($app) if !$class->_same_origin($req);
	my $dbh = $app->db;
	my $ip  = $req->remote_addr;
	my $login = $req->body_param('login') // '';

	if (Lyndbaum::Model::Admin->locked_out($dbh, $ip)) {
		return $app->render_admin('admin_login', {
			title => 'ログイン', login => $login,
			error => 'ログインに続けて失敗したため、しばらく受け付けません。時間をおいてから試してください。',
		}, status => 429);
	}
	if (!Lyndbaum::Model::Admin->authenticate($dbh, $login, $req->body_param('password') // '')) {
		Lyndbaum::Model::Admin->record_failure($dbh, $ip);
		return $app->render_admin('admin_login', {
			title => 'ログイン', login => $login, error => 'ログイン名かパスワードが違います。',
		}, status => 401);
	}

	Lyndbaum::Model::Admin->clear_failures($dbh, $ip);
	# 前のセッションが残っていれば消してから、新しいセッションにする
	Lyndbaum::Model::Session->delete($dbh, $app->session_token($req)) if defined $app->session_token($req);
	my $session = Lyndbaum::Model::Session->create($dbh);
	return $app->redirect($app->url->admin, 303)
		->add_header('Set-Cookie', $app->session_cookie($session->{token}, $session->{expires_at}));
}

sub logout {
	my ($class, $app, $req) = @_;
	my ($session, $res) = $class->authorize($app, $req, post => 1);
	return $res if !$session;
	Lyndbaum::Model::Session->delete($app->db, $app->session_token($req));
	return $app->redirect($app->url->admin('login'), 303)
		->add_header('Set-Cookie', $app->session_cookie(undef));
}

# ログイン後の POST が正しいか（同じサイトからで、CSRF トークンが合う）
sub _valid_post {
	my ($class, $req, $session) = @_;
	return $class->_same_origin($req)
		&& Lyndbaum::Password::equal($req->body_param('csrf_token') // '', $session->{csrf_token});
}

sub _same_origin {
	my ($class, $req) = @_;
	my $origin = $req->origin;
	return defined $origin && lc $origin eq lc $req->own_origin;
}

sub _to_login {
	my ($class, $app) = @_;
	return Lyndbaum::App::admin_headers($app->redirect($app->url->admin('login'), 303));
}

sub forbidden {
	my ($class, $app) = @_;
	return $app->render_admin('admin_error', {
		title => '操作できません',
		error => 'この操作は受け付けられませんでした。管理画面を開き直してから、もう一度試してください。',
	}, status => 403);
}

1;
