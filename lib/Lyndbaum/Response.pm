use strict;
use warnings;

package Lyndbaum::Response;

sub send {
    shift;
    my ($code, $body) = @_;
    print "Status: ${code}\r\n";
    print "Content-Type: text/html; charset=UTF-8\r\n\r\n";
    print "${body}\r\n"
}

1;
