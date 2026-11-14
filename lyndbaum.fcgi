#!/usr/bin/perl
use 5.14.0;
use strict;
#-------------------------------------------------------------------------------
# Satsuki system - Startup routine (for FastCGI)
#					Copyright (C)2005-2023 nabe@abk
#-------------------------------------------------------------------------------
# Last Update : 2023/02/15
#
BEGIN {
	unshift(@INC, './lib');
	$0 =~ m|^(.*?)[^/]*$|;
	chdir($1);
}
use FCGI;
use Satsuki::Base ();
use Satsuki::AutoReload ();
use Satsuki::Timer ();

$SIG{CHLD} = 'IGNORE';	# for fork()

#-------------------------------------------------------------------------------
# 終了の合図（systemctl stop、restart）
#-------------------------------------------------------------------------------
# FCGIのライブラリ（libfcgi）がSIGTERMを受け取ってしまい、要求を待っているスレッドが
# いつまでも終わらない（systemdが待ちきれずにSIGKILLするまで、90秒かかっていた）。
# 自分で受け取り、待っているスレッドの後片付けはせずにすぐ終える
#
require POSIX;
$SIG{TERM} = $SIG{INT} = sub { POSIX::_exit(0); };

#-------------------------------------------------------------------------------
# socket open?
#-------------------------------------------------------------------------------
my $Socket;
my $Threads = int($ARGV[1]) || 10;
if ($Threads<1) { $Threads=1; }
{
	my $path = $ARGV[0];
	if ($path) {
		$Socket  = FCGI::OpenSocket($path, $ARGV[2] || 100);
		if ($path =~ /\.sock$/ && -S $path) {	# UNIX domain socket?
			chmod(0660, $path);	# 同じユーザーかグループ（Webサーバー）だけがつなげる
		}
	}
}

#-------------------------------------------------------------------------------
# Normal mode
#-------------------------------------------------------------------------------
if (!$Socket) {
	&fcgi_main_loop();
	exit(0);
}

#-------------------------------------------------------------------------------
# Socket/thread mode
#-------------------------------------------------------------------------------
{
	require threads;
	&create_threads( $Threads, $Socket );

	while(1) {
		sleep(3);
		my $exit_threads = $Threads - $#{[ threads->list() ]} - 1;
		if ($exit_threads<1) { next; }

		&create_threads( $exit_threads, $Socket );
	}
}
exit(0);

sub create_threads {
	my $num  = shift;
	my $sock = shift;

	foreach(1..$num) {
		my $thr = threads->create(sub {
			my $sock = shift;
			my $req  = FCGI::Request( \*STDIN, \*STDOUT, \*STDERR, \%ENV, $sock );

			&fcgi_main_loop($req, 1);
			threads->detach();
		}, $sock);
		if (!defined $thr) { die "threads->create fail!"; }
	}
}

################################################################################
# FastCGI main loop
################################################################################
sub fcgi_main_loop {
	my $req    = shift || FCGI::Request();
	my $deamon = shift;

	my $modtime = (stat($0))[9];
	my $shutdown;
	while($req->Accept() >= 0) {
		eval {
			#-------------------------------------------------------
			# ライブラリの更新確認
			#-------------------------------------------------------
			my $flag = &Satsuki::AutoReload::check_lib();
			if ($flag) {
				$Satsuki::Base::RELOAD = 1;	# Base.pmコンパイルエラー時
				require Satsuki::Base;		# 次回、強制RELOADさせる。
				# Timerも外されている（Satsuki::で始まるものは全部外す）。
				# 読み込み直さないと、下のSatsuki::Timer->new()が毎回失敗する
				require Satsuki::Timer;
				$Satsuki::Base::RELOAD = 0;
			}

			#-------------------------------------------------------
			# 時間計測開始
			#-------------------------------------------------------
			my $timer = Satsuki::Timer->new();
			$timer->start();

			#-------------------------------------------------------
			# FastCGI環境初期化
			#-------------------------------------------------------
			my $ROBJ = Satsuki::Base->new();	# ルートオブジェクト生成
			$ROBJ->{Timer}      = $timer;
			$ROBJ->{AutoReload} = $flag;
			$ROBJ->{ModRewrite} = $deamon;

			$ROBJ->init_for_fastcgi($req);

			#-------------------------------------------------------
			# メイン
			#-------------------------------------------------------
			$ROBJ->start_up();
			$ROBJ->finish();

			$shutdown = $ROBJ->{Shutdown};
		};
		#-----------------------------------------------------
		# エラー表示
		#-----------------------------------------------------
		if (!$ENV{SatsukiExit} && $@) {
			# 中身（ファイルのパスなど）は見せず、エラーのログ（STDERR）に書く
			print STDERR $@;
			print <<HTML;
Status: 500 Internal Server Error
Content-Type: text/plain; charset=UTF-8

500 Internal Server Error
HTML
		}
		if ($shutdown) { last; }
		#-----------------------------------------------------
		# ライブラリのタイムスタンプ保存
		#-----------------------------------------------------
		&Satsuki::AutoReload::save_lib();

		#-----------------------------------------------------
		# 自分自身の更新チェック
		#-----------------------------------------------------
		if ($modtime != (stat($0))[9]) { last; }
	}
	$req->Finish();
}
