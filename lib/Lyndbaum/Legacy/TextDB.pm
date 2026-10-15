package Lyndbaum::Legacy::TextDB;
# 旧システム（adiary）のテキストDBの読み込み
#
# 1レコードが1ファイル（NNNNN.dat）で、各行は次のどちらか
#   key=value                   1行の値
#   *key=<<区切り … 区切り       複数行の値（ヒアドキュメント）
# key には「p:des_freetext,1:title」のように記号を含むものもある（ブログの設定ファイル）
# '#' で始まるファイルは索引なので読まない
use strict;
use warnings;
use utf8;

use File::Spec;

# テーブル（ディレクトリ）の全レコードを、ファイル名の番号順に返す
sub read_table {
	my ($class, $dir) = @_;
	opendir my $dh, $dir or die "ディレクトリを開けません: $dir: $!\n";
	my @files = sort { $a <=> $b } map { /\A(\d+)\.dat\z/ ? $1 : () } readdir $dh;
	closedir $dh;
	return [ map { $class->read_record(File::Spec->catfile($dir, "$_.dat")) } @files ];
}

sub read_record {
	my ($class, $file) = @_;
	open my $fh, '<:encoding(UTF-8)', $file or die "開けません: $file: $!\n";
	my %record;
	while (my $line = <$fh>) {
		chomp $line;
		next if $line eq '';
		if ($line =~ /\A\*([^=]+)=<<(.+)\z/) {
			my ($key, $end) = ($1, $2);
			my @lines;
			while (1) {
				my $body = <$fh>;
				die "$file: $key の終わり（$end）がありません\n" if !defined $body;
				chomp $body;
				last if $body eq $end;
				push @lines, $body;
			}
			$record{$key} = join "\n", @lines;
		} elsif ($line =~ /\A([^=*][^=]*)=(.*)\z/s) {
			$record{$1} = $2;
		} else {
			die "$file: 読めない行があります: $line\n";
		}
	}
	close $fh;
	return \%record;
}

1;
