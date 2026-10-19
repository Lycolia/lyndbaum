package Lyndbaum::Model::Article;
# 記事とコンテンツページ
use strict;
use warnings;
use utf8;
use feature 'current_sub';

use Encode ();
use Lyndbaum::Model::Tag;
use Lyndbaum::Parser::Common;

# 公開中の記事を表す条件
my $PUBLIC = q{status = 'published' AND deleted_at IS NULL};

my $COLUMNS = 'id, kind, slug, title, syntax, body_src, body_html, description, eyecatch, eyecatch_mode, published_at, updated_at, comments_open';

# 一覧などで取る列（ほかのモデルから記事を取るときにも使う）
sub columns { $COLUMNS }

# 公開中の記事かコンテンツページをslugで1件取る。リンク項目は取らない
sub find_public_by_slug {
	my ($class, $dbh, $slug) = @_;
	return $dbh->selectrow_hashref(
		"SELECT $COLUMNS FROM articles WHERE slug = ? AND kind IN ('post', 'page') AND $PUBLIC",
		undef, $slug,
	);
}

# 時系列の一覧（新しい順）。コンテンツページは含めない
sub list_public_posts {
	my ($class, $dbh, %args) = @_;
	return $dbh->selectall_arrayref(<<"SQL", { Slice => {} }, $args{limit}, $args{offset} // 0);
SELECT $COLUMNS FROM articles
WHERE kind = 'post' AND $PUBLIC
ORDER BY published_at DESC, id DESC
LIMIT ? OFFSET ?
SQL
}

sub count_public_posts {
	my ($class, $dbh) = @_;
	return scalar $dbh->selectrow_array("SELECT COUNT(*) FROM articles WHERE kind = 'post' AND $PUBLIC");
}

# 公開日時の年と月ごとの記事の件数 [ [年, 月, 件数], ... ]（新しい順。日本時間）
#   旧システムの過去ログと同じく、コンテンツページは数えない（検索 /search?d=YYYYMM の件数はコンテンツページを含む）
sub month_counts {
	my ($class, $dbh) = @_;
	my $jst = 9 * 60 * 60;
	my $rows = $dbh->selectall_arrayref(<<"SQL");
SELECT strftime('%Y', published_at + $jst, 'unixepoch') AS y, strftime('%m', published_at + $jst, 'unixepoch') AS m, COUNT(*)
FROM articles
WHERE kind = 'post' AND $PUBLIC AND published_at IS NOT NULL
GROUP BY y, m
ORDER BY y DESC, m DESC
SQL
	return [ map { [ 0 + $_->[0], 0 + $_->[1], $_->[2] ] } @$rows ];
}

# タグ（その子孫を含む）の付いた記事とコンテンツページ
sub list_public_by_tag {
	my ($class, $dbh, $tag_id, %args) = @_;
	return $dbh->selectall_arrayref(<<"SQL", { Slice => {} }, $tag_id, $args{limit}, $args{offset} // 0);
SELECT $COLUMNS FROM articles
WHERE kind IN ('post', 'page') AND $PUBLIC
  AND id IN (SELECT at.article_id
             FROM article_tags at JOIN tag_paths tp ON tp.descendant = at.tag_id
             WHERE tp.ancestor = ?)
ORDER BY published_at DESC, id DESC
LIMIT ? OFFSET ?
SQL
}

sub count_public_by_tag {
	my ($class, $dbh, $tag_id) = @_;
	return scalar $dbh->selectrow_array(<<"SQL", undef, $tag_id);
SELECT COUNT(*) FROM articles
WHERE kind IN ('post', 'page') AND $PUBLIC
  AND id IN (SELECT at.article_id
             FROM article_tags at JOIN tag_paths tp ON tp.descendant = at.tag_id
             WHERE tp.ancestor = ?)
SQL
}

# 記事ごとのタグのIDの一覧 { 記事ID => [タグID, ...] }
sub tag_ids_of {
	my ($class, $dbh, @article_ids) = @_;
	return {} if !@article_ids;
	my $placeholders = join ', ', ('?') x @article_ids;
	my $rows = $dbh->selectall_arrayref(
		"SELECT article_id, tag_id FROM article_tags WHERE article_id IN ($placeholders)",
		undef, @article_ids,
	);
	my %tag_ids;
	push @{ $tag_ids{ $_->[0] } }, $_->[1] for @$rows;
	return \%tag_ids;
}

# 公開中のコンテンツの木を、入れ子の形で返す
#   各項目は{ id, title, slug, children => [...] }
sub content_tree {
	my ($class, $dbh) = @_;
	my $rows = $dbh->selectall_arrayref(<<"SQL", { Slice => {} });
SELECT id, parent_id, title, slug
FROM articles
WHERE kind = 'page' AND $PUBLIC
ORDER BY sort_order, id
SQL
	my %by_id = map { $_->{id} => { %$_, children => [] } } @$rows;
	my @roots;
	for my $row (@$rows) {
		my $node = $by_id{ $row->{id} };
		# 親が非公開かゴミ箱の中なら、子も出さない
		if (!defined $row->{parent_id}) {
			push @roots, $node;
		} elsif (my $parent = $by_id{ $row->{parent_id} }) {
			push @{ $parent->{children} }, $node;
		}
	}
	return \@roots;
}

#----------------------------------------------------------------------
# 管理画面（docs/admin.md の「記事の管理」）

my $ADMIN_COLUMNS = "$COLUMNS, status, created_at, deleted_at, parent_id, sort_order";

# 1件取る（下書きを含む。ゴミ箱の中のものは取らない）
sub find_for_admin {
	my ($class, $dbh, $id) = @_;
	return $dbh->selectrow_hashref(
		"SELECT $ADMIN_COLUMNS FROM articles WHERE id = ? AND kind IN ('post', 'page') AND deleted_at IS NULL",
		undef, $id,
	);
}

# 管理者が公開側で開く記事。下書きを含む（下書きを、公開する前に確かめるため）
sub find_by_slug_for_admin {
	my ($class, $dbh, $slug) = @_;
	return $dbh->selectrow_hashref(
		"SELECT $ADMIN_COLUMNS FROM articles WHERE slug = ? AND kind IN ('post', 'page') AND deleted_at IS NULL",
		undef, $slug,
	);
}

# 一覧の条件。%args の status（draft、published。省くとすべて）、q（題名に含む語）
#   %args：kind（post か page。省くと両方）、status、q
sub _admin_where {
	my (%args) = @_;
	my @where = ($args{kind} ? 'a.kind = ?' : q{a.kind IN ('post', 'page')}, 'a.deleted_at IS NULL');
	my @bind = $args{kind} ? ($args{kind}) : ();
	if ($args{status}) {
		push @where, 'a.status = ?';
		push @bind, $args{status};
	}
	if (defined $args{q} && $args{q} ne '') {
		# 題名は検索用に正規化して持っているので、語も同じく正規化して探す
		push @where, 'instr(s.title, ?) > 0';
		push @bind, Lyndbaum::Parser::Common::normalize_for_search($args{q});
	}
	return (join(' AND ', @where), @bind);
}

# 一覧（下書きと、公開日時の無いものを先に、あとは新しい順）。コメントの数（承認待ちを含む）を付ける
sub list_admin {
	my ($class, $dbh, %args) = @_;
	my ($where, @bind) = _admin_where(%args);
	return $dbh->selectall_arrayref(<<"SQL", { Slice => {} }, @bind, $args{limit}, $args{offset} // 0);
SELECT a.id, a.kind, a.slug, a.title, a.status, a.published_at, a.updated_at,
       (SELECT COUNT(*) FROM comments c WHERE c.article_id = a.id) AS comments_count
FROM articles a LEFT JOIN article_search s ON s.article_id = a.id
WHERE $where
ORDER BY a.published_at IS NOT NULL, a.published_at DESC, a.id DESC
LIMIT ? OFFSET ?
SQL
}

sub count_admin {
	my ($class, $dbh, %args) = @_;
	my ($where, @bind) = _admin_where(%args);
	return scalar $dbh->selectrow_array(
		"SELECT COUNT(*) FROM articles a LEFT JOIN article_search s ON s.article_id = a.id WHERE $where", undef, @bind);
}

# 状態ごとの件数 { draft => N, published => N }（ゴミ箱の中は数えない）
#   $kind（post か page）を渡すと、その種類だけを数える
sub count_by_status {
	my ($class, $dbh, $kind) = @_;
	my %counts = (draft => 0, published => 0);
	my $rows = $dbh->selectall_arrayref(
		'SELECT status, COUNT(*) FROM articles WHERE ' . ($kind ? 'kind = ?' : q{kind IN ('post', 'page')})
		. ' AND deleted_at IS NULL GROUP BY status', undef, $kind ? ($kind) : ());
	$counts{ $_->[0] } = $_->[1] for @$rows;
	return \%counts;
}

# 記事の中身の要約（SHA-256）。編集のフォームに入れておき、保存するときに今の記事と比べて、
# ほかの画面（別のタブなど）で先に保存されていないかを見る
sub digest {
	my ($class, $dbh, $id) = @_;
	require Digest::SHA;
	my $row = $dbh->selectrow_hashref(
		'SELECT title, body_src, status, published_at, comments_open, eyecatch, eyecatch_mode, updated_at FROM articles WHERE id = ?', undef, $id) // return '';
	my $tag_ids = $class->tag_ids_of($dbh, $id)->{$id} // [];
	return Digest::SHA::sha256_hex(Encode::encode_utf8(join "\0",
		map { $_ // '' } @$row{qw(title body_src status published_at comments_open eyecatch eyecatch_mode updated_at)}, sort { $a <=> $b } @$tag_ids));
}

# 記事を保存する。$v は Lyndbaum::ArticleForm->parse の値
#   %opt
#     id       書き換える記事のID。無ければ新しい記事を作る（$v->{kind} が page ならコンテンツページ）
#     context  本文の変換に使う設定（Lyndbaum::App->parser_context）
#     now      今の時刻（テスト用）
#   戻り値は { id, slug }。ほかの画面で先に保存されていたら（フォームを開いたときと記事の中身の要約が違えば）
#   保存せずに { conflict => 今の記事 } を返す
#   （更新日時を変えずに保存することがあるので、更新日時では比べない）
#   コンテンツページの親や名前が正しくなければ、保存せずに { errors => [ 理由, ... ] } を返す
#
#   - 新しい記事のIDは next_id（使い回さない）。記事の slug は「0 + ID」（旧システムと同じ）
#   - コンテンツページの slug は「親の slug/名前」（親が無ければ名前）。親か名前を変えたら、子孫の slug も付け替える
#   - 公開するときに公開日時が空なら、今の時刻にする
#   - keep_updated が真なら、更新日時を変えない（誤字の直しなど、更新として扱いたくないとき）
#   - 識別子の無い見出しに識別子を付ける（見出しの文言を変えても、見出しへのリンクが変わらないように）
#   - 題名か本文が変わったら、保存する前の版を履歴（revisions）に残す（_save_revision）
#     %opt の revision_interval（分）、revision_max（件）は設定の値
#   - 本文を変換し、検索用のテキストを作る
sub save {
	my ($class, $dbh, $v, %opt) = @_;
	my $now = $opt{now} // time;
	my %row = (
		title         => $v->{title},
		body_src      => _add_heading_ids($v->{body_src}),
		status        => $v->{status},
		published_at  => $v->{published_at} // ($v->{status} eq 'published' ? $now : undef),
		comments_open => $v->{comments_open},
		eyecatch      => $v->{eyecatch} // '',
		eyecatch_mode => $v->{eyecatch_mode} // 'auto',
		updated_at    => $now,
	);
	delete $row{updated_at} if $v->{keep_updated} && defined $opt{id};
	my $result;
	local $dbh->{sqlite_use_immediate_transaction} = 1;
	$dbh->begin_work;
	eval {
		my $id = $opt{id};
		my $old = defined $id ? $class->find_for_admin($dbh, $id) // die "記事 $id がありません\n" : undef;
		if ($old && defined $v->{digest} && $v->{digest} ne $class->digest($dbh, $id)) {
			$result = { conflict => $old };
			$dbh->rollback;
			return 1;
		}
		my $kind = $old ? $old->{kind} : ($v->{kind} // 'post') eq 'page' ? 'page' : 'post';
		if ($kind eq 'page') {
			my ($page, $errors) = $class->_page_columns($dbh, $v, $old);
			if (@$errors) {
				$result = { errors => $errors };
				$dbh->rollback;
				return 1;
			}
			%row = (%row, %$page);
		}
		if ($old) {
			$class->_save_revision($dbh, $old, $now, %opt)
				if $old->{title} ne $row{title} || $old->{body_src} ne $row{body_src};
			my @names = sort keys %row;
			$dbh->do(sprintf('UPDATE articles SET %s WHERE id = ?', join ', ', map { "$_ = ?" } @names), undef, @row{@names}, $id);
			$class->_move_descendants($dbh, $id, $old->{slug}, $row{slug}, %{ $opt{context} // {} })
				if $kind eq 'page' && $row{slug} ne $old->{slug};
			$result = { id => $id, slug => $row{slug} // $old->{slug} };
		} else {
			$id = $class->next_id($dbh);
			my %new = (slug => "0$id", %row, id => $id, kind => $kind, syntax => 'markdown', created_at => $now);
			my @names = sort keys %new;
			$dbh->do(sprintf('INSERT INTO articles (%s) VALUES (%s)', join(', ', @names), join(', ', ('?') x @names)),
				undef, @new{@names});
			$result = { id => $id, slug => $new{slug} };
		}

		$class->_save_tags($dbh, $id, $v->{tags});
		my $article = $dbh->selectrow_hashref('SELECT id, slug, title, syntax, body_src FROM articles WHERE id = ?', undef, $id);
		$class->rebuild_body($dbh, $article, %{ $opt{context} // {} });
		$dbh->commit;
		1;
	} or do {
		my $error = $@;
		$dbh->rollback;
		die $error;
	};
	return $result;
}

# 新しい記事のID。最後に使ったID（sequences）の次。完全に削除した記事のIDも使わない
#   ほかの経路（旧データの取り込みやテスト）で入った記事があっても、ぶつからないよう今の最大のIDとも比べる
sub next_id {
	my ($class, $dbh) = @_;
	$dbh->do(q{INSERT OR IGNORE INTO sequences (name, value) VALUES ('articles', 0)});
	$dbh->do(q{UPDATE sequences SET value = MAX(value, (SELECT COALESCE(MAX(id), 0) FROM articles)) + 1 WHERE name = 'articles'});
	return scalar $dbh->selectrow_array(q{SELECT value FROM sequences WHERE name = 'articles'});
}

# コンテンツページの列（slug、parent_id、sort_order）。$old は今のページ（新しいページなら undef）
#   戻り値は（列, 理由の一覧）
my %RESERVED = map { $_ => 1 } qw(search pub admin);   # ルーターが先に使うパス（Lyndbaum::App）
my $MAX_PAGE_NAME = 100;                                 # ページの名前（題名）の長さ
sub _page_columns {
	my ($class, $dbh, $v, $old) = @_;
	my @errors;
	my $parent;
	if (defined $v->{parent_id}) {
		$parent = $dbh->selectrow_hashref(q{SELECT id, slug FROM articles WHERE id = ? AND kind = 'page' AND deleted_at IS NULL},
			undef, $v->{parent_id});
		push @errors, '親のページがありません。' if !$parent;
		if ($parent && $old && grep { $_->{id} == $parent->{id} } $old, @{ $class->descendants($dbh, $old->{id}) }) {
			push @errors, '自分自身や、自分の子孫のページを親にはできません。';
		}
	}
	my $name = $v->{page_name};
	push @errors, $class->page_name_errors($name, root => !$parent) if !@errors;
	return ({}, \@errors) if @errors;

	my $slug = $parent ? "$parent->{slug}/$name" : $name;
	# 自分と子孫の新しい slug が、ほかの記事（ゴミ箱の中を含む）とぶつからないか
	my %mine = map { $_->{id} => 1 } $old ? ($old, @{ $class->descendants($dbh, $old->{id}) }) : ();
	my @slugs = ($slug, $old ? map { $slug . substr($_->{slug}, length $old->{slug}) } @{ $class->descendants($dbh, $old->{id}) } : ());
	for my $s (@slugs) {
		my $other = $dbh->selectrow_hashref('SELECT id, title, deleted_at FROM articles WHERE slug = ?', undef, $s);
		next if !$other || $mine{ $other->{id} };
		push @errors, "URL「/$s」は、" . (defined $other->{deleted_at} ? 'ゴミ箱にある' : '') . "「$other->{title}」が使っています。";
	}
	my $order = $v->{sort_order} // ($old && ($old->{parent_id} // 0) == ($v->{parent_id} // 0) ? $old->{sort_order} : undef)
		// $dbh->selectrow_array(q{SELECT COALESCE(MAX(sort_order), 0) + 1 FROM articles WHERE kind = 'page' AND parent_id IS ?},
			undef, $v->{parent_id});
	return ({ slug => $slug, parent_id => $v->{parent_id}, sort_order => $order }, \@errors);
}

# ページの名前（ページの題名。slug の最後の区切りになる）として使えない理由の一覧。使えれば空
#   %opt の root が真なら、親の無いページの名前としても確かめる
#   管理画面の入力（Lyndbaum::ArticleForm）と、旧データの取り込み（Lyndbaum::Legacy::Importer）で使う
sub page_name_errors {
	my ($class, $name, %opt) = @_;
	my @errors;
	if ($name =~ m{[/\\?#%\x00-\x1F\x7F]} || $name =~ /\A\.\.?\z/) {
		push @errors, 'ページの題名はURLになるので、/ \\ ? # % は使えません。「.」と「..」だけの題名にもできません。';
	} elsif (length $name > $MAX_PAGE_NAME) {
		push @errors, "ページの題名はURLになるので、${MAX_PAGE_NAME}文字までにしてください。";
	} elsif ($opt{root}) {
		push @errors, '親の無いページの題名は、0で始められません（記事のURLと区別するため）。' if $name =~ /\A0/;
		push @errors, "「$name」は管理画面などが使うので、親の無いページの題名にはできません。" if $RESERVED{ lc $name };
	}
	return @errors;
}

# 子孫のページ（ゴミ箱の中を含む）[ { id, slug, deleted_at }, ... ]
sub descendants {
	my ($class, $dbh, $id) = @_;
	return $dbh->selectall_arrayref(<<'SQL', { Slice => {} }, $id);
WITH RECURSIVE d (id) AS (
    SELECT id FROM articles WHERE parent_id = ?
    UNION
    SELECT a.id FROM articles a JOIN d ON a.parent_id = d.id
)
SELECT a.id, a.slug, a.deleted_at FROM articles a JOIN d ON a.id = d.id ORDER BY a.id
SQL
}

# ページの slug が変わったら、子孫の slug の頭も付け替える
#   本文の見出しと目次のリンクには記事のURLが入っているので、子孫の本文も変換し直す
sub _move_descendants {
	my ($class, $dbh, $id, $from, $to, %context) = @_;
	for my $d (@{ $class->descendants($dbh, $id) }) {
		$dbh->do('UPDATE articles SET slug = ? WHERE id = ?', undef, $to . substr($d->{slug}, length $from), $d->{id});
		my $article = $dbh->selectrow_hashref('SELECT id, slug, title, syntax, body_src FROM articles WHERE id = ?', undef, $d->{id});
		$class->rebuild_body($dbh, $article, %context);
	}
}

# 親に選べるページを木の順に並べ、深さを付けて返す（ゴミ箱の中は除く）
#   $exclude_id を渡すと、そのページと子孫を除く（自分や子孫を親にできないため）
sub parent_options {
	my ($class, $dbh, $exclude_id) = @_;
	my $rows = $dbh->selectall_arrayref(q{SELECT id, parent_id, title, slug FROM articles WHERE kind = 'page' AND deleted_at IS NULL ORDER BY sort_order, id},
		{ Slice => {} });
	my %excluded = defined $exclude_id ? map { $_->{id} => 1 } { id => $exclude_id }, @{ $class->descendants($dbh, $exclude_id) } : ();
	my %children;
	push @{ $children{ $_->{parent_id} // 0 } }, $_ for @$rows;
	my @list;
	my $walk = sub {
		my ($parent_id, $depth) = @_;
		for my $page (@{ $children{$parent_id} // [] }) {
			next if $excluded{ $page->{id} };
			push @list, { %$page, depth => $depth };
			__SUB__->($page->{id}, $depth + 1);
		}
	};
	$walk->(0, 0);
	return \@list;
}

#----------------------------------------------------------------------
# ゴミ箱（docs/admin.md の「ゴミ箱」）
#   同じテーブルの deleted_at で表す。戻せば、ID、コメント、タグ、履歴がそのまま戻る

# ゴミ箱へ移す。移した数と、移せなかった理由の一覧を返す
#   子ページ（ゴミ箱の中を除く）のあるページは移さない（子だけが残って、メニューから見えなくなるため）
sub move_to_trash {
	my ($class, $dbh, $ids, %opt) = @_;
	my $now = $opt{now} // time;
	my ($count, @errors) = (0);
	for my $id (@$ids) {
		my $article = $class->find_for_admin($dbh, $id) // next;
		if ($article->{kind} eq 'page' && grep { !defined $_->{deleted_at} } @{ $class->descendants($dbh, $id) }) {
			push @errors, "「$article->{title}」には子ページがあるので、ゴミ箱へ移せません。先に子ページの親を変えるか、子ページをゴミ箱へ移してください。";
			next;
		}
		$count += $dbh->do('UPDATE articles SET deleted_at = ? WHERE id = ? AND deleted_at IS NULL', undef, $now, $id);
	}
	return ($count, \@errors);
}

# ゴミ箱から戻す。戻した数を返す
sub restore {
	my ($class, $dbh, $ids) = @_;
	my $count = 0;
	$count += $dbh->do('UPDATE articles SET deleted_at = NULL WHERE id = ? AND deleted_at IS NOT NULL', undef, $_) for @$ids;
	return $count;
}

# ゴミ箱の記事を完全に削除する（コメント、タグの対応、履歴、検索用のテキストも消える）。ids が undef ならゴミ箱を空にする
#   消した数と、消せなかった理由の一覧を返す。子ページ（ゴミ箱の中を含む）のあるページは消さない
#   （子の slug が「親の slug/名前」のまま、親だけが無くなるため）
sub purge {
	my ($class, $dbh, $ids) = @_;
	$ids //= $dbh->selectcol_arrayref('SELECT id FROM articles WHERE deleted_at IS NOT NULL ORDER BY id');
	my ($count, @errors) = (0);
	# 子を先に消せるよう、子孫の多い順ではなく、子の無いものから消していく
	my %pending = map { $_ => 1 } @$ids;
	my $progress = 1;
	while (%pending && $progress) {
		$progress = 0;
		for my $id (sort { $a <=> $b } keys %pending) {
			next if @{ $class->descendants($dbh, $id) };
			$count += $dbh->do('DELETE FROM articles WHERE id = ? AND deleted_at IS NOT NULL', undef, $id);
			delete $pending{$id};
			$progress = 1;
		}
	}
	for my $id (sort { $a <=> $b } keys %pending) {
		my $title = $dbh->selectrow_array('SELECT title FROM articles WHERE id = ?', undef, $id) // next;
		push @errors, "「$title」には子ページがあるので、完全に削除できません。先に子ページの親を変えてください。";
	}
	return ($count, \@errors);
}

# ゴミ箱の一覧（削除した日時の新しい順）。コメントの数を付ける
sub list_trash {
	my ($class, $dbh) = @_;
	return $dbh->selectall_arrayref(<<'SQL', { Slice => {} });
SELECT a.id, a.kind, a.slug, a.title, a.status, a.published_at, a.deleted_at,
       (SELECT COUNT(*) FROM comments c WHERE c.article_id = a.id) AS comments_count
FROM articles a
WHERE a.kind IN ('post', 'page') AND a.deleted_at IS NOT NULL
ORDER BY a.deleted_at DESC, a.id DESC
SQL
}

sub count_trash {
	my ($class, $dbh) = @_;
	return scalar $dbh->selectrow_array(q{SELECT COUNT(*) FROM articles WHERE kind IN ('post', 'page') AND deleted_at IS NOT NULL});
}

#----------------------------------------------------------------------
# 更新履歴（docs/admin.md の「更新履歴」）

# 保存する前の版を履歴に残す。$old は保存する前の記事
#   前に履歴を残してから revision_interval 分の中なら残さない（続けて何度も保存した分を1つの版にまとめる）
#   記事ごとに revision_max 件を超えたら、古いものから消す。どちらも 0 なら制限しない
sub _save_revision {
	my ($class, $dbh, $old, $now, %opt) = @_;
	my $interval = $opt{revision_interval} // 180;
	my $max      = $opt{revision_max} // 120;
	if ($interval > 0) {
		my $last = $dbh->selectrow_array('SELECT MAX(created_at) FROM revisions WHERE article_id = ?', undef, $old->{id});
		return if defined $last && $now - $last < $interval * 60;
	}
	$dbh->do('INSERT INTO revisions (article_id, title, body_src, saved_at, created_at) VALUES (?, ?, ?, ?, ?)', undef,
		$old->{id}, $old->{title}, $old->{body_src}, $old->{updated_at}, $now);
	if ($max > 0) {
		$dbh->do(<<'SQL', undef, $old->{id}, $old->{id}, $max);
DELETE FROM revisions WHERE article_id = ? AND id NOT IN (
    SELECT id FROM revisions WHERE article_id = ? ORDER BY created_at DESC, id DESC LIMIT ?
)
SQL
	}
}

# 記事の履歴の一覧（新しい順）。本文の文字数を付ける（本文は含めない）
sub revisions {
	my ($class, $dbh, $article_id) = @_;
	return $dbh->selectall_arrayref(<<'SQL', { Slice => {} }, $article_id);
SELECT id, title, length(body_src) AS length, saved_at, created_at
FROM revisions WHERE article_id = ?
ORDER BY created_at DESC, id DESC
SQL
}

# 履歴の1件（本文を含む）
sub revision {
	my ($class, $dbh, $article_id, $id) = @_;
	return $dbh->selectrow_hashref('SELECT id, title, body_src, saved_at, created_at FROM revisions WHERE article_id = ? AND id = ?',
		undef, $article_id, $id);
}

# 記事のタグを付け替える。無いタグは作る
sub _save_tags {
	my ($class, $dbh, $id, $tags) = @_;
	$dbh->do('DELETE FROM article_tags WHERE article_id = ?', undef, $id);
	my ($created, %done);
	for my $names (@$tags) {
		my ($tag_id, $new) = Lyndbaum::Model::Tag->ensure_path($dbh, @$names);
		$created ||= $new;
		next if $done{$tag_id}++;
		$dbh->do('INSERT INTO article_tags (article_id, tag_id) VALUES (?, ?)', undef, $id, $tag_id);
	}
	Lyndbaum::Model::Tag->rebuild_paths($dbh) if $created;
}

# 識別子の無い見出しに、新しい識別子を付ける
#   書き足すと見出しのID以外の出力が変わる場合（add_heading_ids が die する場合）は、書き足さずにそのまま保存する
sub _add_heading_ids {
	my ($text) = @_;
	require Lyndbaum::Parser;
	require Lyndbaum::Parser::Markdown;
	my %used = map { $_->{id} => 1 } @{ Lyndbaum::Parser->parse('markdown', $text, sectioning => 1)->{toc} };
	my ($new) = eval {
		Lyndbaum::Parser::Markdown->add_heading_ids($text, sub {
			my $id = Lyndbaum::Parser::Common->new_heading_id(\%used);
			$used{$id} = 1;
			return $id;
		});
	};
	warn "見出しに識別子を付けられませんでした: $@" if !defined $new;
	return $new // $text;
}

# 本文を変換し、HTMLと説明（一覧に出す要約）と検索用テキストを保存する。$articleのbody_htmlも更新する
#   %contextはLyndbaum::Parser->parseに渡すもの（記事IDはここで足す）
#   変換するのは、記事の保存時と再構築（rebuild_all）のときだけ。表示や検索のときには変換しない
#   （パーサーを直しても、再構築するまでは今の出力が変わらないようにするため）
sub rebuild_body {
	my ($class, $dbh, $article, %context) = @_;
	require Lyndbaum::Parser;
	my $url_of = delete $context{article_url_of};
	my $result = Lyndbaum::Parser->parse($article->{syntax}, $article->{body_src}, %context, article_id => $article->{id},
		($url_of ? (article_url => $url_of->($article->{slug})) : ()));
	$dbh->do('UPDATE articles SET body_html = ?, description = ? WHERE id = ?', undef,
		$result->{html}, Lyndbaum::Parser::Common->summary($result->{html}), $article->{id});
	$dbh->do('INSERT OR REPLACE INTO article_search (article_id, title, text, source) VALUES (?, ?, ?, ?)', undef,
		$article->{id},
		Lyndbaum::Parser::Common::normalize_for_search($article->{title} // ''),
		Lyndbaum::Parser::Common->search_text($article->{title}, $result->{html}),
		Lyndbaum::Parser::Common->search_source($article->{title}, $article->{body_src}));
	$class->_save_links($dbh, $article->{id}, $result->{links} // []);
	$article->{body_html} = $result->{html};
	return $result->{html};
}

# 本文の記事へのリンク（参照元に使う。Lyndbaum::Backlinks）を入れ直す
#   リンク先の記事の参照元はトリガーが作り直しの印を付けるので、変わらないときは書き換えない
sub _save_links {
	my ($class, $dbh, $id, $slugs) = @_;
	my %new = map { $_ => 1 } @$slugs;
	my $old = $dbh->selectcol_arrayref('SELECT target_slug FROM article_links WHERE source_id = ?', undef, $id);
	return if @$old == keys %new && !grep { !$new{$_} } @$old;
	$dbh->do('DELETE FROM article_links WHERE source_id = ?', undef, $id);
	$dbh->do('INSERT INTO article_links (source_id, target_slug) VALUES (?, ?)', undef, $id, $_) for sort keys %new;
}

# 全記事（下書きとゴミ箱を含む）を変換し直す。変換した件数を返す
sub rebuild_all {
	my ($class, $dbh, %context) = @_;
	return $class->_rebuild($dbh, "SELECT id, slug, title, syntax, body_src FROM articles WHERE kind IN ('post', 'page') ORDER BY id", [], %context);
}

sub _rebuild {
	my ($class, $dbh, $sql, $bind, %context) = @_;
	my $articles = $dbh->selectall_arrayref($sql, { Slice => {} }, @$bind);
	return 0 if !@$articles;
	$dbh->begin_work;
	eval {
		$class->rebuild_body($dbh, $_, %context) for @$articles;
		$dbh->commit;
		1;
	} or do {
		my $error = $@;
		$dbh->rollback;
		die $error;
	};
	return scalar @$articles;
}

1;
