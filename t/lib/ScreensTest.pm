use strict;
use utf8;
#-------------------------------------------------------------------------------
# 画面がエラーにならずに出るかのテスト（t/screens_*.t）で共通に使うもの
#-------------------------------------------------------------------------------
# 何を確かめるかは t/screens_admin.t の頭に書いた。
# 並べて動かしたときに早く終わるよう、テーマを前と後ろに分けて2つのファイルで開く。
#
package ScreensTest;
use FindBin;
use Test::More;
use File::Find ();
use File::Spec ();
use AppTest;

sub esc { AppTest::_uri_escape(shift) }

#-------------------------------------------------------------------------------
# 管理画面と補助の画面（すべてシステム管理者で開く）
#-------------------------------------------------------------------------------
# 引数が要る画面は、画面の中のリンクと同じ引数を付ける
our @ADMIN = qw(
	menu personal/ edit /01?edit trash artlist comlist media/ tag_edit contents_edit
	set/ set/detail set/editor
	set2/ set2/usertag set2/header
	design/ design/theme design/edit design/reset design/usercss design/art_sample
	design/theme_colors&name=satsuki2/chie design/theme_readme&name=satsuki2/chie
	plugin/ plugin/modules plugin/mainte
	plugin/plugin_setting&name=des_clock plugin/plugin_readme&name=des_clock
	mainte/ mainte/blog_clear mainte/import mainte/import_img mainte/export
	user/log user/log&id=admin&type=login&result=fail&year=2026&mon=10&page=2
	system/setting system/update system/check system/disk system/copyright
	etc/allow_tags&n=article etc/allow_tags&n=header etc/allow_tags&n=description
	etc/satsuki_tags etc/parser_debug etc/load_session etc/ajax_dummy
	login
);

# 上の表に入れない画面と、その理由
our %SKIP = (
	'login_auth'        => 'ログインの後の振り分け（転送するだけ）',
	'setup'             => '初期セットアップ。管理者がいるときは開けない（t/operations_user.t）',
	'logout'            => 'ログアウト（開くとセッションが消える）',
	'system/'           => 'system/setting へ転送するだけ',
);

#-------------------------------------------------------------------------------
# 開くと書き込む画面
#-------------------------------------------------------------------------------
# { 画面（クエリ） => [ 変わってよいファイル（正規表現）, 理由 ] }
our %GET_WRITES = (
	'media/' => [ qr{^pub/images\.json$}, 'アルバムのフォルダの一覧を、今のフォルダから作り直す（init_image_dir）' ],
);

#-------------------------------------------------------------------------------
# 公開画面（すべてのテーマで開く）
#-------------------------------------------------------------------------------
# [ クエリ, 期待するステータス ]
our @PUBLIC = (
	[ ''                       , 200 ],	# トップ
	[ '/01'                    , 200 ],	# 記事（コメントあり）
	[ '/02'                    , 200 ],	# 記事
	[ '/04'                    , 200 ],	# NSFWの記事
	[ '/page1'                 , 200 ],	# 固定ページ
	[ '/0099'                  , 404 ],	# 無い記事
	[ '/no-such-page'          , 404 ],	# 無い固定ページ
	[ '/99'                    , 404 ],	# 数字だけのURL（固定ページのパーマリンクとして探す）
	[ '&p=2'                   , 404 ],	# 無いページ
	[ '&t=' . esc('タグ1')     , 200 ],	# タグ
	[ '&q=' . esc('記事')      , 200 ],	# 検索（題名）
	[ '&q=' . esc('本文1') . '&all=1', 200 ],	# 検索（本文も）
	[ '&q=' . esc('見つからない'), 404 ],	# 検索（見つからない）
	[ '&d=202610'              , 200 ],	# 月
	[ '&d=2026'                , 200 ],	# 年
);

# すべてのテーマ（pub/assets/theme/テンプレート/テーマ/）
our @THEMES = sort map {
	my $t = File::Spec->abs2rel($_, "$FindBin::Bin/../pub/assets/theme");
	$t =~ s|/$||;
	$t;
} grep { !m{/(?:_[^/]*|js)/?$} } glob("$FindBin::Bin/../pub/assets/theme/*/*/");

#-------------------------------------------------------------------------------
# エラーの確かめ
#-------------------------------------------------------------------------------
sub errors {
	my $r = shift;
	my $body = $r->{body} // '';
	utf8::decode($body);
	my @e;
	push(@e, "status=$r->{status}") if ($r->{status} >= 500);
	while ($body =~ m{class="output-(error|warning|debug)">(.*?)</div>}gs) {
		my ($k, $v) = ($1, $2);
		$v =~ s/<[^>]*>//g;
		push(@e, "$k: $v");
	}
	push(@e, "ERROR: $1") if ($body =~ /\(ERROR\)(.{0,300})/s);
	push(@e, "stderr: $r->{stderr}") if (($r->{stderr} // '') ne '');
	return @e;
}

# 画面が参照している /pub/assets/ の下のファイルで、無いもの（すべての画面の分をためる）
my %MISSING;
sub collect_missing {
	my ($r, $where) = @_;
	my $body = $r->{body} // '';
	while ($body =~ m{(?:src|href|content|data-[\w\-]+)="(?:http://localhost)?/(pub/assets/[^"?#]+)}g) {
		my $file = $1;
		next if (-e "$FindBin::Bin/../$file");
		$MISSING{$file} ||= $where;
	}
}

sub check {
	my ($r, $name, $status) = @_;
	collect_missing($r, $name);
	my @e = errors($r);
	ok(!@e && (!$status || $r->{status} == $status), $name)
		or diag(join("\n", "status=$r->{status} title=" . ($r->{title} // ''), @e));
}

#-------------------------------------------------------------------------------
# skel/ の画面が、すべて表に入っているか
#-------------------------------------------------------------------------------
sub check_listed {
	my %listed = map { my $q = $_; $q =~ s/&.*//; $q =~ s{^/\w+\??}{}; ($q => 1) } @ADMIN;
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
# 組み立てる
#-------------------------------------------------------------------------------
sub new_app {
	my $app = AppTest->new(develop => 1)->setup()->seed();

	# NSFWの記事（pkey=4）と固定ページ（pkey=5）を足す
	my %art = (action => 'edit', parser => 'markdown', enable => 1, body_txt => "本文\n", ymd => '2026-10-05');
	AppTest::is_reload($app->post('admin', '', { %art, title => 'NSFWの記事', nsfw => 1 })) or die 'nsfw article';
	AppTest::is_reload($app->post('admin', '', { %art, title => 'ページ', wiki => 1, link_key_txt => 'page1' })) or die 'content';
	return $app;
}

# 画面を開いても data/ と pub/ が変わらない（%GET_WRITES のファイルは除く）
sub get_unchanged {
	my ($app, $who, $q, $name) = @_;
	my $before = $app->fingerprint();
	my $r = $app->get($who, $q);
	my $allow = $GET_WRITES{$q};
	my @changed = grep { !$allow || $_ !~ $allow->[0] } AppTest::diff_fingerprint($before, $app->fingerprint());
	ok(!@changed, "$name を開いても data/ と pub/ が変わらない")
		or diag("変わったファイル: @changed");
	return $r;
}

#-------------------------------------------------------------------------------
# 開く
#-------------------------------------------------------------------------------
sub open_admin {
	my $app = shift;
	foreach my $q (@ADMIN) {
		check(get_unchanged($app, 'admin', $q, "?$q"), "?$q がエラーにならない");
	}
}

# テーマの前と後ろ（$part は 'first' か 'rest'）。管理画面も開く t/screens_admin.t のほうを少なくする
our $FIRST_THEMES = int(@THEMES * 2 / 5);
sub themes {
	my $part = shift;
	return $part eq 'first' ? @THEMES[0 .. $FIRST_THEMES - 1] : @THEMES[$FIRST_THEMES .. $#THEMES];
}

# 公開画面を、渡したテーマで開く。data/ と pub/ が変わらないかは、全体の最初のテーマでだけ確かめる
sub open_public {
	my ($app, @themes) = @_;
	foreach my $theme (@themes) {
		my $r = $app->post('admin', '', { action => 'design/theme', theme => $theme });
		ok(AppTest::is_reload($r) && !errors($r), "テーマを $theme にする")
			or diag(join("\n", errors($r)));
		my $first_theme = $theme eq $THEMES[0];
		foreach my $p (@PUBLIC) {
			my ($q, $status) = @$p;
			foreach my $who (qw(guest admin)) {
				my $r = $first_theme ? get_unchanged($app, $who, $q, "[$theme] ?$q を $who で") : $app->get($who, $q);
				check($r, "[$theme] ?$q を $who で開くとエラーにならない", $status);
				if ($q eq '') { check_jquery($r, $who, "[$theme] トップ"); }
			}
		}
	}
}

#-------------------------------------------------------------------------------
# jQuery（asys.js）を読むか
#-------------------------------------------------------------------------------
# ログインしていない人の公開画面は adiary.js だけで動く。ログイン中は、記事のページの
# コメントの管理などに使うので、asys.js と admin.js も読む（skel/_frame.html）
sub check_jquery {
	my ($r, $who, $name) = @_;
	my $body = $r->{body} // '';
	my $asys = $body =~ m{/asys\.min\.js} ? 1 : 0;
	my $adm  = $body =~ m{/admin\.min\.js} ? 1 : 0;
	ok($body =~ m{/adiary\.min\.js}, "$name を $who で開くと adiary.js を読む");
	if ($who eq 'guest') {
		ok(!$asys && !$adm, "$name を $who で開くと asys.js と admin.js を読まない");
	} else {
		ok($asys && $adm, "$name を $who で開くと asys.js と admin.js を読む");
	}
}

#-------------------------------------------------------------------------------
# 開いた画面が参照する /pub/assets/ の下のファイル（このファイルで開いた分）
#-------------------------------------------------------------------------------
sub check_missing {
	is_deeply([ sort keys(%MISSING) ], [], '画面が参照する /pub/assets/ の下のファイルが、すべてある')
		or diag(join("\n", map { "$_ ($MISSING{$_})" } sort keys(%MISSING)));
}

1;
