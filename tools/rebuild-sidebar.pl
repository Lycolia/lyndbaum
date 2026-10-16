#!/usr/bin/env perl
# サイドバーのHTMLだけを作り直す。perl tools/rebuild-sidebar.pl [設定ファイル]
use strict;
use warnings;
use utf8;

use FindBin;
use lib "$FindBin::Bin/../lib", "$FindBin::Bin/../extlib";

use Lyndbaum::App;
use Lyndbaum::SidebarCache;

my $root = "$FindBin::Bin/..";
my $app = Lyndbaum::App->new(root => $root, config_file => $ARGV[0] // "$root/config.json");
Lyndbaum::SidebarCache->rebuild($app);
binmode STDOUT, ':encoding(UTF-8)';
print "サイドバーを再生成しました\n";
