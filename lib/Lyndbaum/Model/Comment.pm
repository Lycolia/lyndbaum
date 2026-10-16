package Lyndbaum::Model::Comment;
# コメント。設計は docs/db-schema.md の「コメント」
#   公開側に出すのは status = 'public' のものだけ
use strict;
use warnings;
use utf8;

# 記事の公開中のコメントを、番号の順に
sub public_of {
	my ($class, $dbh, $article_id) = @_;
	return $dbh->selectall_arrayref(<<'SQL', { Slice => {} }, $article_id);
SELECT id, num, by_admin, author_name, body, created_at
FROM comments
WHERE article_id = ? AND status = 'public'
ORDER BY num
SQL
}

# 最近の公開中のコメント（新しい順）。公開中の記事のものだけ
#   各項目は記事の slug と題名を含む
sub recent_public {
	my ($class, $dbh, $limit) = @_;
	return $dbh->selectall_arrayref(<<'SQL', { Slice => {} }, $limit);
SELECT c.num, c.author_name, c.created_at, a.slug, a.title
FROM comments c JOIN articles a ON a.id = c.article_id
WHERE c.status = 'public'
  AND a.kind IN ('post', 'page') AND a.status = 'published' AND a.deleted_at IS NULL
ORDER BY c.created_at DESC, c.id DESC
LIMIT ?
SQL
}

#----------------------------------------------------------------------
# 投稿
#----------------------------------------------------------------------

# コメントを1件保存し、記事の中での番号を返す
#   %c は article_id、status、by_admin、author_name、body、ip、host、user_agent
#   番号は、その記事で最後に使った番号（articles.last_comment_num）の次。消したコメントの番号は使い回さない
#   直接入れた行があっても番号がぶつからないよう、今の最大の番号とも比べる
#   同時に投稿されても番号がぶつからないよう、書き込みの排他を取ってから決める
#   （DBD::SQLite の begin_work は、既定で BEGIN IMMEDIATE になる）
sub create {
	my ($class, $dbh, %c) = @_;
	my $num;
	local $dbh->{sqlite_use_immediate_transaction} = 1;
	$dbh->begin_work;
	eval {
		$num = 1 + $dbh->selectrow_array(<<'SQL', undef, $c{article_id}, $c{article_id});
SELECT MAX(last_comment_num, COALESCE((SELECT MAX(num) FROM comments WHERE article_id = ?), 0))
FROM articles WHERE id = ?
SQL
		$dbh->do('UPDATE articles SET last_comment_num = ? WHERE id = ?', undef, $num, $c{article_id});
		$dbh->do(<<'SQL', undef, @c{qw(article_id)}, $num, @c{qw(status by_admin author_name body ip host user_agent)}, $c{created_at} // time);
INSERT INTO comments (article_id, num, status, by_admin, author_name, body, ip, host, user_agent, created_at)
VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
SQL
		$dbh->commit;
		1;
	} or do {
		my $error = $@;
		$dbh->rollback;
		die $error;
	};
	return $num;
}

# そのIPから、$sinceより後に投稿された件数（承認待ちを含む）
sub count_recent_by_ip {
	my ($class, $dbh, $ip, $since) = @_;
	return scalar $dbh->selectrow_array('SELECT COUNT(*) FROM comments WHERE ip = ? AND created_at > ?', undef, $ip, $since);
}

# これまで管理者として書いたコメントの名前（なりすましを見るため）
sub admin_names {
	my ($class, $dbh) = @_;
	return $dbh->selectcol_arrayref('SELECT DISTINCT author_name FROM comments WHERE by_admin = 1');
}

# 管理者が最後に使った名前（管理者のフォームに最初から入れておく）
sub last_admin_name {
	my ($class, $dbh) = @_;
	return scalar $dbh->selectrow_array('SELECT author_name FROM comments WHERE by_admin = 1 ORDER BY created_at DESC, id DESC LIMIT 1');
}

#----------------------------------------------------------------------
# 管理画面
#----------------------------------------------------------------------

# 状態ごとの件数 { public => N, held => N }
#   $article_id を渡すと、その記事のコメントだけを数える
sub count_by_status {
	my ($class, $dbh, $article_id) = @_;
	my %count = (public => 0, held => 0);
	my $rows = $dbh->selectall_arrayref(
		'SELECT status, COUNT(*) FROM comments' . (defined $article_id ? ' WHERE article_id = ?' : '') . ' GROUP BY status',
		undef, defined $article_id ? ($article_id) : ());
	$count{ $_->[0] } = $_->[1] for @$rows;
	return \%count;
}

# 新しい順の一覧
#   %args：status（undef ならすべて）、article_id（その記事のコメントだけ）、limit、offset
#   各項目は記事の slug、題名、公開中かどうか（article_public）を含む
sub list_admin {
	my ($class, $dbh, %args) = @_;
	my (@where, @bind);
	if (defined $args{status}) {
		push @where, 'c.status = ?';
		push @bind, $args{status};
	}
	if (defined $args{article_id}) {
		push @where, 'c.article_id = ?';
		push @bind, $args{article_id};
	}
	my $where = @where ? 'WHERE ' . join(' AND ', @where) : '';
	return $dbh->selectall_arrayref(<<"SQL", { Slice => {} }, @bind, $args{limit}, $args{offset} // 0);
SELECT c.id, c.article_id, c.num, c.status, c.by_admin, c.author_name, c.body, c.ip, c.host, c.user_agent, c.created_at,
       a.slug, a.title,
       (a.status = 'published' AND a.deleted_at IS NULL) AS article_public
FROM comments c JOIN articles a ON a.id = c.article_id
$where
ORDER BY c.created_at DESC, c.id DESC
LIMIT ? OFFSET ?
SQL
}

sub find {
	my ($class, $dbh, $id) = @_;
	return $dbh->selectrow_hashref('SELECT id, article_id, num, status, ip FROM comments WHERE id = ?', undef, $id);
}

sub set_status {
	my ($class, $dbh, $id, $status) = @_;
	die "コメントの状態が不正です: $status\n" if $status !~ /\A(?:public|held)\z/;
	$dbh->do('UPDATE comments SET status = ? WHERE id = ?', undef, $status, $id);
}

sub delete {
	my ($class, $dbh, $id) = @_;
	$dbh->do('DELETE FROM comments WHERE id = ?', undef, $id);
}

1;
