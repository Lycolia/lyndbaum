package Lyndbaum::Controller::AdminSettings;
# 管理画面の設定（項目の表から画面を作る。項目の書き方は Lyndbaum::SettingsForm）
#   /admin/settings/blog       ブログの設定（Lyndbaum::BlogSettings）
#   /admin/settings/comments   コメントの設定（Lyndbaum::CommentSettings）
#   /admin/settings/editor     編集の設定（Lyndbaum::EditorSettings）
#   POST で保存する。書き方が正しくなければ400で、書いた値を残してフォームを出し直す
use strict;
use warnings;
use utf8;

use Lyndbaum::BlogSettings;
use Lyndbaum::CommentSettings;
use Lyndbaum::Controller::Admin;
use Lyndbaum::EditorSettings;
use Lyndbaum::Model::Setting;

my %PAGES = (
	blog     => { title => 'ブログの設定',   items => 'Lyndbaum::BlogSettings',    nav => 'blog_settings' },
	comments => { title => 'コメントの設定', items => 'Lyndbaum::CommentSettings', nav => 'comment_settings' },
	editor   => { title => '編集の設定',     items => 'Lyndbaum::EditorSettings',  nav => 'editor_settings' },
);

sub form {
	my ($class, $app, $req, $name) = @_;
	my ($session, $res) = Lyndbaum::Controller::Admin->authorize($app, $req);
	return $res if !$session;
	my $page = $PAGES{$name} or return $app->not_found;
	return $class->_render($app, $session, $name, $app->settings, [], saved => ($req->param('saved') // '') eq '1');
}

sub save {
	my ($class, $app, $req, $name) = @_;
	my ($session, $res) = Lyndbaum::Controller::Admin->authorize($app, $req, post => 1);
	return $res if !$session;
	my $page = $PAGES{$name} or return $app->not_found;
	my ($values, $errors) = $page->{items}->parse_form(sub { $req->body_param($_[0]) });
	return $class->_render($app, $session, $name, $values, $errors, status => 400) if @$errors;

	my $dbh = $app->db;
	$dbh->begin_work;
	eval {
		Lyndbaum::Model::Setting->set($dbh, $_, $values->{$_}) for sort keys %$values;
		$dbh->commit;
		1;
	} or do {
		my $error = $@;
		$dbh->rollback;
		die $error;
	};
	return $app->redirect($app->url->admin("settings/$name", saved => 1), 303);
}

sub _render {
	my ($class, $app, $session, $name, $values, $errors, %opt) = @_;
	my $page = $PAGES{$name};
	my %error_of;
	push @{ $error_of{ $_->{key} } }, $_->{message} for @$errors;
	return $app->render_admin('admin_settings', {
		title  => $page->{title},
		script => $app->url->static('js/admin-media.js'),   # 「ファイル一覧から選択」
		action => $app->url->admin("settings/$name"),
		saved  => $opt{saved},
		errors => $errors,
		fields => [ map {
			my $f = $_;
			+{
				%$f,
				is_bool  => $f->{type} eq 'bool',
				is_int   => $f->{type} eq 'int',
				is_lines => $f->{type} eq 'lines',
				is_text  => $f->{type} eq 'text',
				value    => $values->{ $f->{key} },
				checked  => $f->{type} eq 'bool' && $values->{ $f->{key} },
				errors   => $error_of{ $f->{key} } // [],
			}
		} @{ $page->{items}->fields } ],
	}, session => $session, status => $opt{status}, nav => $page->{nav});
}

1;
