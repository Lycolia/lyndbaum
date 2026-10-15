package Lyndbaum::Controller::Article;
# 記事とコンテンツページの表示
#   URLのパスは、記事の slug と同じ（旧システムと同じ形）
#     記事         /0575（slug は「0 + 記事ID」）
#     コンテンツ   /管理人について/保有デバイス（slug は 0 で始まらない）
#   コメントの投稿は、同じURLへのPOST（Lyndbaum::Controller::Comment）
use strict;
use warnings;
use utf8;

use Lyndbaum::CommentToken;
use Lyndbaum::Model::Article;
use Lyndbaum::Model::Comment;
use Lyndbaum::OGP;
use Lyndbaum::View;

sub show {
	my ($class, $app, $req, $slug) = @_;
	my $article = Lyndbaum::Model::Article->find_public_by_slug($app->db, $slug)
		// $class->_draft_for_admin($app, $req, $slug)
		or return $app->not_found;
	my %form;
	$form{notice} = 'コメントは承認待ちです。管理者が承認すると表示されます。' if ($req->param('comment') // '') eq 'held';
	return $class->render_article($app, $req, $article, %form);
}

# 下書き。管理者にだけ見せる（プレビューの代わりに、下書きとして保存して公開側で確かめるため）
sub _draft_for_admin {
	my ($class, $app, $req, $slug) = @_;
	return undef if !$app->admin_session($req);
	my $article = Lyndbaum::Model::Article->find_by_slug_for_admin($app->db, $slug) // return undef;
	return $article->{status} eq 'draft' ? { %$article, is_draft => 1 } : undef;
}

# 記事のページを出す
#   %form はコメントのフォームに戻す値
#     name, body  書いた内容
#     errors      理由の一覧
#     notice      投稿した後の知らせ
#     status      応答のステータス
sub render_article {
	my ($class, $app, $req, $article, %form) = @_;
	my $tag_ids = Lyndbaum::Model::Article->tag_ids_of($app->db, $article->{id});
	my $view = Lyndbaum::View->article($app, $article, $tag_ids->{ $article->{id} } // []);
	$view->{body} = Lyndbaum::View->body($app, $article);
	$view->{comments} = Lyndbaum::View->comments($app, $article);
	$view->{comments_count} = scalar @{ $view->{comments} };
	my $head = $app->page_head($req,
		path        => $app->url->article($article->{slug}),
		type        => 'article',
		title       => $article->{title},
		description => $article->{description},
		image       => Lyndbaum::OGP->article_image($app, $article),
	);
	if ($article->{is_draft}) {
		# 下書きは検索エンジンやキャッシュに残さない。コメントは受け付けないのでフォームも出さない
		$view->{is_draft} = 1;
		$view->{edit_url} = $app->url->admin("articles/$article->{id}");
		return $app->render('article', { title => $article->{title}, article => $view, noindex => 1, head => $head })
			->add_header('Cache-Control', 'no-store');
	}
	$view->{comment_form} = $class->_comment_form($app, $req, $article, %form);
	return $app->render('article', { title => $article->{title}, article => $view, head => $head }, status => $form{status});
}

# コメントのフォーム。受け付けないなら、知らせだけ（無ければ undef）
sub _comment_form {
	my ($class, $app, $req, $article, %form) = @_;
	my $settings = $app->settings;
	my $secret   = $app->config->get('secret_key');
	if (!$settings->{comments_enabled} || !$article->{comments_open} || !defined $secret || $secret eq '') {
		warn "config.json に secret_key が無いので、コメントのフォームを出しません\n"
			if $settings->{comments_enabled} && $article->{comments_open} && (!defined $secret || $secret eq '');
		return $form{notice} ? { open => 0, notice => $form{notice} } : undef;
	}
	my $admin = $app->admin_session($req) ? 1 : 0;
	return {
		open     => 1,
		action   => $app->url->article($article->{slug}),
		token    => Lyndbaum::CommentToken->issue($secret, $article->{id}),
		js_token => $settings->{comments_js_token} ? 1 : 0,
		admin    => $admin,
		name     => $form{name} // ($admin ? Lyndbaum::Model::Comment->last_admin_name($app->db) // '' : ''),
		body     => $form{body} // '',
		errors   => $form{errors} // [],
		notice   => $form{notice},
		script   => $app->url->static('js/comment.js'),
	};
}

1;
