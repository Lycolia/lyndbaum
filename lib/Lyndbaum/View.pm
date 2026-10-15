package Lyndbaum::View;
# モデルの値を、テンプレートに渡す形に整える
use strict;
use warnings;
use utf8;
use feature 'current_sub';

use POSIX qw(ceil);
use Lyndbaum::CommentText;
use Lyndbaum::Date qw(format_date);
use Lyndbaum::Model::Article;
use Lyndbaum::Model::Comment;
use Lyndbaum::Model::Tag;
use Lyndbaum::Parser::Common;

# 記事のページに出す本文のHTML（続きを読むの印は取り除く）
#   変換済みのHTMLを出すだけで、ここでは変換しない。未変換（NULL）なら空
sub body {
	my ($class, $app, $article) = @_;
	my $html = $article->{body_html} // '';
	$html =~ s/\Q$Lyndbaum::Parser::Common::MORE_MARK\E\n?//g;
	return $html;
}

# 記事の一覧を、タグとURLを付けた形にする
sub articles {
	my ($class, $app, $articles) = @_;
	my $tag_ids = Lyndbaum::Model::Article->tag_ids_of($app->db, map { $_->{id} } @$articles);
	return [ map { $class->article($app, $_, $tag_ids->{ $_->{id} } // []) } @$articles ];
}

sub article {
	my ($class, $app, $article, $tag_ids) = @_;
	my $tags = $app->tags;
	return {
		%$article,
		url       => $class->article_url($app, $article),
		published => format_date($article->{published_at}),
		updated   => format_date($article->{updated_at}),
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

# ページ送り。$url_of はページ番号からURLを作る関数
#   今のページが範囲外なら undef を返す（呼ぶ側で404にする）
sub pager {
	my ($class, %args) = @_;
	my ($page, $per_page, $total, $url_of) = @args{qw(page per_page total url_of)};
	my $last = ceil($total / $per_page) || 1;
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
