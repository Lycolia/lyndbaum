#!/usr/bin/env perl
use strict;
use warnings;

unshift(@INC, './lib');

BEGIN {
	if ($] < 5.032) {
		my $main_ver = int($]);
        my $sub_ver = int(($]-$main_ver)*1000);
        my $full_ver = $main_ver.$sub_ver;

		print "Content-Type: text/html;\n\n";
		print "Do not work with <u>Perl $full_ver</u>.<br>Requires <strong>Perl 5.32 or newer</strong>.";
		exit(-1);
	}
};

# eval {
# 	require Lyndbaum::Core;
# 	require Lyndbaum::Route;

# 	my $core = Lyndbaum::Core->new();

# 	Lyndbaum::Route->route($core->request_uri, $core->query_string);
# }
require Lyndbaum::Core;
require Lyndbaum::Response;

my $core = Lyndbaum::Core->new(env => \%ENV);
my $response = eval { $core->run };

if ($response) {
	$response = Lyndbaum::Response->send(
		200,
		$response,
	);
} else {
	# warn $@ if $@;
	# $response = Lyndbaum::Response->text(
	# 	500,
	# 	'Internal Server Error',
	# );
}
