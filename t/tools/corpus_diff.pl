#!/usr/bin/perl
use strict;
#-------------------------------------------------------------------------------
# 全記事の変換結果を、指定したコミットと作業ツリーのパーサーで比べる
#-------------------------------------------------------------------------------
# 記事データ（data/db/art）は git の管理外なので、手元のデータを直接読む。
# 記事の中身はリポジトリに含めない。
#
# 使い方:
#   perl t/tools/corpus_diff.pl                 HEAD と作業ツリーを比べる
#   perl t/tools/corpus_diff.pl --base=abc123   指定したコミットと比べる
#   perl t/tools/corpus_diff.pl --diff          変わった記事の差分も表示する
#
# 対象は入力記法が markdown の記事。[&URL] などで外部へアクセスしないよう、
# HTTP の取得は常に失敗する扱いにする（両方のパーサーで同じ条件）。
#
use FindBin;
use File::Temp ();
use Getopt::Long ();

my $ROOT = "$FindBin::Bin/../..";

my %opt = (base => 'HEAD');
Getopt::Long::GetOptions(\%opt, 'base=s', 'diff', 'render=s');

my $dir = "$ROOT/data/db/art";
if (!-d $dir) { die "記事データが見つかりません（$dir）\n"; }

#-------------------------------------------------------------------------------
# 子プロセス: 渡された lib のパーサーで全記事を変換して出力する
#-------------------------------------------------------------------------------
if ($opt{render}) {
	unshift(@INC, $opt{render}, "$FindBin::Bin/../lib");
	require MarkdownTest;
	require Satsuki::Base::HTTP;
	no warnings 'redefine';
	*Satsuki::Base::HTTP::get = sub { return; };

	foreach my $file (sort glob("$dir/0*.dat")) {
		open(my $fh, '<', $file) or next;
		my $d = do { local $/; <$fh> };	# $/ の変更はこの読み込みだけに限る（パーサーの読み込みに影響させない）
		close($fh);
		if ($d !~ /^parser=markdown$/m) { next; }
		if ($d !~ /\*_text=<<__END_BLK_DATA\n(.*?)\n__END_BLK_DATA/s) { next; }
		my $text = $1;
		(my $pkey = $file) =~ s|.*/0*(\d+)\.dat$|$1|;

		my $md = MarkdownTest::new_parser();
		$md->{thisurl}  = "/0$pkey";
		$md->{thispkey} = $pkey;
		my $out = scalar $md->parse($text);
		print "\x00$pkey\n$out\n";
	}
	exit(0);
}

#-------------------------------------------------------------------------------
# 親プロセス
#-------------------------------------------------------------------------------
my $tmp = File::Temp::tempdir(CLEANUP => 1);

# 比較元のパーサーを取り出す
system("git -C '$ROOT' archive '$opt{base}' lib | tar -x -C '$tmp'") == 0
	or die "git archive に失敗しました（--base=$opt{base}）\n";

my $old = render("$tmp/lib");
my $new = render("$ROOT/lib");

my @changed = grep { $old->{$_} ne $new->{$_} } sort { $a <=> $b } keys(%$new);

printf "比較元: %s / 対象: %d 記事 / 出力が変わった記事: %d\n", $opt{base}, scalar(keys %$new), scalar(@changed);
foreach my $key (@changed) {
	print "  $key\n";
	if ($opt{diff}) {
		my ($fa, $fb) = ("$tmp/a.html", "$tmp/b.html");
		write_file($fa, $old->{$key});
		write_file($fb, $new->{$key});
		print `diff -u --label '$key ($opt{base})' --label '$key (作業ツリー)' '$fa' '$fb'`;
	}
}
exit(@changed ? 1 : 0);

#-------------------------------------------------------------------------------
sub render {
	my $lib = shift;
	my $out = `"$^X" "$0" --render='$lib'`;
	if ($?) { die "変換に失敗しました（$lib）\n"; }
	my %h;
	foreach(split(/\x00/, $out)) {
		if ($_ !~ /^(.*?)\n(.*)$/s) { next; }
		$h{$1} = $2;
	}
	return \%h;
}
sub write_file {
	my ($file, $text) = @_;
	open(my $fh, '>', $file) or die "$file: $!";
	print $fh $text;
	close($fh);
}
