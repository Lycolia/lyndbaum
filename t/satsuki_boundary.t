use strict;
use utf8;
#-------------------------------------------------------------------------------
# lib/Satsuki と CMS の境界のテスト（lib/Satsuki に CMS の知識を増やさないこと）
#-------------------------------------------------------------------------------
# 実行: prove t/satsuki_boundary.t
#
# lib/Satsuki は、CMS（lib/SatsukiApp）から独立した土台で、別のアプリからも使う。
# ここに CMS の名前、置き場所、テーブル、画面の約束事を書くと、ほかのアプリから使えなくなる。
#
# ・CMS の知識を示す語のある行が、基準（%BASELINE）より増えたら落ちる
# ・減ったときも落ちる。基準を下げて、後で戻らないようにする
#
# 基準を増やす変更はしない。増やしたくなったら、CMS の側（lib/SatsukiApp、skel/、plugin/）に置き、
# lib/Satsuki には値や処理を外から渡す形を先に考える。
# コメントも数える（「CMS のこの動作を前提にしている」という印なので）。
#
use FindBin;
use Test::More;
use File::Find ();
binmode(Test::More->builder->$_, ':utf8') foreach (qw(output failure_output todo_output));

my $DIR = "$FindBin::Bin/../lib/Satsuki";

# 見張る語。1行は、種類ごとに1回だけ数える
my @KINDS = (
	['アプリの名前',     qr/SatsukiApp|adiary/i],
	['アプリ本体の参照', qr/\{Main\}|uplaod_files_max/],
	['CMSの置き場所',    qr{(?<![\w.])(?:data|skel|skel\.local|info|docs)/}],
	['CMSのテーブル',    qr/["']art["']|(?<![A-Za-z0-9])_users\b|link_key/],
	['CMSの画面',        qr/lythumb|\.thumbnail/i],
);

# 基準。ファイル（lib/Satsuki からの相対パス）→ 種類 → 行数
my %BASELINE = (
	'Base.pm'      => { 'アプリの名前' => 1, 'アプリ本体の参照' => 1 },
	'Base_2.pm'    => { 'アプリの名前' => 1 },
	'Base/HTTP.pm' => { 'アプリの名前' => 1 },
	'TextParser/Markdown.pm' => { 'CMSの置き場所' => 1, 'CMSの画面' => 4 },
	'TextParser/TagPlugin/Tag_adiary.pm'     => { 'アプリの名前' => 29, 'CMSのテーブル' => 16 },
	'TextParser/TagPlugin/Tag_audio.pm'      => { 'CMSの置き場所' => 1, 'CMSの画面' => 3 },
	'TextParser/TagPlugin/Tag_image.pm'      => { 'アプリの名前' => 1, 'CMSの画面' => 2 },
	'TextParser/TagPlugin/Tag_url_filter.pm' => { 'CMSの置き場所' => 3, 'CMSの画面' => 2 },
);

#-------------------------------------------------------------------------------
# 数える
#-------------------------------------------------------------------------------
my %found;	# ファイル → 種類 → [ "行番号: 行" ]
my @files;
File::Find::find({ no_chdir => 1, wanted => sub {
	if (-f $_ && $_ =~ /\.pm$/) { push(@files, $_); }
}}, $DIR);

foreach my $file (sort @files) {
	my $rel = substr($file, length($DIR) + 1);
	open(my $fh, '<:utf8', $file) || die "$file: $!";
	while (my $line = <$fh>) {
		chomp($line);
		foreach my $k (@KINDS) {
			if ($line !~ $k->[1]) { next; }
			$line =~ s/^\s+//;
			push(@{ $found{$rel}->{ $k->[0] } ||= [] }, "$.: $line");
		}
	}
	close($fh);
}

ok(scalar(@files) > 10, 'lib/Satsuki のモジュールを読めた') || BAIL_OUT("$DIR が読めない");

#-------------------------------------------------------------------------------
# 基準と比べる
#-------------------------------------------------------------------------------
my %all = map { $_ => 1 } (keys(%found), keys(%BASELINE));
foreach my $rel (sort keys(%all)) {
	foreach my $k (@KINDS) {
		my $kind  = $k->[0];
		my $lines = $found{$rel}->{$kind} || [];
		my $now   = scalar(@$lines);
		my $base  = ($BASELINE{$rel} || {})->{$kind} || 0;
		if (!$now && !$base) { next; }

		if ($now > $base) {
			fail("$rel 「$kind」が増えた（基準 $base → $now）");
			diag("lib/Satsuki に CMS の知識を足さない。CMS の側に置き、値や処理を外から渡す");
			diag("  $_") foreach @$lines;
		} elsif ($now < $base) {
			fail("$rel 「$kind」が減った（基準 $base → $now）。%BASELINE を $now に下げること");
		} else {
			pass("$rel 「$kind」は基準のまま（$now）");
		}
	}
}

done_testing();
