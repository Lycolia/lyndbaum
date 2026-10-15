package Lyndbaum::Controller::AdminTag;
# 管理画面のタグの管理（docs/admin.md の「タグの管理」）
#   /admin/tags        タグの木。名前の変更、親の付け替え、並び替え、削除を画面の上で行う
#   POST /admin/tags   組み替えた木の全体（tree、JSON）を受け取り、確かめてからまとめて確定する
#
# 画面の操作だけでは確定しない（操作のたびに閉包テーブルを作り直さないため）。木の組み替えは pub/assets/js/admin-tags.js
use strict;
use warnings;
use utf8;

use JSON::PP ();
use Lyndbaum::Controller::Admin;
use Lyndbaum::Controller::AdminArticle;
use Lyndbaum::Model::Tag;

sub index {
	my ($class, $app, $req) = @_;
	my ($session, $res) = Lyndbaum::Controller::Admin->authorize($app, $req);
	return $res if !$session;
	return $class->_render($app, $session,
		saved       => ($req->param('saved') // '') eq '1',
		feed_failed => ($req->param('feed') // '') eq 'failed');
}

sub save {
	my ($class, $app, $req) = @_;
	my ($session, $res) = Lyndbaum::Controller::Admin->authorize($app, $req, post => 1);
	return $res if !$session;
	my $dbh = $app->db;

	if (($req->body_param('digest') // '') ne Lyndbaum::Model::Tag->digest($dbh)) {
		return $class->_render($app, $session, status => 409,
			errors => ['タグは、ほかの画面（記事の保存で新しいタグを作ったときを含む）で先に変わっています。保存していません。今のタグの一覧から、もう一度操作してください。']);
	}
	my $tree = eval { JSON::PP->new->decode($req->body_param('tree') // '') };
	if (ref $tree ne 'ARRAY' || grep { ref $_ ne 'HASH' } @$tree) {
		return $class->_render($app, $session, status => 400, errors => ['送られたタグの一覧が正しくありません。']);
	}
	my @rows = map {
		+{
			id         => $_->{id},
			name       => $_->{name},
			parent_id  => (defined $_->{parent_id} && $_->{parent_id} ne '' ? $_->{parent_id} : undef),
			sort_order => $_->{sort_order},
			deleted    => $_->{deleted} ? 1 : 0,
		}
	} @$tree;
	my $errors = Lyndbaum::Model::Tag->save_tree($dbh, \@rows);
	# 確かめられなかったときは、送られた木（組み替えた後のもの）のまま画面を出し直す
	return $class->_render($app, $session, status => 400, errors => $errors, tree => $tree) if @$errors;

	# タグの名前はRSSの category に出るので、書き出し直す
	my $feed_ok = Lyndbaum::Controller::AdminArticle->write_static_files($app);
	return $app->redirect($app->url->admin('tags', saved => 1, feed => $feed_ok ? undef : 'failed'), 303);
}

# %opt：errors、saved、feed_failed、status、tree（出し直すときの、送られた木）
sub _render {
	my ($class, $app, $session, %opt) = @_;
	my $dbh    = $app->db;
	my $counts = Lyndbaum::Model::Tag->usage_counts($dbh);
	my $in_use = Lyndbaum::Model::Tag->in_use($dbh);
	my %sent   = map { ($_->{id} // '') => $_ } @{ $opt{tree} // [] };
	my $tags   = [ map {
		my $tag  = $_;
		my $sent = $sent{ $tag->{id} } // {};
		+{
			id         => $tag->{id} + 0,
			name       => $sent->{name} // $tag->{name},
			parent_id  => exists $sent->{parent_id} ? $sent->{parent_id} : $tag->{parent_id},
			sort_order => ($sent->{sort_order} // $tag->{sort_order}) + 0,
			deleted    => $sent->{deleted} ? JSON::PP::true : JSON::PP::false,
			count      => $counts->{ $tag->{id} } // 0,
			in_use     => $in_use->{ $tag->{id} } ? JSON::PP::true : JSON::PP::false,
		}
	} sort { $a->{id} <=> $b->{id} } values %{ Lyndbaum::Model::Tag->all($dbh) } ];
	return $app->render_admin('admin_tags', {
		title       => 'タグ',
		saved       => $opt{saved},
		feed_failed => $opt{feed_failed},
		errors      => $opt{errors} // [],
		digest      => Lyndbaum::Model::Tag->digest($dbh),
		# 木の組み替えに使う（pub/assets/js/admin-tags.js が読む）。テンプレートが属性の値としてエスケープする
		tags_json   => JSON::PP->new->canonical->encode($tags),
		script      => $app->url->static('js/admin-tags.js'),
		count       => scalar @$tags,
	}, session => $session, status => $opt{status});
}

1;
