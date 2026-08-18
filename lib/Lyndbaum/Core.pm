use strict;
use warnings;

package Lyndbaum::Core;

use Lyndbaum::Router;

our $VERSION = '0.01';

sub new {
    my ($class, %_env) = @_;
	my $self = bless({}, $class);

    return bless {
        env     => \%_env,
        version => $VERSION,
        uid     => $<,
        gid     => $(,
        pid     => $$,
        cmd     => $0,
    }, $class;
}

sub run {
    my ($self) = @_;

    return Lyndbaum::Router->route({
        method       => $self->request_method,
        path         => $self->request_path,
        query_string => $self->query_string,
    });
}

sub request_method {
    my ($self) = @_;
    return $self->{env}->{REQUEST_METHOD} // 'GET';
}

sub request_path {
    my ($self) = @_;

    my $path = $self->{env}->{PATH_INFO};

    if (!defined($path) || $path eq '') {
        $path = $self->{env}->{REQUEST_URI} // '/';
        $path =~ s/\?.*\z//;
    }

    return $path eq '' ? '/' : $path;
}

sub query_string {
    my ($self) = @_;
    return $self->{env}->{QUERY_STRING} // '';
}

1;
