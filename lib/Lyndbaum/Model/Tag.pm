package Lyndbaum::Model::Tag;
# タグ
use strict;
use warnings;
use utf8;
use feature 'current_sub';

use Digest::SHA ();
use Encode ();

# 全タグを { ID => タグ } で返す
#   タグは { id, parent_id, name, sort_order, path => [親から順の名前], full_name => '親::子' }
sub all {
	my ($class, $dbh) = @_;
	my $tags = $dbh->selectall_hashref('SELECT id, parent_id, name, sort_order FROM tags', 'id');
	my $path_of = sub {
		my ($tag) = @_;
		return $tag->{path} //= do {
			my $parent = defined $tag->{parent_id} ? $tags->{ $tag->{parent_id} } : undef;
			[ ($parent ? @{ __SUB__->($parent) } : ()), $tag->{name} ];
		};
	};
	for my $tag (values %$tags) {
		$tag->{full_name} = join '::', @{ $path_of->($tag) };
	}
	return $tags;
}

# 名前の列（親から順に）からタグを探す
sub find_by_path {
	my ($class, $tags, @names) = @_;
	my $path = join "\0", @names;
	for my $tag (values %$tags) {
		return $tag if join("\0", @{ $tag->{path} }) eq $path;
	}
	return undef;
}

# 公開中の記事が付いているタグを、件数つきの木の形で返す
#   件数には子孫のタグの記事も含む。記事が1件もないタグは出さない
sub public_tree {
	my ($class, $dbh, $tags) = @_;
	my $counts = $dbh->selectall_hashref(<<'SQL', 'tag_id');
SELECT tp.ancestor AS tag_id, COUNT(DISTINCT a.id) AS count
FROM articles a
JOIN article_tags at ON at.article_id = a.id
JOIN tag_paths tp    ON tp.descendant = at.tag_id
WHERE a.kind IN ('post', 'page') AND a.status = 'published' AND a.deleted_at IS NULL
GROUP BY tp.ancestor
SQL
	my %children;
	for my $tag (sort { $a->{sort_order} <=> $b->{sort_order} || $a->{name} cmp $b->{name} } values %$tags) {
		next if !$counts->{ $tag->{id} };
		push @{ $children{ $tag->{parent_id} // 0 } }, $tag;
	}
	my $build = sub {
		my ($parent_id) = @_;
		return [ map {
			+{ %$_, count => $counts->{ $_->{id} }{count}, children => __SUB__->($_->{id}) }
		} @{ $children{$parent_id} // [] } ];
	};
	return $build->(0);
}

# タグごとの、そのタグを直接付けた記事の数 { タグID => 数 }（下書きを含む。ゴミ箱の中は数えない）
#   管理画面のタグの入力の候補に出す
sub usage_counts {
	my ($class, $dbh) = @_;
	my $rows = $dbh->selectall_arrayref(<<'SQL');
SELECT at.tag_id, COUNT(*)
FROM article_tags at JOIN articles a ON a.id = at.article_id
WHERE a.deleted_at IS NULL
GROUP BY at.tag_id
SQL
	return { map { $_->[0] => $_->[1] } @$rows };
}

# 全タグを木の順（親の次に子。同じ親の中は並び順、名前の順）に並べ、深さ（0から）を付けて返す
sub in_tree_order {
	my ($class, $tags) = @_;
	my %children;
	for my $tag (sort { $a->{sort_order} <=> $b->{sort_order} || $a->{name} cmp $b->{name} } values %$tags) {
		push @{ $children{ $tag->{parent_id} // 0 } }, $tag;
	}
	my @list;
	my $walk = sub {
		my ($parent_id, $depth) = @_;
		for my $tag (@{ $children{$parent_id} // [] }) {
			push @list, { %$tag, depth => $depth };
			__SUB__->($tag->{id}, $depth + 1);
		}
	};
	$walk->(0, 0);
	return \@list;
}

# 名前の列（親から順に）のタグのIDを返す。無ければ親から順に作る
#   作ったタグは、同じ親の中のいちばん後ろに並べる
#   戻り値は（ID, 作ったか）。作ったら、呼ぶ側で rebuild_paths を呼ぶ。トランザクションは呼ぶ側で張る
sub ensure_path {
	my ($class, $dbh, @names) = @_;
	my ($parent_id, $created);
	for my $name (@names) {
		# IS は NULL どうしも等しいとみなす（最上位のタグ）
		my $id = $dbh->selectrow_array('SELECT id FROM tags WHERE parent_id IS ? AND name = ?', undef, $parent_id, $name);
		if (!defined $id) {
			my $order = $dbh->selectrow_array('SELECT COALESCE(MAX(sort_order), 0) + 1 FROM tags WHERE parent_id IS ?',
				undef, $parent_id);
			$dbh->do('INSERT INTO tags (parent_id, name, sort_order) VALUES (?, ?, ?)', undef, $parent_id, $name, $order);
			$id = $dbh->sqlite_last_insert_rowid;
			$created = 1;
		}
		$parent_id = $id;
	}
	return ($parent_id, $created);
}

#----------------------------------------------------------------------
# タグの管理（docs/admin.md の「タグの管理」）
#   画面で組み替えた木の全体を受け取り、確かめてからまとめて書き込む（画面の操作だけでは確定しない）

# タグの表の要約（SHA-256）。画面を開いたときと保存するときで比べ、ほかの画面で変わっていないかを見る
#   記事の保存で新しいタグができたときも変わる
sub digest {
	my ($class, $dbh) = @_;
	my $rows = $dbh->selectall_arrayref('SELECT id, parent_id, name, sort_order FROM tags ORDER BY id');
	return Digest::SHA::sha256_hex(Encode::encode_utf8(join "\n", map { join "\0", map { $_ // '' } @$_ } @$rows));
}

# 記事（ゴミ箱の中を含む）が付いているタグのID { タグID => 1 }。消せないタグ（ON DELETE RESTRICT）
sub in_use {
	my ($class, $dbh) = @_;
	return { map { $_ => 1 } @{ $dbh->selectcol_arrayref('SELECT DISTINCT tag_id FROM article_tags') } };
}

# 組み替えた木を確かめて書き込む
#   $rows は今あるタグすべての [ { id, name, parent_id, sort_order, deleted }, ... ]
#   戻り値は理由の一覧（空なら書き込んだ）。トランザクションはここで張る
sub save_tree {
	my ($class, $dbh, $rows) = @_;
	my @errors;
	my $current = $dbh->selectall_hashref('SELECT id, parent_id, name, sort_order FROM tags', 'id');
	my %row_of;
	for my $row (@$rows) {
		my $id = $row->{id} // '';
		return ['タグの一覧が正しくありません。画面を開き直してください。'] if !$current->{$id} || exists $row_of{$id};
		$row_of{$id} = $row;
	}
	return ['タグの一覧が正しくありません。画面を開き直してください。'] if keys %row_of != keys %$current;

	my %kept = map { $_->{id} => $_ } grep { !$_->{deleted} } @$rows;
	my $label = sub { my $t = $current->{ $_[0] }; "「$t->{name}」" };
	my %seen;
	for my $row (sort { $a->{id} <=> $b->{id} } values %kept) {
		$row->{name} = ($row->{name} // '') =~ s/\A\s+|\s+\z//gr;
		my $name = $row->{name};
		if ($name eq '') {
			push @errors, $label->($row->{id}) . 'の名前が空です。';
		} elsif ($name =~ /::|,/ || $name =~ /[\x00-\x1F\x7F]/) {
			push @errors, "タグの名前「$name」に「::」と「,」は使えません。";
		} elsif (length $name > 100) {
			push @errors, "タグの名前「$name」は100文字までにしてください。";
		}
		my $parent = $row->{parent_id};
		if (defined $parent) {
			if (!$kept{$parent}) {
				push @errors, "「$name」の親のタグがありません（消すタグを親にはできません）。";
			} else {
				# 親をたどって自分に戻れば、循環している
				my ($p, %visited) = ($parent);
				while (defined $p && $kept{$p} && !$visited{$p}++) {
					if ($p == $row->{id}) {
						push @errors, "「$name」の親に、自分自身か自分の子孫を選んでいます。";
						last;
					}
					$p = $kept{$p}{parent_id};
				}
			}
		}
		push @errors, "同じ親の中に「$name」が2つあります。" if $name ne '' && $seen{ ($parent // 0) . "\0$name" }++;
		push @errors, "「$name」の並び順が正しくありません。" if ($row->{sort_order} // '') !~ /\A-?\d{1,9}\z/;
	}
	my $used = $class->in_use($dbh);
	for my $row (grep { $_->{deleted} } @$rows) {
		push @errors, $label->($row->{id}) . 'は記事に付いているので消せません（ゴミ箱の中の記事を含む）。' if $used->{ $row->{id} };
		push @errors, $label->($row->{id}) . 'には子のタグがあるので消せません。' if grep { ($_->{parent_id} // 0) == $row->{id} } values %kept;
	}
	return \@errors if @errors;

	$dbh->begin_work;
	eval {
		# 名前を入れ替えたときに一意の索引にぶつからないよう、いったん仮の名前にしてから書き込む
		$dbh->do('UPDATE tags SET name = ? WHERE id = ?', undef, "\0$_", $_) for keys %kept;
		$dbh->do('UPDATE tags SET parent_id = ?, name = ?, sort_order = ? WHERE id = ?', undef,
			@$_{qw(parent_id name sort_order id)}) for values %kept;
		# 親と子を一緒に消すときは、子から消す（parent_id は ON DELETE RESTRICT）
		my %pending = map { $_->{id} => 1 } grep { $_->{deleted} } @$rows;
		while (%pending) {
			my @leaves = grep { my $id = $_; !$dbh->selectrow_array('SELECT 1 FROM tags WHERE parent_id = ?', undef, $id) } sort keys %pending;
			die "タグを消せませんでした\n" if !@leaves;
			for my $id (@leaves) {
				$dbh->do('DELETE FROM tags WHERE id = ?', undef, $id);
				delete $pending{$id};
			}
		}
		$class->rebuild_paths($dbh);
		$dbh->commit;
		1;
	} or do {
		my $error = $@;
		$dbh->rollback;
		die $error;
	};
	return [];
}

# タグの閉包テーブル（tag_paths）を全件作り直す
#   タグを追加・移動・削除したら呼ぶ。トランザクションは呼ぶ側で張る
sub rebuild_paths {
	my ($class, $dbh) = @_;
	$dbh->do('DELETE FROM tag_paths');
	$dbh->do(<<'SQL');
WITH RECURSIVE p (ancestor, descendant, depth) AS (
    SELECT id, id, 0 FROM tags
    UNION ALL
    SELECT p.ancestor, t.id, p.depth + 1
    FROM p JOIN tags t ON t.parent_id = p.descendant
)
INSERT INTO tag_paths (ancestor, descendant, depth)
SELECT ancestor, descendant, depth FROM p
SQL
}

1;
