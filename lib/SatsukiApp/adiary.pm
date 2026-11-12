use strict;
#-------------------------------------------------------------------------------
# ブログシステム - adiary
#						(C)2006-2024 nabe@abk
#-------------------------------------------------------------------------------
package SatsukiApp::adiary;
use Satsuki::AutoLoader;
use Fcntl;
#-------------------------------------------------------------------------------
our $SYSTEM_NAME = 'Lyndbaum';
our $REPOSITORY_URL = 'https://github.com/Lycolia/lyndbaum';
our $SYSTEM_DESCRIPTION = 'Neo-Modern High-performance CMS software';
# データ管理上数値しか解釈できないので文字列にしてはならない
our $VERSION    = 4.41;
# -fix2, dev3, -nightlyみたいなのを入れる想定
our $BRANCH_VERSION = '';
our $OUTVERSION = sprintf('%.2f', $VERSION) . $BRANCH_VERSION;	# 数値のままだと4.30が4.3になる
our $DATA_VERSION = 4.39;
################################################################################
# ■システム内部イベント
################################################################################
my %SysEvt;
$SysEvt{ARTICLE_FIRST_VISIBLE_PING} = [qw(
	send_update_ping
)];
$SysEvt{ARTICLE_STATE_CHANGE} = [qw(
	update_bloginfo_article
	update_taglist
	update_contents_list
	update_backlinks
)];
$SysEvt{COMMENT_STATE_CHANGE} = [qw(
	update_bloginfo_comment
)];
$SysEvt{ARTCOM_STATE_CHANGE} = [qw(
	generate_rss
)];

################################################################################
# ●コンストラクタ
################################################################################
sub new {
	my ($class, $ROBJ, $DB, $self) = @_;
	if (ref($self) ne 'HASH') { $self={}; }
	bless($self, $class);
	$self->{__FINISH} = 1;

	$self->{ROBJ}    = $ROBJ;
	$self->{DB}      = $DB;
	$self->{VERSION} = $VERSION;
	$self->{OUTVERSION} = $OUTVERSION;
	$self->{SYSTEM_NAME}        = $SYSTEM_NAME;
	$self->{REPOSITORY_URL}     = $REPOSITORY_URL;
	$self->{SYSTEM_DESCRIPTION} = $SYSTEM_DESCRIPTION;
	$self->{HttpReferer} = $ENV{'HTTP_REFERER'} || '';

	# ディフォルト値の設定
	$self->SetDefaultValue();
	$self->{http_agent} = "$SYSTEM_NAME $OUTVERSION on Satsuki-system $ROBJ->{VERSION}";

	# Cache環境向け Timer のロード
	if ($ROBJ->{CGI_cache} && $ENV{SatsukiTimer} ne '0' && !$Satsuki::Timer::VERSION) {
		require Satsuki::Timer;
	}

	return $self;
}

#-------------------------------------------------------------------------------
# ●ディフォルト値の設定
#-------------------------------------------------------------------------------
sub SetDefaultValue {
	my $self = shift;
	my $ROBJ = $self->{ROBJ};

	my %h = (
# フォルダ。Webサーバーの設定もこの場所を前提にしているので、変えない
pub_dir		=> 'pub/',
pubdist_dir	=> 'pub/assets/dist/',
theme_dir	=> 'pub/assets/theme/',
script_dir	=> 'pub/assets/js/',
data_dir	=> 'data/',
info_dir	=> 'info/',
plugin_dir	=> 'plugin/',
# 関連ファイル
system_config_file   => 'data/system_config.dat',
default_config_file  => 'info/default_config.dat',
default_usercss_file => 'info/default_usercss.css',
default_usertag_file => 'info/default_usertag.txt',
default_setting_file => 'info/default_setting.dat',
default_design_file  => 'info/default_design.dat',
allow_tags_head      => 'info/allow_tags_',
# テーマが読めないときに使うテーマ
default_theme	=> 'lyndbaum/lyndbaum',
# パーサー
parsers		=> {
	_order	  => [ qw(markdown simple simple_br) ],
	markdown  => 'Markdown',
	simple	  => 'HTML（そのまま）',
	simple_br => 'HTML（改行処理）'
},
rss_skeleton	=> '_format/rss20',		# RSS 2.0（コメント含む）
words_separator	=> '\s　',			# 検索時のスペース類文字（正規表現）
# アップロードと画像アルバム。ユーザー設定で変えられる
uplaod_files_max   => 64 * 1048576,		# 1回あたりの合計の上限
album_jpeg_quality => 80,			# JPEGサムネイルの品質
album_avif_quality => 65,			# AVIFサムネイルの品質
album_image_ext    => { map { $_ => 1 } qw(jpg jpeg gif png apng webp avif) },	# 許可する画像の拡張子
# 画像以外をアップロードしたときのアイコンと、サムネイルに埋め込むファイル情報のフォント
album_icons	=> 'pub/assets/dist/album-icon/',
album_font	=> 'pub/assets/dist/VL-PGothic-Regular.ttf',
album_font_size	=> 11,
# 内部の設定
blog_cache_unit  => 100,	# ブログ記事キャッシュ保存時の分割単位
theme_skeleton_level => 10,
user_skeleton_level  => 20,
theme_design_skeleton_level => 21,	# テンプレート別に生成したデザイン
default_tag_priority => 100000,
default_wiki_priority=> 100000,
main_skeleton	=> '_main',
article_skeleton=> '_article',
frame_skeleton	=> '_frame',
admin_frame_skeleton => '_frame_admin'
	);
	foreach(keys(%h)) {
		if (!exists($self->{$_})) { $self->{$_} = $h{$_}; }
	}
}

################################################################################
# ●デストラクタ
################################################################################
sub FINISH {
	my $self = shift;
	$self->save_blogset_sys();
	$self->save_sysdat();
}

################################################################################
# ■メイン処理
################################################################################
sub main {
	my $self = shift;
	my $ROBJ = $self->{ROBJ};

	# 現在の日時設定（日付変更時間対策）。設定ファイルの後に初期化されるので、newでは取れない
	$self->{now} = $ROBJ->{Now};

	# システム情報のロード
	my $sys = $self->load_sysdat();

	# 画面で変えた設定（システム設定）。無ければ既定値かユーザー設定の値のまま
	$self->apply_sys_settings($sys);

	# Cookieログイン処理
	$self->authorization();

	# ログイン中の画面は、途中のキャッシュにもブラウザーにも保存させない（管理バーや管理者だけの知らせが入るため）
	if ($ROBJ->{Auth}->{ok}) {
		$ROBJ->{Cache_control} = 'private, no-store';
	}

	# ServerURLのセキィリティを確保
	$self->secure_http_host();

	# 外部HTTPリクエストのUser-Agent
	$ROBJ->{HttpAgent} = "$SYSTEM_NAME v$OUTVERSION" . ($sys->{ServerURL} ? " ($sys->{ServerURL})" : '');

	# pinfoとブログの選択。テーマ選択
	$self->select_blog_and_pinfo();

	# Query/Form処理  ※テーマ選択より後に処理
	$self->read_query_form();

	# 表示スケルトン選択
	$self->select_skeleton( $ROBJ->{Query}->{_} || $self->{query0} );

	# ブログを読めないときは、何も処理せず知らせるだけ
	if ($self->{blog_error}) {
		$ROBJ->{POST} = 0;
		$ROBJ->set_status(503);
		$self->{skeleton} = '_sub/blog_error';
	}

	# ほかのOriginから送られたPOSTは、何も処理せず断る
	if ($ROBJ->{POST} && !$self->is_same_origin_post()) {
		$ROBJ->form_clear();
		$ROBJ->set_status(403);
		$self->{skeleton} = '_sub/post_denied';
	}

	# 初期セットアップの前は、セットアップの画面と処理のほかは何もさせない（公開画面も出さない）
	if (!$self->{blog_error} && $self->is_before_setup()) {
		$self->{setup_mode} = 1;
		if (!$ROBJ->{POST} || $ROBJ->{Form}->{action} ne '_ajax_setup') {
			$ROBJ->{POST} = 0;
			$ROBJ->{Form} = {};
			if ($self->{skeleton} ne 'setup' && $self->{skeleton} ne '_sub/post_denied') {
				$ROBJ->redirect( $self->{myself} . '?setup' );
			}
		}
	}

	#-------------------------------------------------------------
	# POST action判定
	#-------------------------------------------------------------
	my $action = $ROBJ->{POST} && $ROBJ->{Form}->{action};

	if ($action ne '_ajax_login' && !$self->{setup_mode}) {
		# メンテナンスモード
		if ($sys->{mainte_mode} || $self->{require_update}) { $self->mainte_mode(); }
	}
	$action = $ROBJ->{POST} && $ROBJ->{Form}->{action};	# メンテナンスモードで止めた操作は行わない

	#-------------------------------------------------------------
	# POST actionの呼び出し
	#-------------------------------------------------------------
	if ($action) {
		if ($action =~ /^_ajax_\w+$/) {
			my $data = $self->ajax_function( $action );

			# Append debug message
			if ($ROBJ->{Develop} && ref($data) eq 'HASH') {
				$data->{_develop} = 1;
				if (my $err = ($ROBJ->clear_error() . join("\n", @{$ROBJ->{Message}}, @{$ROBJ->{Debug}}))) {
					$data->{_debug} = $err;
				}
			}
			$self->{action_data} = $ROBJ->generate_json( $data );

		} elsif (my ($dir,$file) = $self->parse_skel($action)) {
			local($self->{skel_dir}) = $dir;
			$self->{action_data} = $ROBJ->call( "${dir}_action/$file" );
		}
	}

	#-------------------------------------------------------------
	# スケルトン呼び出し（出力）
	#-------------------------------------------------------------
	$self->output_html();
}

################################################################################
# ■メイン処理ルーチン
################################################################################
#-------------------------------------------------------------------------------
# ●Cookie と Authorization 処理
#-------------------------------------------------------------------------------
sub authorization {
	my $self = shift;
	my $ROBJ = $self->{ROBJ};
	my $auth = $ROBJ->{Auth};

	my $cookie = $ROBJ->get_cookie();
	my $session = $cookie->{session};
	if (ref $session eq 'HASH') {	# ログインセッション処理
		$auth->session_auth($session->{id}, $session->{sid});
	}
	# 管理者 trust mode 設定
	if ($self->{admin_trust_mode} && $auth->{isadmin}) {
		$self->{trust_mode} = 1;
	}
}

#-------------------------------------------------------------------------------
# ●HTTP_HOST インジェクション対策
#-------------------------------------------------------------------------------
sub secure_http_host {
	my $self = shift;
	my $ROBJ = $self->{ROBJ};

	my $srv  = $ROBJ->{ServerURL};
	my $save = $self->{sys}->{ServerURL};

	if (!$ROBJ->{Auth}->{isadmin}) {
		$ROBJ->{ServerURL} = $save || $srv;
	} elsif ($srv ne $save) {
		# 管理者ログイン時の ServerURL を保存しておく
		$self->update_sysdat('ServerURL', $srv);
	}
}

#-------------------------------------------------------------------------------
# ●POSTの送信元が同じOriginか
#-------------------------------------------------------------------------------
# SameSite=Laxでは、隣のサブドメインのような同じサイトからのPOSTを防げないので確かめる。
# Sec-Fetch-Siteは平文のHTTPでは送られないので、そのときはOriginとHostを比べる。
# どちらも無ければ、ブラウザー以外か古いブラウザーなので通す（SameSite=Laxが受け持つ）。
sub is_same_origin_post {
	my $site = lc($ENV{HTTP_SEC_FETCH_SITE});
	if ($site ne '') { return $site eq 'same-origin' || $site eq 'none'; }

	my $origin = $ENV{HTTP_ORIGIN};
	if ($origin eq '') { return 1; }
	return $origin =~ m!^https?://([^/]+)$!i && lc($1) eq lc($ENV{HTTP_HOST});
}

#-------------------------------------------------------------------------------
# ●pinfoとブログ選択処理
#-------------------------------------------------------------------------------
sub select_blog_and_pinfo {
	my $self = shift;
	my $ROBJ = $self->{ROBJ};

	my @pinfo   = @{ $ROBJ->read_path_info() };	# PATH_INFO

	# ブログは1つだけ。無ければ作る。アップデートが要るときは、処理の後に作る
	if (!$self->{require_update} && !$self->exists_blog()) {
		$self->blog_auto_create();
	}
	$self->select_blog();
	if (!$self->{blog} && !$self->{require_update}) {
		$self->{blog_error} = 1;
		print STDERR "$self->{SYSTEM_NAME}: blog is not available. Check " . $self->blog_dir() . " and the blog tables.\n";
	}

	# テーマの設定（$self->{blog}->{theme} と書くと、ブログが無いときに空のハッシュができる）
	my $theme = ($self->{blog} || {})->{theme};
	if (!$theme || $self->load_theme($theme)) {
		$self->load_theme( $self->{default_theme} );
	}

	# pinfoの保存
	my $pinfo = join('/', @pinfo);
	$self->{pinfo}   = $pinfo;
	$self->link_key_encode( $pinfo );
	$self->{e_pinfo} = $pinfo;
	$self->{thisurl} = $pinfo eq '' ? $self->{myself} : ($self->{myself2} . $pinfo);
}

#-------------------------------------------------------------------------------
# ●Query/Form処理
#-------------------------------------------------------------------------------
sub read_query_form {
	my $self = shift;
	my $ROBJ = $self->{ROBJ};

	$ROBJ->read_form();
	my $query = $ENV{QUERY_STRING};
	my $q = $ROBJ->read_query({'t'=>1});
	delete $q->{''};

	# 特殊Queryの処理
	foreach(qw(_theme)) {
		if (!$q->{$_}) { next; }
		# テーマ指定は、デザイン編集のテーマのプレビュー用。ブログの管理者のみ
		if (!$self->{blog_admin}) { delete $q->{$_}; next; }
		my $v = $q->{$_};
		$v =~ s|[^\w\-/]||g;

		$self->load_theme( $v );
		$ROBJ->{no_robots}=1;
		$self->{sp_query} .= "&$_=$v";
		delete $q->{$_};
	}

	# スケルトン指定解釈
	if (%$q) {
		$self->{query} = $query;
		$query =~ m|^([\w\.\-/=]*)|;
		my $q0 = $self->{query0} = index($1,'=')<0 ? $1 : '';	# 検索Queryをスケルトン指定と誤解しないため
		if ($q0 ne '') { delete $q->{$q0}; }
	}
}

#-------------------------------------------------------------------------------
# ●スケルトン選択（theme.htmlからも呼び出される）
#-------------------------------------------------------------------------------
sub select_skeleton {
	my $self = shift;
	my ($dir,$file) = $self->parse_skel( @_ );
	my $skel = "$dir$file";
	my $ROBJ = $self->{ROBJ};

	# スケルトンの存在確認
	if ($skel ne '' && !$ROBJ->check_skeleton($skel)) {
		$ROBJ->redirect( $self->{myself} );
	}
	$self->{skeleton}  = $skel || $self->select_default_skeleton(  );
	$self->{skel_dir}  = $dir;
	$self->{skel_name} = $file;
}

sub select_default_skeleton {
	my $self = shift;
	my $mode = shift || $self->{pinfo};
	my $blog = $self->{blog};
	# IndexNowの鍵ファイル。有効なときだけ返す
	my $sys = $self->{sys};
	if ($sys->{indexnow} && $sys->{indexnow_key} =~ /^[0-9a-f]{32}$/ && $mode eq "$sys->{indexnow_key}.txt") {
		return '_sub/indexnow_key';
	}
	if ($mode ne '' && $mode !~ /^[1-9]\d+$/ || $mode eq '' && $self->{query} eq '' && $blog->{frontpage}) {
		return ($self->{view_event} = $self->{article_skeleton});
	}
	return ($self->{view_event} = $self->{main_skeleton});
}

#-------------------------------------------------------------------------------
# ●初期セットアップの前か（管理者がいなくて、記事も無い）
#-------------------------------------------------------------------------------
# 記事があれば、ユーザーのテーブルを見に行かない。記事が残ったまま管理者を消したとき（パスワードの再設定）は、
# 公開画面を止めず、?setup から管理者を作り直す
sub is_before_setup {
	my $self = shift;
	my $auth = $self->{ROBJ}->{Auth};
	if ($auth->{ok} || ($self->{blog} || {})->{arts}) { return 0; }
	$auth->userdb_init();
	return !$auth->{exists_admin};
}

#-------------------------------------------------------------------------------
# ●HTMLの生成と出力
#-------------------------------------------------------------------------------
sub output_html {
	my $self = shift;
	my $ROBJ = $self->{ROBJ};

	# HTML生成
	my $out;
	if ($self->{action_is_main}) {
		$out = $self->{action_data};
	} else {
		$out = $ROBJ->call( $self->{skeleton} );
	}

	# view event?
	my $view = $self->{view_event};	# _article, _main
	if ($view) {
		$view =~ tr/a-z/A-Z/;
		if ($self->{blog}->{"event:VIEW$view"}) {
			$self->{post_html} = $ROBJ->call( '_view' . $self->{view_event} );
		}
	}

	# mainフレームあり？
	my $frame_name = $self->{frame_skeleton};
	if ($frame_name ne '') {
		# 外フレームを処理する
		$out = $ROBJ->call($frame_name, $out);
	}

	# テンプレートの中でredirect()したときは、転送のページを出し終えているので出さない
	if (!$self->{output_stop} && !$ROBJ->{Redirected}) {
		$ROBJ->output($out);
	}
}

################################################################################
# ■ブログの存在確認と設定ロード
################################################################################
#-------------------------------------------------------------------------------
# ●ブログが作られているか
#-------------------------------------------------------------------------------
sub exists_blog {
	my $self = shift;
	if (exists $self->{_cache_exists_blog}) { return $self->{_cache_exists_blog}; }
	return ($self->{_cache_exists_blog} = $self->{DB}->find_table('art'));
}

#-------------------------------------------------------------------------------
# ●ブログの設定ロード
#-------------------------------------------------------------------------------
# ※書き換えは瞬時に反映され、$blog->{_update}=1 ならばプログラム終了時に保存される。
sub load_blogset {
	my $self = shift;
	my $ROBJ = $self->{ROBJ};
	if ($self->{_loaded_bset}) { return $self->{_loaded_bset}; }
	if (!$self->exists_blog()) { return undef; }

	my $file = $self->blog_dir() . 'setting.dat';
	if (!-e $file) {
		$file = $self->{default_setting_file};
	}

	# 設定のロード
	my $blog = $ROBJ->fread_hash_cached($file);
	if (%$blog) {
		$self->{_loaded_bset} = $blog;
	}
	return $blog;
}

#-------------------------------------------------------------------------------
# ●ブログの権限と初期設定
#-------------------------------------------------------------------------------
# ブログを選択し、内部変数に権限を設定する。
# ブログがみつからないときは undef が返る
sub select_blog {
	my $self = shift;
	my $ROBJ = $self->{ROBJ};

	# 内部変数の初期化（選び直すときは、前の登録も消す）
	$self->{myself}  = $ROBJ->{myself};
	$self->{myself2} = $ROBJ->{myself2};
	$self->{blog}       = undef;
	$self->{allow_view} = undef;
	$self->{allow_com}  = undef;
	$self->{blog_admin} = undef;
	$self->{blog_dir} = $self->blog_dir();
	$self->{blogpub_dir} = $self->{pub_dir};	# 4.31までの生成物（アップデート処理で作り直すまで使う）
	$ROBJ->{Change_hour} = 0;
	$self->{now} = $ROBJ->{Now};
	$self->delete_blog_skeleton();

	my $blog = $self->load_blogset();
	if (!$blog || !%$blog) { return; }	# ブログが無い

	$self->set_blog_permission($blog);

	# ブログ情報設定
	$self->{blog}        = $blog;
	$self->{allow_view}  = 1;	# ブログを選べた。アップデート前でブログが無いときは立たない
	# ブログ個別スケルトンの登録（プラグイン等で生成される）
	if (!$self->{stop_all_plugins}) {
		$ROBJ->regist_skeleton($self->{blog_dir} . 'skel/', $self->{user_skeleton_level});
	}

	# 日付変更時間設定
	my $ch_hour = $blog->{change_hour_int};
	$ROBJ->{Change_hour} = $ch_hour;
	if ($ch_hour) {
		$self->{now} = $ROBJ->time2timehash( $ROBJ->{TM} );
	}

	return $blog;
}

#-------------------------------------------------------------------------------
# ●ブログ用に登録したスケルトンを外す
#-------------------------------------------------------------------------------
sub delete_blog_skeleton {
	my $self = shift;
	my $ROBJ = $self->{ROBJ};
	$ROBJ->delete_skeleton($self->{user_skeleton_level});
	$ROBJ->delete_skeleton($self->{theme_design_skeleton_level});
}

#-------------------------------------------------------------------------------
# ●ブログの権限設定
#-------------------------------------------------------------------------------
sub set_blog_permission {
	my ($self, $blog) = @_;
	my $isadmin = $self->{ROBJ}->{Auth}->{isadmin};

	# ユーザーは管理者1人だけ
	$self->{blog_admin} = $isadmin;
	$self->{allow_edit} = $isadmin;	# 4.31までの生成物（アップデート処理で作り直すまで使う）

	# コメントできるのは、誰でもか管理者だけ
	$self->{allow_com} = ($isadmin || $blog->{allow_com_users} eq '*') ? 1 : 0;
}

#-------------------------------------------------------------------------------
# ●ブログの設定保存	※Finish()から呼ばれる
#-------------------------------------------------------------------------------
sub save_blogset_sys {
	my $self = shift;
	my $ROBJ = $self->{ROBJ};
	my $h = $self->{_loaded_bset};

	if (!$h || !$h->{_update}) { return; }
	delete $h->{_update};
	$ROBJ->fwrite_hash($self->blog_dir() . 'setting.dat', $h, { atomic => 1 });
}

################################################################################
# ■スケルトン用サブルーチン
###############################################################################
#-------------------------------------------------------------------------------
# ●システムモードへ
#-------------------------------------------------------------------------------
sub system_mode {
	my ($self, $title) = @_;
	my $ROBJ = $self->{ROBJ};
	$self->{system_mode}    = 1;
	$ROBJ->{no_robots}      = 1;
	if ($title ne '') { $self->{title} = $title; }

	# テーマは公開画面専用。管理画面ではテーマの雛形を外し、テーマのCSSも読まない（_frame_admin、デザインの画面は design.css）
	$ROBJ->delete_skeleton($self->{theme_skeleton_level});
	$ROBJ->delete_skeleton($self->{theme_design_skeleton_level});
	$self->{system_theme} = 1;

	# 外フレームも管理画面用にする（フレームを使わない出力はそのまま）
	if ($self->{frame_skeleton}) {
		$self->{frame_skeleton} = $self->{admin_frame_skeleton};
	}
}

#-------------------------------------------------------------------------------
# ●Ajax汎用処理
#-------------------------------------------------------------------------------
sub ajax_function {
	my $self = shift;
	my $ROBJ = $self->{ROBJ};

	$self->{action_is_main} = 1;
	$self->{frame_skeleton} = undef;
	$ROBJ->set_content_type('application/json');

	my $h = $self->do_ajax_function(@_);
	if (!ref($h)) { return { ret => $h } }
	if (ref($h) ne 'ARRAY') { return $h; }

	my %r = (ret => shift(@$h));
	if (@$h) {
		my $v = shift(@$h);
		$r{ref($v) ? 'errs' : 'msg'} = $v;
	}
	if (@$h) { $r{data} = shift(@$h); }
	return \%r;
}
sub do_ajax_function {
	my $self = shift;
	my $func = shift;
	my $ROBJ = $self->{ROBJ};

	# ログインと初期セットアップは、ログインしていなくても呼べる（_ajax_setupは管理者がいないことを自分で確かめる）
	if ($func ne '_ajax_login' && $func ne '_ajax_setup' && !$ROBJ->{Auth}->{ok}) {
		return [ -99.1, 'Security Error' ];
	}

	my $r;
	eval { $r = $self->$func( $ROBJ->{Form} ); };
	if (!$@) { return $r; }

	# eval error
	# can()は、AutoLoaderがまだ読み込んでいない関数では偽になるので使わない
	if ($@ =~ /^\[AutoLoader\] Can't find method '\Q$func\E'/) {
		return [ -99.2, "function not found: $func()" ];
	}
	return [ -99.9, $@ ];
}

#-------------------------------------------------------------------------------
# ●ログイン
#-------------------------------------------------------------------------------
sub _ajax_login {
	my $self = shift;
	my $form = shift;
	my $ROBJ = $self->{ROBJ};
	my $auth = $ROBJ->{Auth};
	my $id   = $form->{adiary_id};

	my $r = $auth->login($id, $form->{pass});
	if ($r->{ret}) {	# error
		if (!$ROBJ->{Develop}) { $r->{ret} = 1; }	# 1固定
		return $r;
	}

	# login
	$ROBJ->set_cookie('session', {
		id  => $id,
		sid => $r->{sid}
	}, $auth->{expires});
	$r->{_no_debug}=1;
	return $r;
}

#-------------------------------------------------------------------------------
# ●記事の読み込み
#-------------------------------------------------------------------------------
sub load_articles_current_blog {
	my ($self, $mode, $query, $opt) = @_;
	my $blog = $self->{blog};

	$opt->{pagemode}  = 1;
	$opt->{loads}     = $opt->{load_items} || $blog->{load_items};
	$opt->{blog_only} = $blog->{separate_blog};

	if ($self->{blog_admin}) {
		$opt->{load_hidden} = 1;
	}
	return $self->load_articles($mode, $query, $opt);
}

#-------------------------------------------------------------------------------
# ●単一記事のロード
#-------------------------------------------------------------------------------
sub load_article_current_blog {
	my ($self, $mode, $query, $opt) = @_;

	if ($self->{blog_admin}) {
		$opt->{load_hidden} = 1;
		$opt->{load_draft}  = 1;
	}
	return $self->load_article($mode, $query, $opt);
}

sub load_article {
	my $self = shift;
	my ($art, $ret) = $self->load_articles(@_);
	if (($ret->{mode} ne 'pkey' && $ret->{mode} ne 'wiki') || $#$art != 0) {
		return undef;
	}
	$art = $art->[0];
	return wantarray ? ($art, $ret) : $art;
}

#-------------------------------------------------------------------------------
# ●記事のロード
#-------------------------------------------------------------------------------
# opt.load_hidden	enableでないものもロード
# opt.loads		loadする記事数(max)
# opt.pagemode		ページ処理する
# opt.no_override	公開フラグ等をオーバーライドしない
# opt.blog_only		ブログ記事のみをロードします
#
#Ret:
#	ret.mode	判別したモード
#	ret.pagemode	ページモードかどうか。
#	ret.page	現在のページ数
#	ret.title_tag	検索がタイトルかタグ検索のみ（mode が 'search'のときのみ）
#
sub load_articles {
	my ($self, $mode, $query, $opt) = @_;
	my $ROBJ = $self->{ROBJ};
	my $DB   = $self->{DB};

	# ブログが無い
	my $blog = $self->{blog};

	#-------------------------------------------------------------
	# ●モードセレクタ
	#-------------------------------------------------------------
	my $loads = int($opt->{loads}) || 5;

	my %q;		# DB-query
	my %ret;	# 戻り値
	#-------------------------------------------------------------
	# 記事pkey
	#-------------------------------------------------------------
	if ($mode =~ /^0(\d+)$/) {
		$ret{mode} = 'pkey';

		$q{match} = {pkey => int($1)};
		$q{limit} = 1;

	#-------------------------------------------------------------
	# 年月日指定 / YYYYMMDD
	#-------------------------------------------------------------
	} elsif ($query->{d} =~ /^(\d\d\d\d)(\d\d)(\d\d)$/) {
		$ret{mode} = 'day';

		my $err = $self->check_date($1, $2, $3);
		if ($err ne '') {
			$ROBJ->message($err);
			return [];
		}
		$ret{year} = $1;
		$ret{mon}  = $2;
		$ret{day}  = $3;

		$q{match}    = {yyyymmdd => $query->{d}};
		$q{sort}     = 'tm';
		$q{sort_rev} = 0;

		if ($opt->{blog_only}) {
			$q{match}->{priority} = 0;
		}

	#-------------------------------------------------------------
	# tm指定
	#-------------------------------------------------------------
	} elsif ($query->{tm} =~ /^(\d{9,})$/) {
		$ret{mode} = 'day';

		$q{match}    = {tm => $1};
		$q{sort}     = 'pkey';
		$q{sort_rev} = 0;

	#-------------------------------------------------------------
	# Query
	#-------------------------------------------------------------
	} elsif ($query->{d} || $query->{t} || $query->{c} || $query->{q} !~ /^\s*$/) {
		$ret{mode} = 'search';
		my $title_tag;

		#-------------------------------------------
		# 年月指定 / YYYYMM
		#-------------------------------------------
		if ($query->{d} =~ /^(\d\d\d\d)(\d\d)?$/) {
			$title_tag = 0;
			if ($2) {
				my $err = $self->check_date($1, $2);
				if ($err ne '') {
					$ROBJ->message($err);
					return [];
				}
			}
			$ret{yyyymm} = $query->{d};
			$ret{year} = $1;
			$ret{mon}  = $2;

			if ($2) {
				$q{min} = {yyyymmdd => "$1${2}01"};
				$q{max} = {yyyymmdd => "$1${2}31"};
			} else {
				$q{min} = {yyyymmdd => "${1}0101"};
				$q{max} = {yyyymmdd => "${1}1231"};
			}
			if ($opt->{blog_only}) {
				$q{match}->{priority} = 0;
			}
		}

		#-------------------------------------------
		# タグの検索
		#-------------------------------------------
		if ($query->{t}) {
			if (!defined $title_tag) { $title_tag=1; }
			my $taglist = $self->load_tag_cache();
			my $name2pkey = $taglist->[0];
			my $tags = $query->{t};
			$ROBJ->tag_escape(@$tags);
			my %arts;
			my %t;
			my @tags_txt;
			foreach(@$tags) {
				if ($t{$_}) { next; }
				my $pkey = $name2pkey->{$_};
				if ($_ ne '' && !$pkey) {
					# 存在しないタグ
					$q{match}->{pkey} = -1;
					last;
				}
				push(@tags_txt, $_);
				$t{$_}=1;
				if ($_ eq '') {
					# タグのない記事
					$q{match}->{tags} = '';
					next;
				}
				# 記事のpkeyリストを取得
				my @que = ( $pkey );
				my %a;
				while(@que) {
					my $tag = $taglist->[ shift(@que) ];
					my $arts = $tag->{arts};
					foreach(@$arts) {
						$a{$_}=1;
					}
					push(@que, @{ $tag->{children} });
				}
				foreach(keys(%a)) {
					$arts{$_}++;
				}
				if (!%a){	# 所属が0のタグ
					$q{match}->{pkey} = -1;
				}
			}
			if (%t) {
				$ret{tags} = \@tags_txt;
			}
			if (%arts) {
				my $c = @$tags;		# 指定されたタグの数
				my @ary = grep { $arts{$_} == $c } keys(%arts);
				$q{match}->{pkey} = @ary ? \@ary : [-1];
			}
		}

		#-------------------------------------------
		# コンテンツタイプの検索
		#-------------------------------------------
		if (exists($query->{c})) {
			$title_tag = 0;
			# 画面とURLに出すので、qやtと同じくエスケープする（検索は元の値で行う）
			my $c = $query->{c};
			$q{match}->{ctype} = $c;
			$ROBJ->tag_escape_amp( $c );
			$ret{ctype} = $c;
		}

		#-------------------------------------------
		# 文字列検索
		#-------------------------------------------
		if ($query->{q} !~ /^\s*$/) {
			my $q = $query->{q};
			my @buf;
			$q =~ s!"([^"]+)"!
				push(@buf, $1);
				" \x04[$#buf] ";
			!eg;
			$q =~ s/^ \x04\[/\x04\[/;
			my $sep = $self->{words_separator} || '\s';

			require Encode;
			Encode::_utf8_on($q);
			$q =~ s/[$sep]+/ /g;
			Encode::_utf8_off($q);

			my @words = split(/ /, $q);
			foreach(@words) {
				$_ =~ s/\x04\[(\d+)\]/$buf[$1]/;
			}
			$q{search_words} = \@words;
			$q{search_cols}  = $query->{all} ? ['title','_text', 'tags'] : ['title'];
			if ($query->{all}) {
				$title_tag = 0;
			} else {
				if (!defined) { $title_tag = 1; }
			}

			$q =~ s/\x04\[(\d+)\]/"$buf[$1]"/g;
			$ROBJ->tag_escape_amp( $q );
			$ret{q} = $q;
			$ret{words} = \@words;
		}

		$q{sort}     = ['yyyymmdd', 'tm'];
		$q{sort_rev} = [1, 1];
		$q{limit}    = $loads;
		$ret{pagemode}  = 1;
		$ret{narrow}    = 1;	# 絞り込み
		$ret{title_tag} = $title_tag;

	#-------------------------------------------------------------
	# コンテンツ指定
	#-------------------------------------------------------------
	} elsif ($mode =~ /^[^&]/) {
		$ret{mode} = 'wiki';
		$q{match} = {link_key => $mode};

	#-------------------------------------------------------------
	# 指定なし（最近 n 件）
	#-------------------------------------------------------------
	} else {
		$ret{mode} = '';
		$ret{pagemode} = 1;

		$q{sort}     = ['yyyymmdd', 'tm'];
		$q{sort_rev} = [1, 1];
		$q{limit}    = $loads;

		if ($opt->{blog_only}) {
			$q{match}->{priority} = 0;
		}
	}

	#-------------------------------------------------------------
	# ●ロード対象
	#-------------------------------------------------------------
	$q{flag}={};
	if (!$opt->{load_hidden}) {
		$q{flag}->{enable} = 1;
	}
	if (!$opt->{load_draft}) {
		$q{not_null} = ['tm'];
	}

	#-------------------------------------------------------------
	# ●データのロード
	#-------------------------------------------------------------
	my $logs = [];
	my $page = 1;
	my $limit = $q{limit};
	my $next_page;
	if ($opt->{pagemode} && $ret{pagemode}) {
		$page = int($query->{p});
		if ($page < 1) { $page=1; }
	}
	if ($ret{narrow}) {
		#---------------------------------------------------------------
		# 全該当データを探し、絞り込み条件を作る
		#---------------------------------------------------------------
		$q{cols} = ['pkey', 'yyyymmdd', 'tags'];
		delete $q{limit};
		my $all = $DB->select("art", \%q);
		my $hits = @$all;

		if ($hits > 1) {
			my $taglist = $self->load_tag_cache();
			my $name2pkey = $taglist->[0];
			my $blog_only = $opt->{blog_only};
			my %tags;
			my %year;
			my %mon;
			my %ctype;
			foreach(@$all) {
				my $ymd = $_->{yyyymmdd};
				if (!$blog_only || !$_->{priority}) {
					$year{ substr($ymd,0,4) }++;
					$mon { substr($ymd,0,6) }++;
				}
				my @tags = split(',', $_->{tags});
				my %c;	# aa::b, aa::c 時、aaの重複カウント防止
				foreach my $tag (@tags) {
					my $t;
					foreach(split('::',$tag)) {
						$t = $t ne '' ? "$t\::$_" : $_;
						if ($c{$t}) { next; }
						$c{$t}=1;
						$tags{ $t }++;
					}
				}
				if ($_->{tags} eq '') {
					$tags{''}++;
				}
				$ctype{ $_->{ctype} }++;
			}
			foreach(keys(%tags)) {
				if ($tags{$_} == $hits) { delete $tags{$_}; }
			}
			foreach(keys(%ctype)) {
				if ($ctype{$_} == $hits) { delete $ctype{$_}; }
			}
			foreach(keys(%year)) {
				if ($year{$_} == $hits) { delete $year{$_}; }
			}
			foreach(keys(%mon)) {
				if ($mon{$_} == $hits) { delete $mon{$_}; }
			}
			my %ymd = %year ? %year : %mon;
			if (%tags)  {
				$ret{narrow_tags}     = \%tags;
				$ret{narrow_tag_tree} = $self->make_narrow_tag_tree(\%tags);
				$tags {_order} = [ sort(keys(%tags )) ];
			}
			if (%ctype) { $ret{narrow_ctype} = \%ctype; $ctype{_order} = [ sort(keys(%ctype)) ]; }
			if (%ymd)   { $ret{narrow_ymd}   = \%ymd;   $ymd  {_order} = [ sort(keys(%ymd  )) ]; }
		}

		# 該当ページのデータだけ取り出す
		my $offset = ($page-1) * $limit;
		$ret{page}  = $page;
		$ret{pages} = int(($hits+$limit-1)/$limit);
		$ret{hits}  = $hits;
		$ret{next_page} = ($ret{pages} > $page);

		if ($hits) {
			my @pkeys;
			for(my $i=0; $i<$limit; $i++) {
				my $pkey = $all->[$offset+$i]->{pkey} || next;
				push(@pkeys, $pkey);
			}
			$logs = $DB->select("art", {
				match => { pkey => \@pkeys },
				sort     => $q{sort},
				sort_rev => $q{sort_rev}
			});
		}

	} else {
		if ($opt->{pagemode} && $ret{pagemode}) {
			$ret{page} = $page;
			$q{offset} = ($page-1) * $limit;
			$q{limit} += 1;
		}
		$logs = $DB->select("art", \%q);
		$ret{next_page} = ($ret{page} && $#$logs == $limit);	# 余計に取得した1件が存在する
		if ($ret{next_page}) { pop(@$logs); }			# その1件を読み捨て
	}

	#-------------------------------------------------------------
	# ●ページ送り処理
	#-------------------------------------------------------------
	my $path = $self->{myself2};

	# 単一記事ページ送り
	if ($opt->{pagemode} && exists $blog->{keylist} && $logs->[0]
	 && ($ret{mode} eq 'pkey' || $ret{mode} eq 'wiki')) {
		my $key = $logs->[0]->{link_key} || $logs->[0]->{pkey};
		my $keylist = $blog->{keylist};
		if ($opt->{load_hidden}) { $keylist = $blog->{keylist_all}; }

		# key を探す
		$key =~ s/([^0-9A-Za-z\x80-\xff])/"\\x" . unpack('H2',$1)/eg;
		if ($key && $keylist =~ /([^,]*),$key,([^,]*)/) {
			if ($1 ne '') {
				$ROBJ->encode_uricom(my $x = $1);
				$ret{next_page} = $path . $x;
			}
			if ($2 ne '') {
				$ROBJ->encode_uricom(my $x = $2);
				$ret{prev_page} = $path . $x;
			}
		}
	}

	#-------------------------------------------------------------
	# フラグのオーバーライド確認
	#-------------------------------------------------------------
	if (!$opt->{no_override}) {
		foreach my $flag (qw(com_ok nsfw)) {
			if ($blog->{"${flag}_force"} ne '') {
				my $ow = $blog->{"${flag}_force"};
				foreach(@$logs) {
					$_->{$flag} = $ow;
				}
			}
		}
	}

	#-------------------------------------------------------------
	# 記事データの前処理
	#-------------------------------------------------------------
	foreach(@$logs) {
		$self->post_process_article( $_, $opt );
	}

	#-------------------------------------------------------------
	# 記事指定時の日付処理
	#-------------------------------------------------------------
	if ($logs->[0] && ($ret{mode} eq 'pkey' || $ret{mode} eq 'wiki')) {
		$ret{year} = $logs->[0]->{year};
		$ret{mon}  = $logs->[0]->{mon};
		$ret{day}  = $logs->[0]->{day};
	}
	if ($logs->[0] && $ret{mode} eq 'search' && $ret{year} && !$ret{day}) {
		$ret{art_mon} = $logs->[0]->{mon};
	}

	return wantarray ? ($logs, \%ret) : $logs;
}

#-------------------------------------------------------------------------------
# ●絞り込みのタグを木にする
#-------------------------------------------------------------------------------
# 節は { name, sname, qt, children }。名前順に並べる。
# 親が除かれている（全件に付いている）ときは、残っているいちばん近い先祖の下に付け、
# なければ根に付ける。snameはその先祖からの残りの部分。
sub make_narrow_tag_tree {
	my $self = shift;
	my $tags = shift;
	my @root;
	my %node;
	foreach my $name (sort(keys(%$tags))) {
		if ($name eq '_order') { next; }
		my $n = { name => $name, sname => $name, qt => $tags->{$name}, children => [] };
		$node{$name} = $n;

		my $parent;
		my @p = split('::', $name);
		for(my $i=$#p-1; $i>=0; $i--) {
			my $pname = join('::', @p[0..$i]);
			if (!$node{$pname}) { next; }
			$parent = $node{$pname};
			$n->{sname} = join('::', @p[$i+1..$#p]);
			last;
		}
		push(@{ $parent ? $parent->{children} : \@root }, $n);
	}
	return \@root;
}

#-------------------------------------------------------------------------------
# ●１件の記事データの加工（後処理）
#-------------------------------------------------------------------------------
sub post_process_article {
	my $self = shift;
	my ($art, $opt) = @_;
	my $ROBJ = $self->{ROBJ};

	my $yyyymmdd = $art->{yyyymmdd};
	my $year = $art->{year} = substr($yyyymmdd, 0, 4);
	my $mon  = $art->{mon}  = substr($yyyymmdd, 4, 2);
	my $day  = $art->{day}  = substr($yyyymmdd, 6, 2);

	# 更新日をテンプレートに出す用の処理
	my $update_ymd = $ROBJ->time2timehash($art->{update_tm});
	$art->{upd_year} = $update_ymd->{year};
	$art->{upd_mon}  = $update_ymd->{mon};
	$art->{upd_day}  = $update_ymd->{day};

	# 更新日の表示制御フラグ
	$art->{shown_upd_date} = "$year$mon$day" != "$art->{upd_year}$art->{upd_mon}$art->{upd_day}";

	# コンテンツkey関連
	my $key = $art->{link_key};
	$art->{elink_key} = $key;
	$self->link_key_encode( $art->{elink_key} );

	# 下書き?
	$art->{draft} = $art->{tm} ? 0 : 1;

	# 曜日の取得
	$art->{wday} = $self->get_dayweek($art->{year}, $art->{mon}, $art->{day});
	$art->{wday_name} = $ROBJ->{WDAY_name}->[ $art->{wday} ];

	# メイン画像
	if ($art->{main_image} =~ /^(.*?)\?(\d+),(\d+)/) {
		$art->{main_image}   = $1;
		$art->{main_image_w} = $2;
		$art->{main_image_h} = $3;
	}
	return $art;
}

# link_key処理のみ
sub post_process_link_key {
	my $self = shift;
	my $dat = shift;
	$dat->{elink_key} = $dat->{link_key};
	return $self->link_key_encode( $dat->{elink_key} );
}

# タグ情報からタグリンクの生成
sub make_taglinks {
	my $self = shift;
	my $ROBJ = $self->{ROBJ};
	my @tags = split(',', shift);
	my $link = $self->{myself} . '?&amp;t=';
	foreach my $tag (@tags) {
		my $t;
		my $s='';
		foreach(split('::', $tag)) {
			$t  =  $t ne '' ? "$t\::$_" : $_;
			my $x = $t;
			$ROBJ->encode_uricom($x);
			$s .= ($s ne '' ? '::' : '') . "<a href=\"$link$x\">$_</a>";
		}
		$tag = "<span class=\"tag\">$s</span>";
	}
	return join('',@tags);
}

#-------------------------------------------------------------------------------
# ●コメントのロードと加工
#-------------------------------------------------------------------------------
# $a_pkey の代わりに記事のデータ（ハッシュ）を与えたほうが高速
#
sub load_comments_current_blog {
	my $self = shift;
	my $a_pkey = shift;
	my $num  = shift;
	my $opt  = shift || {};

	# コメント数を確認
	if (ref($a_pkey)) {
		my $art = $a_pkey;
		$a_pkey = $art->{pkey};
		if (!$art->{coms_all} || !$self->{blog_admin} && !$art->{coms}) {
			return [];
		}
	}

	if (!exists($opt->{enable_only})) {
		$opt->{enable_only} = $self->{blog_admin} ? 0 : 1;
	}
	$opt->{loads} = $num ? $num : undef;

	# ロード
	return $self->load_comments($a_pkey, $opt);
}

#-------------------------------------------------------------------------------
# ●コメントのロード
#-------------------------------------------------------------------------------
# opt.loads		ロードするコメント数（上限）
# opt.enable_only	公開コメントのみ表示
#
sub load_comments {
	my $self = shift;
	my ($a_pkey, $opt) = @_;
	my $DB   = $self->{DB};

	# コメントのロード
	my $loads  = $opt->{loads} ne '' ? int($opt->{loads}) : undef;
	my %h;
	$h{match} = {a_pkey => int($a_pkey)};
	$h{sort}  = ['num', 'tm'];
	if ($opt->{enable_only}) {
		$h{flag} = { enable => 1 };
	}
	if (defined $loads) {
		# 新しい方から指定数のみ取得する
		$h{sort_rev} = 1;
		$h{limit}    = $loads;
	}

	# ロード
	my $comments = $DB->select("com", \%h);
	$self->set_comment_by_admin($comments);
	if (defined $loads) {
		return [ reverse(@$comments) ];
	}
	return $comments;
}

#-------------------------------------------------------------------------------
# ●管理者が書いたコメントに印を付ける
#-------------------------------------------------------------------------------
# 管理者が書いたコメントに by_admin=1 を付ける
#
sub set_comment_by_admin {
	my $self = shift;
	my $comments = shift;
	my $auth = $self->{ROBJ}->{Auth};

	if (!$self->{_admin_ids}) {
		my $users = $auth->{DB}->select_match($auth->{table}, '*cols', ['id']);
		$self->{_admin_ids} = { map { $_->{id} => 1 } @$users };
	}
	my $ids = $self->{_admin_ids};
	foreach(@$comments) {
		my $id = $_->{id};
		if ($id eq '') { next; }
		$_->{by_admin} = $ids->{$id} ? 1 : 0;
	}
	return $comments;
}

#-------------------------------------------------------------------------------
# ●管理者の表示名
#-------------------------------------------------------------------------------
# 読者のコメントでRSSを作り直すときなど、管理者がログインしていなくても使う
sub admin_name {
	my $self = shift;
	my $auth = $self->{ROBJ}->{Auth};
	my $user = $auth->{DB}->select_match_limit1($auth->{table}, '*cols', ['name']);
	return $user ? $user->{name} : '';
}

################################################################################
# ■プラグインシステム
################################################################################
#-------------------------------------------------------------------------------
# ●指定したイベントを呼び出す
#-------------------------------------------------------------------------------
sub call_event {
	my $self = shift;
	my $evt  = shift;	# イベント名
	if ($evt eq '') {
		$self->{ROBJ}->message('"event name" is null.');
		return -99;
	}
	my $r=0;
	$r += $self->do_call_event("$evt#before", undef, @_);
	$r += $self->do_call_event( $evt        , undef, @_);
	$r += $self->do_call_event("$evt#after" , undef, @_);
	return $r;
}

sub do_call_event {
	my $self = shift;
	my $evt  = shift;	# イベント名
	my $blog = shift || $self->{blog};
	my $ROBJ = $self->{ROBJ};
	if (!$blog) { return 0; }

	my @evt = $self->{stop_all_plugins} ? () : split(/\r?\n/, $blog->{"event:$evt"});
	push(@evt, @{ $SysEvt{$evt} || [] });
	if (!@evt) { return 0; }

	my $ret=0;
	$evt =~ s/^(.*):.*$/$1/;	# : 以降を除去
	local($self->{event_name}) = $evt;
	my %h;
	my $once = 0 < index($evt, '#');
	foreach(@evt) {
		my $x = index($_, '=');
		my $name = $x<0 ? '' : substr($_, 0, $x);
		my $op   = substr($_, $x+1);

		if ($h{$op}) { next; }
		$h{$op} = $once;

		# system 設定のイベント処理
		if ($x == -1) {
			my $r = $self->$_(@_);
			$ret += $r ? 1 : 0;
			next;
		}

		# プラグインによるイベント処理
		my $r;
		if ($op =~ m|^func/([\w\-]+\.pm)$|) {
			# ファイルをロードして無名ルーチンを呼び出す
			$r = $self->call_plugin_function($1, $name, @_);
		} elsif ($op =~ m|^skel/([\w/-]+)$|) {
			# スケルトンファイルを呼び出す
			$r = $ROBJ->call($1, $name, @_);
		} else {
			$ROBJ->error("[plugin=%s] Unknown method : %s", $name, $op);
			$r = -1;
		}
		# 結果の保存
		$self->{return}->{$name} = $r;
		$ret += $r ? 1 : 0;
	}
	return $ret;
}

#-------------------------------------------------------------------------------
# ●プラグインファイルをロードして無名ルーチンを呼び出す
#-------------------------------------------------------------------------------
sub call_plugin_function {
	my $self = shift;
	my $name = shift;
	my $ROBJ = $self->{ROBJ};

	my $file = $self->{blog_dir} . "func/$name";
	my $func = $self->load_plugin_function($name, $file);
	if (!ref($func)) {
		$ROBJ->error("[plugin=%s] Load error", $name);
		return $func;
	}

	my $r;
	$self->{call_file} = $file;
	eval { $r = &$func($self, @_) };
	delete $self->{call_file};
	if ($@) {
		$ROBJ->error("[plugin=%s] Execute error : %s", $name, $@);
		return -10;
	}
	return $r;
}

#-------------------------------------------------------------------------------
# ●プラグインのロードとコンパイル（キャッシュ付）
#-------------------------------------------------------------------------------
my %plugin_cache;
my %plugin_cache_tm;
sub load_plugin_function {
	my $self = shift;
	my ($name, $file) = @_;

	my @st = stat($file);
	if (!$st[9]) { return -1; }
	if ($plugin_cache_tm{$file} == $st[9]) {
		return $plugin_cache{$file};
	}

	my $fh;
	my $func;
	sysopen($fh, $file, O_RDONLY);
	my $r = sysread($fh, $func, $st[7]);
	close($fh);
	if ($r != $st[7]) { return -2; }	# 読み込んだバイト数確認

	# Perlでコンパイル
	eval "\$func=$func";
	if ($@) {
		$self->{ROBJ}->error("[plugin=%s] Compile error : %s", $name, $@);
		return -3;
	}
	# キャッシュ
	$plugin_cache_tm{$file} = $st[9];
	return ($plugin_cache{$file} = $func);
}

#-------------------------------------------------------------------------------
# ●JavaScript/CSSプラグインをロード
#-------------------------------------------------------------------------------
sub load_jscss_events {
	my $self = shift;
	my $name = shift;
	if (!$self->{blog}) { return []; }
	if ($self->{stop_all_plugins}) { return []; }

	$name =~ tr/a-z/A-Z/;
	my $evt = $self->{blog}->{"event:$name"};
	my $dir = $self->{pub_dir} . 'plugin/';	# plugin_pub_dir（adiary_4.pm）。公開画面で毎回通るので、ここでは読み込まない

	my @ary;
	foreach(split("\n", $evt)) {
		my ($name, $file) = $self->split_equal($_);
		if (!$name) { next; }
		push(@ary, ($file =~ m!^/|^https?://!i ? '' : $dir) . $file);
	}
	return \@ary;
}

#-------------------------------------------------------------------------------
# ●プラグインの設定をロード
#-------------------------------------------------------------------------------
sub load_plgset {
	my ($self,$name,$key) = @_;
	my $blog = $self->{blog} || return;

	if ($key ne '') {
		return $blog->{"p:$name:$key"};
	}

	# ブログの設定は項目が多いので、全項目を毎回見ない。プラグインごとの項目名を一度だけ作る
	my $index = $self->{_plgset_index};
	if (!$index || $self->{_plgset_blog} != $blog) {
		$index = $self->{_plgset_index} = {};
		$self->{_plgset_blog} = $blog;
		foreach(keys(%$blog)) {
			if (substr($_,0,2) ne 'p:') { next; }
			my $x = index($_, ':', 2);
			if ($x < 0) { next; }
			push(@{ $index->{substr($_,2,$x-2)} }, substr($_,$x+1));
		}
	}
	my %h;
	foreach(@{ $index->{$name} || [] }) {
		$h{$_} = $blog->{"p:$name:$_"};
	}
	return \%h;
}

################################################################################
# ■システム情報 / ブログ情報の管理
################################################################################
#-------------------------------------------------------------------------------
# ●システムdatをロードする
#-------------------------------------------------------------------------------
sub load_sysdat {
	my $self = shift;
	if ($self->{sys}) { return $self->{sys}; }
	my $ROBJ = $self->{ROBJ};
	my $sys = $ROBJ->fread_hash_cached($self->{system_config_file}, {NoError=>1});
	if (!$sys || !%$sys) {
		$sys = $ROBJ->fread_hash($self->{default_config_file});
		$sys->{_update}=1;
		$sys->{VERSION} = $self->{VERSION};
	}
	$self->{sys}=$sys;
	# Secret_word 自動設定
	if (!$sys->{Secret_word}) {
		$self->update_sysdat('Secret_word', $ROBJ->generate_nonce(40));
	}
	# Versionチェック
	if ($sys->{VERSION} < $DATA_VERSION) {
		$self->{require_update} = 1;
	}

	return $sys;
}

#-------------------------------------------------------------------------------
# ●画面で変えた設定を反映する
#-------------------------------------------------------------------------------
# 認証とフォームの読み込みより先に呼ぶ。空は「設定していない」、0は値として扱う
sub apply_sys_settings {
	my ($self, $sys) = @_;
	my $auth = $self->{ROBJ}->{Auth};

	if ($sys->{max_sessions}) { $auth->{max_sessions} = $sys->{max_sessions}; }
	foreach(qw(pass_min all_logout fail_count_ip fail_count fail_minute)) {
		if ($sys->{$_} ne '') { $auth->{$_} = $sys->{$_}; }
	}
	if ($sys->{session_days} ne '') { $auth->{expires} = $sys->{session_days} * 86400; }

	foreach(qw(album_jpeg_quality album_avif_quality)) {
		if ($sys->{$_} ne '') { $self->{$_} = $sys->{$_}; }
	}
	if ($sys->{upload_max_mb} ne '') { $self->{uplaod_files_max} = $sys->{upload_max_mb} * 1048576; }
}

#-------------------------------------------------------------------------------
# ●システムdatを更新する
#-------------------------------------------------------------------------------
sub update_sysdat {
	my $self = shift;
	$self->update_hash( $self->{sys}, @_ );
	$self->{sys}->{_update}=1;
}

#-------------------------------------------------------------------------------
# ●システムdatを保存する	※Finish()から呼ばれる
#-------------------------------------------------------------------------------
sub save_sysdat {
	my $self = shift;
	my $ROBJ = $self->{ROBJ};
	my $sys = $self->{sys};
	if (! $sys->{_update}) { return 0; }
	delete $sys->{_update};
	$ROBJ->fwrite_hash($self->{system_config_file}, $sys, { atomic => 1 });
}

#-------------------------------------------------------------------------------
# ●タグデータのロード
#-------------------------------------------------------------------------------
# &generate_tag_tree で生成
sub load_tag_cache {
	my $self = shift;
	my $ROBJ = $self->{ROBJ};

	my $file = $self->blog_dir() . "tag_cache.txt";
	return $ROBJ->fread_lines_cached($file, {
		NoError=>1,
		PostProcessor=>\&load_tag_postprocessor
	});
}

sub load_tag_postprocessor {
	my ($self, $ary) = @_;
	my %name2pkey;
	my $i=-1;
	$ary = [ map {
		chomp($_);
		$i++;
		my @a=split("\t");
		defined $a[1] && ($name2pkey{$a[6]}=$i);
		defined $a[1] ? { pkey=>$i, upnode=>int($a[0]), qt=>$a[1], qtall=>$a[2], priority=>$a[3], name=>$a[6],
		#	children=>$a[4], arts=>$a[5]
			children=> [split(',',$a[4])],
			arts    => [split(',',$a[5])]
		} : undef;
	} @$ary ];
	$ary->[0] = \%name2pkey;
	return $ary;
}

#-------------------------------------------------------------------------------
# ●記事情報キャッシュのロード（ブログ記事）
#-------------------------------------------------------------------------------
sub load_art_node {
	my ($self, $pkey) = @_;

	my $cache = $self->{_loadart_cache} ||= {};
	my $key   = $pkey;
	if ($cache->{$key}) { return $cache->{$key}; }

	my $con = $self->load_arts_cache( $pkey );
	my %c = %{ $con->{$pkey} || {} };
	$c{prev} = $con->{ $c{prev} };
	$c{next} = $con->{ $c{next} };
	return ($cache->{$key} = \%c);
}
sub load_arts_cache {
	my $self = shift;
	my $num  = sprintf("%04d", int((shift)/($self->{blog_cache_unit} || 0x7fffffff)));
	my $ROBJ = $self->{ROBJ};
	return $ROBJ->fread_lines_cached( $self->{blog_dir} . "arts/$num.dat", {
		NoError=>1,
		PostProcessor=>\&load_arts_postprocessor
	});
}
sub load_arts_postprocessor {
	my ($self, $ary) = @_;
	my %h;
	foreach(@$ary) {
		chomp($_);
		my @a=split("\t", $_);
		$h{$a[0]} = { pkey=>$a[0], prev=>$a[1], next=>$a[2], title=>$a[3] };
	}
	return \%h;
}

#-------------------------------------------------------------------------------
# ●記事情報キャッシュのロード（コンテンツ）
#-------------------------------------------------------------------------------
sub load_content_node {
	my ($self, $pkey) = @_;

	my $cache = $self->{_loadcn_cache} ||= {};
	my $key   = $pkey;
	if ($cache->{$key}) { return $cache->{$key}; }

	my $con = $self->load_contents_cache();
	my %c = %{ $con->{$pkey} || {} };
	$c{upnode} = $con->{ $c{upnode} };
	$c{prev}   = $con->{ $c{prev} };
	$c{next}   = $con->{ $c{next} };
	my @ch = map { $con->{$_} } split(",",$c{children});
	if (@ch) { $c{children} = \@ch; }
	if ($c{upnode} && $c{upnode}->{children}) {
		my @fam;
		my @fam = map { $con->{$_} } split(",",$c{upnode}->{children});
		if (@fam) {
			my @f = grep {$_->{pkey} != $pkey} @fam;
			if (@f) { $c{family} = \@f; }
		}
	}
	return ($cache->{$key} = \%c);
}
sub load_contents_cache {
	my $self = shift;
	my $ROBJ = $self->{ROBJ};
	return $ROBJ->fread_lines_cached( $self->{blog_dir} . 'arts/contents.dat', {
		NoError=>1,
		PostProcessor=>\&load_contents_postprocessor
	});
sub load_contents_postprocessor {
	my ($ROBJ, $ary) = @_;
	my %h;
	foreach(@$ary) {
		chomp($_);
		my @a=split("\t", $_);
		$h{$a[0]} = {
			pkey      => $a[0],
			link_key  => $a[1],
			upnode    => $a[2],
			prev      => $a[3],
			next      => $a[4],
			children  => $a[5],
			title     => $a[6]
		};
		$self->post_process_link_key( $h{$a[0]} );
	}
	return \%h;
}
}

################################################################################
# security id system for post of no login
################################################################################
#-------------------------------------------------------------------------------
# ●コメントフォームのトークン
#-------------------------------------------------------------------------------
# 形：v1.記事番号.発行した時刻.署名（確かめるのはcheck_comment_token）
sub make_comment_token {
	my ($self, $a_pkey, $tm) = @_;
	my $payload = 'v1.' . int($a_pkey) . '.' . ($tm || $self->{ROBJ}->{TM});
	return $payload . '.' . $self->sign_comment_token($payload);
}
# 署名：$payloadをSecret_wordでHMAC-SHA256にし、base64urlにしたもの
sub sign_comment_token {
	my ($self, $payload) = @_;
	my $hmac = eval { require Digest::SHA; \&Digest::SHA::hmac_sha256_base64 };
	if (!$hmac) {
		require Digest::SHA::PurePerl;
		$hmac = \&Digest::SHA::PurePerl::hmac_sha256_base64;
	}
	my $sig = $hmac->($payload, $self->{sys}->{Secret_word});
	$sig =~ tr|+/|-_|;
	return $sig;
}

################################################################################
# ■サブルーチン
################################################################################
#-------------------------------------------------------------------------------
# ●blog_dirを取得
#-------------------------------------------------------------------------------
sub blog_dir {
	my $self = shift;
	return "$self->{data_dir}blog/";
}
sub blogimg_dir {
	my $self = shift;
	return $self->{pub_dir} . 'attachments/';
}

#-------------------------------------------------------------------------------
# ●skeleton dirを取得
#-------------------------------------------------------------------------------
sub parse_skel {
	my ($self, $str) = @_;
	if ($str =~ m|\.\.|) { return; }	# safety
	if ($str !~ m|^((?:[A-Za-z0-9][\w\-]*/)*)([A-Za-z0-9][\w\-]*)?$|) { return ; }
	my $b = ($1 ne '' && $2 eq '') ? 'index' : $2;
	return wantarray ? ($1,$b) : "$1$b";
}

#-------------------------------------------------------------------------------
# ●テーマの選択
#-------------------------------------------------------------------------------
sub load_theme {
	my ($self, $theme) = @_;
	if ($self->{theme} eq $theme) { return 0; }
	my $ROBJ = $self->{ROBJ};

	if ($theme !~ m|^([\w-]+)/([\w-]+)/?$| ) { return -1; }	# error
	my $name = $2;
	my $dir = $self->{theme_dir} . "$1/";
	if (! -r "$dir$name/$name.css") { return 1; }		# not found

	# 内部変数に記録
	$self->{theme}      = $theme;
	$self->{template}   = $1;
	$self->{theme_name} = $name;

	# スケルトンテンプレートの登録
	$ROBJ->delete_skeleton($self->{theme_skeleton_level});
	$ROBJ->delete_skeleton($self->{theme_design_skeleton_level});
	if (-r "${dir}_skel") {
		$ROBJ->regist_skeleton("${dir}_skel/", $self->{theme_skeleton_level});

		# このテンプレートのスケルトンを元に生成したデザイン（デザインの保存時に生成）
		my $tdir = $self->{blog_dir} . "skel_theme/$self->{template}/";
		if ($self->{blog_dir} && !$self->{stop_all_plugins} && -d $tdir) {
			$ROBJ->regist_skeleton($tdir, $self->{theme_design_skeleton_level});
		}
	}
	return 0;
}

#-------------------------------------------------------------------------------
# ●日付指定のチェック（確認処理）
#-------------------------------------------------------------------------------
sub check_date {
	my ($self, $year, $mon, $day) = @_;
	if ($year < 1980) { return 'Can not specify before 1980'; }
	if ($year > 9999) { return 'Can not specify after 9999'; }
	if ($mon < 1 || 12 < $mon) { return 'Illegal month'; }
	if ($day > 0) {
		my $days = $self->get_mdays($year, $mon);
		if ($day < 1 || $days < $day) { return 'Illegal day'; }
	} elsif ($day ne '') { return 'Illegal day'; }
	return ;
}

#-------------------------------------------------------------------------------
# ●指定月の日数取得
#-------------------------------------------------------------------------------
sub get_mdays {
	my $self = shift;
	my ($year, $m) = @_; # 1  2  3  4  5  6  7  8  9 10 11 12
	my @mdays      = qw(0 31 28 31 30 31 30 31 31 30 31 30 31);
	if ($m != 2)   { return $mdays[$m]; }
	if ($year &   3) { return 28; }	# 4で割り切れない
	if ($year % 100) { return 29; }	# 100で割り切れない
	if ($year % 400) { return 28; }	# 400で割り切れない
	return 29;			# 400で割り切れる
}

#-------------------------------------------------------------------------------
# ●曜日の取得
#-------------------------------------------------------------------------------
sub get_dayweek {
	my $self = shift;
	my ($y, $m, $d) = @_;
	if ($m < 3) { $y--; $m+=12; }
	return ($y + ($y>>2) - int($y/100) + int($y/400) + int((13*$m + 8)/5) + $d) % 7;
}

#-------------------------------------------------------------------------------
# ●yyyymmdd文字列の加工
#-------------------------------------------------------------------------------
sub format_ymd {
	my $self = shift;
	my $ymd  = shift;
	my $sep  = shift || '-';
	return substr($ymd,0,4) . $sep . substr($ymd,4,2). $sep . substr($ymd,6,2);
}

#-------------------------------------------------------------------------------
# ●ハッシュを更新
#-------------------------------------------------------------------------------
sub update_hash {
	my $self = shift;
	my ($h, $k, $v) = @_;
	if (!ref($k)) {
		$h->{$k}=$v;
		return ;
	}
	foreach(keys(%$k)) {
		$h->{$_}=$k->{$_};
	}
}

#-------------------------------------------------------------------------------
# ●key=val表記を分離
#-------------------------------------------------------------------------------
sub split_equal {
	my $self = shift;
	my $str  = shift;
	my $x = index($str, shift || '=');
	if ($x == -1) { return ; }
	my $k = substr($str, 0, $x);
	my $v = substr($str, $x+1);
	return ($k,$v);
}

#-------------------------------------------------------------------------------
# ●link_keyエンコード
#-------------------------------------------------------------------------------
sub link_key_encode {
	my $self = shift;
	my $fp = $self->{blog}->{frontpage};
	foreach(@_) {
		if ($_ eq $fp) { $_=''; next; }

		# ここを修正したら contents-edit.js も修正のこと
		$_ =~ s/([^\w!\(\)\*\-\.\~\/:;=])/'%' . unpack('H2',$1)/eg;
		$_ =~ s|^/|.//|;
		# myself2が / のとき //lkey となって http://lkey と解釈されるのを防ぐ
	}
	return $_[0];
}

#-------------------------------------------------------------------------------
# ●rssファイル取得
#-------------------------------------------------------------------------------
sub load_rss_files {
	my $self = shift;
	return [ split(',', $self->{blog}->{rss_files}) ];
}

#-------------------------------------------------------------------------------
# ●js/cssファイルの登録
#-------------------------------------------------------------------------------
sub regist_jslib {
	my $self = shift;
	push(@{ $self->{jslibfiles} ||=[] }, @_);
}
sub regist_js {
	my $self = shift;
	push(@{ $self->{jsfiles} ||=[] }, @_);
}
sub regist_csslib {
	my $self = shift;
	push(@{ $self->{csslibfiles} ||=[] }, @_);
}
sub regist_css {
	my $self = shift;
	push(@{ $self->{cssfiles} ||=[] }, @_);
}
sub load_jscss {
	my $self = shift;
	my $name = shift;
	my $ROBJ = $self->{ROBJ};
	my $base = $ROBJ->{Basepath};

	my @ary = @{ $self->{$name . 'files'} || []};
	push(@ary, @{ $self->load_jscss_events($name) });

	my %h;
	@ary = grep { $h{$_}++; $h{$_}<2 } @ary;
	foreach(@ary) {
		if ($_ =~ m!^/|^https?://!i) { next; }
		$_ = $base . $_ . '?' . $ROBJ->get_lastmodified( $_ );
	}
	return \@ary;
}
# ヘッダに追加
sub add_header {
	my $self = shift;
	$self->{extra_header} .= join('', @_);
}

#-------------------------------------------------------------------------------
# ●htmlの登録
#-------------------------------------------------------------------------------
sub regist_post_html {
	my $self = shift;
	$self->{post_html} .= join('', @_);
}

#-------------------------------------------------------------------------------
# ●記事編集権限チェック
#-------------------------------------------------------------------------------
sub check_editor {
	my $self = shift;
	return $self->{blog_admin} ? 1 : 0;
}

#---------------------------------------------------------------------
# ●配列から指定した数をランダムにロードする
#---------------------------------------------------------------------
sub load_from_ary {
	my $self = shift;
	my ($ary,$num) = @_;
	my $max = @$ary;
	if ($max <= $num) { return $ary; }
	my @a = @$ary;
	for(my $i=0; $i<$max; $i++) {
		my $r = int(rand($max));
		my $x = $a[$i];
		$a[$i] = $a[$r];
		$a[$r] = $x;
	}
	return [ splice(@a, 0, $num) ];
}



1;
