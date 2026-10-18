#!/usr/bin/env perl
# 全記事について、旧システム（adiary）の出力HTMLと、新しいパーサーの出力を比べる
#   perl t/tools/corpus-diff.pl [オプション] <旧システムの data> <ブログID>
#     --id=575    この記事だけ比べ、差分を表示する
#     --diff      違いのあった記事の差分を表示する
#     --limit=N   差分を表示する記事の数（既定は 10）
#
# 旧システムの出力は、記事データ（git の管理外）の text 欄をそのまま読む。記事の中身はリポジトリに含めない
# 比べる前に、両方をテストと同じ規則で正規化し、旧システムの側には docs/compat-diffs.md の意図的な差分を当てる
use strict;
use warnings;
use utf8;

use FindBin;
use lib "$FindBin::Bin/../../lib", "$FindBin::Bin/../lib";

use File::Spec;
use File::Temp qw(tempdir);
use Getopt::Long;
use Lyndbaum::Legacy::Importer;
use Lyndbaum::Legacy::TextDB;
use Lyndbaum::Parser;
use MarkdownTest qw(normalize_html);

binmode STDOUT, ':encoding(UTF-8)';
my %opt = (limit => 10);
GetOptions(\%opt, 'id=i', 'diff', 'limit=i') or die "オプションが不正です\n";
my ($data_dir, $blog_id) = @ARGV;
die "使い方: $0 [--id=記事ID] [--diff] <旧システムの data> <ブログID>\n" if !defined $blog_id;

my $articles = Lyndbaum::Legacy::TextDB->read_table(File::Spec->catdir($data_dir, 'db', "${blog_id}_art"));
my $rewrite = Lyndbaum::Legacy::Importer->body_rewriter($blog_id, '/pub/attachments/');
my (@same, @changed);
for my $art (@$articles) {
	next if ($art->{parser} // '') ne 'markdown' || !defined $art->{text};
	next if $opt{id} && $art->{pkey} != $opt{id};

	my $body = $art->{_text} // '';
	$rewrite->($body);   # 取り込むときと同じ書き換え
	my $new = Lyndbaum::Parser->parse('markdown', $body,
		article_id => $art->{pkey}, article_url => "/$art->{link_key}", attachment_path => '/pub/attachments/', sectioning => 1)->{html};
	my $old = legacy_to_current($art->{text}, $art->{link_key}, $blog_id);

	my ($a, $b) = map { normalize_both(normalize_html($_)) } $old, $new;
	if ($a eq $b) {
		push @same, $art->{pkey};
	} else {
		push @changed, { id => $art->{pkey}, old => $a, new => $b };
	}
}

printf "比べた記事: %d / 一致: %d / 違いあり: %d\n", @same + @changed, scalar @same, scalar @changed;
print '違いのあった記事: ', join(', ', map { $_->{id} } @changed), "\n" if @changed;

my $shown = 0;
for my $c (@changed) {
	last if !$opt{id} && (!$opt{diff} || $shown++ >= $opt{limit});
	print "\n==== 記事 $c->{id}\n";
	print first_difference($c->{old}, $c->{new});
	if ($opt{id} || $opt{diff}) {
		print unified_diff($c->{old}, $c->{new});
	}
}

# 旧システムの出力に、意図的な差分（docs/compat-diffs.md）を当てる
sub legacy_to_current {
	my ($html, $slug, $blog_id) = @_;
	# バナーのアイコンの属性（旧データには古い版の出力が混ざっている）
	$html =~ s{<svg width="25" viewbox="0 0 24 24"(?: aria-label="fontSize small")?>}{<svg width="25" viewBox="0 0 24 24" aria-label="fontSize small">}g;
	# 埋め込みの大きさは style 属性で書いていた
	$html =~ s{<iframe class="([^"]+)" style="width:480px; height:270px;" src="([^"]+?)\??" frameborder="0"\s*(?:scrolling="no")?>}{
		my ($class, $src) = ($1, $2);
		qq{<iframe class="$class" width="480" height="270" src="$src" frameborder="0"}
			. ($class =~ /niconico/ ? ' scrolling="no"' : '') . ' allowfullscreen>';
	}ge;
	# 見出しと目次のリンクは、リンク先のパーセントエンコードを戻してから比べる
	$html =~ s{href="(/[^"#]*#[^"]*)"}{ my $x = $1; $x =~ s/%([0-9a-fA-F]{2})/chr hex $1/eg; utf8::decode($x); qq{href="$x"} }ge;
	# 脚注のリンクにも記事のURLを付ける
	$html =~ s{href="#(fn-|fnref-)}{href="/$slug#$1}g;
	# 画像の拡大表示の属性（Fancybox から Lythumb に替えた）
	$html =~ s{ data-fancybox=}{ data-lythumb=}g;
	# ファイル名と同じ代替テキストは、取り込むときに落とす
	$html =~ s{(<a href="[^"]*/([^"/]+)" class="tag-image-[A-Za-z]*") title="([^"]*)"((?: data-lythumb="[^"]*")?><img) alt="([^"]*)"}{
		my ($head, $file, $title, $mid, $alt) = ($1, $2, $3, $4, $5);
		$file =~ s/%([0-9a-fA-F]{2})/chr hex $1/eg; utf8::decode($file);
		$alt eq $file ? qq{$head title=""$mid alt=""} : qq{$head title="$title"$mid alt="$alt"};
	}ge;
	# 代替テキストを省いた画像の title（旧システムは「image:サイズ」を出していた）
	$html =~ s{ title="image:[A-Za-z]*"}{ title=""}g;
	# 添付ファイルのパス
	$html =~ s{(?:https?://[A-Za-z0-9.-]+)?/pub/\Q$blog_id\E/image/}{/pub/attachments/}g;
	# 添付ファイルのフォルダの名前（adiary/ → posts/。Lyndbaum::Legacy::Importer の %FOLDERS）
	$html =~ s{/pub/attachments/adiary/}{/pub/attachments/posts/}g;
	# 続きを読むの印
	$html =~ s{<!--%SeeMore%-->}{<!--more-->}g;
	# YouTube の埋め込み
	$html =~ s{<module name="youtube" vid="([\w-]+)"(?: width="\d+" height="\d+")?(?: opt="start=(\d+)")?>}{
		qq{<iframe class="youtube-player" width="480" height="270" src="https://www.youtube.com/embed/$1}
			. (defined $2 ? "?start=$2" : '') . qq{" frameborder="0" allowfullscreen></iframe>}
	}ge;
	# <p> の中の <div> と <figure>
	$html =~ s{<p>(<div class="notice_banner.*?</div></div>)</p>}{$1}gs;
	$html =~ s{<p>(<figure>.*?</figure>)</p>}{$1}gs;
	return $html;
}

# 両方に当てる正規化
sub normalize_both {
	my ($html) = @_;
	# 空要素の書き方（<br>、<br/>、<br />、<source … />）
	$html =~ s{<(br|hr)\s*/?>}{<$1 />}g;
	$html =~ s{<((?:source|img)\b[^<>]*?)\s*/>}{<$1>}g;
	# URLのパーセントエンコード
	$html =~ s{(href|src)="([^"]*)"}{ my ($k, $x) = ($1, $2); $x =~ s/%([0-9a-fA-F]{2})/chr hex $1/eg; utf8::decode($x); qq{$k="$x"} }ge;
	# 番号付きリストの開始番号（意図的な差分）
	$html =~ s{<ol start="\d+">}{<ol>}g;
	# サムネイルのファイル名（X.jpg と X.jpg.jpg が混ざっている）は、画像の段階で決めるので区別しない
	$html =~ s{(/\.thumbnail/[^"]+?)(?:\.jpg)?"}{$1"}g;
	return $html;
}

# 最初に違うところの前後を表示する
sub first_difference {
	my ($a, $b) = @_;
	my $i = 0;
	$i++ while $i < length $a && $i < length $b && substr($a, $i, 1) eq substr($b, $i, 1);
	my $from = $i > 60 ? $i - 60 : 0;
	return sprintf "  旧: …%s\n  新: …%s\n", substr($a, $from, 160), substr($b, $from, 160);
}

sub unified_diff {
	my ($a, $b) = @_;
	my $dir = tempdir(CLEANUP => 1);
	my @files;
	for my $pair (['old', $a], ['new', $b]) {
		my $file = File::Spec->catfile($dir, $pair->[0]);
		open my $fh, '>:encoding(UTF-8)', $file or die $!;
		(my $text = $pair->[1]) =~ s/></>\n</g;   # タグごとに行を分けて見やすくする
		print $fh "$text\n";
		close $fh;
		push @files, $file;
	}
	my $out = `diff -u --label 旧 --label 新 $files[0] $files[1]`;
	utf8::decode($out);
	return $out;
}
