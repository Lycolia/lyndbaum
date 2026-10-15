#!/usr/bin/env perl
# DBのスキーマを最新にする
#   perl tools/migrate.pl [設定ファイル]
use strict;
use warnings;
use utf8;

use FindBin;
use lib "$FindBin::Bin/../lib", "$FindBin::Bin/../extlib";

use Lyndbaum::Config;
use Lyndbaum::DB;

my $root   = "$FindBin::Bin/..";
my $config = Lyndbaum::Config->load($ARGV[0] // "$root/config.json");
my $dbh    = Lyndbaum::DB->connect($config->path_of('db_path', $root));

my @applied = Lyndbaum::DB->migrate($dbh, "$root/db/migrations");
binmode STDOUT, ':encoding(UTF-8)';
if (@applied) {
	printf "適用しました: %s\n", join(', ', map { sprintf '%04d', $_ } @applied);
} else {
	print "最新です\n";
}
