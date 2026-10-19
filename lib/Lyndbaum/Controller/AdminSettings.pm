package Lyndbaum::Controller::AdminSettings;
# 管理画面の設定（項目の表から画面を作る。項目の書き方は Lyndbaum::SettingsForm）
#   /admin/settings/blog       ブログの設定（Lyndbaum::BlogSettings）
#   /admin/settings/comments   コメントの設定（Lyndbaum::CommentSettings）
#   /admin/settings/editor     編集の設定（Lyndbaum::EditorSettings）
#   POST で保存する。書き方が正しくなければ400で、書いた値を残してフォームを出し直す
#   /admin/settings/icon       サイトのアイコンの入れ替えと削除（POST だけ。ブログの設定の画面にフォームがある。Lyndbaum::SiteIcon）
use strict;
use warnings;
use utf8;

use Lyndbaum::BlogSettings;
use Lyndbaum::CommentSettings;
use Lyndbaum::Controller::Admin;
use Lyndbaum::EditorSettings;
use Lyndbaum::Model::Setting;
use Lyndbaum::SettingsForm;
use Lyndbaum::SiteIcon;

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
	return $class->_render($app, $session, $name, $app->settings, [], saved => ($req->param('saved') // '') eq '1',
		icon_done => $req->param('icon') // '');
}

# サイトのアイコン。op が delete なら消して既定のロゴに戻し、それ以外は送られた画像に入れ替える
#   入れ替えられなければ、400 でブログの設定の画面を出し直して理由を出す
sub save_icon {
	my ($class, $app, $req) = @_;
	my $too_large = $app->admin_session($req) && $req->body_too_large;
	my ($session, $res) = Lyndbaum::Controller::Admin->authorize($app, $req, post => !$too_large);
	return $res if !$session;
	my $error;
	if ($too_large) {
		# 大きすぎる本文は読まないので、CSRFトークンも読めない。何も変えずに理由を出す
		$error = sprintf 'ファイルが大きすぎます（%dMBまで）。', $app->upload_max_bytes / 1024 / 1024;
	} elsif (($req->body_param('op') // '') eq 'delete') {
		Lyndbaum::SiteIcon->remove($app);
		return $app->redirect($app->url->admin('settings/blog', icon => 'deleted'), 303);
	} else {
		my ($upload) = $req->uploads('file');
		if (!$upload || ($upload->{filename} // '') eq '') {
			$error = '画像を選んでください。';
		} elsif (!eval { Lyndbaum::SiteIcon->save($app, filename => $upload->{filename}, data => $upload->{data}); 1 }) {
			($error = $@) =~ s/\n\z//;
		} else {
			return $app->redirect($app->url->admin('settings/blog', icon => 'saved'), 303);
		}
	}
	return $class->_render($app, $session, 'blog', $app->settings, [], icon_error => $error, status => 400);
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
		# サイトのアイコンのフォーム（ブログの設定だけ）
		icon   => $name eq 'blog' ? {
			action  => $app->url->admin('settings/icon'),
			preview => Lyndbaum::SiteIcon->urls($app)->{icon_192},
			custom  => ($app->settings->{site_icon} // '') ne '',
			saved   => ($opt{icon_done} // '') eq 'saved',
			deleted => ($opt{icon_done} // '') eq 'deleted',
			error   => $opt{icon_error},
		} : undef,
		fields => [ map {
			my $f = $_;
			+{
				%$f,
				is_bool  => $f->{type} eq 'bool',
				is_int   => $f->{type} eq 'int' && !$f->{presets},
				# 選択肢と「直接入力」。部品（preset_field.html）には for の変数 preset で渡す
				preset   => $f->{presets} ? [ Lyndbaum::SettingsForm->preset_field($f, $values->{ $f->{key} }, name => $f->{key}) ] : [],
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
