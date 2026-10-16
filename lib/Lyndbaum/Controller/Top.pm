package Lyndbaum::Controller::Top;
# トップページ（記事の新しい順の一覧）
use strict;
use warnings;
use utf8;

use Lyndbaum::Controller qw(page_number);
use Lyndbaum::Controller::Legacy;
use Lyndbaum::Model::Article;
use Lyndbaum::View;

sub index {
	my ($class, $app, $req) = @_;
	if (my $res = Lyndbaum::Controller::Legacy->redirect_query($app, $req)) {
		return $res;
	}

	my $per_page = $app->settings->{per_page};
	my $pager = Lyndbaum::View->pager(
		page     => page_number($req),
		per_page => $per_page,
		total    => Lyndbaum::Model::Article->count_public_posts($app->db),
		url_of   => sub { $app->url->top(page => $_[0] > 1 ? $_[0] : undef) },
	) or return $app->not_found;

	my $articles = Lyndbaum::Model::Article->list_public_posts(
		$app->db,
		limit  => $per_page,
		offset => ($pager->{page} - 1) * $per_page,
	);
	my $settings = $app->settings;
	return $app->render('top', {
		articles => Lyndbaum::View->articles($app, $articles),
		pager    => $pager,
		head     => $app->page_head($req,
			path        => $app->url->top(page => $pager->{page} > 1 ? $pager->{page} : undef),
			type        => 'website',
			title       => $settings->{blog_title},
			description => $settings->{blog_description},
		),
	}, req => $req);
}

1;
