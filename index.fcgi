#!/usr/bin/env perl
# FastCGIの入口（常駐させるとき）。処理はLyndbaum::FastCGIとLyndbaum::Appに任せる
#   perl index.fcgi ソケット [プロセスの数] [1つのプロセスが受けるリクエストの数]
#   例：perl index.fcgi /run/lyndbaum/lyndbaum.sock 4 1000
#   systemdなどで動かし続ける（docs/deploy.mdの「FastCGIで動かす」）。CGIで動かすときの入口はindex.cgi
use strict;
use warnings;
use utf8;

BEGIN {
	if ($] < 5.032) {
		printf STDERR "Requires Perl 5.32 or newer (this is Perl %vd).\n", $^V;
		exit 1;
	}
}

use FindBin;
use lib "$FindBin::Bin/lib", "$FindBin::Bin/extlib";

binmode STDERR, ':encoding(UTF-8)';
my ($socket, $procs, $max_requests) = @ARGV;
$procs        //= 4;
$max_requests //= 1000;
if (!defined $socket || $socket eq '' || grep { !/\A[1-9]\d*\z/ } $procs, $max_requests) {
	print STDERR "使い方：perl index.fcgi ソケット [プロセスの数（既定は4）] [1つのプロセスが受けるリクエストの数（既定は1000）]\n";
	exit 2;
}
if (!eval { require FCGI; 1 }) {
	print STDERR "FCGIモジュールがありません。OSのパッケージ（DebianとUbuntuはlibfcgi-perl）で入れるか、index.cgiで動かしてください\n";
	exit 1;
}

require Lyndbaum::FastCGI;
Lyndbaum::FastCGI->run(
	root         => $FindBin::Bin,
	config_file  => $ENV{LYNDBAUM_CONFIG} // "$FindBin::Bin/config.json",
	socket       => $socket,
	procs        => $procs,
	max_requests => $max_requests,
);
