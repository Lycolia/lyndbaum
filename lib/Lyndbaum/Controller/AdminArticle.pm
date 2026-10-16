package Lyndbaum::Controller::AdminArticle;
# 管理画面の記事の管理（docs/admin.md の「記事の管理」）
#   /admin/articles?status=draft|published&q=語&page=N   記事の一覧（kind=page ならコンテンツページの一覧）
#   /admin/articles/new?kind=page                         新しい記事のフォーム（kind=page ならコンテンツページ）
#   POST /admin/articles                                  新しい記事を保存
#   /admin/articles/ID                                    編集のフォーム
#   POST /admin/articles/ID                               保存
#   /admin/articles/ID/revisions/REV                      履歴の1件（JSON）
#   POST /admin/articles/ID/trash                         ゴミ箱へ移す（編集のフォームから）
#   POST /admin/articles/trash                            選んだ記事をゴミ箱へ移す（一覧から。id を複数）
#   /admin/trash                                          ゴミ箱
#   POST /admin/trash                                     ゴミ箱の操作（mode=restore|purge|purge_all、id を複数）
#   POST /admin/rebuild                                   全記事の本文を変換し直す（再構築）
#
# プレビューは作らない。下書きとして保存すれば記事のIDが決まり、管理者は公開側のURLで下書きを見られる
use strict;
use warnings;
use utf8;

use JSON::PP ();
use Lyndbaum::ArticleForm;
use Lyndbaum::Controller qw(page_number);
use Lyndbaum::Controller::Admin;
use Lyndbaum::Date qw(format_date);
use Lyndbaum::StaticFiles;
use Lyndbaum::Model::Article;
use Lyndbaum::Model::Tag;
use Lyndbaum::OGP;
use Lyndbaum::Response;
use Lyndbaum::SidebarCache;
use Lyndbaum::UrlTitle;
use Lyndbaum::View;

my $PER_PAGE = 20;
my %STATUS_LABEL = (draft => '下書き', published => '公開中');

sub index {
	my ($class, $app, $req) = @_;
	my ($session, $res) = Lyndbaum::Controller::Admin->authorize($app, $req);
	return $res if !$session;
	my $dbh = $app->db;

	# 記事とコンテンツページは別々の一覧にする（WordPress の投稿と固定ページと同じ）
	my $kind = _kind($req->param('kind'));
	my $status = $req->param('status') // '';
	$status = undef if !$STATUS_LABEL{$status};
	my $q = $req->param('q') // '';
	$q =~ s/\A\s+|\s+\z//g;
	my %cond = (kind => $kind, status => $status, q => $q);
	my $list_url = sub { $app->url->admin('articles', kind => $kind eq 'page' ? 'page' : undef, @_) };

	my $pager = Lyndbaum::View->pager(
		page     => page_number($req),
		per_page => $PER_PAGE,
		total    => Lyndbaum::Model::Article->count_admin($dbh, %cond),
		url_of   => sub { $list_url->(status => $status, q => $q, page => $_[0] > 1 ? $_[0] : undef) },
	) or return $app->not_found;

	my $counts = Lyndbaum::Model::Article->count_by_status($dbh, $kind);
	my ($trashed) = ($req->param('trashed') // '') =~ /\A(\d+)\z/;   # ゴミ箱へ移した数（_move_to_trash）
	my $articles = Lyndbaum::Model::Article->list_admin($dbh, %cond, limit => $PER_PAGE, offset => ($pager->{page} - 1) * $PER_PAGE);
	return $app->render_admin('admin_articles', {
		title    => $kind eq 'page' ? 'ページ' : '記事',
		is_page  => $kind eq 'page',
		kind     => $kind,
		list_url => $list_url->(),
		q        => $q,
		status   => $status // '',
		filters  => [ map {
			my ($value, $label, $count) = @$_;
			+{ label => $label, count => $count, url => $list_url->(status => $value, q => $q),
			   current => ($status // '') eq ($value // '') }
		} [ undef, 'すべて', $counts->{draft} + $counts->{published} ], [ draft => '下書き', $counts->{draft} ],
		  [ published => '公開中', $counts->{published} ] ],
		articles => [ map {
			+{
				%$_,
				status_label => $STATUS_LABEL{ $_->{status} },
				published    => format_date($_->{published_at}),
				updated      => format_date($_->{updated_at}),
				edit_url     => $app->url->admin("articles/$_->{id}"),
				comments_url => $app->url->admin('comments', article => $_->{id}),
				url          => $app->url->article($_->{slug}),
			}
		} @$articles ],
		pager    => $pager,
		trash_count => Lyndbaum::Model::Article->count_trash($dbh),
		trashed     => $trashed,
		feed_failed => ($req->param('feed') // '') eq 'failed',
	}, session => $session, nav => $kind eq 'page' ? 'pages' : 'articles');
}

# 一覧の種類。page でなければ post
sub _kind {
	my ($value) = @_;
	return ($value // '') eq 'page' ? 'page' : 'post';
}

sub new_form {
	my ($class, $app, $req) = @_;
	my ($session, $res) = Lyndbaum::Controller::Admin->authorize($app, $req);
	return $res if !$session;
	my $kind = ($req->param('kind') // '') eq 'page' ? 'page' : 'post';
	return $class->_render_form($app, $session, { comments_open => 1, status => 'draft', kind => $kind });
}

sub edit_form {
	my ($class, $app, $req, $id) = @_;
	my ($session, $res) = Lyndbaum::Controller::Admin->authorize($app, $req);
	return $res if !$session;
	my $article = Lyndbaum::Model::Article->find_for_admin($app->db, $id) or return $app->not_found;
	return $class->_render_form($app, $session, $class->_values_of($app, $article),
		saved       => ($req->param('saved') // '') eq '1',
		feed_failed => ($req->param('feed') // '') eq 'failed');
}

sub create {
	my ($class, $app, $req) = @_;
	return $class->_save($app, $req, undef);
}

sub update {
	my ($class, $app, $req, $id) = @_;
	return $class->_save($app, $req, $id);
}

sub _save {
	my ($class, $app, $req, $id) = @_;
	my ($session, $res) = Lyndbaum::Controller::Admin->authorize($app, $req, post => 1);
	return $res if !$session;
	my $dbh = $app->db;
	my $old;
	if (defined $id) {
		$old = Lyndbaum::Model::Article->find_for_admin($dbh, $id) or return $app->not_found;
	}

	my $tags = $app->tags;
	my ($v, $errors) = Lyndbaum::ArticleForm->parse(
		values     => sub { $req->body_params($_[0]) },
		tag_exists => sub { Lyndbaum::Model::Tag->find_by_path($tags, @_) },
		page       => $old ? $old->{kind} eq 'page' : ($req->body_param('kind') // '') eq 'page',
	);
	return $class->_render_form($app, $session, { %$v, id => $id }, errors => $errors, status => 400) if @$errors;

	# [&URL] のページのタイトルは、変換する前に取得しておく（変換の途中では外へ取りに行かないため）
	Lyndbaum::UrlTitle->fetch_missing($dbh, $v->{body_src}, context => { $app->parser_context }, agent => $class->_agent($app));
	my $settings = $app->settings;
	my $result = Lyndbaum::Model::Article->save($dbh, $v, id => $id, context => { $app->parser_context },
		revision_interval => $settings->{revision_interval}, revision_max => $settings->{revision_max});
	if (my $page_errors = $result->{errors}) {
		return $class->_render_form($app, $session, { %$v, id => $id },
			errors => [ map { +{ key => 'page_name', message => $_ } } @$page_errors ], status => 400);
	}
	if (my $now = $result->{conflict}) {
		# 書いた内容は消さずにフォームに戻す。要約は今の記事のものにするので、もう一度保存すれば上書きになる
		return $class->_render_form($app, $session, { %$v, id => $id, digest => Lyndbaum::Model::Article->digest($dbh, $id) },
			conflict => 1, status => 409);
	}

	my $feed_ok = $class->write_static_files($app);
	return $app->redirect($app->url->admin("articles/$result->{id}", saved => 1, feed => $feed_ok ? undef : 'failed'), 303);
}

# 履歴の1件（JSON）。編集の画面で、今の本文との差分と全文を見るため（pub/assets/js/admin-article.js）
sub revision {
	my ($class, $app, $req, $id, $revision_id) = @_;
	my ($session, $res) = Lyndbaum::Controller::Admin->authorize($app, $req);
	return $res if !$session;
	my $rev = Lyndbaum::Model::Article->revision($app->db, $id, $revision_id) or return $app->not_found;
	return Lyndbaum::App::admin_headers(Lyndbaum::Response->json({
		id    => $rev->{id} + 0,
		title => $rev->{title},
		body  => $rev->{body_src},
		saved => format_date($rev->{saved_at})->{datetime},
	}));
}

# ゴミ箱へ移す（編集のフォームから）。移したら一覧へ
sub trash {
	my ($class, $app, $req, $id) = @_;
	my ($session, $res) = Lyndbaum::Controller::Admin->authorize($app, $req, post => 1);
	return $res if !$session;
	my $article = Lyndbaum::Model::Article->find_for_admin($app->db, $id) or return $app->not_found;
	return $class->_move_to_trash($app, $session, [$id], $article->{kind});
}

# 選んだ記事をゴミ箱へ移す（一覧から）
sub trash_selected {
	my ($class, $app, $req) = @_;
	my ($session, $res) = Lyndbaum::Controller::Admin->authorize($app, $req, post => 1);
	return $res if !$session;
	return $class->_move_to_trash($app, $session, [ _ids($req) ], _kind($req->body_param('kind')));
}

# 移したら、その種類（$kind）の一覧へ
sub _move_to_trash {
	my ($class, $app, $session, $ids, $kind) = @_;
	my ($count, $errors) = Lyndbaum::Model::Article->move_to_trash($app->db, $ids);
	my $feed_ok = $class->write_static_files($app);
	return $class->_errors($app, $session, 'ゴミ箱へ移せなかった記事があります', $count, '件の記事をゴミ箱へ移しました。', $errors)
		if @$errors;
	return $app->redirect($app->url->admin('articles', kind => $kind eq 'page' ? 'page' : undef, trashed => $count,
		feed => $feed_ok ? undef : 'failed'), 303);
}

sub trash_index {
	my ($class, $app, $req) = @_;
	my ($session, $res) = Lyndbaum::Controller::Admin->authorize($app, $req);
	return $res if !$session;
	my $dbh = $app->db;
	my $articles = Lyndbaum::Model::Article->list_trash($dbh);
	my $tag_ids  = Lyndbaum::Model::Article->tag_ids_of($dbh, map { $_->{id} } @$articles);
	my $tags     = $app->tags;
	my ($done)   = ($req->param('done') // '') =~ /\A(restore|purge|purge_all)\z/;
	my ($count)  = ($req->param('count') // '') =~ /\A(\d+)\z/;
	return $app->render_admin('admin_trash', {
		title    => 'ゴミ箱',
		notice   => defined $done && defined $count ? {
			restore   => "${count}件の記事を戻しました。",
			purge     => "${count}件の記事を完全に削除しました。",
			purge_all => "ゴミ箱を空にしました（${count}件）。",
		}->{$done} : undef,
		feed_failed => ($req->param('feed') // '') eq 'failed',
		articles => [ map {
			my $article = $_;
			+{
				%$article,
				is_page   => $article->{kind} eq 'page',
				deleted   => format_date($article->{deleted_at}),
				published => format_date($article->{published_at}),
				tags      => join(', ', sort map { $tags->{$_}{full_name} } grep { $tags->{$_} } @{ $tag_ids->{ $article->{id} } // [] }),
			}
		} @$articles ],
	}, session => $session);
}

# ゴミ箱の操作。mode：restore（戻す）、purge（完全に削除）、purge_all（ゴミ箱を空にする）
sub trash_update {
	my ($class, $app, $req) = @_;
	my ($session, $res) = Lyndbaum::Controller::Admin->authorize($app, $req, post => 1);
	return $res if !$session;
	my $dbh  = $app->db;
	my $mode = $req->body_param('mode') // '';
	my ($count, $errors) = (0, []);
	if ($mode eq 'restore') {
		$count = Lyndbaum::Model::Article->restore($dbh, [ _ids($req) ]);
	} elsif ($mode eq 'purge') {
		($count, $errors) = Lyndbaum::Model::Article->purge($dbh, [ _ids($req) ]);
	} elsif ($mode eq 'purge_all') {
		($count, $errors) = Lyndbaum::Model::Article->purge($dbh, undef);
	} else {
		return $app->render_admin('admin_error', { title => '操作できません', error => '操作が正しくありません。' }, session => $session, status => 400);
	}
	my $feed_ok = $class->write_static_files($app);
	return $class->_errors($app, $session, '完全に削除できなかった記事があります', $count, '件の記事を完全に削除しました。', $errors)
		if @$errors;
	return $app->redirect($app->url->admin('trash', done => $mode, count => $count, feed => $feed_ok ? undef : 'failed'), 303);
}

# 一部の記事を操作できなかったとき
sub _errors {
	my ($class, $app, $session, $title, $count, $done, $errors) = @_;
	return $app->render_admin('admin_result', {
		title  => $title,
		done   => $count ? "$count$done" : undef,
		errors => $errors,
	}, session => $session, status => 409);
}

# フォームで選んだ記事のID（id を複数）
sub _ids {
	my ($req) = @_;
	my %seen;
	return grep { /\A[1-9]\d{0,9}\z/ && !$seen{$_}++ } $req->body_params('id');
}

sub rebuild {
	my ($class, $app, $req) = @_;
	my ($session, $res) = Lyndbaum::Controller::Admin->authorize($app, $req, post => 1);
	return $res if !$session;
	my $count = Lyndbaum::Model::Article->rebuild_all($app->db, $app->parser_context);
	Lyndbaum::SidebarCache->rebuild($app);
	my $feed_ok = $class->write_static_files($app);
	return $app->redirect($app->url->admin(undef, rebuilt => $count, feed => $feed_ok ? undef : 'failed'), 303);
}

# アイキャッチの欄に出すもの。auto_url は保存した本文の最初の画像、blog_url はブログの画像
sub _eyecatch {
	my ($class, $app, $article, $v) = @_;
	my $mode = $v->{eyecatch_mode} // 'auto';
	my $blog = $app->settings->{blog_image} // '';
	my %urls = (
		auto_url => $article ? Lyndbaum::OGP->first_image($article->{body_html}) // '' : '',
		blog_url => $blog ne '' ? $app->url->attachment($blog) : '',
	);
	my $preview = $mode eq 'chosen' && ($v->{eyecatch} // '') ne '' ? $app->url->attachment($v->{eyecatch})
		: $mode eq 'auto' && $urls{auto_url} ne '' ? $urls{auto_url} : $urls{blog_url};
	return { %urls, $mode => 1, preview => $preview, attachment_base => $app->url->attachment('') };
}

# 外部のページを取りに行くときの User-Agent
sub _agent {
	my ($class, $app) = @_;
	my $site = $app->config->get('site_url');
	return 'Lyndbaum' . (defined $site && $site ne '' ? " (+$site)" : '');
}

# RSS とサイトマップを書き出す（Lyndbaum::StaticFiles）。書き出せなくても記事の保存は取り消さず、
# 理由はエラーログに残して、画面では知らせるだけにする。すべて書き出せたら真
sub write_static_files {
	my ($class, $app) = @_;
	my $errors = Lyndbaum::StaticFiles->write_all($app);
	warn "RSSかサイトマップを書き出せませんでした: $_\n" for @$errors;
	return !@$errors;
}

# DBの記事を、フォームの値の形にする
sub _values_of {
	my ($class, $app, $article) = @_;
	my $tags = $app->tags;
	my $tag_ids = Lyndbaum::Model::Article->tag_ids_of($app->db, $article->{id})->{ $article->{id} } // [];
	return {
		%$article,
		($article->{kind} eq 'page' ? (
			page_name => Lyndbaum::Model::Article->page_name($article),
			sort_text => $article->{sort_order},
		) : ()),
		tag_chips      => [ map { +{ name => $_, new => 0 } } sort map { $tags->{$_}{full_name} } grep { $tags->{$_} } @$tag_ids ],
		published_text => defined $article->{published_at} ? format_date($article->{published_at})->{input} : '',
		digest         => Lyndbaum::Model::Article->digest($app->db, $article->{id}),
	};
}

# フォームを出す。$v はフォームの値（id があれば編集）
#   %opt：errors、saved、feed_failed、conflict、status
sub _render_form {
	my ($class, $app, $session, $v, %opt) = @_;
	my $id = $v->{id};
	my $dbh = $app->db;
	my $article = defined $id ? Lyndbaum::Model::Article->find_for_admin($dbh, $id) : undef;
	my $is_page = $article ? $article->{kind} eq 'page' : ($v->{kind} // '') eq 'page';
	my $revisions = $article ? Lyndbaum::Model::Article->revisions($dbh, $id) : [];
	my %error_of;
	$error_of{ $_->{key} } = 1 for @{ $opt{errors} // [] };
	my $tags   = $app->tags;
	my $counts = Lyndbaum::Model::Tag->usage_counts($app->db);
	my $tree   = Lyndbaum::Model::Tag->in_tree_order($tags);
	return $app->render_admin('admin_article_form', {
		title       => defined $id ? ($is_page ? 'ページの編集' : '記事の編集') : ($is_page ? '新しいページ' : '新しい記事'),
		action      => defined $id ? $app->url->admin("articles/$id") : $app->url->admin('articles'),
		trash_action => defined $id ? $app->url->admin("articles/$id/trash") : undef,
		is_page     => $is_page,
		# 親に選べるページ（自分と子孫は除く）。木の形が分かるよう、深さの分だけ字下げする
		parents     => $is_page ? [ map {
			+{ id => $_->{id}, label => ('　' x $_->{depth}) . $_->{title}, selected => ($v->{parent_id} // 0) == $_->{id} }
		} @{ Lyndbaum::Model::Article->parent_options($dbh, $id) } ] : [],
		article     => $article ? {
			id        => $id,
			url       => $app->url->article($article->{slug}),
			published => $article->{status} eq 'published',
			is_page   => $article->{kind} eq 'page',
			updated   => format_date($article->{updated_at}),
		} : undef,
		form        => {
			title          => $v->{title} // '',
			body           => $v->{body_src} // '',
			tag_chips      => $v->{tag_chips} // [],
			published_at   => $v->{published_text} // '',
			comments_open  => $v->{comments_open},
			keep_updated   => $v->{keep_updated},
			digest         => $v->{digest} // '',
			eyecatch       => $v->{eyecatch} // '',
			page_name      => $v->{page_name} // '',
			sort_order     => $v->{sort_text} // '',
		},
		revision_count => scalar @$revisions,
		revisions   => [ map {
			+{ %$_, saved => format_date($_->{saved_at}), created => format_date($_->{created_at}),
			   url => $app->url->admin("articles/$id/revisions/$_->{id}") }
		} @$revisions ],
		eyecatch         => $class->_eyecatch($app, $article, $v),
		error_of    => \%error_of,
		errors      => $opt{errors} // [],
		saved       => $opt{saved},
		feed_failed => $opt{feed_failed},
		conflict    => $opt{conflict},
		# タグの入力の候補（pub/assets/js/admin-article.js が読む）。テンプレートが属性の値としてエスケープする
		tag_data    => JSON::PP->new->canonical->encode([
			map { +{ name => $_->{full_name}, count => $counts->{ $_->{id} } // 0 } } @$tree
		]),
		# 「一覧から選ぶ」。木の形が分かるよう、深さの分だけ字下げする
		tag_options => [ map { +{ name => $_->{full_name}, label => ('　' x $_->{depth}) . $_->{name} } } @$tree ],
		script      => $app->url->static('js/admin-article.js'),
		thumbnail_size => $app->settings->{thumbnail_size},
	}, session => $session, status => $opt{status},
		# 左のナビ：新しく書くときは「新しい記事」か「新しいページ」、既存の記事やページの編集はそれぞれの一覧
		nav => defined $id ? ($is_page ? 'pages' : 'articles') : $is_page ? 'new_page' : 'new_article');
}

1;
