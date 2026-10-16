package Lyndbaum::SidebarCache;
# 更新時に生成したサイドバーのHTML。検索フォームと管理者情報は含めない
use strict;
use warnings;
use utf8;

use File::Spec;
use Cwd qw(abs_path);
use Time::HiRes ();
use Lyndbaum::Template;
use Lyndbaum::View;
use Lyndbaum::SidebarBoxes;

# 描画方法や許可リストを変えたときも、ファイルの更新情報で作り直す
my @SOURCES = (
	qw(templates/sidebar_tags.html templates/sidebar_menu.html
	   templates/tag_tree_item.html templates/content_tree_item.html),
	map { "lib/Lyndbaum/$_.pm" } qw(SidebarCache View SidebarBoxes HTML URL Date Model/Article Model/Tag Model/Comment),
);

sub _key {
	my ($app) = @_;
	return join "\0", 'sidebar-v1', abs_path($app->{root}),
		$app->config->get('base_path') // '',
		map {
			my $file = File::Spec->catfile($app->{root}, $_);
			my @st = Time::HiRes::stat($file);
			die "サイドバーのファイルを確認できません: $file: $!\n" if !@st;
			join ':', $_, @st[7, 9, 10];
		} @SOURCES;
}

sub _read {
	my ($dbh, $key) = @_;
	return $dbh->selectrow_hashref(
		'SELECT tags_html AS sidebar_tags, menu_html AS sidebar_menu FROM sidebar_cache WHERE id = 1 AND cache_key = ?',
		undef, $key);
}

# 通常は読み出すだけ。初回、テンプレート変更時、外部ツールで更新された場合もここで補う
sub get {
	my ($class, $app) = @_;
	my $key = _key($app);
	return _read($app->db, $key) // $class->rebuild($app, key => $key);
}

# 元データの読み出しから保存まで排他する。他の更新より古い結果で上書きしない
sub rebuild {
	my ($class, $app, %opt) = @_;
	my $dbh = $app->db;
	my $key = $opt{key} // _key($app);
	die "サイドバーの再生成はトランザクション終了後に行ってください\n" if !$dbh->{AutoCommit};
	local $dbh->{sqlite_use_immediate_transaction} = 1;
	$dbh->begin_work;
	my $html;
	eval {
		# get の確認後に、ほかのリクエストがすでに生成していたらそれを使う
		$html = _read($dbh, $key) if $opt{key};
		if (!$html) {
			# 同じリクエスト内の編集前の設定・タグを使わない
			delete @$app{qw(settings tags)};
			# テンプレート変更後の手動再生成でも、解析済みの古い構文木を使わない
			my $template = Lyndbaum::Template->new(dir => File::Spec->catdir($app->{root}, 'templates'));
			$html = {
				sidebar_tags => $template->render('sidebar_tags', {
					tag_tree => Lyndbaum::View->tag_tree($app),
				}),
				sidebar_menu => $template->render('sidebar_menu', {
					content_tree    => Lyndbaum::View->content_tree($app),
					recent_comments => Lyndbaum::View->recent_comments($app),
					recent_posts    => Lyndbaum::View->recent_posts($app),
					archive         => Lyndbaum::View->archive($app),
					sidebar_boxes   => Lyndbaum::SidebarBoxes->for_display($app->settings->{sidebar_boxes}),
				}),
			};
			$dbh->do('INSERT OR REPLACE INTO sidebar_cache (id, cache_key, tags_html, menu_html) VALUES (1, ?, ?, ?)',
				undef, $key, @$html{qw(sidebar_tags sidebar_menu)});
		}
		$dbh->commit;
		1;
	} or do {
		my $error = $@;
		$dbh->rollback;
		die $error;
	};
	return $html;
}

1;
