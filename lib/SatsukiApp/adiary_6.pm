use strict;
#-------------------------------------------------------------------------------
# adiary_6.pm (C)nabe@abk
#-------------------------------------------------------------------------------
# ・システムアップデート
#-------------------------------------------------------------------------------
use SatsukiApp::adiary ();
use SatsukiApp::adiary_2 ();
use SatsukiApp::adiary_3 ();
use SatsukiApp::adiary_4 ();
use SatsukiApp::adiary_5 ();
package SatsukiApp::adiary;
################################################################################
# ■ワンライナーなサブルーチン等
################################################################################
my $UPDATE_MIN_VERSION = '4.31';	# これより古いデータからのアップデートはできない
my @update_versions = (
	{ ver => '4.32', plugin=>1 },	# ブログが無いときの分岐を雛形とプラグインから消し、変数の名前をそろえた。デザインのスケルトンを作り直す
	{ ver => '4.33', func => 'sys_update_433', system=>1, plugin=>1 },	# マルチサイトと複数ユーザーの残りの列を消した。記事情報モジュールの「投稿者の表示」を削除したので、デザインのスケルトンを作り直す
	{ ver => '4.34', func => 'sys_update_434', system=>1 },	# 操作の記録のうち、削除の記録を消す
	{ ver => '4.37', rebuild_cond => ['\[\*toc'] },	# 目次を「目次」の見出し付きの<nav>で囲んだので、目次のある記事を作り直す
	{ ver => '4.38', func => 'sys_update_438' },	# 記事の直前の保存のテーブル（lastrev）を作る
	{ ver => '4.39', rebuild_cond => ['\(\('] },	# 注釈の一覧を、書いた見出しの下に出すようにしたので、注釈のある記事を作り直す
	{ ver => '4.41.0' }	# 版の書式をmajor.minor.patchにした。データの版を新しい書式で書き直すだけ
);
#-------------------------------------------------------------------------------
# ●システムアップデート
#-------------------------------------------------------------------------------
sub system_update {
	my $self = shift;
	my $ROBJ = $self->{ROBJ};
	my $auth = $ROBJ->{Auth};
	if (!$auth->{isadmin}) { $ROBJ->message('Operation not permitted'); return 5; }

	# 古すぎるデータは何も変更せずに断る。処理を続けると、新しい版の処理が古いデータの上で動いて壊す
	if ($self->update_unsupported()) {
		$ROBJ->message('Update from this version is not supported');
		return 20;
	}

	my %opt;
	my $cur = $self->{sys}->{VERSION};

	my $exists = $self->select_blog();

	foreach my $h (@update_versions) {
		if ($self->version_cmp($cur, $h->{ver}) >= 0) { next; }
		$ROBJ->message("System update for Ver %s", $h->{ver});
		$opt{rebuild} ||= $h->{rebuild};	# 全記事再構築
		$opt{plugin}  ||= $h->{plugin};		# プラグイン更新
		$opt{theme}   ||= $h->{theme};		# テーマカスタムCSS更新
		$opt{info}    ||= $h->{info};		# ブログ付加情報更新

		# 条件付きリビルド
		if ($h->{rebuild_cond}) {
			$opt{rebuild_cond} ||= [];
			push(@{ $opt{rebuild_cond} }, @{ $h->{rebuild_cond} });
		}

		my $func = $h->{func};
		if ($func && ($exists || $h->{system})) {
			$self->$func();
		}
		$cur = $h->{ver};
	}
	$self->select_blog();
	if (!$exists) { %opt = (); }	# ブログが無ければ再構築などは不要

	# 再構築
	if ($opt{rebuild}) {
		$ROBJ->message("Rebuild blog");
		$self->rebuild_blog();
		$opt{info} = 0;

	# 条件付き再構築（記事内容による）
	} elsif ($opt{rebuild_cond}) {
		my @ary = map { qr/$_/i } @{ $opt{rebuild_cond} };
		my $cnt = 0;
		my $filter = sub {
			my $h = shift;
			foreach(@ary) {
				if ($h->{_text} =~ /$_/) { $cnt++; return 1; }	# rebuild
			}
			return 0;
		};
		$self->rebuild_blog({ filter => $filter });
		if ($cnt) {
			$ROBJ->message("Rebuild '%d articles'", $cnt);
		}
		$opt{info} = 0;

	}
	# プラグイン再インストール
	if ($opt{plugin}) {
		$ROBJ->message("Reinstall all plugins");
		local($self->{stop_plugin_install_msg}) = 1;
		$self->reinstall_plugins();
	}
	# テーマカスタムCSS更新
	if ($opt{theme}) {
		$ROBJ->message("Remake all custom css");
		$self->remake_theme_custom_css();
	}
	# ブログ付加情報の再構築
	if ($opt{info}) {
		$ROBJ->message("Rebuild blog infomation");
		$self->blog_info_rebuild();
	}

	$self->update_sysdat('VERSION', $cur);
	return 0;
}

#-------------------------------------------------------------------------------
# ●このデータからはアップデートできないか
#-------------------------------------------------------------------------------
sub update_unsupported {
	my $self = shift;
	return $self->version_cmp($self->{sys}->{VERSION}, $UPDATE_MIN_VERSION) < 0 ? 1 : 0;
}

#-------------------------------------------------------------------------------
# ●システムアップデート for Ver4.33
#-------------------------------------------------------------------------------
# マルチサイトと複数ユーザーの残りの列を消す。書いた人は管理者だけなので、記事ごとに持たない
sub sys_update_433 {
	my $self = shift;
	my $auth = $self->{ROBJ}->{Auth};

	$self->drop_columns_433($auth->{DB}, $auth->{table}, qw(isadmin disable));

	my $blog = $self->{blog};
	if (!$blog) { return; }
	my @author = qw(name id ip host agent);
	$self->drop_columns_433($self->{DB}, 'art',   @author);
	$self->drop_columns_433($self->{DB}, 'trash', @author, 'deleted_id');
	$self->update_blogset($blog, 'p:dea_art-info:author', undef);
}
sub drop_columns_433 {
	my ($self, $DB, $table, @cols) = @_;
	foreach(@cols) {
		if ($DB->drop_column($table, $_)) {
			$self->{ROBJ}->message("Blog database error(%s)", "$table.$_");
		}
	}
}

#-------------------------------------------------------------------------------
# ●システムアップデート for Ver4.34
#-------------------------------------------------------------------------------
# 操作の記録のうち、削除の記録を消す。ユーザーの削除はもう記録しない
sub sys_update_434 {
	my $self = shift;
	my $auth = $self->{ROBJ}->{Auth};

	$auth->{DB}->delete_match($auth->{table} . '_log', 'type', 'delete');
}

#-------------------------------------------------------------------------------
# ●システムアップデート for Ver4.38
#-------------------------------------------------------------------------------
# 記事の直前の保存のテーブルを作る
sub sys_update_438 {
	my $self = shift;
	if ($self->{DB}->find_table('lastrev')) { return; }
	if ($self->create_lastrev_table()) {
		$self->{ROBJ}->message("Blog database error(%s)", 'lastrev');
	}
}

1;
