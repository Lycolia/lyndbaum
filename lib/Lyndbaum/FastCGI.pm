package Lyndbaum::FastCGI;
# FastCGIの常駐プロセス（index.fcgi。docs/deploy.mdの「FastCGIで動かす」）
#   親のプロセスがソケットを開き、子のプロセスを決まった数だけ作る。子はリクエストを受けてはLyndbaum::App->respondに渡す
#   子は決まった数のリクエストを受けたら終わり、親が作り直す（メモリが増え続けないように）
#   止める合図（TERM、INT）を受けたら、親は子に伝えて、子がみな終わるのを待つ。子は処理の途中なら、応答を返し終えてから終わる
#   FCGIモジュール（XS。OSのパッケージで入れる）が要る。無いときはindex.cgiで動かす
use strict;
use warnings;
use utf8;

use FCGI;
use Lyndbaum::App;

# 起動してすぐに終わった子を作り直すまで待つ秒数（設定の誤りなどで、作り直しを繰り返さないように）
my $RESPAWN_WAIT = 1;

# %args
#   root          アプリの置き場所
#   config_file   設定ファイル
#   socket        待ち受けるソケット。UNIXソケットのパスか、「:ポート」「ホスト:ポート」
#   procs         子のプロセスの数
#   max_requests  1つの子が受けるリクエストの数
sub run {
	my ($class, %args) = @_;
	# 前に動いていたときのソケットのファイルが残っていると開けないので消す
	unlink $args{socket} if -S $args{socket};
	my $socket = FCGI::OpenSocket($args{socket}, 128);
	die "ソケットを開けません: $args{socket}: $!\n" if !defined $socket || $socket < 0;

	my %children;   # pid => 作った時刻
	my $stopping = 0;
	local $SIG{TERM} = local $SIG{INT} = sub {
		$stopping = 1;
		kill TERM => keys %children;
	};
	while (1) {
		while (!$stopping && keys %children < $args{procs}) {
			my $pid = fork // die "forkできません: $!\n";
			if (!$pid) {
				$class->_child($socket, %args);
				exit 0;
			}
			$children{$pid} = time;
		}
		my $pid = wait;
		last if $pid < 0;
		my $started = delete $children{$pid};
		if (!$stopping && $? != 0 && defined $started && time - $started < $RESPAWN_WAIT) {
			warn "子のプロセス（$pid）が起動してすぐに終わりました（終了状態$?）。${RESPAWN_WAIT}秒待って作り直します\n";
			sleep $RESPAWN_WAIT;
		}
	}
	FCGI::CloseSocket($socket);
	unlink $args{socket} if -S $args{socket};
	return;
}

sub _child {
	my ($class, $socket, %args) = @_;
	my %env;
	my $request = FCGI::Request(\*STDIN, \*STDOUT, \*STDERR, \%env, $socket);
	# 接続が切れても、書き込みで落ちないようにする（FCGIがエラーとして扱う）
	local $SIG{PIPE} = 'IGNORE';
	my $stop = 0;
	for (1 .. $args{max_requests}) {
		# 待っているあいだは、止める合図ですぐに終わる（受けているリクエストは無い）
		local $SIG{TERM} = local $SIG{INT} = 'DEFAULT';
		last if $request->Accept < 0;
		# 処理の途中では、応答を返し終えてから終わる
		local $SIG{TERM} = local $SIG{INT} = sub { $stop = 1 };
		# 処理の中のwarnは、FCGIがWebサーバーのエラーログへ送る。FCGIは文字（UTF-8のバイト列でないもの）を
		# 受け付けなくなる予定なので、バイト列にして渡す（待っているあいだのSTDERRは、index.fcgiでUTF-8にしてある）
		local $SIG{__WARN__} = \&_warn_bytes;
		# FCGIが中身を入れ替える%envを、アプリにはそのまま渡さず写して渡す（リクエストをまたいで同じハッシュを持たせない）
		my $response = Lyndbaum::App->respond(
			root        => $args{root},
			config_file => $args{config_file},
			env         => { %env },
			input       => \*STDIN,
		);
		binmode STDOUT;
		print $response->as_cgi;
		$request->Finish;
		last if $stop;
	}
	return;
}

sub _warn_bytes {
	my $message = join '', @_;
	utf8::encode($message) if $message =~ /[^\x00-\xff]/;
	print STDERR $message;
}

1;
