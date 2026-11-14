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
my $UPDATE_MIN_VERSION = 4.42;	# これより古いデータからのアップデートはできない
my @update_versions = (
	{ ver => 4.43, func => 'sys_update_443', system=>1, rebuild=>1, plugin=>1, theme=>1 }	# 同時編集の確認を削除したので、システム設定のedit_lock_intervalとブログのlock/を消す。システム設定のalbum_*_qualityをmedia_*_qualityに移す。添付ファイルのフォルダをpub/attachments/からpub/attach/にしたので、フォルダと保存したパスを移し、全記事とデザインのスケルトンを作り直す。固定ページの内部の名前をwikiからpageにしたので、記事のctypeとブログの設定を移し、テーマの色の調整のCSSを作り直す
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
		if ($cur >= $h->{ver}) { next; }
		$ROBJ->message("System update for Ver %.2f", $h->{ver});
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
	return $self->{sys}->{VERSION} < $UPDATE_MIN_VERSION ? 1 : 0;
}

#-------------------------------------------------------------------------------
# ●システムアップデート for Ver4.43
#-------------------------------------------------------------------------------
# 同時編集の確認を削除したので、システム設定の間隔と、ブログのロックのファイルを置いたディレクトリを消す
# 内部の名前をalbumからmediaにしたので、システム設定のサムネイルの品質を新しい名前に移す
# 添付ファイルのフォルダをpub/attachments/からpub/attach/にしたので、フォルダと、ブログの設定と記事に保存したパスを移す
# 固定ページの内部の名前をwikiからpageにしたので、記事とゴミ箱のctypeと、ブログの設定を移す
sub sys_update_443 {
	my $self = shift;
	my $ROBJ = $self->{ROBJ};
	$self->update_sysdat('edit_lock_interval', undef);	# 値が空のキーは保存しない
	foreach(qw(jpeg avif)) {
		my $old = $self->{sys}->{"album_${_}_quality"};
		if ($old eq '') { next; }
		if ($self->{sys}->{"media_${_}_quality"} eq '') { $self->update_sysdat("media_${_}_quality", $old); }
		$self->update_sysdat("album_${_}_quality", undef);
	}

	my $old_img = $self->{pub_dir} . 'attachments/';
	my $img     = $self->blogimg_dir();
	if (-d $old_img) {
		if (-e $img) {
			$ROBJ->message("Already exists '%s'", $img);
		} else {
			rename($old_img, $img) || $ROBJ->message("Rename '%s' failed", $old_img);
		}
	}

	my $blog = $self->{blog};
	if (!$blog) { return; }
	my $dir = $self->{blog_dir} . 'lock/';
	if (-d $dir) { $ROBJ->dir_delete($dir); }

	# ブログの設定（ブログの画像、アイコン、プラグインの画像など）のパス
	my $old_path = qr|pub/attachments/|;
	my $new_path = 'pub/attach/';
	my %up;
	foreach(keys(%$blog)) {
		if (ref($blog->{$_}) || $blog->{$_} !~ $old_path) { next; }
		($up{$_} = $blog->{$_}) =~ s/$old_path/$new_path/g;
	}
	if (%up) { $self->update_blogset($blog, \%up); }

	# 固定ページの内部の名前をwikiからpageにしたので、ブログの設定（編集画面の既定、プラグインの設定、テーマの色の調整）を移す
	{
		my %up;
		my %rename = ('wiki' => 'page', 'p:dea_art-info:wiki_tm' => 'p:dea_art-info:page_tm');
		foreach(keys(%rename)) {
			if (!exists($blog->{$_})) { next; }
			if ($blog->{ $rename{$_} } eq '') { $up{ $rename{$_} } = $blog->{$_}; }
			$up{$_} = undef;
		}
		foreach(keys(%$blog)) {
			if ($_ !~ /^theme_custom:/ || $blog->{$_} !~ /^wikibg=/m) { next; }
			($up{$_} = $blog->{$_}) =~ s/^wikibg=/pagebg=/mg;
		}
		if (%up) { $self->update_blogset($blog, \%up); }
	}

	# 固定ページのctypeをwikiからpageにする。rev、lastrevにはctypeの列が無い
	foreach my $table (qw(art trash)) {
		if (!$self->{DB}->find_table($table)) { next; }
		my $ary = $self->{DB}->select_match($table, 'ctype', 'wiki', '*cols', ['pkey']);
		if (!@$ary) { next; }
		$self->{DB}->begin();
		foreach(@$ary) {
			$self->{DB}->update_match($table, { ctype => 'page' }, 'pkey', $_->{pkey});
		}
		if ($self->{DB}->commit()) { $ROBJ->message("Blog database error(%s)", $table); }
	}

	# 記事の原文（HTML、Markdownで書いたパス）とパースしたもの。artのtextは作り直すが、ゴミ箱は作り直さない
	my $DB = $self->{DB};
	my %cols = (
		art     => [qw(_text text text_s)],
		trash   => [qw(_text text text_s)],
		rev     => [qw(_text)],
		lastrev => [qw(_text)]
	);
	foreach my $table (sort keys(%cols)) {
		if (!$DB->find_table($table)) { next; }
		my $ary = $DB->select_match($table, '*cols', ['pkey', @{ $cols{$table} }]);
		$DB->begin();
		foreach my $h (@$ary) {
			my %up;
			foreach(@{ $cols{$table} }) {
				my $v = $h->{$_};
				if ($v =~ s/$old_path/$new_path/g) { $up{$_} = $v; }
			}
			if (%up) { $DB->update_match($table, \%up, 'pkey', $h->{pkey}); }
		}
		if ($DB->commit()) { $ROBJ->message("Blog database error(%s)", $table); }
	}
}

1;
