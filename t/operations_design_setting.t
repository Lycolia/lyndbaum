use strict;
use utf8;
#-------------------------------------------------------------------------------
# デザインモジュールの設定のテスト
#-------------------------------------------------------------------------------
# 実行: prove -l t/operations_design_setting.t
#
# デザインモジュールの「デザイン設定」（css_setting.html、module-d.css）は無くした。
# 残した項目（センタリング、改行、ログインの消去）は普通の設定（setting.html）にあり、HTMLで効く。
# ページタイトル、検索ボックス、ドロップダウンメニューは、デザイン設定を消しただけ。
# 前の版のデータは、アップデート処理で、消した設定、画像、作ったCSSを片付ける。
#
use FindBin;
BEGIN { push(@INC, "$FindBin::Bin/lib", "$FindBin::Bin/../lib"); }
use Test::More;
use AppTest;
use OpsTest;

binmode(Test::More->builder->$_, ':utf8') foreach (qw(output failure_output todo_output));

my $ROOT = "$FindBin::Bin/..";
my @MODULES = qw(dea_freetext dem_freetext des_freetext deh_description deh_searchbox dem_searchbox deh_title dem_ddmenu deh_login);

sub write_file {
	my ($file, $txt) = @_;
	open(my $fh, '>:utf8', $file) || die "$file: $!";
	print $fh $txt;
	close($fh);
}
# モジュールを置く（デザインの保存）
sub place {
	my $app = shift;
	my $r = $app->post('admin', '', [ action => 'design/edit', @_ ]);
	cmp_ok($r->{status}, '<', 400, 'モジュールを置ける');
	return $r;
}
# 設定を保存する
sub setting {
	my ($app, $name, %f) = @_;
	my $r = $app->post('admin', '', { action => 'plugin/plugin_setting', module_name => $name, %f });
	like($r->{body}, qr/^ret=0$/m, "$name の設定を保存できる");
	unlike($r->{body}, qr/^msg=/m, "$name の設定の保存でメッセージが出ない");
	return $r;
}
# 画面が出したURLから、AppTestに渡すクエリを取り出す（AppTestはSCRIPT_NAMEを足して呼ぶ）
sub query_of {
	my $url = shift;
	$url =~ s/&amp;/&/g;
	$url =~ s{^/lyndbaum\.cgi}{};
	$url =~ s{^\?}{};	# パスが無いときは、クエリだけを渡す
	return $url;
}

#-------------------------------------------------------------------------------
# ファイル
#-------------------------------------------------------------------------------
subtest 'デザイン設定のファイルが無い' => sub {
	my @found = map { glob("$ROOT/plugin/*/$_") } qw(css_setting.html css_validator.html module-d.css);
	is_deeply(\@found, [], 'プラグインにデザイン設定のファイルが無い');
	ok(!-e "$ROOT/skel/_sub/module_css_$_.html", "CSSを作るスケルトン（module_css_$_）が無い") foreach (qw(generate delete));
};

#-------------------------------------------------------------------------------
# デザイン編集の画面から、設定の画面を開く
#-------------------------------------------------------------------------------
my $app = AppTest->new()->setup()->seed();
my $dir = $app->dir;

subtest 'デザイン編集から設定の画面を辿る' => sub {
	my $b = body($app->get('admin', 'design/edit'));
	unlike($b, qr/css-setting/, 'デザイン設定の印とボタンの名前を出さない');
	unlike($b, qr/user-css-url/, 'CSSの読み直し用のURLを出さない');

	# 設定の画面のURLは、画面が出したもの（data-url）にモジュール名を付ける（design-edit.jsと同じ）
	my ($url) = $b =~ m{<form method="POST" id="setting-form"\s+data-url="([^"]*)">};
	ok($url, '設定の画面のURLを出す');
	my %want = (
		des_freetext    => qr/name="text_centering" value="1">/,
		dem_freetext    => qr/name="text_centering" value="1">/,
		dea_freetext    => qr/name="text_centering" value="1">/,
		deh_description => qr/name="br" value="1">/,
		deh_login       => qr/name="erase_login" value="1">/
	);
	foreach my $name (sort keys(%want)) {
		like($b, qr/data-module-name="\Q$name\E"\s+data-type="[^"]*"\s+data-setting="1"\s+data-load-module-html=/, "$name：設定のボタンを出す印がある");
		my $r = $app->get('admin', query_of($url) . $name);
		is($r->{status}, 200, "$name：設定の画面を開ける");
		like(body($r), $want{$name}, "$name：移した欄がある（既定はチェックなし）");
	}
	# 前のデザイン設定の画面のURL（&mode=css）でも、普通の設定の画面が出る
	like(body($app->get('admin', query_of($url) . 'deh_login&mode=css')), qr/name="erase_login"/, '&mode=cssを付けても普通の設定の画面');

	# ページタイトルは、デザイン設定を消したので、設定を持たない
	like($b, qr/data-module-name="deh_title"\s+data-type="header"\s+data-setting=""\s+data-load-module-html=""/, 'deh_title：設定のボタンを出す印が無い');
	ok(!-e "$ROOT/plugin/deh_title/setting.html", 'deh_title：設定の画面のファイルが無い');

	# デザイン設定の項目は残っていない
	foreach my $name (@MODULES) {
		my $s = body($app->get('admin', query_of($url) . $name));
		unlike($s, qr/name="(?:bg|font_c|margin0|padding0|border_w|width|height|titleimg|bgfile|no_centering)"/, "$name：デザイン設定の項目が無い");
	}
};

#-------------------------------------------------------------------------------
# フリー入力のセンタリング
#-------------------------------------------------------------------------------
subtest 'フリー入力のセンタリング' => sub {
	place($app,
		header_ary => 'deh_login', header_ary => 'deh_title', header_ary => 'deh_description', header_ary => 'dem_ddmenu,1',
		side_a_ary => 'des_freetext,1',
		main_a_ary => 'dem_freetext,1',
		art_f_ary  => 'dea_freetext,1'
	);
	my $top = sub { body($app->get('guest', '')) };

	# 既定のHTMLは、前と同じ
	my $b = $top->();
	like($b, qr{<div class="side-module" data-title="" data-module-name="des_freetext,1" id="des-freetext-1">}, 'サイドバー：既定のクラスは前と同じ');
	like($b, qr{<div class="dem-module" data-module-name="dem_freetext,1" id="dem-freetext-1">}, 'メイン：既定のクラスは前と同じ');
	# 記事の下のフリー入力は、記事のページに出る（画面が出したリンクを辿る）
	my ($href) = $b =~ m{<article[^>]*>\s*<h1[^>]*>.*?<a href="([^"]*)" class="title">}s;
	ok($href, '記事のリンクがある');
	my $art = sub { body($app->get('guest', query_of($href))) };
	like($art->(), qr{<div class="dem-module" data-module-name="dea_freetext,1">}, '記事：既定のクラスは前と同じ');

	setting($app, 'des_freetext,1', title => 'T', class => 'side-module', free_txt => 'side text', text_centering => 1);
	setting($app, 'dem_freetext,1', free_txt => 'main text', text_centering => 1);
	setting($app, 'dea_freetext,1', free_txt => 'art text', text_centering => 1);
	like($art->(), qr{<div class="dem-module center" data-module-name="dea_freetext,1">\nart text</div>}, '記事：centerのクラスが付く');
	like(body($app->get('admin', 'plugin/plugin_setting&name=dea_freetext,1')), qr/name="text_centering" value="1" checked/, '記事：設定の画面に保存した値が出る');
	$b = $top->();
	like($b, qr{<div class="side-module center" data-title="T" data-module-name="des_freetext,1" id="des-freetext-1">}, 'サイドバー：centerのクラスが付く');
	like($b, qr{<div class="dem-module center" data-module-name="dem_freetext,1" id="dem-freetext-1">\nmain text</div>}, 'メイン：centerのクラスが付く');
	like(body($app->get('admin', 'plugin/plugin_setting&name=des_freetext,1')), qr/name="text_centering" value="1" checked/, 'サイドバー：設定の画面に保存した値が出る');
	like(body($app->get('admin', 'plugin/plugin_setting&name=dem_freetext,1')), qr/name="text_centering" value="1" checked/, 'メイン：設定の画面に保存した値が出る');

	# タイトルを付けたメインのフリー入力（<article>）
	setting($app, 'dem_freetext,1', title => '見出し', free_txt => 'main text', text_centering => 1);
	like($top->(), qr{<article class="system message center" data-module-name="dem_freetext,1" id="dem-freetext-1">}, 'メイン（タイトルあり）：centerのクラスが付く');

	# centerは、base.cssが中央寄せにする
	like(read_file("$ROOT/pub/assets/theme/base.css"), qr/\.center\s*\{ text-align: center; \}/, 'base.cssに.centerがある');

	# デザイン編集で保存した後の取り直し（design/load_module。design-edit.jsが呼ぶ）にも出る
	my $r = $app->post('admin', '', { action => 'design/load_module', module_name => 'des_freetext,1' });
	like(body($r), qr{<div class="side-module center" }, '取り直したHTMLにも出る');
	$r = $app->post('admin', '', { action => 'design/load_module', module_name => 'des_freetext,1', mode => 'css' });
	like(body($r), qr{<div class="side-module center" }, 'mode=cssを付けても、HTMLを返す（CSSは返さない）');

	setting($app, 'des_freetext,1', title => 'T', class => 'side-module', free_txt => 'side text');
	setting($app, 'dem_freetext,1', title => '見出し', free_txt => 'main text');
	setting($app, 'dea_freetext,1', free_txt => 'art text');
	$b = $top->();
	like($b, qr{<div class="side-module" data-title="T" data-module-name="des_freetext,1"}, 'サイドバー：チェックを外すと戻る');
	like($b, qr{<article class="system message" data-module-name="dem_freetext,1"}, 'メイン：チェックを外すと戻る');
	like($art->(), qr{<div class="dem-module" data-module-name="dea_freetext,1">}, '記事：チェックを外すと戻る');

	# 設定を保存しても、CSSを作らない
	ok(!glob("$dir/data/blog/css.d/*"), 'css.d/にファイルを作らない');
};

#-------------------------------------------------------------------------------
# サイトの説明の改行
#-------------------------------------------------------------------------------
subtest 'サイトの説明の改行' => sub {
	my $r = $app->post('admin', 'set/', { action => 'set/index', blog_name => 'テストのサイト', description_txt => "1行目\n2行目" });
	ok(AppTest::is_reload($r), 'サイトの説明を2行にする');
	like(read_file("$dir/data/blog/setting.dat"), qr/^description_txt=1行目<br>2行目$/m, '設定には<br>で入る');

	my $desc = sub { (body($app->get('guest', '')) =~ m{(<div class="dem-module" data-module-name="deh_description" id="head-description">.*?</div>)}s)[0] // '' };
	is($desc->(), qq|<div class="dem-module" data-module-name="deh_description" id="head-description">\n1行目2行目</div>|, '既定では改行を出さない（前は、CSSで<br>を隠していた）');

	setting($app, 'deh_description', br => 1);
	is($desc->(), qq|<div class="dem-module" data-module-name="deh_description" id="head-description">\n1行目<br>2行目</div>|, '改行を有効にすると<br>を出す');
	like(body($app->get('admin', 'plugin/plugin_setting&name=deh_description')), qr/name="br" value="1" checked/, '設定の画面に保存した値が出る');

	setting($app, 'deh_description');
	unlike($desc->(), qr/<br>/, 'チェックを外すと戻る');
};

#-------------------------------------------------------------------------------
# ページタイトル。デザイン設定を消しただけで、HTMLは前と同じ
#-------------------------------------------------------------------------------
subtest 'ページタイトルのHTMLは前と同じ' => sub {
	my ($t) = body($app->get('guest', '')) =~ m{(<div id="page-title".*?</div>)}s;
	is($t, qq|<div id="page-title" class="site-title" data-module-name="deh_title">\n\t<a href="/lyndbaum.cgi">テストのサイト</a>\n</div>|, 'タイトルのHTML');
};

#-------------------------------------------------------------------------------
# ログインの消去
#-------------------------------------------------------------------------------
subtest 'ログインの消去' => sub {
	my $nav = sub { (body($app->get('guest', '')) =~ m{(<nav id="nav-header".*?</nav>)}s)[0] // '' };
	like($nav->(), qr{<a class="adminmenu login" href="[^"]*\?login" rel="nofollow">ログイン</a>}, '既定ではログインのリンクを出す');

	setting($app, 'deh_login', erase_login => 1);
	like($nav->(), qr{<a class="adminmenu login erase-login" href="[^"]*\?login" rel="nofollow">&emsp;</a>}, '見えなくする（リンクは残る）');
	like(body($app->get('admin', 'plugin/plugin_setting&name=deh_login')), qr/name="erase_login" value="1" checked/, '設定の画面に保存した値が出る');

	# 画面が出したリンクを辿る
	my ($href) = $nav->() =~ m{<a class="adminmenu login erase-login" href="([^"]*)"};
	is($app->get('guest', query_of($href))->{status}, 200, 'ログインのリンクを開ける');

	setting($app, 'deh_login');
	unlike($nav->(), qr/erase-login/, 'チェックを外すと戻る');
};

#-------------------------------------------------------------------------------
# ドロップダウンメニュー
#-------------------------------------------------------------------------------
subtest 'ドロップダウンメニューは常にセンタリング' => sub {
	like(body($app->get('guest', '')), qr{<div class="ddmenu dd-centering" data-module-name="dem_ddmenu,1" id="dem-ddmenu-1">}, 'dd-centeringを付ける');
	# 前の版で保存した「センタリングしない」が残っていても変わらない
	my $file = "$dir/data/blog/setting.dat";
	write_file($file, read_file($file) . "p:dem_ddmenu,1:no_centering=1\n");
	like(body($app->get('guest', '')), qr{<div class="ddmenu dd-centering" data-module-name="dem_ddmenu,1"}, '前の設定が残っていても付ける');
};

#-------------------------------------------------------------------------------
# 設定のリセットと、モジュールを外したとき
#-------------------------------------------------------------------------------
subtest '設定のリセット' => sub {
	setting($app, 'deh_login', erase_login => 1);
	my $r = $app->post('admin', '', { action => 'plugin/reset_plugin', name => 'deh_login' });
	like($r->{body}, qr/^ret=0$/m, 'リセットできる');
	unlike($r->{body}, qr/^msg=/m, 'メッセージが出ない');
	unlike(body($app->get('guest', '')), qr/erase-login/, 'リセットすると、ログインのリンクが見える');
	unlike(read_file("$dir/data/blog/setting.dat"), qr/^p:deh_login:/m, '設定が消える');
};

#-------------------------------------------------------------------------------
# ログインヘッダーは普通のモジュール。デザイン編集の見本に出て、外せる
#-------------------------------------------------------------------------------
subtest 'ログインヘッダーを外せる' => sub {
	my $nav = qr{<nav id="nav-header" data-module-name="deh_login">};

	# デザイン編集の見本には、ログイン中でも出す。固定（data-fix）の印は無い
	my $sample = body($app->get('admin', 'design/art_sample'));
	like($sample, $nav, '見本に出る（固定の印が無い）');
	like($sample, qr{<a class="adminmenu logout" href="[^"]*\?logout">ログアウト</a>}, '見本には、ログイン中の中身を出す');
	my ($info) = body($app->get('admin', 'design/edit')) =~ m{(<div title="ログインヘッダー"\s+data-module-name="deh_login".*?</div>)}s;
	like($info // '', qr{<nav id="nav-header" data-module-name="deh_login">}, '追加の一覧から置くHTMLにも、固定の印が無い');
	unlike(read_file("$ROOT/tools/js/src/design-edit.js"), qr/deh_login/, '保存のときに、JSがログインヘッダーを足さない');

	# 公開画面。ログイン中は出さない（管理バーがある）
	unlike(body($app->get('admin', '')), qr/id="nav-header"/, 'ログイン中の公開画面には出さない');
	like(body($app->get('admin', '')), qr/<nav id="admin-bar"/, 'ログイン中の公開画面には管理バーがある');
	like(body($app->get('guest', '')), $nav, 'ログアウト中の公開画面には出す');

	# 外して保存する
	place($app, header_ary => 'deh_title', side_a_ary => 'des_searchbox');
	my $r = $app->get('guest', '');
	is($r->{status}, 200, '外した後も、公開画面を開ける');
	unlike(body($r), qr/nav-header|\?login"/, '外すと、ログアウト中にログインのリンクを出さない');
	like(body($r), qr{<div id="page-title" class="site-title" data-module-name="deh_title">}, 'ほかのヘッダーのモジュールは出る');
	$r = $app->get('admin', 'design/art_sample');
	is($r->{status}, 200, '外した後も、見本を開ける');
	unlike(body($r), qr/id="nav-header"/, '外した後の見本には出ない');
	like(body($app->get('admin', '')), qr/<nav id="admin-bar"/, '外しても、ログイン中の管理バーは出る');
	is($app->get('guest', 'login')->{status}, 200, '?loginでログインの画面を開ける');

	# 置き直す。画面が出したログインのリンクを辿る
	place($app, header_ary => 'deh_login', header_ary => 'deh_title', side_a_ary => 'des_searchbox');
	my ($href) = body($app->get('guest', '')) =~ m{<nav id="nav-header" data-module-name="deh_login">.*?<a class="adminmenu login" href="([^"]*)"}s;
	ok($href, '置き直すと、ログインのリンクが出る');
	is($app->get('guest', query_of($href))->{status}, 200, 'ログインのリンクを開ける');

	# デザインを保存していないサイトでは、雛形の既定の中身が出す
	my $fresh = AppTest->new()->setup();
	like(body($fresh->get('guest', '')), $nav, '保存していないサイトでも、ログアウト中に出る');
	like(body($fresh->get('admin', 'design/art_sample')), $nav, '保存していないサイトの見本にも出る');
};

#-------------------------------------------------------------------------------
# 前の版のデータからのアップデート
#-------------------------------------------------------------------------------
subtest '前の版のデータを片付ける' => sub {
	my $old = AppTest->new()->setup()->seed();
	my $d   = $old->dir;
	place($old,
		header_ary => 'deh_login', header_ary => 'deh_title', header_ary => 'deh_description',
		side_a_ary => 'des_freetext,1', side_a_ary => 'des_searchbox',
		main_a_ary => 'dem_ddmenu,1'
	);
	ok(AppTest::is_reload($old->post('admin', 'design/usercss', { action => 'design/usercss', usercss_txt => ".my-css { color: red; }\n" })), 'ユーザーCSSを保存する');
	like(read_file("$d/pub/custom/dynamic.css"), qr/\.my-css/, 'dynamic.cssにユーザーCSSが入る');

	# 前の版の状態にする。デザイン設定を保存してあり、CSSを作るイベントが付いている
	my $setting = "$d/data/blog/setting.dat";
	my $plugins = "$d/data/blog/plugins.dat";
	my @css_mods = ('deh_login', 'deh_title', 'deh_description', 'des_freetext,1', 'dem_ddmenu,1');
	my $s = read_file($setting);
	$s .= join('', map { "$_\n" } (
		'p:deh_title:font_c=#ff0000', 'p:deh_title:titleimg=deh_title-titleimg.png', 'p:deh_title:titleimg_w=10', 'p:deh_title:titleimg_h=10',
		'p:deh_title:bgfile=deh_title-bgfile.png', 'p:deh_title:top=10',
		'p:deh_login:erase_login=1', 'p:deh_login:bg=#000000', 'p:deh_login:head_bgfile=../../data/blog/plugins.dat', 'p:deh_login:margin7=3',
		'p:deh_description:br=1', 'p:deh_description:bg=#ffffff', 'p:deh_description:abs_x=5',
		'p:des_freetext,1:text_centering=1', 'p:des_freetext,1:bg=#eeeeee', 'p:des_freetext,1:free_txt=kept text', 'p:des_freetext,1:class=side-module', 'p:des_freetext,1:title=T',
		'p:dem_ddmenu,1:no_centering=1', 'p:dem_ddmenu,1:width1=100', 'p:dem_ddmenu,1:depth=2',
		'p:des_searchbox:radio_none=1', 'p:des_searchbox:bg=keep',
		(map { ("event:INSTALL:$_=$_=skel/_sub/module_css_generate", "event:SETTING:$_=$_=skel/_sub/module_css_generate", "event:UNINSTALL:$_=$_=skel/_sub/module_css_delete") } grep { $_ ne 'dem_ddmenu,1' } @css_mods)
	));
	write_file($setting, $s);
	my $p = read_file($plugins);
	foreach(grep { $_ ne 'dem_ddmenu,1' } @css_mods) {
		$p =~ s/^\Q$_\E:events=.*\n//m;
		$p .= "*$_:events=<<__END_BLK_DATA\nINSTALL=skel/_sub/module_css_generate\nSETTING=skel/_sub/module_css_generate\nUNINSTALL=skel/_sub/module_css_delete\n__END_BLK_DATA\n";
	}
	write_file($plugins, $p);

	mkdir("$d/data/blog/css.d");
	write_file("$d/data/blog/css.d/$_-d.css", "#old-$_ { color: blue; }\n") foreach (map { (my $n = $_) =~ tr/,/-/; $_ } @css_mods);
	write_file("$d/data/blog/css.d/other_plugin-d.css", ".other-plugin { color: green; }\n");
	my $img = "$d/pub/attach/\@system";
	system('mkdir', '-p', $img) == 0 || die;
	AppTest::_copy("$ROOT/pub/assets/dist/default-icon.png", "$img/$_") foreach (qw(deh_title-titleimg.png deh_title-bgfile.png keep.png));

	my $sys  = "$d/data/system_config.dat";
	my $conf = read_file($sys);
	$conf =~ s/^VERSION=.*$/VERSION=4.44/m;
	write_file($sys, $conf);

	my $r = $old->post('admin', 'system/update', { action => 'system/update' });
	ok(AppTest::is_reload($r), 'アップデート処理を行える');
	unlike(body($r), qr/File not found|module_css|failed/, '無いスケルトンを呼んだエラーが出ない');

	$s = read_file($setting);
	unlike($s, qr/^p:deh_title:(?:font_c|titleimg|titleimg_w|titleimg_h|bgfile|top)=/m, 'ページタイトルのデザイン設定を消す');
	unlike($s, qr/^p:deh_login:(?:bg|head_bgfile|margin7)=/m, 'ログインヘッダーのデザイン設定を消す');
	unlike($s, qr/^p:deh_description:(?:bg|abs_x)=/m, 'サイトの説明のデザイン設定を消す');
	unlike($s, qr/^p:des_freetext,1:bg=/m, 'フリー入力のデザイン設定を消す');
	unlike($s, qr/^p:dem_ddmenu,1:(?:no_centering|width1)=/m, 'ドロップダウンメニューのデザイン設定を消す');
	like($s, qr/^p:deh_login:erase_login=1$/m, 'ログインの消去は残す');
	like($s, qr/^p:deh_description:br=1$/m, '改行は残す');
	like($s, qr/^p:des_freetext,1:text_centering=1$/m, 'センタリングは残す');
	like($s, qr/^p:des_freetext,1:free_txt=kept text$/m, 'フリー入力の本文は残す');
	like($s, qr/^p:dem_ddmenu,1:depth=2$/m, 'ドロップダウンメニューの普通の設定は残す');
	like($s, qr/^p:des_searchbox:bg=keep$/m, 'デザイン設定を持たなかったモジュールの設定には触らない');
	unlike($s, qr/module_css_/, 'サイトの設定にCSSを作るイベントが残らない');
	unlike(read_file($plugins), qr/module_css_/, 'プラグインの情報にCSSを作るイベントが残らない');

	ok(!-e "$img/deh_title-titleimg.png", 'タイトル画像を消す');
	ok(!-e "$img/deh_title-bgfile.png", '背景画像を消す');
	ok(-e "$img/keep.png", 'ほかの画像は消さない');
	ok(-e $plugins, '名前が決まった形でないファイルは消さない');

	my @left = map { m{([^/]+)$} } glob("$d/data/blog/css.d/*");
	is_deeply([ sort @left ], [ '_usercss-d.css', 'other_plugin-d.css' ], 'css.d/には、ユーザーCSSと、ほかのプラグインのCSSだけが残る');
	my $dyn = read_file("$d/pub/custom/dynamic.css");
	like($dyn, qr/\.my-css \{ color: red; \}/, 'dynamic.cssにユーザーCSSが残る');
	like($dyn, qr/\.other-plugin/, 'dynamic.cssにほかのプラグインのCSSが残る');
	unlike($dyn, qr/#old-/, 'dynamic.cssから前のモジュールのCSSが消える');

	# 公開画面。残した設定が効き、dynamic.cssを読む
	my $b = body($old->get('guest', ''));
	like($b, qr{<link rel="stylesheet" href="/pub/custom/dynamic\.css\?\d+" id="user-css">}, '公開画面はdynamic.cssを読む');
	like($b, qr{<div class="side-module center" data-title="T" data-module-name="des_freetext,1"}, 'センタリングが効く');
	like($b, qr{class="adminmenu login erase-login"}, 'ログインの消去が効く');
	like($b, qr{<div class="ddmenu dd-centering" data-module-name="dem_ddmenu,1"}, 'ドロップダウンメニューはセンタリング');

	# アップデートの後も、設定の保存とモジュールの入れ直しでエラーが出ない
	setting($old, 'deh_login', erase_login => 1);
	setting($old, 'des_freetext,1', title => 'T', class => 'side-module', free_txt => 'kept text', text_centering => 1);
	$r = $old->post('admin', 'system/update', { action => 'design/reinstall_modules' });
	unlike(body($r), qr/File not found|module_css/, 'モジュールの入れ直しでエラーが出ない');
	$r = place($old, header_ary => 'deh_login', header_ary => 'deh_title', side_a_ary => 'des_searchbox');
	unlike(body($r), qr/File not found|module_css/, 'モジュールを外してもエラーが出ない');
	is($old->get('guest', '')->{status}, 200, '公開画面を開ける');
};

done_testing();
