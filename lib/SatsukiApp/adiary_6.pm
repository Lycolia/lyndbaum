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
my $UPDATE_MIN_VERSION = 4.25;	# これより古いデータからのアップデートはできない
my @update_versions = (
	{ ver => 4.27, plugin=>1, func => 'sys_update_427' },	# プライベートモードを削除した。雛形から403の分岐を消したので、デザインのスケルトンを作り直す
	{ ver => 4.28, func => 'sys_update_428', system=>1 },	# 設定ファイルをやめて既定値をコードに移し、変えたい値だけをユーザー設定（lyndbaum.user.cgi）に書くようにした
	{ ver => 4.29, func => 'sys_update_429' },	# アイキャッチを選んだ画像だけにし、「設定しない」（main_image の ?none）を廃止した
	{ ver => 4.30, plugin=>1, info=>1 },	# 記事一覧の雛形（_main）で、OGPをUser-Agentによらず出すようにした。デザインのスケルトンを作り直す。RSSの版の表示を直したので書き出し直す
	{ ver => 4.31, func => 'sys_update_431', system=>1 }	# ユーザーを管理者1人にした。ほかのユーザーと、権限の設定を消す
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

	# プライベートモードの削除（Ver4.27）。閉じていたブログが公開されるので、確認が無いとアップデートしない
	if ($cur < 4.27 && ($self->{blog} || {})->{private} && !$ROBJ->{Form}->{publish_private}) {
		$ROBJ->form_error('publish_private', 'Confirm that this blog will be published');
		return 10;
	}

	# ユーザーを管理者1人にした（Ver4.31）。ほかのユーザーを消すので、確認が無いとアップデートしない
	if (@{ $self->load_update_other_users() } && !$ROBJ->{Form}->{remove_other_users}) {
		$ROBJ->form_error('remove_other_users', 'Confirm that other users will be deleted');
		return 10;
	}

	my $exists = $self->select_blog();

	# プライベートモードのファイルを pub/ へ戻す（Ver4.27）。各バージョンの処理は pub/ の下を見るので、それより先に行う
	if ($cur < 4.27 && $exists && $exists->{pub_private_dir} ne '') {
		if ($self->restore_private_dir()) { return 1; }
		$opt{rebuild} = 1;	# 記事の中の画像のURLが変わる
	}

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
# ●アップデートで消すユーザー（実行している管理者のほかの全員）
#-------------------------------------------------------------------------------
sub load_update_other_users {
	my $self = shift;
	if ($self->{sys}->{VERSION} >= 4.31) { return []; }
	my $auth = $self->{ROBJ}->{Auth};
	return [ grep { $_->{id} ne $auth->{id} } @{ $auth->load_users() } ];
}

#-------------------------------------------------------------------------------
# ●システムアップデート for Ver4.31
#-------------------------------------------------------------------------------
sub sys_update_431 {
	my $self = shift;
	my $ROBJ = $self->{ROBJ};
	my $auth = $ROBJ->{Auth};

	my @ids = map { $_->{id} } @{ $self->load_update_other_users() };
	if (@ids) {
		my $r = $auth->user_delete(\@ids);
		if ($r->{ret}) { $ROBJ->message($r->{msg}); }
	}

	my $blog = $self->{blog};
	if (!$blog) { return; }
	foreach(qw(admin_users editors edit_by_author_only)) {
		$self->update_blogset($blog, $_, undef);
	}
	if ($blog->{allow_com_users} ne '*') {
		$self->update_blogset($blog, 'allow_com_users', '');
	}
}

#-------------------------------------------------------------------------------
# ●システムアップデート for Ver4.27
#-------------------------------------------------------------------------------
# プライベートモードを削除した。ファイルは restore_private_dir で先に戻してある
sub sys_update_427 {
	my $self = shift;
	my $blog = $self->{blog};
	foreach(qw(private pub_private_dir viewers view_pass)) {
		$self->update_blogset($blog, $_, undef);
	}
}

#-------------------------------------------------------------------------------
# ●プライベートモードのフォルダのファイルを pub/ へ戻す
#-------------------------------------------------------------------------------
# 戻すのはブログが書き出すものだけ。手で置いたものは公開しないよう、フォルダごと残す。
# 途中で失敗したら pub_private_dir を消さず、もう一度アップデート処理を行えるようにする（0以外を返す）
my @Private_dir_files = qw(attachments plugin custom static
	images.json contents.json taglist.json sitemap.xml);

sub restore_private_dir {
	my $self = shift;
	my $ROBJ = $self->{ROBJ};
	my $blog = $self->{blog};
	my $old_dir = "$self->{pub_dir}$blog->{pub_private_dir}/";
	my $new_dir = $self->{pub_dir};
	my @files = (@Private_dir_files, @{ $self->load_rss_files() });

	# 上書きしないよう、移す前に確かめる
	foreach(@files) {
		if (-e "$old_dir$_" && -e "$new_dir$_") {
			$ROBJ->message('Move failed (%s)', "$old_dir$_");
			return 1;
		}
	}
	foreach(@files) {
		if (!-e "$old_dir$_") { next; }
		if (!rename("$old_dir$_", "$new_dir$_")) {
			$ROBJ->message('Move failed (%s)', "$old_dir$_");
			return 2;
		}
	}

	# 設定に入っているパス（ブログの画像、アイコンなど）を書き換える
	my $re = join('|', map { quotemeta("$old_dir$_") } sort { length($b) <=> length($a) } @files);
	foreach(keys(%$blog)) {
		if ($blog->{$_} !~ /^(?:$re)/) { next; }
		$self->update_blogset($blog, $_, $new_dir . substr($blog->{$_}, length($old_dir)));
	}

	rmdir($old_dir) || $ROBJ->message('Remove folder failed (%s)', $old_dir);
	$self->update_blogset($blog, 'pub_private_dir', undef);
	return 0;
}

#-------------------------------------------------------------------------------
# ○新しいブログの初期設定のファイル（4.10まで）を消す
#-------------------------------------------------------------------------------
sub delete_default_setting_file {
	my $self = shift;
	my $file = $self->{data_dir} . 'default_setting.dat';
	if (-e $file) {
		my $ok = $self->{ROBJ}->file_delete($file);
		$self->{ROBJ}->message($ok ? "Delete '%s'" : "Delete '%s' failed", $file);
	}
}

#-------------------------------------------------------------------------------
# ●システムアップデート for Ver4.29
#-------------------------------------------------------------------------------
# アイキャッチの「設定しない」を廃止した。保存してある ?none を空にする
sub sys_update_429 {
	my $self = shift;
	my $ROBJ = $self->{ROBJ};
	my $DB   = $self->{DB};
	foreach my $table (qw(art trash)) {
		if (!$DB->find_table($table)) { next; }
		$DB->begin();
		$DB->update_match($table, { main_image => '' }, 'main_image', '?none');
		if ($DB->commit()) { $ROBJ->message("Blog database error(%s)", $table); }
	}
}

#-------------------------------------------------------------------------------
# ●システムアップデート for Ver4.28
#-------------------------------------------------------------------------------
# 設定ファイルをやめて既定値をコードに移し、変えたい値だけをユーザー設定（lyndbaum.user.cgi）に書くようにした
sub sys_update_428 {
	my $self = shift;
	$self->delete_default_setting_file();
	$self->migrate_conf_428();
}

#-------------------------------------------------------------------------------
# ○4.27までの設定ファイルを、ユーザー設定に移す
#-------------------------------------------------------------------------------
# 有効な行のうち、4.27の見本（lyndbaum_conf_427.txt）と違うものを写す。
# ユーザー設定が書けないときは、今までの設定ファイルのまま動き続ける
#
# 組み立てる行と、コードに移して変えないことにした項目は写さない
my $Conf_sample_428 = 'lib/SatsukiApp/lyndbaum_conf_427.txt';
# 画面で変えられるようにした項目：システム設定のキー、値を割る数、画面の入力の範囲
my %Conf_to_sys_428 = (
	'v.uplaod_files_max'	=> [ 'upload_max_mb',      1048576, 1, 2048 ],
	'v.album_jpeg_quality'	=> [ 'album_jpeg_quality', 1,       1, 100  ],
	'v.album_avif_quality'	=> [ 'album_avif_quality', 1,       1, 100  ],
	'Auth.pass_min'		=> [ 'pass_min',           1,       8, 64   ],
	'Auth.expires'		=> [ 'session_days',       86400,   1, 365  ],
	'Auth.all_logout'	=> [ 'all_logout',         1,       0, 1    ],
	'Auth.fail_count'	=> [ 'fail_count',         1,       3, 100  ],
	'Auth.fail_minute'	=> [ 'fail_minute',        1,       1, 1440 ]
);
my %Conf_unit_428 = (K=>1024, M=>1048576, G=>1073741824, sec=>1, min=>60, hour=>3600, day=>86400, week=>604800);
my $Conf_not_movable_428 = qr/^\s*<\$(?:constant\(|const\(|regist_skeleton\(|load_language_file\(|ifumask\(|If_post_exec_pre\s*=|v\s*=|DB\s*=|Auth\s*=|v\.(?:\w+_dir|system_config_file|default_\w+_file|allow_tags_head|default_theme|parsers|rss_skeleton|words_separator|album_icons|album_font|album_font_size)\s*=)/;
sub migrate_conf_428 {
	my $self = shift;
	my $ROBJ = $self->{ROBJ};
	my $conf = $ROBJ->{Conf_file};
	if ($conf eq '' || !-r $conf) { return; }	# 移行の必要がない
	my $env  = $ROBJ->{Env_file};
	my $user = $ROBJ->{User_file};

	my $sample = $self->conf_statements_428($Conf_sample_428);
	my %sample = map { $_->{key} => 1 } @$sample;

	# 定数はファイルごとなので、ユーザー設定からは使えない
	my @const = map { $_->{key} =~ /^<\$const(?:ant)?\((\w+)\)/ ? $1 : () } @$sample;
	my $use_const = '(?<![\.\w])(?:' . join('|', @const) . ')\b';

	my @move;
	my @not_moved;
	my @out_of_range;
	my $admin_trust;
	my $start_up;
	foreach my $file ($env, $conf) {
		if (!-r $file) { next; }
		foreach my $st (@{ $self->conf_statements_428($file) }) {
			if ($st->{key} =~ /^<\$v\.admin_trust_mode\s*=/) { $admin_trust = 1; }
			if ($st->{key} =~ /^<\$Auth\.start_up\s*=/)      { $start_up    = 1; }
			if ($sample{ $st->{key} }) { next; }
			if ($st->{key} =~ $Conf_not_movable_428 || $st->{key} =~ /$use_const/) {
				push(@not_moved, @{ $st->{lines} });
			} elsif (my $to_sys = $self->conf_to_sys_428($st->{key})) {
				$self->update_sysdat(@$to_sys);
			} else {
				# 画面で変える項目でも、画面で扱えない値はユーザー設定で動かし続ける
				if ($st->{key} =~ /^<\$(v\.\w+|Auth\.\w+)\s*=/ && $Conf_to_sys_428{$1}) {
					push(@out_of_range, @{ $st->{lines} });
				}
				push(@move, @{ $st->{lines} });
			}
		}
	}
	# どちらも既定はONなので、止めていた人の設定が変わらないようにする
	if (!$admin_trust) {
		push(@move, "<\$v.admin_trust_mode = 0>\n");
	}
	if (!$start_up) {
		push(@move, "<\$Auth.start_up = 0>\n");
	}

	my @out = (
		"<\@20> pragma : 最適化on（コマンド以外を無視）\n",
		"<\@#>\n",
		"# ユーザー設定。書ける項目は lyndbaum.user.cgi.sample を見てください\n",
		"# 4.27までの設定ファイル（$conf）から移しました\n",
		"\n",
		@move
	);
	if ($ROBJ->fwrite_lines($user, \@out)) {
		$ROBJ->clear_error();
		$ROBJ->message("Can't write '%s'. Please create it with these lines, and delete '%s'.", $user, $conf);
		foreach(@out) {
			my $x = $_;
			$x =~ s/\s+$//;
			if ($x ne '') { $ROBJ->message("  %s", $x); }
		}
		return;
	}
	$ROBJ->message("Create '%s'", $user);

	if (@out_of_range) {
		$ROBJ->message("These values can't be set on the setting screen, so they stay in '%s'.", $user);
		foreach(@out_of_range) {
			my $x = $_;
			$x =~ s/\s+$//;
			$ROBJ->message("  %s", $x);
		}
	}

	# 写せなかった行を知らせる。控えから確かめられる
	if (@not_moved) {
		$ROBJ->message("These lines were not moved to '%s'. Please check them.", $user);
		foreach(@not_moved) {
			my $x = $_;
			$x =~ s/\s+$//;
			$ROBJ->message("  %s", $x);
		}
	}

	# 今までのファイルは控えを残して消す。消せなくても、ユーザー設定があれば読まない
	foreach my $file ($env, $conf) {
		if (!-e $file) { next; }
		my $base   = $file =~ m|([^/]+)$| ? $1 : $file;
		my $backup = $self->{data_dir} . "$base.428.bak";
		if ($ROBJ->file_copy($file, $backup)) {
			$ROBJ->clear_error();
			$ROBJ->message("Can't copy '%s' to '%s'. Please delete '%s' after checking it.", $file, $backup, $file);
			next;
		}
		my $ok = $ROBJ->file_delete($file);
		$ROBJ->message($ok ? "Move '%s' to '%s'" : "Can't delete '%s'. It is not used now (backup: '%s').", $file, $backup);
	}
}

#-------------------------------------------------------------------------------
# ○画面で変える項目の行を、システム設定のキーと値にする
#-------------------------------------------------------------------------------
# 画面で変える項目でないか、画面で扱えない値（範囲の外、割り切れない、式）なら undef
sub conf_to_sys_428 {
	my ($self, $key) = @_;
	if ($key !~ /^<\$(v\.\w+|Auth\.\w+)\s*=\s*(\d+|true)\s*(\w*)\s*>$/) { return; }
	my ($name, $val, $unit) = ($1, $2, $3);
	my $h = $Conf_to_sys_428{$name};
	if (!$h) { return; }
	if ($unit ne '' && !$Conf_unit_428{$unit}) { return; }
	$val = ($val eq 'true' ? 1 : $val) * ($unit ne '' ? $Conf_unit_428{$unit} : 1);

	my ($sys_key, $div, $min, $max) = @$h;
	if ($val % $div) { return; }
	$val = $val / $div;
	if ($val < $min || $max < $val) { return; }
	return [ $sys_key, $val ];
}

#-------------------------------------------------------------------------------
# ○設定ファイルを文に分ける
#-------------------------------------------------------------------------------
# 空行、コメント、コマンドでない行は捨てる。begin から <$end> までは1つの文にする
# key：比べるための文字列。空白を詰め、中のコメントを除く
# lines：ファイルの行（中のコメントは除く）
sub conf_statements_428 {
	my ($self, $file) = @_;
	my @st;
	my $cur;
	foreach my $line (@{ $self->{ROBJ}->fread_lines($file) }) {
		my $x = $line;
		$x =~ s/^\s+|\s+$//g;
		$x =~ s/\s+/ /g;
		if ($cur) {
			if ($x eq '' || substr($x, 0, 1) eq '#') { next; }
			push(@{ $cur->{lines} }, $line);
			$cur->{key} .= "\n$x";
			if ($x =~ /^<\$end>/) {
				push(@st, $cur);
				$cur = undef;
			}
			next;
		}
		if (substr($x, 0, 2) ne '<$') { next; }
		my $h = { key => $x, lines => [ $line ] };
		if ($x =~ /=\s*begin\w*>$/) {
			$cur = $h;
			next;
		}
		push(@st, $h);
	}
	return \@st;
}

1;
