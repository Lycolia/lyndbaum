use strict;
#-------------------------------------------------------------------------------
# 起動時の組み立て（DB、ログイン、本体を作る）
#-------------------------------------------------------------------------------
# 起動スクリプト（lyndbaum.cgi、lyndbaum.fcgi）が、Satsuki::Base の start_up に setup を渡す。
# Satsuki は、どのアプリを動かすかを知らない。このCMSの置き場所と既定値は、ここに持つ。
#
package SatsukiApp::adiary::Startup;

#-------------------------------------------------------------------------------
# ●DB、ログイン、本体を作る
#-------------------------------------------------------------------------------
# 既定値は、できるだけそれぞれのnewに持つ。
sub setup {
	my $ROBJ = shift;

	$ROBJ->{Temp} = 'data/tmp/';
	$ROBJ->{WDAY_name} = ['日', '月', '火', '水', '木', '金', '土'];
	$ROBJ->{AMPM_name} = ['午前', '午後', '深夜'];

	# wwwプロセスで実行されてるようならば0775,0664になるようにする
	# ほかの人が書けるようにしない（__cache/のPerlはevalするので、書き換えられるとコードを実行される）
	if ($ROBJ->{UID} ne '' && $ROBJ->{UID} < 101) { umask(002); }

	$ROBJ->regist_skeleton('skel/');
	$ROBJ->regist_skeleton('skel.local/', 2);
	$ROBJ->load_language_file('info/lang/ja.utf8.txt');

	my $db   = $ROBJ->{DB}   = $ROBJ->loadpm('DB_text', 'data/db/');
	my $auth = $ROBJ->{Auth} = $ROBJ->loadpm('Auth', $db);
	$auth->{table}    = '_users';

	$ROBJ->{v} = $ROBJ->{Main} = $ROBJ->loadapp('adiary', $db, { admin_trust_mode => 1 });

	# フォームを読む前に、制限を設定する
	$ROBJ->{If_post_exec_pre} = \&form_options;
}

#-------------------------------------------------------------------------------
# ●フォームの制限の設定
#-------------------------------------------------------------------------------
sub form_options {
	my $ROBJ = shift;
	my $opt  = $ROBJ->{Form_options} ||= {};

	$opt->{str_max_chars} = 80;	# 文字数

	# マルチパート用の設定。データインポートや画像アップロードの最大サイズ
	$opt->{allow_multipart} = $ROBJ->{Auth}->{ok};
	$opt->{multipart_total_max_size} = $ROBJ->{Main}->{uplaod_files_max};

	# 大きいデータの場合、送信ファイルを一度テンポラリに書き出す
	if ($ENV{CONTENT_LENGTH} > 1048576) {
		$opt->{multipart_temp_flag} = 1;
	}
	# ホスト名逆引き（2重引き）
	$ROBJ->resolve_host();
}

1;
