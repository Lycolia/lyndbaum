package Lyndbaum::Controller::AdminSettings;
# 管理画面の設定（項目の表から画面を作る。項目の書き方は Lyndbaum::SettingsForm）
#   /admin/settings/blog       ブログの設定（Lyndbaum::BlogSettings）
#   /admin/settings/comments   コメントの設定（Lyndbaum::CommentSettings）
#   /admin/settings/editor     編集の設定（Lyndbaum::EditorSettings）
#   POST で保存する。書き方が正しくなければ400で、書いた値を残してフォームを出し直す
#   /admin/settings/icon       サイトのアイコンの入れ替えと削除（POST だけ。ブログの設定の画面にフォームがある。Lyndbaum::SiteIcon）
#   /admin/settings/blog_image ブログの画像の入れ替えと削除（同じ。Lyndbaum::BlogImage）
use strict;
use warnings;
use utf8;

use Lyndbaum::BlogImage;
use Lyndbaum::BlogSettings;
use Lyndbaum::CommentSettings;
use Lyndbaum::Controller::Admin;
use Lyndbaum::EditorSettings;
use Lyndbaum::Model::Setting;
use Lyndbaum::SettingsForm;
use Lyndbaum::SiteIcon;

# ブログの設定の画面で入れ替える画像。ファイルを送るので、設定の項目とは別のフォームにする
#   preview は今の画像のURL（入れていなければ既定のロゴか undef）。saved と deleted は、入れ替えた後と消した後に出す文
my %IMAGES = (
	icon => {
		module  => 'Lyndbaum::SiteIcon',
		title   => 'サイトのアイコン',
		help    => 'ブラウザのタブ、ブックマーク、スマートフォンのホーム画面などに出します。正方形でなければ、真ん中を正方形に切り抜きます。512×512px以上を目安にしてください。動くGIFは最初の1コマだけを使います。',
		square  => 1,
		default => '既定のロゴ',
		delete  => '消して既定のロゴに戻す',
		preview => sub { Lyndbaum::SiteIcon->urls($_[0])->{icon_192} },
		saved   => 'サイトのアイコンを入れ替えました。',
		deleted => 'サイトのアイコンを消して、既定のロゴに戻しました。',
	},
	blog_image => {
		module  => 'Lyndbaum::BlogImage',
		title   => 'ブログの画像',
		help    => 'OGPで、記事に画像が無いときや、トップページに出します。画像はそのまま使います（1200×630pxくらいを目安に）。',
		default => 'ありません（OGPに画像を出しません）',
		delete  => '消す',
		preview => sub { Lyndbaum::BlogImage->url($_[0]) },
		saved   => 'ブログの画像を入れ替えました。',
		deleted => 'ブログの画像を消しました。',
	},
);

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
		image => $req->param('image'), done => $req->param('done'));
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

# サイトのアイコン（icon）とブログの画像（blog_image）。op が delete なら消し、それ以外は送られた画像に入れ替える
#   入れ替えられなければ、400 でブログの設定の画面を出し直して理由を出す
sub save_image {
	my ($class, $app, $req, $key) = @_;
	my $image = $IMAGES{$key} or return $app->not_found;
	my $too_large = $app->admin_session($req) && $req->body_too_large;
	my ($session, $res) = Lyndbaum::Controller::Admin->authorize($app, $req, post => !$too_large);
	return $res if !$session;
	my $error;
	if ($too_large) {
		# 大きすぎる本文は読まないので、CSRFトークンも読めない。何も変えずに理由を出す
		$error = sprintf 'ファイルが大きすぎます（%dMBまで）。', $app->upload_max_bytes / 1024 / 1024;
	} elsif (($req->body_param('op') // '') eq 'delete') {
		$image->{module}->remove($app);
		return $app->redirect($app->url->admin('settings/blog', image => $key, done => 'deleted') . "#$key", 303);
	} else {
		my ($upload) = $req->uploads('file');
		if (!$upload || ($upload->{filename} // '') eq '') {
			$error = '画像を選んでください。';
		} elsif (!eval { $image->{module}->save($app, filename => $upload->{filename}, data => $upload->{data}); 1 }) {
			($error = $@) =~ s/\n\z//;
		} else {
			return $app->redirect($app->url->admin('settings/blog', image => $key, done => 'saved') . "#$key", 303);
		}
	}
	return $class->_render($app, $session, 'blog', $app->settings, [], image => $key, image_error => $error, status => 400);
}

# ブログの設定の画面に出す、画像のフォーム。%opt の image と done（saved か deleted）、image_error は、入れ替えた結果
sub _images {
	my ($class, $app, %opt) = @_;
	return [ map {
		my ($key, $image) = ($_, $IMAGES{$_});
		my $mine = ($opt{image} // '') eq $key;
		my $done = ($opt{done} // '') =~ /\A(?:saved|deleted)\z/ ? $opt{done} : undef;
		+{
			%$image,
			key     => $key,
			action  => $app->url->admin("settings/$key"),
			preview => $image->{preview}->($app),
			custom  => $image->{module}->custom($app),
			notice  => $mine && $done ? $image->{$done} : undef,
			error   => $mine ? $opt{image_error} : undef,
		}
	} qw(icon blog_image) ];
}

sub _render {
	my ($class, $app, $session, $name, $values, $errors, %opt) = @_;
	my $page = $PAGES{$name};
	my %error_of;
	push @{ $error_of{ $_->{key} } }, $_->{message} for @$errors;
	return $app->render_admin('admin_settings', {
		title  => $page->{title},
		# 「ファイル一覧から選択」のある項目があるときだけ
		script => (grep { $_->{media} } @{ $page->{items}->fields }) ? $app->url->static('js/admin-media.js') : undef,
		action => $app->url->admin("settings/$name"),
		saved  => $opt{saved},
		errors => $errors,
		# サイトのアイコンとブログの画像のフォーム（ブログの設定だけ）
		images => $name eq 'blog' ? $class->_images($app, %opt) : [],
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
