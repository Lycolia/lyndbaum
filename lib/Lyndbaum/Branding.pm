package Lyndbaum::Branding;
# サイトの見た目に使う画像（サイトのアイコン、ブログの画像）の置き場所。pub/branding/
#   ブログの設定の画面で入れ替えたり消したりする（Lyndbaum::SiteIcon、Lyndbaum::BlogImage）。添付ファイル（メディア）とは別に扱う
use strict;
use warnings;
use utf8;

use File::Path qw(make_path);
use File::Spec;
use Lyndbaum::StaticFiles;

my $DIR = 'pub/branding';
my $URL = '/pub/branding';

# 受け付ける画像の拡張子（Lyndbaum::Upload->kind_of に渡す）。GIF は動くものでも最初の1コマだけ使う
our @IMAGE_EXTS = qw(png jpg jpeg webp gif);

# 置き場所のフォルダ。config.json の branding_dir（テストで、リポジトリの pub/ を書き換えないようにするため）
sub dir {
	my ($class, $app) = @_;
	return Lyndbaum::StaticFiles->path_of($app, branding_dir => $DIR);
}

sub url {
	my ($class, $name) = @_;
	return "$URL/$name";
}

# ファイルを書き出す（フォルダが無ければ作る）
sub write_file {
	my ($class, $app, $name, $bytes) = @_;
	my $dir = $class->dir($app);
	make_path($dir, { mode => 0755 });
	return Lyndbaum::StaticFiles->write_file(File::Spec->catfile($dir, $name), $bytes);
}

# ファイルを消す（無ければ何もしない）
sub remove_file {
	my ($class, $app, $name) = @_;
	my $file = File::Spec->catfile($class->dir($app), $name);
	unlink $file or die "$file: $!\n" if -e $file;
}

1;
