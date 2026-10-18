package Lyndbaum::App;
# アプリ本体。設定とDBを持ち、リクエストをコントローラに振り分ける
use strict;
use warnings;
use utf8;

use File::Spec;
use Lyndbaum::Config;
use Lyndbaum::DB;
use Lyndbaum::Model::Comment;
use Lyndbaum::Model::Setting;
use Lyndbaum::Model::Tag;
use Lyndbaum::Request;
use Lyndbaum::Response;
use Lyndbaum::Router;
use Lyndbaum::Template;
use Lyndbaum::Backlinks;
use Lyndbaum::URL;
use Lyndbaum::View;
use Lyndbaum::SidebarCache;
use Lyndbaum::OGP;
use Lyndbaum::SearchForm;

my $APP_VERSION = '0.1.0-beta5';

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
	require Lyndbaum::Media;
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
		# slug から記事のURLを作る関数。Lyndbaum::Model::Article->rebuild_body が article_url にして渡す
		article_url_of  => sub { $self->url->article($_[0]) },
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

	# クラス名は上のルーティング表にある固定値。require は読み込み済みなら再実行しない
	my $module = $class =~ s{::}{/}gr;
	require "$module.pm";
	my $res = $class->$action($self, $req, @captures);
	# 更新によって無効になったHTMLは、次の閲覧を待たずに作り直す
	#   更新はコミット済みなので、作り直せなくてもエラーにしない（次の閲覧で作る）
	if ($req->method eq 'POST') {
		eval { Lyndbaum::SidebarCache->get($self); 1 }
			or warn "サイドバーのHTMLを作り直せませんでした: $@";
		eval { Lyndbaum::Backlinks->rebuild($self); 1 }
			or warn "参照元のHTMLを作り直せませんでした: $@";
	}
	return $res;
}

# 公開側のページを出力する。テンプレートの出力を layout.html で包む
#   %args
#     status  応答のステータス（既定は 200）
#     req     リクエスト。渡すと、ログイン中なら画面の上に管理者のメニューを出す
#     edit    管理者のメニューの「編集」の行き先（記事のページで渡す）
sub render {
	my ($self, $name, $vars, %args) = @_;
	my $session = $args{req} ? $self->admin_session($args{req}) : undef;
	my $sidebar = Lyndbaum::SidebarCache->get($self);
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
				'js/article.js', 'js/sidebar.js' ],
		},
		form         => Lyndbaum::SearchForm->values,   # サイドバーの検索フォーム
		%$sidebar,
		app_version => $APP_VERSION,
		admin_bar   => $session ? $self->_admin_bar($session, %args) : undef,
	);
	my %all = (%common, %$vars);
	my $content = $self->template->render($name, \%all);
	my $html    = $self->template->render('layout', { %all, content => $content });
	my $res = Lyndbaum::Response->html($html, status => $args{status} // 200);
	# 管理者のメニューにはログアウトのボタンと CSRF のトークンが入るので、管理画面と同じく
	# ブラウザやプロキシに残さず、ほかのサイトの枠の中にも表示させない
	return $session ? admin_headers($res) : $res;
}

# 画面の上に出す、管理者のメニュー（templates/admin_bar.html）
#   左端は、公開側ではダッシュボード、管理画面ではブログ（WordPress と同じ）
#   %args
#     held   承認待ちのコメントの数（呼ぶ側で数えてあれば渡す）
#     new    新着のコメントの数（同じ）
#     admin  真なら管理画面に出すもの
#     edit   「編集」の行き先
sub _admin_bar {
	my ($self, $session, %args) = @_;
	my $held = $args{held} // Lyndbaum::Model::Comment->count_by_status($self->db)->{held};
	my $new  = $args{new} // Lyndbaum::Model::Comment->count_new($self->db);
	return {
		home_url    => $args{admin} ? $self->url->top : $self->url->admin,
		home_label  => $args{admin} ? 'ブログを表示' : 'ダッシュボード',
		new_article => $self->url->admin('articles/new'),
		new_page    => $self->url->admin('articles/new', kind => 'page'),
		# 新着があれば、すべての一覧（開くと既読になる）。無くて承認待ちがあれば、承認待ちの一覧
		comments    => _comments_url($self, $new, $held),
		held_count  => $held,
		new_count   => $new,
		edit        => $args{edit},
		logout      => $self->url->admin('logout'),
		csrf_token  => $session->{csrf_token},
	};
}

# 管理画面の左のナビで、今のページとして目立たせる項目（_admin_menu の key）。テンプレートの名前から決める
#   同じテンプレートで複数の項目にあたるもの（設定、記事の編集）は、呼ぶ側が render_admin に nav を渡す
my %NAV_OF = (
	admin_dashboard    => 'dashboard',
	admin_articles     => 'articles',
	admin_article_form => 'articles',
	admin_trash        => 'trash',
	admin_media        => 'media',
	admin_comments     => 'comments',
	admin_tags         => 'tags',
	admin_sidebar      => 'sidebar',
	admin_settings     => 'blog_settings',
);

# 管理画面のページを出力する。テンプレートの出力を admin_layout.html で包む
#   ブラウザやプロキシに残さず、ほかのサイトの枠の中にも表示させない
#   %args
#     session  ログイン中のセッション。渡すと、上のバーと左のナビを出す
#     status   応答のステータス（既定は 200）
#     nav      左のナビで目立たせる項目（省くとテンプレートの名前から決める）
sub render_admin {
	my ($self, $name, $vars, %args) = @_;
	my $session = $args{session};
	my $held    = $session ? Lyndbaum::Model::Comment->count_by_status($self->db)->{held} : 0;
	my $new     = $session ? Lyndbaum::Model::Comment->count_new($self->db) : 0;
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
			unsaved_script   => $self->url->static('js/admin-unsaved.js'),
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
		admin_bar  => $session ? $self->_admin_bar($session, admin => 1, held => $held, new => $new) : undef,
		admin_menu => $session ? $self->_admin_menu($args{nav} // $NAV_OF{$name} // '', $held, $new) : undef,
		%$vars,
	);
	my $content = $self->template->render($name, \%all);
	my $html    = $self->template->render('admin_layout', { %all, content => $content });
	return admin_headers(Lyndbaum::Response->html($html, status => $args{status} // 200));
}

# 管理画面の左のナビ（templates/admin_layout.html）
#   子のある項目は、今のページがその中にあるときだけ子を出す（WordPress と同じ）
#   [ { key, label, url, count, new_count, current, open, children => [ { key, label, url, current }, ... ] }, ... ]
#   count は承認待ち、new_count は新着のコメントの数（コメントの項目だけ）
sub _admin_menu {
	my ($self, $nav, $held, $new) = @_;
	my $u = $self->url;
	my @menu = (
		[ dashboard => 'ダッシュボード', $u->admin ],
		[ articles  => '記事', $u->admin('articles'), [
			[ articles    => '記事の一覧', $u->admin('articles') ],
			[ new_article => '新しい記事', $u->admin('articles/new') ],
		] ],
		[ pages     => 'ページ', $u->admin('articles', kind => 'page'), [
			[ pages    => 'ページの一覧', $u->admin('articles', kind => 'page') ],
			[ new_page => '新しいページ', $u->admin('articles/new', kind => 'page') ],
		] ],
		[ trash     => 'ゴミ箱', $u->admin('trash') ],
		[ media     => 'メディア', $u->admin('media') ],
		[ comments  => 'コメント', _comments_url($self, $new, $held), undef, $held, $new ],
		[ tags      => 'タグ',     $u->admin('tags') ],
		[ sidebar   => 'サイドバー', $u->admin('sidebar') ],
		[ settings  => '設定', $u->admin('settings/blog'), [
			[ blog_settings    => 'ブログ',   $u->admin('settings/blog') ],
			[ comment_settings => 'コメント', $u->admin('settings/comments') ],
			[ editor_settings  => '編集',     $u->admin('settings/editor') ],
		] ],
	);
	return [ map {
		my ($key, $label, $url, $children, $count, $new_count) = @$_;
		my @children = map { +{ key => $_->[0], label => $_->[1], url => $_->[2], current => $_->[0] eq $nav } } @{ $children // [] };
		my $open = grep { $_->{current} } @children;
		+{
			key      => $key,
			label    => $label,
			url      => $url,
			count    => $count,
			new_count => $new_count,
			current  => ($key eq $nav || $open) ? 1 : 0,
			children => $open ? \@children : [],
		};
	} @menu ];
}

# 管理者のメニューとナビの「コメント」の行き先
#   新着があれば、すべての一覧（開くと既読になる）。無くて承認待ちがあれば、承認待ちの一覧
sub _comments_url {
	my ($self, $new, $held) = @_;
	return $self->url->admin('comments', status => !$new && $held ? 'held' : undef);
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
#   1つのリクエストの中では、最初に調べた結果を使い回す（記事のページでは何度か調べるため）
sub admin_session {
	my ($self, $req) = @_;
	if (!exists $req->{admin_session}) {
		my $token = $req->cookie($SESSION_COOKIE);
		$req->{admin_session} = undef;
		if (defined $token && $token ne '') {
			require Lyndbaum::Model::Session;
			$req->{admin_session} = Lyndbaum::Model::Session->find($self->db, $token);
		}
	}
	return $req->{admin_session};
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
