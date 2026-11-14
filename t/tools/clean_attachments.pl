#!/usr/bin/perl
use strict;
#-------------------------------------------------------------------------------
# 今ある画像のメタ情報を消し、サムネイルをAVIFにする
#-------------------------------------------------------------------------------
# アップロードのときと同じものを消す（Satsuki::ImageMeta。Exifは残す）。
# サイトを動かしたままでよいが、Webサーバーと同じユーザーで動かす（ファイルの持ち主が変わらないように）。
#
# 使い方:
#   perl t/tools/clean_attachments.pl <pub/attachments/>               … 数えて出すだけ。何も変えない
#   perl t/tools/clean_attachments.pl <pub/attachments/> --run         … 原本のメタ情報を消し、AVIFのサムネイルを作る
#   perl t/tools/clean_attachments.pl <pub/attachments/> --remove-old  … AVIFのサムネイルがある画像と動画の、JPEGのサムネイルを消す
#
#   --thumb-size=320  サムネイルの長い辺（既定は data/blog/setting.dat の edit_thumb_size。無ければ320）
#   --quality=60      サムネイルの画質（既定はシステム設定の media_avif_quality。無ければ65）
#   --force           --run で、AVIFのサムネイルがあっても作り直す（大きさや画質を変えたとき）
#   --data=<data/>    記事のデータの場所（既定は <pub/attachments/>/../../data/）
#   --conf=<file>     設定ファイル（既定は <pub/attachments/>/../../lyndbaum.user.cgi）
#
# 手順:
#   1. --run で、原本を片付けてAVIFのサムネイルを作る。前のJPEGのサムネイルは残すので、記事はそのまま見られる
#   2. 管理画面で全記事を再構築する。記事のサムネイルがAVIFを指すようになる
#   3. --remove-old で、JPEGのサムネイルを消す。記事のHTMLがまだJPEGを指しているものは消さずに一覧に出す
#
# - 動画のサムネイルは、サーバーでは動画の1コマを切り出せないので作らない。
#   管理画面の ?system/update の「動画のサムネイル」で、ブラウザーで作り直す（AVIFになる）。
#   --remove-old では、AVIFで作り直した動画のJPEGのサムネイル（.poster.jpg と .jpg）を消す
# - ゴミ箱（.trashbox）は触らない
# - 原本の更新日時は元のままにする（メディア管理の日付が変わらないように）
#
use FindBin;
use lib "$FindBin::Bin/../../lib";
use Getopt::Long ();
use File::Find ();
use Satsuki::ImageMeta;
use Satsuki::ImageFormat;

my %opt;
Getopt::Long::GetOptions(\%opt, 'run', 'remove-old', 'force', 'thumb-size=i', 'quality=i', 'data=s', 'conf=s') || usage();
my $dir = shift(@ARGV);
if ($dir eq '' || @ARGV || ($opt{run} && $opt{'remove-old'}) || ($opt{force} && $opt{'remove-old'})) { usage(); }
$dir =~ s|/?$|/|;
if (!-d $dir) { die "フォルダが無い: $dir\n"; }
my $data = $opt{data} || "$dir../../data/";
$data =~ s|/?$|/|;
my $root = "$dir../../";
my $conf = $opt{conf} || "${root}lyndbaum.user.cgi";

my %IMAGE = map { $_ => 1 } qw(jpg jpeg png apng webp gif avif);	# サムネイルを作る形式（設定の media_image_ext）
my %CLEAN = map { $_ => 1 } qw(jpg jpeg png apng webp);		# メタ情報を消す形式
my %VIDEO = map { $_ => 1 } qw(mp4 m4v webm ogv);		# 動画（SatsukiApp::adiary の is_video）

sub usage {
	die "usage: $0 <pub/attachments/> [--run [--force] | --remove-old] [--thumb-size=N] [--quality=N] [--data=<data/>] [--conf=<file>]\n";
}

#-------------------------------------------------------------------------------
# 画像の一覧（.thumbnail と .trashbox の中は除く）
#-------------------------------------------------------------------------------
my @files;
File::Find::find({
	no_chdir => 1,
	preprocess => sub { grep { $_ ne '.thumbnail' && $_ ne '.trashbox' } @_ },
	wanted => sub {
		if (!-f $_) { return; }
		if ($_ =~ /\.(\w+)$/ && ($IMAGE{lc($1)} || $VIDEO{lc($1)})) { push(@files, $_); }
	}
}, $dir);
@files = sort @files;

if ($opt{'remove-old'}) {
	remove_old();
	exit(0);
}

#-------------------------------------------------------------------------------
# メタ情報を消す・サムネイルを作る
#-------------------------------------------------------------------------------
my $avif = Satsuki::ImageFormat::can_write_avif();
my $size = $opt{'thumb-size'} || thumb_size_setting() || 320;
my $quality = $opt{quality} || media_avif_quality_setting() || 65;
if (!$avif) { print "ImageMagickでAVIFを書けないので、サムネイルは作らない\n"; }

my ($n, $cleaned, $saved, $thumbs, @fail) = (0, 0, 0, 0);
@files = grep { /\.(\w+)$/ && $IMAGE{lc($1)} } @files;	# 動画は --remove-old だけで扱う
foreach my $file (@files) {
	$n++;
	if ($n % 100 == 0) { print STDERR "\r$n/" . scalar(@files); }
	my ($ext) = $file =~ /\.(\w+)$/;
	$ext = lc($ext);

	# 原本のメタ情報
	if ($CLEAN{$ext}) {
		my ($r, $s);
		if ($opt{run}) {
			my @st = stat($file);
			($r, $s) = Satsuki::ImageMeta::clean_file($file, {});
			if (!$r && $s) { utime($st[8], $st[9], $file); }
		} else {
			open(my $fh, '<:raw', $file) || next;
			my $d = do { local $/; <$fh> };
			close($fh);
			my $new;
			($r, $new) = Satsuki::ImageMeta::clean_data($d, {});
			$s = defined $new ? length($d) - length($new) : 0;
		}
		if ($r < 0) { push(@fail, "メタ情報 ($r): $file"); }
		elsif ($s) { $cleaned++; $saved += $s; }
	}

	# AVIFのサムネイル
	if ($avif) {
		my ($d, $name) = $file =~ m|^(.*/)([^/]+)$|;
		my $thumb = "$d.thumbnail/$name.avif";
		if (!$opt{force} && -e $thumb) { next; }
		$thumbs++;
		if (!$opt{run}) { next; }
		if (!-d "$d.thumbnail") { mkdir("$d.thumbnail"); }
		my $r = Satsuki::ImageFormat::make_thumbnail($file, $thumb, $size, { quality => $quality });
		if ($r) { $thumbs--; push(@fail, "サムネイル ($r): $file"); }
	}
}
print STDERR "\r" if (@files >= 100);

my $verb = $opt{run} ? '' : '（数えただけ。--run で実行する）';
printf("画像: %d\n", scalar(@files));
printf("メタ情報を消した画像: %d、減った大きさ: %.1f MB%s\n", $cleaned, $saved / 1048576, $verb);
if ($avif) { printf("作ったAVIFのサムネイル（%dpx、画質%d）: %d%s\n", $size, $quality, $thumbs, $verb); }
if (@fail) { print "失敗:\n", map { "  $_\n" } @fail; }
if ($opt{run} && $thumbs) {
	print "\n次に、管理画面で全記事を再構築してから、--remove-old でJPEGのサムネイルを消してください\n";
}
exit(0);

#-------------------------------------------------------------------------------
# ○ブログの設定のサムネイルの大きさ
#-------------------------------------------------------------------------------
sub thumb_size_setting {
	open(my $fh, '<', "${data}blog/setting.dat") || return;
	while(<$fh>) {
		if (/^edit_thumb_size=(\d+)/) { return $1; }
	}
	return;
}

#-------------------------------------------------------------------------------
# ○AVIFのサムネイルの画質（media_avif_quality。アップロードのときと同じ）
#-------------------------------------------------------------------------------
# 画面で保存した値（システム設定）を先に見る
sub media_avif_quality_setting {
	if (open(my $sys, '<', "${data}system_config.dat")) {
		while(<$sys>) {
			if (/^media_avif_quality=(\d+)\s*$/) { return $1; }
		}
	}
	open(my $fh, '<', $conf) || return;
	while(<$fh>) {
		if (/^<\$v\.media_avif_quality\s*=\s*(\d+)\s*>/) { return $1; }
	}
	return;
}

#-------------------------------------------------------------------------------
# ○JPEGのサムネイルを消す
#-------------------------------------------------------------------------------
sub remove_old {
	# 記事のHTMLが指しているサムネイルの名前（ファイル名だけで見る。同じ名前なら別のフォルダのものも消さない）
	# 動画の記事用のサムネイルは「動画名.poster」の名前で入る
	my %used;
	if (-d "${data}db") {
		File::Find::find({ no_chdir => 1, wanted => sub {
			if (!-f $_ || $_ !~ /\.dat$/) { return; }
			open(my $fh, '<', $_) || return;
			while(my $line = <$fh>) {
				while($line =~ m{\.thumbnail/([^"'\s<>/]+)\.jpg}g) {
					my $name = $1;
					$name =~ s/%([0-9A-Fa-f]{2})/chr(hex($1))/eg;
					$used{$name} = 1;
				}
			}
			close($fh);
		}}, "${data}db");
	} else {
		die "記事のデータが無い: ${data}db（--data で指定してください）\n";
	}

	my ($count, $bytes, @kept) = (0, 0);
	foreach my $file (@files) {
		my ($d, $name, $ext) = $file =~ m|^(.*/)([^/]+?)(?:\.(\w+))?$|;
		$name .= ".$ext";
		# 動画は、記事用（.poster）と一覧用の両方がAVIFになっていれば消す
		my @names = $VIDEO{lc($ext)} ? ("$name.poster", $name) : ($name);
		if (grep { !-e "$d.thumbnail/$_.avif" } @names) { next; }
		foreach(@names) {
			my $jpg = "$d.thumbnail/$_.jpg";
			if (!-e $jpg) { next; }
			if ($used{$_}) { push(@kept, $jpg); next; }
			my $s = -s $jpg;
			if (unlink($jpg)) { $count++; $bytes += $s; }
		}
	}
	printf("消したJPEGのサムネイル: %d、%.1f MB\n", $count, $bytes / 1048576);
	if (@kept) {
		print "記事のHTMLがまだ指しているので消さなかったもの（全記事を再構築してから、もう一度実行してください）:\n";
		print map { "  $_\n" } @kept;
	}
}
