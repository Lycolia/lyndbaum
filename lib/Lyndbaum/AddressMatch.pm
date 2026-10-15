package Lyndbaum::AddressMatch;
# 拒否するIPアドレスとホスト名の照合
#
#   IPアドレスの書き方
#     192.0.2.10 / 2001:db8::1     そのアドレスだけ
#     192.0.2.0/24 / 2001:db8::/32  CIDR
#     192.0.2.                      前方一致（末尾が . か : のとき）
#   ホスト名の書き方
#     example.net / .example.net    そのホストと、その下のホスト（spam.example.netなど）。大文字と小文字は区別しない
use strict;
use warnings;
use utf8;

use Socket qw(inet_pton AF_INET AF_INET6);

# IPアドレスの書き方が正しければ真
sub valid_ip_rule {
	my ($class, $rule) = @_;
	return !!_parse_ip_rule($rule);
}

sub valid_host_rule {
	my ($class, $rule) = @_;
	return $rule =~ /\A\.?[A-Za-z0-9](?:[A-Za-z0-9-]*[A-Za-z0-9])?(?:\.[A-Za-z0-9](?:[A-Za-z0-9-]*[A-Za-z0-9])?)*\z/;
}

# $ipが規則のどれかに当たれば真
sub ip_matches {
	my ($class, $ip, $rules) = @_;
	for my $rule (@$rules) {
		my $parsed = _parse_ip_rule($rule) or next;
		if ($parsed->{prefix_text}) {
			return 1 if index(lc $ip, lc $parsed->{prefix_text}) == 0;
			next;
		}
		my $packed = _pack($ip) or next;
		next if length $packed != length $parsed->{network};
		return 1 if _same_prefix($packed, $parsed->{network}, $parsed->{bits});
	}
	return 0;
}

sub host_matches {
	my ($class, $host, $rules) = @_;
	$host = lc($host // '');
	return 0 if $host eq '';
	for my $rule (@$rules) {
		(my $domain = lc $rule) =~ s/\A\.//;
		return 1 if $host eq $domain || substr($host, -length(".$domain")) eq ".$domain";
	}
	return 0;
}

sub _parse_ip_rule {
	my ($rule) = @_;
	return undef if !defined $rule || $rule eq '';
	if ($rule =~ m{\A([0-9A-Fa-f:.]+)/(\d{1,3})\z}) {
		my ($address, $bits) = ($1, $2);
		my $network = _pack($address) or return undef;
		return undef if $bits > length($network) * 8;
		return { network => $network, bits => $bits };
	}
	if ($rule =~ /\A[0-9A-Fa-f:.]+[.:]\z/ && $rule =~ /[0-9A-Fa-f]/) {
		return { prefix_text => $rule };
	}
	my $network = _pack($rule) or return undef;
	return { network => $network, bits => length($network) * 8 };
}

sub _pack {
	my ($ip) = @_;
	return inet_pton($ip =~ /:/ ? AF_INET6 : AF_INET, $ip);
}

# 2つのアドレス（バイト列）の先頭 $bitsビットが同じなら真
sub _same_prefix {
	my ($x, $y, $bits) = @_;
	my $bytes = int($bits / 8);
	return 0 if substr($x, 0, $bytes) ne substr($y, 0, $bytes);
	my $rest = $bits % 8 or return 1;
	my $mask = (0xFF << (8 - $rest)) & 0xFF;
	return (ord(substr $x, $bytes, 1) & $mask) == (ord(substr $y, $bytes, 1) & $mask);
}

1;
