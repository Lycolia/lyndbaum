use strict;
use utf8;
#-------------------------------------------------------------------------------
# 操作（POSTの action）の権限のテスト
#-------------------------------------------------------------------------------
# 実行: prove t/permission_action.t
#
# 操作ごとに、できる人の下限を決めて確かめる。
#	・下限より下の人が送っても、data/ と pub/ が何も変わらず、通ったときの応答も返らない
#	・下限の人が同じものを送ると通る（送る中身が正しいことの確かめ。これが無いと、
#	  中身の誤りで弾かれているのか、権限で弾かれているのか分からない）
#	・同じものをGETで送ると、システム管理者でも通らない（ログインのCookieはSameSite=Laxで、
#	  ほかのサイトのリンクから開くGETにはCookieが乗るため。docs/仕様/機能一覧.md の「CSRFの対策」）
# 権限は docs/仕様/機能一覧.md の「2. 操作（POSTとAjax）」の表のとおり。
#
use FindBin;
BEGIN { push(@INC, "$FindBin::Bin/lib", "$FindBin::Bin/../lib"); }
use Test::More;
our $TODO;
use File::Find ();
use File::Spec ();
use AppTest;

binmode(Test::More->builder->$_, ':utf8') foreach (qw(output failure_output todo_output));

# 権限の低い順
my @ROLES = qw(guest admin);
my %LEVEL = map { $ROLES[$_] => $_ } 0..$#ROLES;

my $PNG = do {
	open(my $fh, '<:raw', "$FindBin::Bin/../pub/assets/dist/default-icon.png") || die $!;
	local $/; <$fh>;
};
my $FOLDER = $AppTest::IMAGE_FOLDER;
my $FILE   = $AppTest::IMAGE_FILE;
my $VIDEO  = $AppTest::VIDEO_FILE;

#-------------------------------------------------------------------------------
# 通ったことの確かめ方
#-------------------------------------------------------------------------------
# 既定は「data/ か pub/ が変わった」。応答で分かるものは、次の関数で確かめる
sub json_ret0 { my $r = shift; $r->{json} && defined $r->{json}->{ret} && $r->{json}->{ret} eq '0' }
sub json_any  { my $r = shift; $r->{status} == 200 && $r->{headers}->{'content-type'} =~ m{^(?:application|text)/json} }
sub text_ret0 { my $r = shift; $r->{headers}->{'content-type'} =~ m{^text/} && $r->{body} =~ /^ret=0$/m }
sub no_frame  { my $r = shift; $r->{status} == 200 && $r->{body} =~ /\S/ && $r->{body} !~ /<title>/i }

#-------------------------------------------------------------------------------
# 操作の一覧
#-------------------------------------------------------------------------------
# { action, min（できる人の下限）, form, ok（通ったことの確かめ方。省くと data/ か pub/ が変わったこと）,
#   todo（下限の人でも通らない、分かっている不具合）}
my @ACTIONS = (
	#---------------------------------------------------------------
	# Ajax
	#---------------------------------------------------------------
	{ action => '_ajax_self_change_name', min => 'admin', ok => \&json_ret0,
	  form => { name => '自分の名前' } },
	{ action => '_ajax_self_change_pass', min => 'admin', ok => \&json_ret0,
	  form => { now_pass => $AppTest::PASS, pass => 'new-pass-5678', pass2 => 'new-pass-5678' } },

	#---------------------------------------------------------------
	# 記事とコメント
	#---------------------------------------------------------------
	{ action => 'edit', min => 'admin',
	  form => { title => '新しい記事', body_txt => "本文\n", parser => 'markdown', enable => 1, ymd => '2026-10-02' } },
	{ action => 'delete', min => 'admin',
	  form => { delete_pkey_ary => 1, title => 'editorの記事' } },
	{ action => 'articles_edit', min => 'admin',
	  form => { mode => 'disable', pkey_ary => 1 } },
	{ action => 'comments_edit', min => 'admin',
	  form => { disable => 1, pkey_ary => 1 } },
	{ action => 'trash', min => 'admin', label => 'trash（戻す）',
	  form => { mode => 'restore', pkey_ary => 3 } },
	{ action => 'trash', min => 'admin', label => 'trash（完全に削除）',
	  form => { mode => 'purge', pkey_ary => 3 } },
	{ action => 'trash', min => 'admin', label => 'trash（空にする）',
	  form => { mode => 'purge_all' } },
	{ action => 'ajax_lock', min => 'admin', ok => \&json_any,
	  form => { pkey => 1, sid => 'test' } },
	{ action => 'ajax_revision', min => 'admin', ok => \&json_any,
	  form => { pkey => 1 } },

	#---------------------------------------------------------------
	# 画像アルバム
	#---------------------------------------------------------------
	{ action => 'media/upload_form', min => 'admin', ok => \&text_ret0,
	  form => [ folder => $FOLDER, size => 120, file_ary => { filename => 'up.png', content => $PNG, type => 'image/png' } ] },
	{ action => 'media/load_image_files', min => 'admin', ok => \&json_any,
	  form => { folder => $FOLDER } },
	{ action => 'media/load_exif_files', min => 'admin', ok => \&json_any,
	  form => { folder => $FOLDER } },
	{ action => 'media/create_folder', min => 'admin', ok => \&json_ret0,
	  form => { folder => '/', name => 'new' } },
	{ action => 'media/rename_folder', min => 'admin', ok => \&json_ret0,
	  form => { folder => '/', old => 'test', name => 'test2' } },
	{ action => 'media/delete_folder', min => 'admin', ok => \&json_ret0,
	  form => { folder => $FOLDER } },
	{ action => 'media/rename_file', min => 'admin', ok => \&json_ret0,
	  form => { folder => $FOLDER, old => $FILE, name => 'b.png' } },
	{ action => 'media/move_files', min => 'admin', ok => \&json_ret0,
	  form => { from => $FOLDER, to => '/', file_ary => $FILE } },
	{ action => 'media/delete_files', min => 'admin', ok => \&json_ret0,
	  form => { folder => $FOLDER, file_ary => $FILE } },
	{ action => 'media/remake_thumbnail', min => 'admin', ok => \&json_ret0,
	  form => { folder => $FOLDER, file_ary => $FILE, size => 100 } },
	{ action => 'media/remove_exifjpeg', min => 'admin', ok => \&json_ret0,
	  form => { folder => $FOLDER, file_ary => $FILE } },
	{ action => 'media/refresh', min => 'admin', ok => \&json_ret0,
	  form => {} },
	{ action => 'media/upload_video_thumbnail', min => 'admin', ok => \&json_ret0,
	  form => [ folder => $FOLDER, file => $VIDEO,
		poster => { filename => 'poster.png', content => $PNG, type => 'image/png' } ] },
	{ action => 'etc/ajax_upload', min => 'admin', ok => \&json_ret0,
	  form => [ folder => $FOLDER, size => 120, file_ary => { filename => 'up2.png', content => $PNG, type => 'image/png' } ] },

	#---------------------------------------------------------------
	# ブログの設定
	#---------------------------------------------------------------
	{ action => 'set/index', min => 'admin',
	  form => { blog_name => '新しい名前', description_txt => '' } },
	{ action => 'set/detail', min => 'admin',
	  form => { load_items => 3 } },
	{ action => 'set/editor', min => 'admin',
	  form => { enable => 0 } },
	{ action => 'set2/tag_edit', min => 'admin',
	  form => { del_ary => 1 } },
	{ action => 'set2/contents_edit', min => 'admin',
	  form => { contents_txt_ary => '1,0,1,new-key' } },
	{ action => 'set2/usertag', min => 'admin',
	  form => { usertag_txt => "[mytag]\nhtml = <b>\$1</b>\n" } },
	{ action => 'set2/header', min => 'admin',
	  form => { html_header_txt => '<meta name="test" content="1">' } },

	#---------------------------------------------------------------
	# デザイン
	#---------------------------------------------------------------
	{ action => 'design/theme', min => 'admin',
	  form => { theme => 'satsuki2/chie' } },
	{ action => 'design/edit', min => 'admin',
	  form => { side_a_ary => 'des_clock' } },
	{ action => 'design/load_module', min => 'admin', ok => \&no_frame,
	  form => { module_name => 'des_artlist' } },
	{ action => 'design/reset', min => 'admin',
	  form => { all => 1 } },
	{ action => 'design/reinstall_modules', min => 'admin', ok => \&AppTest::is_reload,	# 同じものを入れ直すので、ファイルは変わらない
	  form => {} },
	{ action => 'design/usercss', min => 'admin',
	  form => { usercss_txt => 'body { color: red; }' } },

	#---------------------------------------------------------------
	# プラグインとメンテナンス
	#---------------------------------------------------------------
	{ action => 'plugin/index', min => 'admin',
	  form => { 'sitemap' => 1 } },
	{ action => 'plugin/plugin_setting', min => 'admin', ok => \&text_ret0,
	  form => { module_name => 'des_clock' } },
	{ action => 'plugin/reinstall_plugins', min => 'admin', ok => \&AppTest::is_reload,
	  form => {} },
	{ action => 'plugin/reset_plugin', min => 'admin', ok => \&text_ret0,
	  form => { name => 'des_clock' } },
	{ action => 'plugin/reset_plugins', min => 'admin', ok => \&AppTest::is_reload,
	  form => { name_ary => 'des_clock' } },
	{ action => 'mainte/blog_rebuild', min => 'admin',
	  form => {} },
	{ action => 'mainte/blog_clear', min => 'admin',
	  form => { yes => 'yes' } },
	{ action => 'mainte/import', min => 'admin', ok => \&text_ret0,
	  form => [ type => 'MT', file => { filename => 'import.txt', content => "TITLE: 取り込んだ記事\nDATE: 10/03/2026 12:00:00\n-----\nBODY:\n本文\n-----\n--------\n" } ] },
	{ action => 'mainte/import_img_init', min => 'admin', ok => \&json_any,
	  form => {} },
	{ action => 'mainte/import_img', min => 'admin', ok => sub { $_[0]->{status} == 200 && $_[0]->{body} !~ /<title>/i },	# 取り込む画像が無いので、応答は空
	  form => { pkey => 1 } },
	{ action => 'mainte/export', min => 'admin', ok => sub { $_[0]->{status} == 200 && $_[0]->{headers}->{'content-type'} !~ m{^text/html} },
	  form => { file => '10_movable_type' } },

	#---------------------------------------------------------------
	# システム
	#---------------------------------------------------------------
	{ action => 'system/setting', min => 'admin',
	  form => { mainte_txt => 'メンテナンス中' } },
	{ action => 'system/update', min => 'admin', ok => \&AppTest::is_reload,
	  form => {} },
	{ action => 'system/rebuild_blog', min => 'admin', ok => \&AppTest::is_reload,
	  form => {} },
	{ action => 'system/rebuild_blog_info', min => 'admin', ok => \&AppTest::is_reload,
	  form => {} },
	{ action => 'system/reinstall_plugins', min => 'admin', ok => \&AppTest::is_reload,
	  form => {} },
	{ action => 'system/remake_custom_css', min => 'admin', ok => \&AppTest::is_reload,
	  form => {} },
	{ action => 'etc/init_session', min => 'admin', ok => sub { $_[0]->{body} =~ /^snum=/m },
	  form => {} },
);

# 上の表に入れない操作と、その理由
my %SKIP = (
	'_ajax_login'       => '誰でも',
	'_ajax_setup'       => '管理者がいないときだけ（t/operations_user.t）',
	'comment_post'      => '誰でも（ブログの設定で、コメントできる人を決める）',
	'etc/dummy'         => '誰でも（何もしない）',
);

# 上の表に入れない操作を、GETで送るときの中身
my %SKIP_FORM = (
	'_ajax_login'       => { adiary_id => 'admin', pass => $AppTest::PASS },
	'_ajax_setup'       => { adiary_id => 'newuser', name => 'newuser', pass => $AppTest::PASS, pass2 => $AppTest::PASS, blog_name => '乗っ取り' },
	'comment_post'      => { a_pkey => 1, comment_txt => 'GETのコメント', name => 'admin' },
	'etc/dummy'         => {},
);

#-------------------------------------------------------------------------------
# skel/ の操作と _ajax_ の関数が、すべて表に入っているか
#-------------------------------------------------------------------------------
{
	my %listed = map { $_->{action} => 1 } @ACTIONS;
	my @all;
	File::Find::find({ no_chdir => 1, wanted => sub {
		return if (!m{/_action/([\w\-]+)\.html$});
		my $a = File::Spec->abs2rel($_, "$FindBin::Bin/../skel");
		$a =~ s{_action/}{};
		$a =~ s/\.html$//;
		push(@all, $a);
	}}, "$FindBin::Bin/../skel");
	foreach my $pm (glob("$FindBin::Bin/../lib/SatsukiApp/adiary*.pm")) {
		open(my $fh, '<', $pm) || die "$pm: $!";
		push(@all, map { /^sub\s+(_ajax_\w+)/ ? $1 : () } <$fh>);
	}
	my @missing = grep { !$listed{$_} && !$SKIP{$_} } @all;
	is_deeply([ sort @missing ], [], '操作はすべて表に入っている')
		or diag("表に足す操作: @missing");
}

#-------------------------------------------------------------------------------
# 権限
#-------------------------------------------------------------------------------
my $app  = AppTest->new()->setup()->seed();
my $snap = $app->snapshot();

#-------------------------------------------------------------------------------
# GETで送っても通らない
#-------------------------------------------------------------------------------
# フォームの中身をクエリにして、システム管理者で送る。送り方は2通り
#	?action=操作&名前=値...
#	?操作の画面&action=操作&名前=値...（set/detail のように、画面と同じ名前の操作を、その画面のURLで送る）
# ファイル（multipartで送るもの）はクエリにできないので、ファイル名だけを入れる
sub get_queries {
	my ($action, $form) = @_;
	my @f = @$form;
	my @list;
	while(@f) {
		my $k = shift(@f);
		my $v = shift(@f);
		$v = $v->{filename} if (ref($v));
		push(@list, AppTest::_uri_escape($k) . '=' . AppTest::_uri_escape($v));
	}
	my $q = join('&', @list);
	return $action =~ /^_/ ? ($q) : ($q, "$action&$q");
}
sub check_get {
	my ($label, $action, $form, $ok, $before) = @_;
	foreach my $q (get_queries($action, $form)) {
		my $r = $app->get('admin', $q);
		my @changed = AppTest::diff_fingerprint($before, $app->fingerprint());
		ok(!@changed && !($ok && $ok->($r)), "$label をGET（?$q）で送っても通らない")
			or diag(@changed ? "変わったファイル: @changed" : "通ったときの応答が返った: status=$r->{status} " . substr($r->{body}, 0, 200));
		if (@changed) {
			$app->restore($snap);
		}
	}
}

is_deeply([ sort keys(%SKIP_FORM) ], [ sort keys(%SKIP) ], '表に入れない操作の、GETで送る中身がそろっている');
foreach my $action (sort keys(%SKIP_FORM)) {
	my $f = $SKIP_FORM{$action};
	$app->restore($snap);
	check_get($action, $action, [ action => $action, map { ($_, $f->{$_}) } sort keys(%$f) ], undef, $app->fingerprint());
}

#-------------------------------------------------------------------------------
# 表の操作
#-------------------------------------------------------------------------------
foreach my $c (@ACTIONS) {
	my $label = $c->{label} || $c->{action};
	my $ok    = $c->{ok};
	my @form  = ref($c->{form}) eq 'ARRAY' ? @{$c->{form}} : map { ($_, $c->{form}->{$_}) } sort keys(%{$c->{form}});
	unshift(@form, action => $c->{action});

	$app->restore($snap);
	my $before = $app->fingerprint();

	# GET
	check_get($label, $c->{action}, \@form, $ok, $before);

	# 下限より下の人
	foreach my $who (grep { $LEVEL{$_} < $LEVEL{$c->{min}} } @ROLES) {
		my $r = $app->post($who, '', \@form);
		my @changed = AppTest::diff_fingerprint($before, $app->fingerprint());
		ok(!@changed && !($ok && $ok->($r)), "$label を $who はできない")
			or diag(@changed ? "変わったファイル: @changed" : "通ったときの応答が返った: status=$r->{status} " . substr($r->{body}, 0, 200));
		if (@changed) {
			$app->restore($snap);
		}
	}

	# 下限の人
	{
		my $who = $c->{min};
		my $r = $app->post($who, '', \@form);
		my @changed = AppTest::diff_fingerprint($before, $app->fingerprint());
		my $done = $ok ? $ok->($r) : @changed;
		local $TODO = $c->{todo};
		ok($done, "$label を $who はできる")
			or diag("status=$r->{status} title=" . ($r->{title} // '') . ' body=' . substr($r->{body} // '', 0, 300) . ($r->{stderr} ? "\nstderr=$r->{stderr}" : ''));
	}
}

done_testing();
