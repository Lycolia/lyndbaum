package Lyndbaum::Response;
# レスポンス。本文は文字列（文字）で持ち、出力するときにUTF-8にする
use strict;
use warnings;
use utf8;

use Encode qw(encode_utf8);
use JSON::PP ();

my %STATUS_TEXT = (
	200 => 'OK',
	301 => 'Moved Permanently',
	302 => 'Found',
	303 => 'See Other',
	304 => 'Not Modified',
	400 => 'Bad Request',
	401 => 'Unauthorized',
	403 => 'Forbidden',
	404 => 'Not Found',
	405 => 'Method Not Allowed',
	409 => 'Conflict',
	413 => 'Payload Too Large',
	429 => 'Too Many Requests',
	500 => 'Internal Server Error',
);

sub new {
	my ($class, %args) = @_;
	return bless {
		status       => $args{status} // 200,
		content_type => $args{content_type} // 'text/html',
		headers      => $args{headers} // [],
		body         => $args{body} // '',
	}, $class;
}

sub status       { $_[0]{status} }
sub content_type { $_[0]{content_type} }
sub body         { $_[0]{body} }

# ヘッダーの値（同じ名前が複数あるときはすべて）
sub headers_of {
	my ($self, $name) = @_;
	my @headers = @{ $self->{headers} };
	my @values;
	while (my ($key, $value) = splice(@headers, 0, 2)) {
		push @values, $value if lc $key eq lc $name;
	}
	return @values;
}

sub add_header {
	my ($self, $name, $value) = @_;
	push @{ $self->{headers} }, $name, $value;
	return $self;
}

sub html {
	my ($class, $body, %args) = @_;
	return $class->new(%args, content_type => 'text/html', body => $body);
}

# JSON。本文は文字列で持ち、出力するときにUTF-8にする
sub json {
	my ($class, $data, %args) = @_;
	return $class->new(%args, content_type => 'application/json', body => JSON::PP->new->canonical->encode($data));
}

# CGIとして出力するバイト列
sub as_cgi {
	my ($self) = @_;
	my $status = $self->{status};
	my $out = "Status: $status " . ($STATUS_TEXT{$status} // '') . "\r\n";
	$out .= "Content-Type: $self->{content_type}; charset=UTF-8\r\n";
	my @headers = @{ $self->{headers} };
	while (my ($name, $value) = splice(@headers, 0, 2)) {
		$out .= "$name: $value\r\n";
	}
	$out .= "\r\n";
	return encode_utf8($out . $self->{body});
}

1;
