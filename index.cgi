#!/usr/bin/env perl
# 入口。処理はすべて Lyndbaum::App に任せる
#   常駐させるときの入口はindex.fcgi（docs/deploy.mdの「FastCGIで動かす」）
use strict;
use warnings;
use utf8;

BEGIN {
	if ($] < 5.032) {
		print "Status: 500 Internal Server Error\r\n";
		print "Content-Type: text/plain; charset=UTF-8\r\n\r\n";
		printf "Requires Perl 5.32 or newer (this is Perl %vd).\n", $^V;
		exit;
	}
}

use FindBin;
use lib "$FindBin::Bin/lib", "$FindBin::Bin/extlib";

use Lyndbaum::App;

my $response = Lyndbaum::App->respond(
	root        => $FindBin::Bin,
	config_file => $ENV{LYNDBAUM_CONFIG} // "$FindBin::Bin/config.json",
	env         => \%ENV,
	input       => \*STDIN,
);

binmode STDOUT;
print $response->as_cgi;
