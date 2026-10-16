package Lyndbaum::Controller::AdminSidebar;
# 管理画面のサイドバーの自由欄（Lyndbaum::SidebarBoxes。docs/admin.md の「サイドバーの自由欄」）
#   GET  /admin/sidebar   今の欄と、空の欄を1つ出す
#   POST /admin/sidebar   並べた順に保存する。題名も中身も空の欄は消す。書き方が正しくなければ400で、書いた値を残して出し直す
use strict;
use warnings;
use utf8;

use Lyndbaum::Controller::Admin;
use Lyndbaum::Model::Setting;
use Lyndbaum::SidebarBoxes;

sub form {
	my ($class, $app, $req) = @_;
	my ($session, $res) = Lyndbaum::Controller::Admin->authorize($app, $req);
	return $res if !$session;
	return $class->_render($app, $session, Lyndbaum::SidebarBoxes->decode($app->settings->{sidebar_boxes}), [],
		saved => ($req->param('saved') // '') eq '1');
}

sub save {
	my ($class, $app, $req) = @_;
	my ($session, $res) = Lyndbaum::Controller::Admin->authorize($app, $req, post => 1);
	return $res if !$session;
	my ($boxes, $errors) = Lyndbaum::SidebarBoxes->parse_form([ $req->body_params('box_title') ], [ $req->body_params('box_html') ]);
	return $class->_render($app, $session, $boxes, $errors, status => 400) if @$errors;
	Lyndbaum::Model::Setting->set($app->db, sidebar_boxes => Lyndbaum::SidebarBoxes->encode($boxes));
	return $app->redirect($app->url->admin('sidebar', saved => 1), 303);
}

sub _render {
	my ($class, $app, $session, $boxes, $errors, %opt) = @_;
	return $app->render_admin('admin_sidebar', {
		title     => 'サイドバーの自由欄',
		action    => $app->url->admin('sidebar'),
		script    => $app->url->static('js/admin-sidebar.js'),
		saved     => $opt{saved},
		errors    => $errors,
		boxes     => [ @$boxes, { title => '', html => '', blank => 1 } ],
		max_title => $Lyndbaum::SidebarBoxes::MAX_TITLE,
	}, session => $session, status => $opt{status});
}

1;
