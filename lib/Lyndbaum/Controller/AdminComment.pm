package Lyndbaum::Controller::AdminComment;
# 管理画面のコメントの管理と、コメントの設定
#   /admin/comments?status=held|public&page=N   一覧（statusを省くとすべて）
#   POST /admin/comments/ID                      1件の操作（action=approve|hide|delete|block_ip）
use strict;
use warnings;
use utf8;

use Lyndbaum::CommentSettings;
use Lyndbaum::Controller qw(page_number);
use Lyndbaum::Controller::Admin;
use Lyndbaum::Date qw(format_date);
use Lyndbaum::Model::Comment;
use Lyndbaum::Model::Setting;
use Lyndbaum::View;

my $PER_PAGE = 20;
my %STATUS_LABEL = (held => '承認待ち', public => '公開中');

sub index {
	my ($class, $app, $req) = @_;
	my ($session, $res) = Lyndbaum::Controller::Admin->authorize($app, $req);
	return $res if !$session;

	my $status = $req->param('status') // '';
	$status = undef if !$STATUS_LABEL{$status};
	my $counts = Lyndbaum::Model::Comment->count_by_status($app->db);
	my $total  = defined $status ? $counts->{$status} : $counts->{public} + $counts->{held};

	my $pager = Lyndbaum::View->pager(
		page     => page_number($req),
		per_page => $PER_PAGE,
		total    => $total,
		url_of   => sub { $app->url->admin('comments', status => $status, page => $_[0] > 1 ? $_[0] : undef) },
	) or return $app->not_found;
	my $here = $app->url->admin('comments', status => $status, page => $pager->{page} > 1 ? $pager->{page} : undef);

	my $comments = Lyndbaum::Model::Comment->list_admin($app->db,
		status => $status, limit => $PER_PAGE, offset => ($pager->{page} - 1) * $PER_PAGE);
	my $settings = $app->settings;
	my $blocked  = Lyndbaum::CommentSettings->lines_of($settings, 'comments_block_ips');
	return $app->render_admin('admin_comments', {
		title    => 'コメント',
		filters  => [ map {
			my ($value, $label, $count) = @$_;
			+{ label => $label, count => $count, url => $app->url->admin('comments', status => $value), current => ($status // '') eq ($value // '') }
		} [ undef, 'すべて', $counts->{public} + $counts->{held} ], [ held => '承認待ち', $counts->{held} ], [ public => '公開中', $counts->{public} ] ],
		comments => [ map {
			my $c = $_;
			+{
				%$c,
				status_label => $STATUS_LABEL{ $c->{status} },
				held         => $c->{status} eq 'held',
				created      => format_date($c->{created_at}),
				url          => $c->{article_public} ? $app->url->article($c->{slug}) . "#c$c->{num}" : undef,
				action_url   => $app->url->admin("comments/$c->{id}"),
				ip_blocked   => scalar grep { $_ eq $c->{ip} } @$blocked,
			}
		} @$comments ],
		back     => $here,
		pager    => $pager,
	}, session => $session);
}

# 1件の操作。終わったら一覧に戻る
sub update {
	my ($class, $app, $req, $id) = @_;
	my ($session, $res) = Lyndbaum::Controller::Admin->authorize($app, $req, post => 1);
	return $res if !$session;
	my $dbh = $app->db;
	my $comment = Lyndbaum::Model::Comment->find($dbh, $id) or return $app->not_found;

	my $action = $req->body_param('action') // '';
	if ($action eq 'approve') {
		Lyndbaum::Model::Comment->set_status($dbh, $id, 'public');
	} elsif ($action eq 'hide') {
		Lyndbaum::Model::Comment->set_status($dbh, $id, 'held');
	} elsif ($action eq 'delete') {
		# 取り消せないので、確認のチェックが入っているときだけ消す
		return $class->_error($app, $session, '削除するときは、確認のチェックを入れてください。')
			if ($req->body_param('confirm') // '') ne '1';
		Lyndbaum::Model::Comment->delete($dbh, $id);
	} elsif ($action eq 'block_ip') {
		return $class->_error($app, $session, 'このコメントにはIPアドレスが記録されていません。') if $comment->{ip} eq '';
		Lyndbaum::Model::Setting->set($dbh, comments_block_ips =>
			Lyndbaum::CommentSettings->add_line($app->settings, 'comments_block_ips', $comment->{ip}));
	} else {
		return $class->_error($app, $session, '操作が正しくありません。');
	}
	return $app->redirect(_back($app, $req), 303);
}

sub _error {
	my ($class, $app, $session, $message) = @_;
	return $app->render_admin('admin_error', { title => '操作できません', error => $message }, session => $session, status => 400);
}

# 操作の後に戻る先。管理画面のコメントの一覧のURLだけを受け付ける（ほかのサイトへ飛ばされないように）
sub _back {
	my ($app, $req) = @_;
	my $list = $app->url->admin('comments');
	my $back = $req->body_param('back') // '';
	return $back =~ /\A\Q$list\E(?:\?[A-Za-z0-9=&]*)?\z/ ? $back : $list;
}

1;
