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
		dbh   => $dbh,
		where => join(' AND ', map { "($_)" } @where),
		bind  => \@bind,
	}, $class;
}

# 当たった記事の [ [ID, 公開日時, { 祖先を含むタグID => 1 }], ... ]（新しい順）
#   件数、一覧のページ分け、タグと年月の候補は、すべてこの結果から作る。
#   検索語の LIKE は記事の全文を読むので、条件の評価は1回だけにする
sub _hits {
	my ($self) = @_;
	return $self->{hits} //= do {
		my $rows = $self->{dbh}->selectall_arrayref(<<"SQL", undef, @{ $self->{bind} });
SELECT a.id, a.published_at, tp.ancestor
FROM articles a
LEFT JOIN article_tags hit_at ON hit_at.article_id = a.id
LEFT JOIN tag_paths tp        ON tp.descendant = hit_at.tag_id
WHERE $self->{where}
ORDER BY a.published_at DESC, a.id DESC
SQL
		my (@hits, %hit_of);
		for my $row (@$rows) {
			my ($id, $published_at, $tag_id) = @$row;
			my $hit = $hit_of{$id} //= do { push @hits, [ $id, $published_at, {} ]; $hits[-1] };
			$hit->[2]{$tag_id} = 1 if defined $tag_id;
		}
		\@hits;
	};
}

sub count {
	my ($self) = @_;
	return scalar @{ $self->_hits };
}

# 当たった記事を新しい順に。本文は、表示する記事の分だけ取る
sub list {
	my ($self, %args) = @_;
	my $hits = $self->_hits;
	my $offset = $args{offset} // 0;
	my $last = $offset + $args{limit} - 1;
	$last = $#$hits if $last > $#$hits;
	return [] if $offset > $last;
	my @ids = map { $_->[0] } @$hits[ $offset .. $last ];
	my $columns = Lyndbaum::Model::Article->columns;
	my $placeholders = join ', ', ('?') x @ids;
	return $self->{dbh}->selectall_arrayref(<<"SQL", { Slice => {} }, @ids);
SELECT $columns FROM articles
WHERE id IN ($placeholders)
ORDER BY published_at DESC, id DESC
SQL
}

# タグごとの件数 { タグID => 件数 }。親のタグには子孫のタグの記事も数える
sub tag_counts {
	my ($self) = @_;
	my %counts;
	$counts{$_}++ for map { keys %{ $_->[2] } } @{ $self->_hits };
	return \%counts;
}

# タグの無い記事の件数
sub untagged_count {
	my ($self) = @_;
	return scalar grep { !%{ $_->[2] } } @{ $self->_hits };
}

# 公開日時（日本時間）の年ごと、または月ごとの件数 [ [年 or 月, 件数], ... ]（古い順）
#   $unit は year か month
sub date_counts {
	my ($self, $unit) = @_;
	my %counts;
	for my $hit (@{ $self->_hits }) {
		next if !defined $hit->[1];
		my @t = gmtime($hit->[1] + $JST);
		$counts{ $unit eq 'month' ? $t[4] + 1 : $t[5] + 1900 }++;
	}
	return [ map { [ $_, $counts{$_} ] } sort { $a <=> $b } keys %counts ];
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
