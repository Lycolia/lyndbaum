package Lyndbaum::URL;
# URLの組み立て。URLの体系はここと、App.pm のルーティング表にまとめる
use strict;
use warnings;
use utf8;

use Encode qw(encode_utf8);

# base_path   アプリのURLの接頭辞（例：/blog、mod_rewrite を使わないなら /index.cgi）
# static_path      CSSなどの静的ファイルのURLの接頭辞
# attachment_path  添付ファイルのURLの接頭辞（/ で終わる）
sub new {
	my ($class, %args) = @_;
	return bless {
		base_path       => $args{base_path} // '',
		static_path     => $args{static_path} // '/pub/assets',
		attachment_path => $args{attachment_path} // '/pub/attachments/',
	}, $class;
}

sub top {
	my ($self, %query) = @_;
	return $self->_path('/') . _query(%query);
}

# 記事とコンテンツページ。パスは slug と同じ（記事は「0 + ID」、コンテンツページは「親/子」）
sub article {
	my ($self, $slug) = @_;
	return $self->_path('/' . join '/', map { escape_segment($_) } split m{/}, $slug);
}

# タグの付いた記事。タグで絞り込んだ検索にする（そのまま絞り込みを続けられるように）
#   名前の列（親から順に）を受け取る
sub tag {
	my ($self, $names, %query) = @_;
	return $self->search(t => [$names], %query);
}

# 検索。%query
#   q     検索語
#   in    範囲（title、source。本文のときは付けない）
#   t     タグの名前の列の配列（[ [親, 子], ... ]）。空の配列 [] はタグの無い記事
#   d     年（YYYY）か年月（YYYYMM）
#   page  ページ番号（1のときは付けない）
sub search {
	my ($self, %query) = @_;
	my @pairs;
	push @pairs, [ q => $query{q} ] if defined $query{q} && $query{q} ne '';
	push @pairs, [ in => $query{in} ] if $query{in} && $query{in} ne 'text';
	push @pairs, [ t => join '::', @$_ ] for @{ $query{t} // [] };
	push @pairs, [ d => $query{d} ] if $query{d};
	push @pairs, [ page => $query{page} ] if $query{page} && $query{page} > 1;
	my $query = join '&', map { escape_segment($_->[0]) . '=' . _escape_query($_->[1]) } @pairs;
	return $self->_path('/search') . ($query ne '' ? "?$query" : '');
}

# 管理画面。$pageを付けると /admin/$page。%queryはクエリ（値が偽のものは付けない）
sub admin {
	my ($self, $page, %query) = @_;
	return $self->_path('/admin' . (defined $page ? "/$page" : '')) . _query(%query);
}

# RSS。Lyndbaum::Feed が pub/rss.xml に書き出す
sub feed {
	my ($self) = @_;
	return '/pub/rss.xml';
}

# 添付ファイル。$path は「フォルダ/ファイル名」（posts/2026/10/a.png）
sub attachment {
	my ($self, $path) = @_;
	return $self->{attachment_path} . join '/', map { escape_segment($_) } split m{/}, $path;
}

# サイトマップ。Lyndbaum::Sitemap が pub/sitemap.xml に書き出す
sub sitemap {
	my ($self) = @_;
	return '/pub/sitemap.xml';
}

sub static {
	my ($self, $file) = @_;
	return "$self->{static_path}/$file";
}

sub _path {
	my ($self, $path) = @_;
	return $self->{base_path} . $path;
}

# 値が偽のものは付けない（page => 1 など）
sub _query {
	my (%query) = @_;
	my @pairs = map { escape_segment($_) . '=' . escape_segment($query{$_}) }
		grep { $query{$_} } sort keys %query;
	return @pairs ? '?' . join('&', @pairs) : '';
}

# クエリの値をパーセントエンコードする。タグの区切りの : は読みやすいように残す
sub _escape_query {
	my ($text) = @_;
	my $bytes = encode_utf8($text);
	$bytes =~ s/([^A-Za-z0-9\-._~:])/sprintf '%%%02X', ord $1/eg;
	return $bytes;
}

# パスの1区切り分をパーセントエンコードする
sub escape_segment {
	my ($text) = @_;
	my $bytes = encode_utf8($text);
	$bytes =~ s/([^A-Za-z0-9\-._~])/sprintf '%%%02X', ord $1/eg;
	return $bytes;
}

1;
