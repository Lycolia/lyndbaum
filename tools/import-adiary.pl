#!/usr/bin/env perl
# 旧システム（adiary）のテキストDBから、記事、タグ、ブログの設定を取り込み、全記事の本文を変換して、RSSとサイトマップを書き出す
#   perl tools/import-adiary.pl <旧システムの data> <ブログID> [設定ファイル]
#   例: perl tools/import-adiary.pl data lycolia
# 取り込み先のDBは空であること。スキーマは先に tools/migrate.pl で作っておく
# 本文に書かれた旧システムの添付ファイルのパス（/pub/ブログID/image/）は、設定の attachment_path に書き換える
use strict;
use warnings;
use utf8;

use FindBin;
use lib "$FindBin::Bin/../lib", "$FindBin::Bin/../extlib";

use Lyndbaum::App;
use Lyndbaum::StaticFiles;
use Lyndbaum::Legacy::Importer;
use Lyndbaum::Model::Article;
use Lyndbaum::SidebarCache;
use Lyndbaum::Backlinks;
use Lyndbaum::BlogImage::Writer;

my ($data_dir, $blog_id, $config_file) = @ARGV;
die "使い方: $0 <旧システムの data> <ブログID> [設定ファイル]\n" if !defined $blog_id;

my $root = "$FindBin::Bin/..";
my $app  = Lyndbaum::App->new(root => $root, config_file => $config_file // "$root/config.json");
my %context = $app->parser_context;

my $result = Lyndbaum::Legacy::Importer->run($app->db, $data_dir, $blog_id,
	attachment_path => $context{attachment_path});
# ブログの画像は、添付ファイルの中から pub/branding/ へ写す（添付ファイルは先に置いておく。docs/migrate-from-adiary.md）
my $blog_image_error;
if (defined $result->{blog_image}) {
	eval { Lyndbaum::BlogImage::Writer->copy_attachment($app, $result->{blog_image}); 1 } or ($blog_image_error = $@) =~ s/\n\z//;
}
my $rebuilt = Lyndbaum::Model::Article->rebuild_all($app->db, %context);
Lyndbaum::SidebarCache->rebuild($app);
Lyndbaum::Backlinks->rebuild($app, all => 1);

binmode STDOUT, ':encoding(UTF-8)';
print "記事: $result->{articles} 件（添付ファイルのパスを書き換えた記事: $result->{rewritten} 件、"
	. "ファイル名と同じ代替テキストを落とした記事: $result->{image_alts} 件、識別子を書き足した見出し: $result->{heading_ids} 個、"
	. "先頭の / を外した記事へのリンク: $result->{article_links} 個、"
	. "付け替えた画像の拡大表示の属性（data-fancybox → data-lythumb）: $result->{lythumb} 個）\n";
print "タグ: $result->{tags} 件\n";
print "記事とタグの対応: $result->{article_tags} 件\n";
print "コメント: $result->{comments} 件（取り込まなかった非公開コメント: $result->{private_comments} 件）\n";
print "設定: $result->{settings} 件\n";
print defined $blog_image_error ? "ブログの画像（$result->{blog_image}）を写せませんでした: $blog_image_error。ブログの設定の画面で入れ直してください\n"
	: defined $result->{blog_image} ? "ブログの画像: $result->{blog_image} を写しました\n" : '';
print "本文を変換した記事: $rebuilt 件\n";

# 本文が変わったので、RSSとサイトマップも書き出し直す。site_url が無いなど、書き出せなくても変換の結果は残す
my $errors = Lyndbaum::StaticFiles->write_all($app);
print @$errors ? map { "RSSかサイトマップを書き出せませんでした: $_\n" } @$errors : "RSSとサイトマップを書き出しました\n";
