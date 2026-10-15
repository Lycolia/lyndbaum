package Lyndbaum::OGP;
# OGP と Twitter Card のメタタグ（docs/ogp.md）
use strict;
use warnings;
use utf8;

use HTML::Entities qw(decode_entities);
use URI;

# 記事の OGP の画像（サイトの中のパスか、外部の URL）。無ければ undef
#   og_image_mode
#     auto    本文の最初の画像。サムネイルを元の画像へのリンクで囲んでいれば、元の画像（旧システムと同じ）
#     chosen  og_image（添付ファイルの中のパス）
#     none    使わない
sub article_image {
	my ($class, $app, $article) = @_;
	my $mode = $article->{og_image_mode} // 'auto';
	return undef if $mode eq 'none';
	return $app->url->attachment($article->{og_image}) if $mode eq 'chosen' && ($article->{og_image} // '') ne '';
	return $mode eq 'auto' ? $class->first_image($article->{body_html}) : undef;
}

# 本文の HTML の最初の画像
sub first_image {
	my ($class, $html) = @_;
	$html // return undef;
	# <a href="元の画像"><img src="サムネイル"></a>（[image:S:…]）なら元の画像
	while ($html =~ m{(<a\b[^>]*>\s*)?<img\b[^>]*?\bsrc="([^"]+)"}g) {
		my ($link, $src) = ($1, $2);
		if (defined $link && $link =~ /\bhref="([^"]+\.(?:jpe?g|png|apng|gif|webp))"/i) {
			return decode_entities($1);
		}
		return decode_entities($src);
	}
	return undef;
}

# メタタグの一覧 [ { attr => 'property' | 'name', key, content }, ... ]
#   %args
#     type         article か website
#     url          ページの絶対 URL
#     title        題名
#     description  説明
#     image        画像（サイトの中のパスか、外部の URL）。無ければブログの画像
#     base         絶対 URL にするときの元（https://blog.example.jp）
sub tags {
	my ($class, $app, %args) = @_;
	my $settings = $app->settings;
	my $image = $args{image};
	my $large = defined $image;   # 記事の画像があれば大きなカードにする（旧システムと同じ）
	$image //= ($settings->{blog_image} // '') ne '' ? $app->url->attachment($settings->{blog_image}) : undef;
	$image = URI->new_abs($image, "$args{base}/")->as_string if defined $image;
	my @tags = (
		[ property => 'og:type',        $args{type} ],
		[ property => 'og:url',         $args{url} ],
		[ property => 'og:title',       $args{title} ],
		[ property => 'og:description', $args{description} ],
		(defined $image ? [ property => 'og:image', $image ] : ()),
		[ property => 'og:site_name',   $settings->{blog_title} ],
		[ property => 'og:locale',      'ja_JP' ],
		[ name     => 'twitter:card',   $large ? 'summary_large_image' : 'summary' ],
		[ name     => 'twitter:title',  $args{title} ],
		[ name     => 'twitter:description', $args{description} ],
		(defined $image ? [ name => 'twitter:image', $image ] : ()),
	);
	# 値の無いもの（説明が空など）は出さない
	return [ map { +{ attr => $_->[0], key => $_->[1], content => $_->[2] } } grep { ($_->[2] // '') ne '' } @tags ];
}

1;
