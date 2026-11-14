use strict;
#-------------------------------------------------------------------------------
# Markdownパーサーのテスト用ヘルパー
#-------------------------------------------------------------------------------
# パーサーは本番と同じ設定（skel/_parser/markdown.html, skel/_sub/satsuki_tags_parser.html）
# で組み立てる。本番の設定を変えたときは、ここも合わせること。
#
package MarkdownTest;
use Exporter 'import';
our @EXPORT_OK = qw(new_parser parse_md normalize_html load_cases);

use File::Basename ();
use File::Spec ();
use File::Temp ();

my $ROOT = File::Spec->rel2abs( File::Basename::dirname(__FILE__) . '/../..' );

my $ROBJ;
my $SATSUKI;
#-------------------------------------------------------------------------------
# ●パーサーの生成
#-------------------------------------------------------------------------------
# %opt で本番の設定を上書きできる（例: sectioning => 1）
sub new_parser {
	my %opt = @_;
	if (!$ROBJ) {
		require Satsuki::Base;
		$ROBJ = Satsuki::Base->new();
	}
	if (!$SATSUKI) {
		# キャッシュファイルは存在しないパスを渡す（空ファイルだとプラグインのタグが読み込まれない）
		my $cache = File::Temp::tempdir(CLEANUP => 1) . '/textparser_plugin_cache.dat';
		$SATSUKI = $ROBJ->loadpm('TextParser::Satsuki', $cache);
		$SATSUKI->load_tagdata("$ROOT/info/textparser_tags.txt", 1);
		$SATSUKI->{vars} = {
			Basepath => '/',
			public   => 'pub/',
			pubdist  => 'pub/assets/dist/',
			myself   => '/',
			myself2  => '/',
			image    => 'pub/attach/',
		};
		$SATSUKI->{image_attr}  = 'data-lythumb="k%k"';
	}

	my $md = $ROBJ->loadpm('TextParser::Markdown');
	my %conf = (
		section_hnum     => 3,
		tab_width        => 4,
		md_in_htmlblk    => 1,
		sectioning       => 1,
		gfm_ext          => 1,
		strict_list      => 1,
		satsuki_tags     => 1,
		satsuki_syntax_h => 1,
		satsuki_seemore  => 1,
		satsuki_footnote => 1,
		seemore_msg      => '続きを読む',
		image_attr       => 'data-lythumb="k%k"',
		%opt
	);
	foreach(keys(%conf)) { $md->{$_} = $conf{$_}; }
	$md->{satsuki_obj} = $md->{satsuki_tags} ? $SATSUKI : undef;
	$md->{thisurl}  = '/0001';
	$md->{thispkey} = 1;
	return $md;
}

sub parse_md {
	my ($text, %opt) = @_;
	my $md = new_parser(%opt);
	return scalar $md->parse($text);
}

#-------------------------------------------------------------------------------
# ●HTMLの正規化（比較用）
#-------------------------------------------------------------------------------
# タグの前後の改行と字下げを無視する。<pre>の中身はそのまま比較する。
# 数値文字参照（&#64; &#x40;）は文字に戻す（メールアドレスの難読化が毎回ランダムなため）。
sub normalize_html {
	my $html = shift;
	$html =~ s/&#x([0-9a-fA-F]+);/chr(hex($1))/eg;
	$html =~ s/&#(\d+);/chr($1)/eg;
	my @parts = split(/(<pre\b.*?<\/pre>)/s, $html);
	foreach(@parts) {
		if (/^<pre\b/) { next; }
		s/[ \t]*\n[ \t]*/\n/g;
		s/>\n+/>/g;
		s/\n+</</g;
		s/\n+/ /g;
	}
	my $r = join('', @parts);
	$r =~ s/^\s+|\s+$//g;
	return $r;
}

#-------------------------------------------------------------------------------
# ●テストケースの読み込み
#-------------------------------------------------------------------------------
# === ケース名
# （ここから --- input までの行は無視されるので、コメントを書ける）
# --- options: sectioning=1                    （省略可）
# --- todo: 理由                                （省略可。今のパーサーが満たさないもの）
# --- input
# Markdown
# --- expected
# HTML
#
sub load_cases {
	my $file = shift;
	open(my $fh, '<:utf8', $file) or die "$file: $!";
	my @lines = <$fh>;
	close($fh);

	my @cases;
	my ($case, $sect);
	foreach(@lines) {
		if (/^=== (.*?)\s*$/) {
			$case = { name => $1, input => '', expected => '', options => {} };
			push(@cases, $case);
			$sect = undef;
			next;
		}
		if (!$case) { next; }	# 先頭のコメント
		if (/^--- options:\s*(.*?)\s*$/) {
			foreach(split(/\s+/, $1)) {
				my ($k, $v) = split(/=/, $_, 2);
				$case->{options}->{$k} = $v;
			}
			next;
		}
		if (/^--- todo:\s*(.*?)\s*$/) { $case->{todo} = $1; next; }
		if (/^--- (input|expected)\s*$/) { $sect = $1; next; }
		if ($sect) { $case->{$sect} .= $_; }
	}
	foreach(@cases) {
		$_->{input}    =~ s/\n\z//;
		$_->{expected} =~ s/\n\z//;
	}
	return \@cases;
}

1;
