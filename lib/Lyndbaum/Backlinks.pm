package Lyndbaum::Backlinks;
# 参照元（この記事へリンクしている記事の一覧）。記事のページの、本文とコメントの間に出す
#
# - リンクは、本文を変換するときに article_links に入れ直す（Lyndbaum::Model::Article->rebuild_body）
#   数えるのは [文字](slug) の形だけ（Lyndbaum::Parser::Markdown の _add_link）
# - HTMLは templates/backlinks.html で作り、articles.backlinks_html に保存しておく。表示のときは読むだけ
# - 作り直しが要る記事は、トリガーが backlinks_html を NULL にする（db/migrations/0001_init.sql）
#   POST の処理の終わり（Lyndbaum::App->handle）と、再構築・取り込みのときに、NULL の記事の分を作る
# - テンプレートを変えたときは、再構築（tools/rebuild-html.pl か管理画面）で全記事の分を作り直す
use strict;
use warnings;
use utf8;

use File::Spec;
use Lyndbaum::Template;

# 参照元に出す記事。公開中でゴミ箱に無いもの。自分自身へのリンクは除く。新しい順
my $SOURCES_SQL = <<'SQL';
SELECT a.id, a.slug, a.title
FROM article_links l JOIN articles a ON a.id = l.source_id
WHERE l.target_slug = ? AND a.id <> ?
  AND a.kind IN ('post', 'page') AND a.status = 'published' AND a.deleted_at IS NULL
ORDER BY a.published_at DESC, a.id DESC
SQL

# 作り直しが要る記事（backlinks_html が NULL のもの）の参照元のHTMLを作って保存する。作った数を返す
#   %opt
#     all  真なら、全記事の分を作り直す（テンプレートを変えたときのため。再構築と取り込みで使う）
#     ids  この記事だけを見る（表示のときに、まだ無ければ作るため）
sub rebuild {
	my ($class, $app, %opt) = @_;
	my $dbh = $app->db;
	die "参照元の作り直しはトランザクション終了後に行ってください\n" if !$dbh->{AutoCommit};
	local $dbh->{sqlite_use_immediate_transaction} = 1;
	$dbh->begin_work;
	my $count = 0;
	eval {
		$dbh->do('UPDATE articles SET backlinks_html = NULL') if $opt{all};
		my $sql = q{SELECT id, slug FROM articles WHERE backlinks_html IS NULL AND kind IN ('post', 'page')};
		my @bind;
		if ($opt{ids}) {
			$sql .= sprintf ' AND id IN (%s)', join ', ', ('?') x @{ $opt{ids} };
			@bind = @{ $opt{ids} };
		}
		my $targets = $dbh->selectall_arrayref($sql, { Slice => {} }, @bind);
		my $template = @$targets ? _template($app) : undef;
		for my $target (@$targets) {
			$dbh->do('UPDATE articles SET backlinks_html = ? WHERE id = ?', undef,
				_render($app, $template, $target), $target->{id});
			$count++;
		}
		$dbh->commit;
		1;
	} or do {
		my $error = $@;
		$dbh->rollback;
		die $error;
	};
	return $count;
}

# 記事のページに出す参照元のHTML。保存したものを読むだけ
#   まだ作っていなければ（直接SQLで書き換えた場合など）ここで作る。保存できなければ、保存せずに作って出す
sub html {
	my ($class, $app, $article) = @_;
	my $sql = 'SELECT backlinks_html FROM articles WHERE id = ?';
	my $html = $app->db->selectrow_array($sql, undef, $article->{id});
	return $html if defined $html;
	eval { $class->rebuild($app, ids => [ $article->{id} ]); 1 }
		or warn "参照元のHTMLを保存できませんでした（保存せずに生成します）: $@";
	$html = $app->db->selectrow_array($sql, undef, $article->{id});
	return $html // _render($app, _template($app), $article);
}

# テンプレートを変えた後の再構築でも、解析済みの古い構文木を使わないよう、毎回読み直す
sub _template {
	my ($app) = @_;
	return Lyndbaum::Template->new(dir => File::Spec->catdir($app->{root}, 'templates'));
}

# 参照元が無ければ空文字（テンプレートの出力が空白だけのときも空にする）
sub _render {
	my ($app, $template, $target) = @_;
	my $sources = $app->db->selectall_arrayref($SOURCES_SQL, { Slice => {} }, $target->{slug}, $target->{id});
	return '' if !@$sources;
	my $html = $template->render('backlinks', {
		backlinks => [ map { +{ title => $_->{title}, url => $app->url->article($_->{slug}) } } @$sources ],
	});
	return $html =~ /\S/ ? $html : '';
}

1;
