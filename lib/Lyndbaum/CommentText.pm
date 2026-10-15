package Lyndbaum::CommentText;
# コメントの本文（プレーンテキスト）を表示用のHTMLにする
#
#   >>N          同じ記事のコメント N（#cN）へのリンク
#   http(s)://…  リンク。リンクの文字は URL をそのまま出し、rel="nofollow ugc noopener noreferrer" を付ける
#   それ以外     エスケープする。改行と空白は CSS（white-space: pre-wrap）でそのまま見せる
#
# 戻り値のHTMLはここでエスケープする。<a> 以外のタグは出さない
use strict;
use warnings;
use utf8;

use Lyndbaum::HTML qw(escape_html escape_text);

# URL に使える文字（ASCII のみ。日本語の文章に続けて書かれた URL を、文章の手前で切るため）
my $URL_RE = qr{https?://[A-Za-z0-9\-._~:/?#\[\]@!\$&'()*+,;=%]+};

sub to_html {
	my ($class, $text) = @_;
	my $html = '';
	for my $part (split /(>>\d+|$URL_RE)/, $text // '') {
		if ($part =~ /\A>>(\d+)\z/) {
			$html .= qq{<a href="#c$1">} . escape_text($part) . '</a>';
		} elsif ($part =~ /\A$URL_RE\z/) {
			my ($url, $rest) = _trim_url($part);
			$html .= qq{<a href="} . escape_html($url) . qq{" rel="nofollow ugc noopener noreferrer">} . escape_text($url) . '</a>'
				. escape_text($rest);
		} else {
			$html .= escape_text($part);
		}
	}
	return $html;
}

# URL の末尾の句読点と、対になっていない閉じ括弧は、URL に含めない
#   「（https://example.com/）」や「https://example.com/.」のような書き方のため
sub _trim_url {
	my ($url) = @_;
	my $rest = '';
	while ($url =~ m{[.,;:!?'"\]]\z} || ($url =~ /\)\z/ && ($url =~ tr/(//) < ($url =~ tr/)//))) {
		$rest = chop($url) . $rest;
	}
	return ($url, $rest);
}

1;
