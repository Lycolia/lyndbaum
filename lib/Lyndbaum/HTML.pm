package Lyndbaum::HTML;
# HTMLのエスケープと、記事に書かれた生のHTMLの許可リスト。エスケープ処理はここに集める
use strict;
use warnings;
use utf8;

use Exporter 'import';
our @EXPORT_OK = qw(escape_html escape_text sanitize_tag sanitize_html strip_tags is_safe_url);

my %ENTITY = (
	'&' => '&amp;',
	'<' => '&lt;',
	'>' => '&gt;',
	'"' => '&quot;',
	"'" => '&#39;',
);

# 属性値にも使えるエスケープ
sub escape_html {
	my ($text) = @_;
	return '' if !defined $text;
	$text =~ s/([&<>"'])/$ENTITY{$1}/g;
	return $text;
}

# 本文の文字のエスケープ（属性値には使わない）。旧システムの出力に合わせて引用符は残す
sub escape_text {
	my ($text) = @_;
	return '' if !defined $text;
	$text =~ s/([&<>])/$ENTITY{$1}/g;
	return $text;
}

# タグを取り除いて文字だけにする（目次や title 属性用）。文字参照はそのまま残す
sub strip_tags {
	my ($html) = @_;
	$html =~ s/<[^>]*>//g;
	return $html;
}

#----------------------------------------------------------------------
# 記事に書ける生のHTML
#----------------------------------------------------------------------

# 許可するタグと、そのタグに書ける属性（共通の属性は %COMMON_ATTRS）
my %ALLOWED_TAGS = (
	(map { $_ => [] } qw(
		b i u s em strong small sub sup span br code kbd mark del ins q cite var samp wbr abbr
		ruby rt rp time p div section blockquote pre hr ul ol li dl dt dd
		figure figcaption details summary caption thead tbody tfoot tr center
		h1 h2 h3 h4 h5 h6
	)),
	a        => [qw(href target rel name data-lythumb)],
	img      => [qw(src alt width height loading)],
	table    => [qw(border cellpadding cellspacing width)],
	th       => [qw(colspan rowspan align width scope)],
	td       => [qw(colspan rowspan align width)],
	col      => [qw(span width)],
	colgroup => [qw(span width)],
	video    => [qw(src width height controls autoplay loop muted playsinline poster preload)],
	audio    => [qw(src controls autoplay loop muted preload)],
	source   => [qw(src type)],
	iframe   => [qw(src width height frameborder allow allowfullscreen scrolling loading referrerpolicy)],
	details  => [qw(open)],
	time     => [qw(datetime)],
	abbr     => [qw(title)],
	li       => [qw(value)],
	ol       => [qw(start type reversed)],
);
my %COMMON_ATTRS = map { $_ => 1 } qw(class id title style lang dir);
my %URL_ATTRS    = map { $_ => 1 } qw(href src poster);

# ブロックとして扱うタグ（この名前で始まる行はHTMLブロックになる）
our %BLOCK_TAGS = map { $_ => 1 } qw(
	div p section blockquote pre hr ul ol li dl dt dd figure figcaption details summary
	table caption thead tbody tfoot tr th td col colgroup center video audio source iframe
	h1 h2 h3 h4 h5 h6
);

# 1つのタグ（<…> や </…>）を許可リストに照らして返す。許可しないタグは undef
#   属性は許可したものだけを残し、URLは http(s)、相対パス、mailto のみ
sub sanitize_tag {
	my ($tag) = @_;
	my ($close, $name, $rest) = $tag =~ m{\A<(/?)([a-zA-Z][a-zA-Z0-9]*)\b(.*?)/?>\z}s or return undef;
	$name = lc $name;
	my $allowed = $ALLOWED_TAGS{$name} or return undef;
	return "</$name>" if $close;

	my %attr_ok = (%COMMON_ATTRS, map { $_ => 1 } @$allowed);
	my @attrs;
	while ($rest =~ /([a-zA-Z_:][\w:.-]*)(?:\s*=\s*(?:"([^"]*)"|'([^']*)'|([^\s"'=<>`]+)))?/g) {
		my ($attr, $value) = (lc $1, $2 // $3 // $4);
		next if !$attr_ok{$attr};
		if (!defined $value) {
			push @attrs, $attr;
			next;
		}
		$value = _decode_entities($value);
		next if $URL_ATTRS{$attr} && !_safe_url($value);
		next if $attr eq 'style' && $value =~ /expression|url\s*\(|javascript:/i;
		push @attrs, $attr . '="' . escape_html($value) . '"';
	}
	return '<' . join(' ', $name, @attrs) . '>';
}

# 管理者が書いたHTMLの断片（サイドバーの自由欄など）を、許可リストに照らして返す
#   タグは sanitize_tag に通し、許可しないタグは文字として出す。コメント（<!-- -->）は消す
#   閉じていないタグは最後に閉じ、対応の無い閉じタグは消す（周りのレイアウトを崩さないため）
my %VOID_TAGS = map { $_ => 1 } qw(br hr img wbr col source);
sub sanitize_html {
	my ($html) = @_;
	$html =~ s/<!--.*?(?:-->|\z)//gs;
	my ($out, @open) = ('');
	for my $part (split /(<[^<>]*>)/, $html) {
		if ($part !~ /\A</) {
			$part =~ s/&(?!(?:#\d+|#x[0-9a-fA-F]+|[a-zA-Z][a-zA-Z0-9]*);)/&amp;/g;
			$part =~ s/</&lt;/g;
			$part =~ s/>/&gt;/g;
			$out .= $part;
			next;
		}
		my $tag = sanitize_tag($part);
		if (!defined $tag) {
			$out .= escape_text($part);
		} elsif (my ($name) = $tag =~ m{\A</(\w+)>\z}) {
			my ($i) = grep { $open[$_] eq $name } reverse 0 .. $#open;
			next if !defined $i;
			$out .= join '', map { "</$_>" } reverse splice @open, $i;
		} else {
			($name) = $tag =~ /\A<(\w+)/;
			push @open, $name if !$VOID_TAGS{$name};
			$out .= $tag;
		}
	}
	return $out . join '', map { "</$_>" } reverse @open;
}

sub _safe_url {
	my ($url) = @_;
	(my $check = $url) =~ s/[\x00-\x20]//g;
	return 1 if $check !~ /\A[a-zA-Z][a-zA-Z0-9+.-]*:/;
	return $check =~ /\A(?:https?|ftp|mailto):/i;
}

sub _decode_entities {
	my ($text) = @_;
	$text =~ s/&#x([0-9a-fA-F]+);/chr(hex $1)/eg;
	$text =~ s/&#(\d+);/chr($1)/eg;
	$text =~ s/&quot;/"/g;
	$text =~ s/&lt;/</g;
	$text =~ s/&gt;/>/g;
	$text =~ s/&amp;/&/g;
	return $text;
}

# URLとして安全か（リンクの href などに使う）
sub is_safe_url { _safe_url($_[0]) }

1;
