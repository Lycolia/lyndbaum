#!/usr/bin/env perl
# 全記事の本文を変換し直し（変換済みのHTMLと検索用テキストを作り直す）、RSSとサイトマップを書き出す
#   perl tools/rebuild-html.pl [設定ファイル]
# パーサーを直したときは、これを実行するまで表示と検索は変わらない
use strict;
use warnings;
use utf8;

use FindBin;
use lib "$FindBin::Bin/../lib", "$FindBin::Bin/../extlib";

use Lyndbaum::App;
use Lyndbaum::StaticFiles;
use Lyndbaum::Model::Article;
use Lyndbaum::SidebarCache;

my $root = "$FindBin::Bin/..";
my $app  = Lyndbaum::App->new(root => $root, config_file => $ARGV[0] // "$root/config.json");
my $count = Lyndbaum::Model::Article->rebuild_all($app->db, $app->parser_context);
Lyndbaum::SidebarCache->rebuild($app);

binmode STDOUT, ':encoding(UTF-8)';
print "$count 件の記事を変換しました\n";

# 本文が変わったので、RSSとサイトマップも書き出し直す。site_url が無いなど、書き出せなくても変換の結果は残す
my $errors = Lyndbaum::StaticFiles->write_all($app);
print @$errors ? map { "RSSかサイトマップを書き出せませんでした: $_\n" } @$errors : "RSSとサイトマップを書き出しました\n";
