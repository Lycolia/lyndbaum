package Lyndbaum::Model::Search;
# 記事の検索と、絞り込みの候補（ファセット）の件数
#
#   my $search = Lyndbaum::Model::Search->new($dbh,
#       words    => [ 'perl', 'nginx' ],   # 正規化済みの検索語。すべてを含む記事を探す
#       scope    => 'text',                 # title（タイトル）、text（本文）、source（原文）
#       tag_ids  => [ 3, 5 ],               # すべてのタグ（子孫のタグを含む）が付いた記事
#       untagged => 0,                      # 真ならタグの無い記事
#       from     => 1767193200,             # 公開日時の範囲 [from, to)
#       to       => 1769871600,
#   );
#
# 対象は公開中の記事とコンテンツページ。設計は docs/db-schema.md の「ファセット検索」
use strict;
use warnings;
use utf8;

use Time::Local qw(timegm);
use Lyndbaum::Model::Article;

# 範囲ごとに、article_search のどの列を探すか
my %COLUMN_OF = (
	title  => 'title',
	text   => 'text',
	source => 'source',
);

# 日本時間で年月を数えるためのずれ（秒）
my $JST = 9 * 60 * 60;

sub new {
	my ($class, $dbh, %args) = @_;
	my $column = $COLUMN_OF{ $args{scope} // 'text' } // die "検索の範囲が不正です\n";

	my (@where, @bind);
	push @where, q{a.kind IN ('post', 'page') AND a.status = 'published' AND a.deleted_at IS NULL};
	for my $word (@{ $args{words} // [] }) {
		push @where, "a.id IN (SELECT article_id FROM article_search WHERE $column LIKE ? ESCAPE '\\')";
		push @bind, '%' . _escape_like($word) . '%';
	}
	for my $tag_id (@{ $args{tag_ids} // [] }) {
		push @where, <<'SQL';
EXISTS (SELECT 1 FROM article_tags at JOIN tag_paths tp ON tp.descendant = at.tag_id
        WHERE at.article_id = a.id AND tp.ancestor = ?)
SQL
		push @bind, $tag_id;
	}
	push @where, 'NOT EXISTS (SELECT 1 FROM article_tags at WHERE at.article_id = a.id)' if $args{untagged};
	if (defined $args{from}) {
		push @where, 'a.published_at >= ? AND a.published_at < ?';
		push @bind, $args{from}, $args{to};
	}

	return bless {
		dbh  => $dbh,
		hit  => 'SELECT a.id FROM articles a WHERE ' . join(' AND ', map { "($_)" } @where),
		bind => \@bind,
	}, $class;
}

sub count {
	my ($self) = @_;
	return scalar $self->{dbh}->selectrow_array("SELECT COUNT(*) FROM ($self->{hit})", undef, @{ $self->{bind} });
}

# 当たった記事を新しい順に
sub list {
	my ($self, %args) = @_;
	my $columns = Lyndbaum::Model::Article->columns;
	return $self->{dbh}->selectall_arrayref(<<"SQL", { Slice => {} }, @{ $self->{bind} }, $args{limit}, $args{offset} // 0);
SELECT $columns FROM articles
WHERE id IN ($self->{hit})
ORDER BY published_at DESC, id DESC
LIMIT ? OFFSET ?
SQL
}

# タグごとの件数 { タグID => 件数 }。親のタグには子孫のタグの記事も数える
sub tag_counts {
	my ($self) = @_;
	my $rows = $self->{dbh}->selectall_arrayref(<<"SQL", undef, @{ $self->{bind} });
SELECT tp.ancestor, COUNT(DISTINCT at.article_id)
FROM article_tags at JOIN tag_paths tp ON tp.descendant = at.tag_id
WHERE at.article_id IN ($self->{hit})
GROUP BY tp.ancestor
SQL
	return { map { $_->[0] => $_->[1] } @$rows };
}

# タグの無い記事の件数
sub untagged_count {
	my ($self) = @_;
	return scalar $self->{dbh}->selectrow_array(<<"SQL", undef, @{ $self->{bind} });
SELECT COUNT(*) FROM articles a
WHERE a.id IN ($self->{hit})
  AND NOT EXISTS (SELECT 1 FROM article_tags at WHERE at.article_id = a.id)
SQL
}

# 公開日時（日本時間）の年ごと、または月ごとの件数 [ [年 or 月, 件数], ... ]（古い順）
#   $unit は year か month
sub date_counts {
	my ($self, $unit) = @_;
	my $format = $unit eq 'month' ? '%m' : '%Y';
	my $rows = $self->{dbh}->selectall_arrayref(<<"SQL", undef, @{ $self->{bind} });
SELECT strftime('$format', published_at + $JST, 'unixepoch') AS k, COUNT(*)
FROM articles
WHERE id IN ($self->{hit}) AND published_at IS NOT NULL
GROUP BY k
ORDER BY k
SQL
	return [ map { [ 0 + $_->[0], $_->[1] ] } @$rows ];
}

# 年（と月）から、公開日時の範囲 [from, to) を返す（日本時間）
sub date_range {
	my ($class, $year, $month) = @_;
	my ($from_y, $from_m, $to_y, $to_m) = defined $month
		? ($year, $month, $month == 12 ? ($year + 1, 1) : ($year, $month + 1))
		: ($year, 1, $year + 1, 1);
	return (_epoch($from_y, $from_m) - $JST, _epoch($to_y, $to_m) - $JST);
}

# 月の1日 0時（UTC）のUNIX時刻
sub _epoch {
	my ($year, $month) = @_;
	return timegm(0, 0, 0, 1, $month - 1, $year);
}

sub _escape_like {
	my ($text) = @_;
	$text =~ s/([\\%_])/\\$1/g;
	return $text;
}

1;
