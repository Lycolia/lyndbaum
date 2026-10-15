package Lyndbaum::StaticFiles;
# 静的なファイルとして書き出すもの（RSS、サイトマップ）。Webサーバーがそのまま返す
#   記事を保存したとき、ゴミ箱へ出し入れしたとき、完全に削除したとき、再構築と取り込みのときに書き出し直す
use strict;
use warnings;
use utf8;

use File::Spec;
use File::Temp qw(tempfile);
use Lyndbaum::Feed;
use Lyndbaum::Sitemap;

# RSS とサイトマップを書き出す。書き出せなかったものの理由の一覧を返す（空ならすべて書き出した）
#   1つが書き出せなくても、ほかは書き出す
sub write_all {
	my ($class, $app) = @_;
	my @errors;
	for my $writer (qw(Lyndbaum::Feed Lyndbaum::Sitemap)) {
		eval { $writer->write($app); 1 } or push @errors, $@ =~ s/\n\z//r;
	}
	return \@errors;
}

# 書き出す先のパス。$key は config.json の項目（テストで、リポジトリの pub/ を書き換えないようにするため）
sub path_of {
	my ($class, $app, $key, $default) = @_;
	return File::Spec->rel2abs($app->config->get($key) // $default, $app->{root});
}

# ファイルを書き出す。一時ファイルに書いてから置き換えるので、読みに来た人が書きかけのファイルを読むことはない
sub write_file {
	my ($class, $file, $bytes) = @_;
	my (undef, $dir) = File::Spec->splitpath($file);
	my ($fh, $tmp) = tempfile('.write-XXXXXX', DIR => $dir, UNLINK => 0);
	binmode $fh;
	print {$fh} $bytes or die "$tmp: $!\n";
	close $fh or die "$tmp: $!\n";
	chmod 0644, $tmp;
	rename $tmp, $file or do { my $error = $!; unlink $tmp; die "$file: $error\n" };
	return $file;
}

1;
