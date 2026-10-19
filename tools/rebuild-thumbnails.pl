#!/usr/bin/env perl
# 添付ファイルの画像のサムネイル（.thumbnail/名前.jpg）を、編集の設定の大きさ（thumbnail_size）で作り直す
#   perl tools/rebuild-thumbnails.pl [--missing] [設定ファイル]
#     --missing  サムネイルが無い画像だけ作る（あるものは大きさが違っても変えない）
# サムネイルの大きさは編集の設定の1か所だけで決めるので、そこを変えたら、これを実行して今までの画像にも合わせる
# ゴミ箱（.trashbox）の中は作り直さない。記事の本文（記法の S と L）は書き換えない
use strict;
use warnings;
use utf8;

use FindBin;
use lib "$FindBin::Bin/../lib", "$FindBin::Bin/../extlib";

use Getopt::Long qw(GetOptions);
use Lyndbaum::App;
use Lyndbaum::Upload;

binmode STDOUT, ':encoding(UTF-8)';
binmode STDERR, ':encoding(UTF-8)';

GetOptions('missing' => \my $missing) or die "使い方: perl tools/rebuild-thumbnails.pl [--missing] [設定ファイル]\n";

my $root = "$FindBin::Bin/..";
my $app  = Lyndbaum::App->new(root => $root, config_file => $ARGV[0] // "$root/config.json");
my $size = $app->settings->{thumbnail_size};
my $result = Lyndbaum::Upload->rebuild_thumbnails(dir => $app->attachment_dir, media => $app->media, size => $size, missing => $missing);

print "長い辺 ${size}px で、$result->{made} 件のサムネイルを作りました\n";
print "$result->{skipped} 件はサムネイルがあるので、そのままにしました\n" if $missing;
if (@{ $result->{errors} }) {
	print STDERR "作れなかったもの：\n", map { "  $_\n" } @{ $result->{errors} };
	exit 1;
}
