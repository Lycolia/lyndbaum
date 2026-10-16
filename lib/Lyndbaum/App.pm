package Lyndbaum::App;
# アプリ本体。設定とDBを持ち、リクエストをコントローラに振り分ける
use strict;
use warnings;
use utf8;

use File::Spec;
use Lyndbaum::Config;
use Lyndbaum::DB;
use Lyndbaum::Model::Session;
use Lyndbaum::Model::Setting;
use Lyndbaum::Model::Tag;
use Lyndbaum::Request;
use Lyndbaum::Response;
use Lyndbaum::Router;
use Lyndbaum::Template;
use Lyndbaum::URL;
use Lyndbaum::View;
use Lyndbaum::Controller::Top;
use Lyndbaum::Controller::Admin;
use Lyndbaum::Controller::AdminArticle;
use Lyndbaum::Controller::AdminComment;
use Lyndbaum::Controller::AdminSettings;
use Lyndbaum::Controller::AdminSidebar;
use Lyndbaum::SidebarBoxes;
use Lyndbaum::Controller::AdminTag;
use Lyndbaum::Controller::AdminUpload;
use Lyndbaum::Controller::AdminMedia;
use Lyndbaum::Media;
use Lyndbaum::OGP;
use Lyndbaum::Controller::Article;
use Lyndbaum::Controller::Comment;
use Lyndbaum::Controller::Search;
use Lyndbaum::Controller::Static;

my $APP_VERSION = '0.2.0-beta';

# ルーティング表。URLから処理を追うときはここを見る
# URLの組み立ては Lyndbaum::URL にある
my $ROUTER = Lyndbaum::Router->new(
	[ GET => qr{\A/\z},             'Lyndbaum::Controller::Top',     'index' ],
	[ GET => qr{\A/search\z},       'Lyndbaum::Controller::Search',  'index' ],
	# 静的なファイル（/pub/assets/、/pub/attachments/、/pub/rss.xml）。Webサーバーが返すので、ここに来るのは無いファイルだけ
	[ GET  => qr{\A/pub(?:/|\z)},   'Lyndbaum::Controller::Static',  'not_found' ],
	[ POST => qr{\A/pub(?:/|\z)},   'Lyndbaum::Controller::Static',  'not_found' ],
	# 管理画面
	[ GET  => qr{\A/admin\z},        'Lyndbaum::Controller::Admin',   'dashboard'  ],
	[ GET  => qr{\A/admin/login\z},  'Lyndbaum::Controller::Admin',   'login_form' ],
	[ POST => qr{\A/admin/login\z},  'Lyndbaum::Controller::Admin',   'login'      ],
	[ POST => qr{\A/admin/logout\z}, 'Lyndbaum::Controller::Admin',   'logout'     ],
	[ GET  => qr{\A/admin/articles\z},          'Lyndbaum::Controller::AdminArticle', 'index'     ],
	[ GET  => qr{\A/admin/articles/new\z},      'Lyndbaum::Controller::AdminArticle', 'new_form'  ],
	[ POST => qr{\A/admin/articles\z},          'Lyndbaum::Controller::AdminArticle', 'create'    ],
	[ GET  => qr{\A/admin/articles/(\d+)\z},    'Lyndbaum::Controller::AdminArticle', 'edit_form' ],
	[ POST => qr{\A/admin/articles/(\d+)\z},    'Lyndbaum::Controller::AdminArticle', 'update'    ],
	[ GET  => qr{\A/admin/articles/(\d+)/revisions/(\d+)\z}, 'Lyndbaum::Controller::AdminArticle', 'revision' ],
	[ POST => qr{\A/admin/articles/(\d+)/trash\z}, 'Lyndbaum::Controller::AdminArticle', 'trash'  ],
	[ POST => qr{\A/admin/articles/trash\z},    'Lyndbaum::Controller::AdminArticle', 'trash_selected' ],
	[ GET  => qr{\A/admin/trash\z},             'Lyndbaum::Controller::AdminArticle', 'trash_index'    ],
	[ POST => qr{\A/admin/trash\z},             'Lyndbaum::Controller::AdminArticle', 'trash_update'   ],
	[ GET  => qr{\A/admin/tags\z},              'Lyndbaum::Controller::AdminTag',     'index'     ],
	[ POST => qr{\A/admin/tags\z},              'Lyndbaum::Controller::AdminTag',     'save'      ],
	[ GET  => qr{\A/admin/media\z},             'Lyndbaum::Controller::AdminMedia',   'page'       ],
	[ GET  => qr{\A/admin/media/folders\z},     'Lyndbaum::Controller::AdminMedia',   'folders'    ],
	[ GET  => qr{\A/admin/media/files\z},       'Lyndbaum::Controller::AdminMedia',   'files'      ],
	[ GET  => qr{\A/admin/media/usage\z},       'Lyndbaum::Controller::AdminMedia',   'usage'      ],
	[ POST => qr{\A/admin/media/trash\z},       'Lyndbaum::Controller::AdminMedia',   'trash'      ],
	[ GET  => qr{\A/admin/media/trash\z},       'Lyndbaum::Controller::AdminMedia',   'trash_list' ],
	[ POST => qr{\A/admin/media/trash/restore\z}, 'Lyndbaum::Controller::AdminMedia', 'restore'    ],
	[ POST => qr{\A/admin/media/trash/purge\z}, 'Lyndbaum::Controller::AdminMedia',   'purge'      ],
	[ POST => qr{\A/admin/upload\z},            'Lyndbaum::Controller::AdminUpload',  'upload'    ],
	[ POST => qr{\A/admin/rebuild\z},           'Lyndbaum::Controller::AdminArticle', 'rebuild'   ],
	[ GET  => qr{\A/admin/comments\z},          'Lyndbaum::Controller::AdminComment', 'index'         ],
	[ POST => qr{\A/admin/comments/(\d+)\z},    'Lyndbaum::Controller::AdminComment', 'update'        ],
	[ GET  => qr{\A/admin/sidebar\z},           'Lyndbaum::Controller::AdminSidebar', 'form' ],
	[ POST => qr{\A/admin/sidebar\z},           'Lyndbaum::Controller::AdminSidebar', 'save' ],
	[ GET  => qr{\A/admin/settings/(\w+)\z},   'Lyndbaum::Controller::AdminSettings', 'form' ],
	[ POST => qr{\A/admin/settings/(\w+)\z},   'Lyndbaum::Controller::AdminSettings', 'save' ],
	# 記事（/0575）とコンテンツページ（/親/子）。パスは slug と同じ
	# ほかのどれにも当たらなかったものを見るので最後に置く。コンテンツページの slug には、
	# ここより前のもの（search、pub と pub/…、admin と admin/…）を使えない
	[ GET  => qr{\A/(.+)\z},         'Lyndbaum::Controller::Article', 'show'   ],
	[ POST => qr{\A/(.+)\z},         'Lyndbaum::Controller::Comment', 'create' ],   # コメントの投稿
);

sub new {
	my ($class, %args) = @_;
	my $config = $args{config} // Lyndbaum::Config->load($args{config_file});
	return bless {
		root   => $args{root},
		config => $config,
	}, $class;
}

sub config { $_[0]{config} }

# DBへの接続は、必要になったときに一度だけ行う
sub db {
	my ($self) = @_;
	$self->{db} //= Lyndbaum::DB->connect($self->config->path_of('db_path', $self->{root}));
	return $self->{db};
}

sub url {
	my ($self) = @_;
	return $self->{url} //= Lyndbaum::URL->new(
		base_path   => $self->config->get('base_path'),
		static_path => $self->config->get('static_path'),
		attachment_path => $self->config->get('attachment_path'),
	);
}

# 絶対 URL の元（https://blog.example.jp）。config.json の site_url。無ければリクエストのホスト名から作る
sub site_base {
	my ($self, $req) = @_;
	my $site = $self->config->get('site_url') // '';
	return $site ne '' ? $site =~ s{/+\z}{}r : $req->own_origin;
}

# 公開側のページの <head> に足すもの（canonical、meta description、OGP）
#   %args：path（ページのパス）、type（article か website）、title、description、image（Lyndbaum::OGP->tags）
sub page_head {
	my ($self, $req, %args) = @_;
	my $base = $self->site_base($req);
	my $url  = $base . $args{path};
	return {
		canonical   => $url,
		description => $args{description},
		ogp         => Lyndbaum::OGP->tags($self, %args, url => $url, base => $base),
	};
}

# 添付ファイルを置くディレクトリ（ファイルシステムのパス）。config.json の attachment_dir（既定は pub/attachments）
#   URL の attachment_path と同じ場所を指すようにする
sub attachment_dir {
	my ($self) = @_;
	my $dir = $self->config->get('attachment_dir') // 'pub/attachments';
	return File::Spec->file_name_is_absolute($dir) ? $dir : File::Spec->catdir($self->{root}, $dir);
}

# 添付ファイルの一覧とゴミ箱（Lyndbaum::Media）
#   ゴミ箱は添付ファイルの置き場所の .trashbox（旧システムと同じ）。Web から見えるので、ゴミ箱の中もサムネイルで確かめられる
#   （. で始まるので、メディアのフォルダの木には出ない）
sub media {
	my ($self) = @_;
	return $self->{media} //= Lyndbaum::Media->new(
		dir       => $self->attachment_dir,
		trash_dir => File::Spec->catdir($self->attachment_dir, $Lyndbaum::Media::TRASH),
	);
}

# ファイルを送るフォームの本文の大きさの上限（バイト）。config.json の upload_max_mb（既定は 20）
sub upload_max_bytes {
	my ($self) = @_;
	my $mb = $self->config->get('upload_max_mb') // 20;
	return ($mb =~ /\A\d+\z/ ? $mb : 20) * 1024 * 1024;
}

# サイトの中のパス（/0575 など）を絶対URLにする。RSSのように、ページの外で使うURLに使う
#   tools/ から書き出すときはリクエストが無く、ホスト名がわからないので、config.json の site_url を使う
sub absolute_url {
	my ($self, $path) = @_;
	my $site = $self->config->get('site_url') // '';
	die "config.json に site_url（例：https://blog.example.jp）がありません\n" if $site eq '';
	$site =~ s{/+\z}{};
	return $site . $path;
}

sub settings {
	my ($self) = @_;
	return $self->{settings} //= Lyndbaum::Model::Setting->all($self->db);
}

# 全タグ。1リクエストの中では使い回す
sub tags {
	my ($self) = @_;
	return $self->{tags} //= Lyndbaum::Model::Tag->all($self->db);
}

# 本文の変換に使う設定（Lyndbaum::Parser->parse に渡すもの）
sub parser_context {
	my ($self) = @_;
	my $dbh = $self->db;
	return (
		attachment_path => $self->config->get('attachment_path') // '/pub/attachments/',
		sectioning      => 1,
		url_title       => sub {
			scalar $dbh->selectrow_array('SELECT title FROM url_cache WHERE url = ? AND ok = 1', undef, $_[0]);
		},
		base_path       => $self->config->get('base_path') // '',
	);
}

sub template {
	my ($self) = @_;
	return $self->{template} //= Lyndbaum::Template->new(dir => File::Spec->catdir($self->{root}, 'templates'));
}

# %opt は Lyndbaum::Request->new に渡す（input：POST の本文を読むファイルハンドル）
sub handle {
	my ($self, $env, %opt) = @_;
	my $req = Lyndbaum::Request->new($env, max_upload => $self->upload_max_bytes, %opt);

	my ($class, $action, @captures) = $ROUTER->match($req->method, $req->path);
	return $self->not_found if !$class;

	return $class->$action($self, $req, @captures);
}

# 公開側のページを出力する。テンプレートの出力を layout.html で包む
sub render {
	my ($self, $name, $vars, %args) = @_;
	my %common = (
		blog         => $self->settings,
		urls         => {
			top    => $self->url->top,
			search => $self->url->search,
			style  => $self->url->static('css/style.css'),
			feed   => $self->url->feed,
			# 画像の拡大表示（Fancybox）とコードの色付け（Prism.js）。pub/assets/js/article.js が動かす
			fancybox_css => $self->url->static('js/extlib/fancybox/jquery.fancybox.min.css'),
			prism_css    => $self->url->static('js/extlib/prismjs/prism.css'),
			prism_core   => $self->url->static('js/extlib/prismjs/prism-core.min.js'),
			scripts      => [ map { $self->url->static($_) }
				'js/extlib/fancybox/jquery-3.2.1.min.js', 'js/extlib/fancybox/jquery.fancybox.min.js',
				'js/extlib/prismjs/prism-autoloader.min.js', 'js/extlib/prismjs/prism-line-numbers.min.js',
				'js/extlib/prismjs/prism-toolbar.min.js', 'js/extlib/prismjs/prism-copy-to-clipboard.min.js',
				'js/article.js' ],
		},
		form         => Lyndbaum::Controller::Search->form,   # サイドバーの検索フォーム
		content_tree => Lyndbaum::View->content_tree($self),
		tag_tree     => Lyndbaum::View->tag_tree($self),
		recent_comments => Lyndbaum::View->recent_comments($self),
		recent_posts    => Lyndbaum::View->recent_posts($self),
		archive         => Lyndbaum::View->archive($self),
		sidebar_boxes   => Lyndbaum::SidebarBoxes->for_display($self->settings->{sidebar_boxes}),
		app_version => $APP_VERSION
	);
	my %all = (%common, %$vars);
	my $content = $self->template->render($name, \%all);
	my $html    = $self->template->render('layout', { %all, content => $content });
	return Lyndbaum::Response->html($html, status => $args{status} // 200);
}

# 管理画面のページを出力する。テンプレートの出力を admin_layout.html で包む
#   ブラウザやプロキシに残さず、ほかのサイトの枠の中にも表示させない
sub render_admin {
	my ($self, $name, $vars, %args) = @_;
	my $session = $args{session};
	my %all = (
		blog       => $self->settings,
		urls       => {
			top    => $self->url->top,
			admin            => $self->url->admin,
			logout           => $self->url->admin('logout'),
			articles         => $self->url->admin('articles'),
			new_article      => $self->url->admin('articles/new'),
			new_page         => $self->url->admin('articles/new', kind => 'page'),
			trash_selected   => $self->url->admin('articles/trash'),
			trash            => $self->url->admin('trash'),
			tags             => $self->url->admin('tags'),
			upload           => $self->url->admin('upload'),
			media            => $self->url->admin('media'),
			media_script     => $self->url->static('js/admin-media.js'),
			admin_script     => $self->url->static('js/admin.js'),
			rebuild          => $self->url->admin('rebuild'),
			comments         => $self->url->admin('comments'),
			blog_settings    => $self->url->admin('settings/blog'),
			comment_settings => $self->url->admin('settings/comments'),
			editor_settings  => $self->url->admin('settings/editor'),
			sidebar          => $self->url->admin('sidebar'),
			style  => $self->url->static('css/style.css'),
		},
		logged_in  => $session ? 1 : 0,
		csrf_token => $session ? $session->{csrf_token} : '',
		%$vars,
	);
	my $content = $self->template->render($name, \%all);
	my $html    = $self->template->render('admin_layout', { %all, content => $content });
	return admin_headers(Lyndbaum::Response->html($html, status => $args{status} // 200));
}

# 管理画面の応答に付けるヘッダー
sub admin_headers {
	my ($res) = @_;
	return $res
		->add_header('Cache-Control', 'no-store')
		->add_header('X-Frame-Options', 'DENY')
		->add_header('Content-Security-Policy', "frame-ancestors 'none'");
}

#----------------------------------------------------------------------
# 管理者のセッション
#----------------------------------------------------------------------

my $SESSION_COOKIE = 'lyndbaum_session';

# ログイン中ならセッション（{ csrf_token, ... }）、そうでなければ undef
sub admin_session {
	my ($self, $req) = @_;
	return Lyndbaum::Model::Session->find($self->db, $req->cookie($SESSION_COOKIE));
}

# 管理者のログイン名（なりすましを見るため）。登録されていなければ undef
sub admin_login {
	my ($self) = @_;
	return scalar $self->db->selectrow_array('SELECT login FROM admin WHERE id = 1');
}

sub session_token {
	my ($self, $req) = @_;
	return $req->cookie($SESSION_COOKIE);
}

# セッションの Cookie。$token が undef なら消す
#   Secure は既定で付ける。手元の http で試すときだけ、設定の cookie_secure を false にする
sub session_cookie {
	my ($self, $token, $expires_at) = @_;
	my $path = $self->config->get('base_path') || '/';
	my @attrs = ("Path=$path", 'HttpOnly', 'SameSite=Lax');
	push @attrs, 'Secure' if $self->config->get('cookie_secure') // 1;
	if (defined $token) {
		return join '; ', "$SESSION_COOKIE=$token", 'Max-Age=' . ($expires_at - time), @attrs;
	}
	return join '; ', "$SESSION_COOKIE=", 'Max-Age=0', @attrs;
}

sub redirect {
	my ($self, $location, $status) = @_;
	return Lyndbaum::Response->new(
		status       => $status // 301,
		content_type => 'text/plain',
		headers      => [ Location => $location ],
		body         => "Moved\n",
	);
}

sub not_found {
	my ($self) = @_;
	return $self->render('not_found', { title => 'ページが見つかりません' }, status => 404);
}

1;
