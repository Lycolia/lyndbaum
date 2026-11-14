use strict;
use utf8;
#-------------------------------------------------------------------------------
# 画面の権限のテスト
#-------------------------------------------------------------------------------
# 実行: prove t/permission_screen.t
#
# 画面ごとに、開ける人の下限を決め、それより下の人には出ず、下限の人には出ることを確かめる。
# 権限は docs/仕様/機能一覧.md の「1. 画面」の表のとおり。
#
use FindBin;
BEGIN { push(@INC, "$FindBin::Bin/lib", "$FindBin::Bin/../lib"); }
use Test::More;
use File::Find ();
use File::Spec ();
use AppTest;

binmode(Test::More->builder->$_, ':utf8') foreach (qw(output failure_output todo_output));

# 権限の低い順
my @ROLES = qw(guest admin);
my %LEVEL = map { $ROLES[$_] => $_ } 0..$#ROLES;

#-------------------------------------------------------------------------------
# 画面の一覧
#-------------------------------------------------------------------------------
# [ クエリ, 開ける人の下限, 出たことの確かめ方 ]
# 確かめ方が文字列なら、ステータスが200で、<title>がその文字列で始まること。
# 関数なら、その関数が真を返すこと（枠の無い画面など）。
my $text  = sub { my $r = shift; $r->{status} == 200 && $r->{headers}->{'content-type'} =~ m|^text/plain| };
my $json  = sub { my $r = shift; $r->{status} == 200 && $r->{json} && !$r->{json}->{_error} };

my @SCREENS = (
	# 公開画面
	[ ''                    , 'guest' , 'テストのブログ' ],
	[ '/01'                 , 'guest' , 'editorの記事' ],

	# ログインと共通
	[ 'menu'                , 'admin'  , 'ダッシュボード' ],
	[ 'personal/'           , 'admin'  , '名前・パスワードの変更' ],
	[ 'edit'                , 'admin', '記事の作成' ],
	[ '/01?edit'            , 'admin', sub { $_[0]->{status} == 200 && ($_[0]->{title} // '') =~ /editorの記事 - 記事の編集/ } ],
	[ 'trash'               , 'admin', 'ゴミ箱' ],
	[ 'artlist'             , 'admin', '記事一覧' ],
	[ 'artlist&enable=draft', 'admin', '記事一覧' ],	# 下書きの絞り込み
	[ 'comlist'             , 'admin', 'コメント一覧' ],
	[ 'media/'              , 'admin', 'メディア管理' ],
	[ 'tag_edit'            , 'admin', 'タグの編集' ],
	[ 'contents_edit'       , 'admin', '固定ページの表示順' ],

	# ブログの設定
	[ 'set/'                , 'admin' , 'ブログの基本設定' ],
	[ 'set/detail'          , 'admin' , '詳細/コメント設定' ],
	[ 'set/editor'          , 'admin' , '編集画面の設定' ],

	# その他の設定
	[ 'set2/'               , 'admin', 'その他の設定' ],
	[ 'set2/usertag'        , 'admin', '記法タグのカスタマイズ' ],
	[ 'set2/header'         , 'admin' , 'ヘッダ設定' ],

	# デザイン
	[ 'design/'             , 'admin' , 'デザイン編集' ],
	[ 'design/theme'        , 'admin' , 'テーマ選択' ],
	[ 'design/edit'         , 'admin' , 'デザイン編集' ],
	[ 'design/reset'        , 'admin' , 'デザインの初期化' ],
	[ 'design/usercss'      , 'admin' , 'ユーザーCSSの設定' ],
	[ 'design/art_sample'   , 'admin' , sub { $_[0]->{status} == 200 } ],	# 題名は最新の記事のもの
	[ 'design/theme_colors&name=satsuki2/chie', 'admin', $json ],
	[ 'design/theme_readme&name=satsuki2/chie', 'admin', $text ],

	# プラグイン
	[ 'plugin/'             , 'admin' , 'プラグインの設定' ],
	[ 'plugin/modules'      , 'admin' , 'テザインモジュール一覧' ],
	[ 'plugin/mainte'       , 'admin' , 'プラグインのメンテナンス' ],
	[ 'plugin/plugin_setting&name=des_clock', 'admin', sub { $_[0]->{status} == 200 && $_[0]->{body} =~ /\S/ } ],
	[ 'plugin/plugin_readme&name=des_clock' , 'admin' , $text ],

	# ブログのメンテナンス
	[ 'mainte/'             , 'admin' , 'ブログの再構築' ],
	[ 'mainte/blog_clear'   , 'admin' , '全記事の削除' ],
	[ 'mainte/import'       , 'admin' , '記事のインポート' ],
	[ 'mainte/import_img'   , 'admin' , '外部画像の取り込み' ],
	[ 'mainte/export'       , 'admin' , '記事のエクスポート' ],

	# ユーザーとシステム
	[ 'user/log'            , 'admin' , '操作の記録' ],
	[ 'system/setting'      , 'admin' , 'システム設定' ],
	[ 'system/update'       , 'admin' , 'アップデート処理設定' ],
	[ 'system/check'        , 'admin' , 'システム管理メニュー' ],
	[ 'system/disk'         , 'admin' , 'ディレクトリ使用量' ],
	[ 'system/copyright'    , 'admin' , '著作権表示' ],

	# 補助の画面
	[ 'etc/allow_tags'      , 'admin', '使用可能なHTMLタグ一覧' ],
	[ 'etc/satsuki_tags'    , 'admin', '記法タグの一覧' ],
	[ 'etc/load_session'    , 'admin'  , $text ],
	[ 'etc/ajax_dummy'      , 'admin'  , $text ],
);

# 上の表に入れない画面と、その理由
my %SKIP = (
	'login'            => '誰でも開くログインの画面',
	'login_auth'       => 'ログインの後の振り分け（転送するだけ）',
	'setup'            => '初期セットアップ。管理者がいるときは開けない（t/operations_user.t）',
	'logout'           => 'ログアウト（開くとセッションが消える）',
	'system/'          => 'system/setting へ転送するだけ',
	'etc/parser_debug' => '開発モード（Develop）のときだけ',
);

#-------------------------------------------------------------------------------
# skel/ の画面が、すべて表に入っているか
#-------------------------------------------------------------------------------
{
	my %listed = map { my $q = $_->[0]; $q =~ s/&.*//; $q =~ s{^/\w+\??}{}; ($q => 1) } @SCREENS;
	my @missing;
	File::Find::find({ no_chdir => 1, wanted => sub {
		return if (!/\.html$/ || m{/_});
		my $q = File::Spec->abs2rel($_, "$FindBin::Bin/../skel");
		$q =~ s/\.html$//;
		$q =~ s{(^|/)index$}{$1};
		push(@missing, $q) if (!$listed{$q} && !$SKIP{$q});
	}}, "$FindBin::Bin/../skel");
	is_deeply([ sort @missing ], [], 'skel/ の画面はすべて表に入っている')
		or diag("表に足す画面: @missing");
}

#-------------------------------------------------------------------------------
# 権限
#-------------------------------------------------------------------------------
my $app = AppTest->new()->setup()->seed();

foreach my $s (@SCREENS) {
	my ($query, $min, $check) = @$s;
	my $ok = ref($check) ? $check : do {
		my $title = $check;
		sub { $_[0]->{status} == 200 && index($_[0]->{title} // '', $title) == 0 };
	};
	foreach my $who (@ROLES) {
		my $r = $app->get($who, $query);
		my $expect = $LEVEL{$who} >= $LEVEL{$min} ? 1 : 0;
		my $name   = sprintf('?%s を %s は%s', $query, $who, $expect ? '開ける' : '開けない');
		ok(($ok->($r) ? 1 : 0) == $expect, $name)
			or diag("status=$r->{status} title=" . ($r->{title} // '') . " location=" . ($r->{headers}->{location} // ''));
	}
}

done_testing();
