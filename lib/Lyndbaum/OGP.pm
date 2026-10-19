package Lyndbaum::OGP;
# OGP と Twitter Card のメタタグ（docs/ogp.md）
use strict;
use warnings;
use utf8;

use Lyndbaum::BlogImage;

# HTML::Entities と URI は、要るときだけ読み込む（CGI では、読み込むものが増えると表示が遅くなる。t/public-dependencies.t）

# 記事のアイキャッチ（サイトの中のパスか、外部の URL）。無ければ undef
#   選んだ画像（eyecatch。添付ファイルの中のパス）があればそれを、無ければ本文の最初の画像
#   （サムネイルを元の画像へのリンクで囲んでいれば、元の画像。旧システムと同じ）
sub article_image {
	my ($class, $app, $article) = @_;
	return $app->url->attachment($article->{eyecatch}) if ($article->{eyecatch} // '') ne '';
	return $class->first_image($article->{body_html});
}

# 本文の HTML の最初の画像
sub first_image {
	my ($class, $html) = @_;
	$html // return undef;
	# <a href="元の画像"><img src="サムネイル"></a>（[image:S:…]）なら元の画像
	while ($html =~ m{(<a\b[^>]*>\s*)?<img\b[^>]*?\bsrc="([^"]+)"}g) {
		my ($link, $src) = ($1, $2);
		if (defined $link && $link =~ /\bhref="([^"]+\.(?:jpe?g|png|apng|gif|webp))"/i) {
			return _decode_entities($1);
		}
		return _decode_entities($src);
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
	$image //= Lyndbaum::BlogImage->url($app);
	$image = _absolute($image, $args{base}) if defined $image;
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

# 属性の値の文字参照を戻す。& が無ければそのまま
sub _decode_entities {
	my ($value) = @_;
	return $value if $value !~ /&/;
	require HTML::Entities;
	return HTML::Entities::decode_entities($value);
}

# サイトの中のパスか URL を、$base（https://blog.example.jp、パスを含むこともある）からの絶対 URL にする
#   ふだんの画像（/ で始まり、エスケープの要らない文字だけで、. や .. の段の無いパス）は、$base のオリジンにつなぐだけ。
#   それ以外は URI->new_abs に任せる
sub _absolute {
	my ($url, $base) = @_;
	if ($url =~ m{\A/(?!/)(?:[A-Za-z0-9\-_.~!\$&'()*+,;=:@/]|%[0-9A-Fa-f]{2})*\z} && $url !~ m{/\.\.?(?:/|\z)}
		&& $base =~ m{\A([A-Za-z][A-Za-z0-9+.\-]*://[^/?#]*)}) {
		return $1 . $url;
	}
	require URI;
	return URI->new_abs($url, "$base/")->as_string;
}

1;
