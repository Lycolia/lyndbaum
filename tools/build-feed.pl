#!/usr/bin/env perl
# RSS（pub/rss.xml）とサイトマップ（pub/sitemap.xml）を書き出す
#   perl tools/build-feed.pl [設定ファイル]
# 記事の保存と再構築（tools/rebuild-html.pl）のときにも書き出すので、ふだんは実行しなくてよい
use strict;
use warnings;
use utf8;

use FindBin;
use lib "$FindBin::Bin/../lib", "$FindBin::Bin/../extlib";

use Lyndbaum::App;
use Lyndbaum::StaticFiles;

binmode STDOUT, ':encoding(UTF-8)';
binmode STDERR, ':encoding(UTF-8)';
my $root = "$FindBin::Bin/..";
my $app  = Lyndbaum::App->new(root => $root, config_file => $ARGV[0] // "$root/config.json");
my $errors = Lyndbaum::StaticFiles->write_all($app);
die map { "書き出せませんでした: $_\n" } @$errors if @$errors;
print "RSSとサイトマップを書き出しました\n";
