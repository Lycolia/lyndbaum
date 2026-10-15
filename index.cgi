#!/usr/bin/env perl
# 入口。処理はすべて Lyndbaum::App に任せる
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
use Lyndbaum::Response;

my $response = eval {
	my $app = Lyndbaum::App->new(
		root        => $FindBin::Bin,
		config_file => $ENV{LYNDBAUM_CONFIG} // "$FindBin::Bin/config.json",
	);
	$app->handle(\%ENV);
};
if (!$response) {
	warn $@;
	$response = Lyndbaum::Response->new(
		status       => 500,
		content_type => 'text/plain',
		body         => "Internal Server Error\n",
	);
}

binmode STDOUT;
print $response->as_cgi;
