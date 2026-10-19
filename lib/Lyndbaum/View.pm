package Lyndbaum::View;
# モデルの値を、テンプレートに渡す形に整える
use strict;
use warnings;
use utf8;
use feature 'current_sub';

use File::Spec;
use URI::Escape qw(uri_unescape);
use Lyndbaum::CommentText;
use Lyndbaum::Date qw(format_date);
use Lyndbaum::Model::Article;
use Lyndbaum::Model::Comment;
use Lyndbaum::Model::Tag;
use Lyndbaum::OGP;
use Lyndbaum::Parser::Common;

# 記事のページに出す本文のHTML（続きを読むの印は取り除く）
#   変換済みのHTMLを出すだけで、ここでは変換しない。未変換（NULL）なら空
sub body {
	my ($class, $app, $article) = @_;
	my $html = $article->{body_html} // '';
	$html =~ s/\Q$Lyndbaum::Parser::Common::MORE_MARK\E\n?//g;
	return $html;
}

# 記事の一覧を、タグとURLと一覧の画像と本文を付けた形にする
#   本文（body）は続きを読むの印より前。印が無ければ全文。印があれば has_more が真
sub articles {
	my ($class, $app, $articles) = @_;
	my $tag_ids = Lyndbaum::Model::Article->tag_ids_of($app->db, map { $_->{id} } @$articles);
	return [ map {
		my ($body, $has_more) = Lyndbaum::Parser::Common->excerpt($_->{body_html});
		+{
			%{ $class->article($app, $_, $tag_ids->{ $_->{id} } // []) },
			list_image => $class->list_image($app, $_),
			body       => $body,
			has_more   => $has_more,
		}
	} @$articles ];
}

# 一覧に出すアイキャッチの画像のURL。無ければ undef
#   アイキャッチ（Lyndbaum::OGP->article_image）が添付ファイルのときだけ出す（外部の画像は一覧では読み込まない）
#   サムネイル（同じフォルダの .thumbnail/名前.jpg）があればそれを、無ければ元の画像を使う
sub list_image {
	my ($class, $app, $article) = @_;
	my $url    = Lyndbaum::OGP->article_image($app, $article) // return undef;
	my $prefix = $app->url->attachment('');
	return undef if index($url, $prefix) != 0 || $url =~ /[?#]/;
	# ファイルの名前はバイト列のまま扱う（ディスクの上の名前と比べるため）
	my @segments = map { uri_unescape($_) } split m{/}, substr($url, length $prefix), -1;
	return undef if !@segments || grep { $_ eq '' || $_ eq '.' || $_ eq '..' } @segments;
	my $name  = pop @segments;
	my $thumb = File::Spec->catfile($app->attachment_dir, @segments, '.thumbnail', "$name.jpg");
	return $url if !-f $thumb;
	(my $thumb_url = $url) =~ s{([^/]+)\z}{.thumbnail/$1.jpg};
	return $thumb_url;
}

sub article {
	my ($class, $app, $article, $tag_ids) = @_;
	my $tags = $app->tags;
	my $published = format_date($article->{published_at});
	my $updated   = format_date($article->{updated_at});
	return {
		%$article,
		url       => $class->article_url($app, $article),
		published => $published,
		updated   => $updated,
		# 更新日は、投稿日と日付が違うときだけ出す（投稿した日のうちに直したときは出さない）
		show_updated => $updated && (!$published || $updated->{date} ne $published->{date}),
		is_page   => $article->{kind} eq 'page',
		tags      => [
			map { $class->tag($app, $_) }
			sort { $a->{full_name} cmp $b->{full_name} }
			grep { defined } map { $tags->{$_} } @$tag_ids
		],
	};
}

sub article_url {
	my ($class, $app, $article) = @_;
	return $app->url->article($article->{slug});
}

sub tag {
	my ($class, $app, $tag) = @_;
	return { %$tag, url => $app->url->tag($tag->{path}) };
}

# サイドバーのタグの木（件数つき）
sub tag_tree {
	my ($class, $app) = @_;
	my $add_url = sub {
		my ($nodes) = @_;
		return [ map { +{ %$_, url => $app->url->tag($_->{path}), children => __SUB__->($_->{children}) } } @$nodes ];
	};
	return $add_url->(Lyndbaum::Model::Tag->public_tree($app->db, $app->tags));
}

# サイドバーのコンテンツの木
sub content_tree {
	my ($class, $app) = @_;
	my $add_url = sub {
		my ($nodes) = @_;
		return [ map {
			+{
				%$_,
				url      => $app->url->article($_->{slug}),
				children => __SUB__->($_->{children}),
			}
		} @$nodes ];
	};
	return $add_url->(Lyndbaum::Model::Article->content_tree($app->db));
}

# 記事の公開中のコメント
sub comments {
	my ($class, $app, $article) = @_;
	return [ map {
		+{
			num         => $_->{num},
			by_admin    => $_->{by_admin},
			author_name => $_->{author_name},
			created     => format_date($_->{created_at}),
			html        => Lyndbaum::CommentText->to_html($_->{body}),
		}
	} @{ Lyndbaum::Model::Comment->public_of($app->db, $article->{id}) } ];
}

# サイドバーの「最近のコメント」
my $RECENT_COMMENTS = 5;
sub recent_comments {
	my ($class, $app) = @_;
	return [ map {
		+{
			url         => $app->url->article($_->{slug}) . "#c$_->{num}",
			title       => $_->{title},
			author_name => $_->{author_name},
			created     => format_date($_->{created_at}),
		}
	} @{ Lyndbaum::Model::Comment->recent_public($app->db, $RECENT_COMMENTS) } ];
}

# サイドバーの「最近の記事」（コンテンツページは含めない）
my $RECENT_POSTS = 5;
sub recent_posts {
	my ($class, $app) = @_;
	return [ map {
		+{ url => $class->article_url($app, $_), title => $_->{title} }
	} @{ Lyndbaum::Model::Article->list_public_posts($app->db, limit => $RECENT_POSTS) } ];
}

# サイドバーの「過去ログ」。年ごとに月を並べる（新しい順）。いちばん新しい年は open にする（最初から開く）
sub archive {
	my ($class, $app) = @_;
	my @years;
	for my $row (@{ Lyndbaum::Model::Article->month_counts($app->db) }) {
		my ($year, $month, $count) = @$row;
		if (!@years || $years[-1]{year} != $year) {
			push @years, { year => $year, count => 0, open => !@years, url => $app->url->search(d => $year), months => [] };
		}
		$years[-1]{count} += $count;
		push @{ $years[-1]{months} }, {
			label => sprintf('%04d年%02d月', $year, $month),
			count => $count,
			url   => $app->url->search(d => sprintf('%04d%02d', $year, $month)),
		};
	}
	return \@years;
}

# ページ送り。$url_of はページ番号からURLを作る関数
#   今のページが範囲外なら undef を返す（呼ぶ側で404にする）
sub pager {
	my ($class, %args) = @_;
	my ($page, $per_page, $total, $url_of) = @args{qw(page per_page total url_of)};
	my $last = int(($total + $per_page - 1) / $per_page) || 1;   # 切り上げ（POSIX の ceil は読み込まない）
	return undef if $page < 1 || $page > $last;
	return {
		page     => $page,
		last     => $last,
		total    => $total,
		has_more => $last > 1,
		prev_url => $page > 1     ? $url_of->($page - 1) : undef,
		next_url => $page < $last ? $url_of->($page + 1) : undef,
	};
}

1;
