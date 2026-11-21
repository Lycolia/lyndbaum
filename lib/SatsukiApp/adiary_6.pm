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
	{ ver => 4.43, func => 'sys_update_443', system=>1, rebuild=>1, plugin=>1, theme=>1 },	# 同時編集の確認を削除したので、システム設定のedit_lock_intervalとサイトのlock/を消す。システム設定のalbum_*_qualityをmedia_*_qualityに移す。添付ファイルのフォルダをpub/attachments/からpub/attach/にしたので、フォルダと保存したパスを移し、全記事とデザインのスケルトンを作り直す。固定ページの内部の名前をwikiからpageにしたので、記事のctypeとサイトの設定を移し、テーマの色の調整のCSSを作り直す。記事ヘッダの日時の設定を消す。satsuki2系のテーマの色の調整のfixhelpfontを、ヘルプの文字の色helpfontに移す
	{ ver => 4.45, func => 'sys_update_445', rebuild=>1, plugin=>1, theme=>1 }	# 見出しの段を一段上げた（サイト名h1→div、記事タイトルと画面の名前h2→h1、本文h3〜→h2〜）。全記事、デザインのスケルトン、テーマの色の調整のCSSを作り直す。サイドバーのモジュールと外枠のクラス、idからhatenaを外したので、フリー入力のモジュールに保存したクラスを移す。デザインモジュールのデザイン設定を無くしたので、その設定、画像、CSSを消す
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
		$opt{info}    ||= $h->{info};		# サイト付加情報更新

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
	if (!$exists) { %opt = (); }	# サイトが無ければ再構築などは不要

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
	# サイト付加情報の再構築
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
# 同時編集の確認を削除したので、システム設定の間隔と、サイトのロックのファイルを置いたディレクトリを消す
# 内部の名前をalbumからmediaにしたので、システム設定のサムネイルの品質を新しい名前に移す
# 添付ファイルのフォルダをpub/attachments/からpub/attach/にしたので、フォルダと、サイトの設定と記事に保存したパスを移す
# 固定ページの内部の名前をwikiからpageにしたので、記事とゴミ箱のctypeと、サイトの設定を移す
# 記事ヘッダの日時の設定（tmdate、wiki_tm）を消す
# satsuki2系のテーマの色の調整の、前のポップアップのヘルプの色（fixhelpfont）を、ヘルプの文字の色（helpfont）にしたので、保存した値を移す
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

	# サイトの設定（サイトの画像、アイコン、プラグインの画像など）のパス
	my $old_path = qr|pub/attachments/|;
	my $new_path = 'pub/attach/';
	my %up;
	foreach(keys(%$blog)) {
		if (ref($blog->{$_}) || $blog->{$_} !~ $old_path) { next; }
		($up{$_} = $blog->{$_}) =~ s/$old_path/$new_path/g;
	}
	if (%up) { $self->update_blogset($blog, \%up); }

	# 固定ページの内部の名前をwikiからpageにしたので、サイトの設定（編集画面の既定、テーマの色の調整）を移す
	# 記事ヘッダ（dea_art-info）の日時の設定（tmdate、wiki_tm）は、#70から効いておらず、意味の違う設定にしたので、移さずに消す
	{
		my %up = map { ("p:dea_art-info:$_" => undef) } grep { exists($blog->{"p:dea_art-info:$_"}) } qw(tmdate wiki_tm page_tm);
		# 編集画面の設定suggest_link_key（親のパーマリンクから自動設定する）は、パーマリンクを「親のパーマリンク/名前」に決めたので消す
		if (exists($blog->{suggest_link_key})) { $up{suggest_link_key} = undef; }
		my %rename = ('wiki' => 'page');
		foreach(keys(%rename)) {
			if (!exists($blog->{$_})) { next; }
			if ($blog->{ $rename{$_} } eq '') { $up{ $rename{$_} } = $blog->{$_}; }
			$up{$_} = undef;
		}
		# satsuki2系のテーマの色の調整の、前のポップアップのヘルプの色fixhelpfontを、ヘルプの文字（.help-text）の色helpfontにした
		foreach(keys(%$blog)) {
			if ($_ !~ /^theme_custom:/ || $blog->{$_} !~ /^(?:wikibg|fixhelpfont)=/m) { next; }
			my $v = $blog->{$_};
			$v =~ s/^wikibg=/pagebg=/mg;
			$v =~ s/^fixhelpfont=/helpfont=/mg;
			$up{$_} = $v;
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

#-------------------------------------------------------------------------------
# ●システムアップデート for Ver4.45
#-------------------------------------------------------------------------------
# サイドバーのモジュールのクラスをhatena-moduleからside-moduleにしたので、フリー入力（des_freetext）の設定に保存したクラスを移す
# スケルトンやプラグインが出すクラスは、プラグインの再インストールで作り直される。この設定は入力された値なので、ここで書き換える
sub sys_update_445 {
	my $self = shift;
	my $blog = $self->{blog};
	if (!$blog) { return; }

	my %up;
	foreach(keys(%$blog)) {
		if ($_ !~ /^p:des_freetext(?:,\d+)?:class$/ || ref($blog->{$_})) { next; }
		my $v = $blog->{$_};
		if ($v =~ s/(?<![\w-])hatena-module(?![\w-])/side-module/g) { $up{$_} = $v; }
	}
	if (%up) { $self->update_blogset($blog, \%up); }

	$self->sys_update_445_design_setting($blog);
}

# デザインモジュールのデザイン設定（css_setting.html、module-d.css）を無くしたので、保存してある設定、アップロードした画像、作ったCSSを消す
# 普通の設定に移した項目（text_centering、br、erase_login）は、キーの名前を変えていないので、そのまま残す
sub sys_update_445_design_setting {
	my $self = shift;
	my $blog = shift;
	my $ROBJ = $self->{ROBJ};

	# 消す設定のキー（消したcss_validator.htmlが保存していたもの）
	my @box = qw(bg bg_alpha border_c border_r border_w font_c font_s height line_h margin0 margin1 margin2 margin3 padding0 padding1 padding2 padding3 shadow_b shadow_bb);
	my %keys = (
		'dea_freetext'    => [ @box ],
		'dem_freetext'    => [ @box, qw(abs_x abs_y centering width) ],
		'des_freetext'    => [ @box, qw(centering) ],
		'deh_description' => [ @box, qw(abs_x abs_y width) ],
		'deh_searchbox'   => [ @box, qw(abs_x abs_y width width2) ],
		'dem_searchbox'   => [ @box, qw(width width2) ],
		'deh_title'       => [ qw(bg bg_alpha bgfile_fit border0 border1 border2 border3 border_c border_r centering fbg fbg_alpha font_bf font_c font_f font_s height left margin0 margin1 margin2 margin3 s_bl s_c0 s_c1 s_mode s_oc s_ow s_w top) ],
		'dem_ddmenu'      => [ qw(arrow bg_trans border font height item_bg item_left item_padding margin0 margin1 margin2 margin3 nob_left nob_lr nob_right nob_tb no_centering no_shadow padding select_bg tbg_trans vbottom width1 width1_free width2 zindex) ],
		'deh_login'       => [ qw(absolute bf bg bg_attach body_bg body_bg_alpha body_bg_attach font_c font_ca head_bg head_bg_alpha head_bgfile_fit head_bgfile_norep margin0 margin1 margin2 margin3 margin4 margin5 margin6 margin7 nav_bg nav_bg_alpha padding0 padding1 padding2 padding3 padding4 padding5 padding6 padding7 width) ]
	);
	# アップロードした画像のキー。値はファイル名（「モジュール名-キー.拡張子」。upload_image_for_plugin）で、幅と高さも保存している
	my %images = (
		'deh_title' => [ qw(titleimg bgfile) ],
		'deh_login' => [ qw(bgfile body_bgfile head_bgfile) ]
	);
	my %del;
	foreach my $n (keys(%keys)) {
		$del{$n} = { map { $_ => 1 } @{ $keys{$n} } };
	}
	my %is_image;
	foreach my $n (keys(%images)) {
		foreach(@{ $images{$n} }) {
			$del{$n}->{$_} = $del{$n}->{"${_}_w"} = $del{$n}->{"${_}_h"} = 1;
			$is_image{"$n:$_"} = 1;
		}
	}

	# CSSを作るイベント（INSTALL、SETTING、UNINSTALLで呼んでいたスケルトンは消した）を外す
	# この後のプラグインの入れ直しで、前のUNINSTALLのイベントが、無いスケルトンを呼ばないようにする
	my $css_evt = qr!=skel/_sub/module_css_(?:generate|delete)$!;
	my $strip = sub {
		my $v = join("\n", grep { $_ !~ $css_evt } split(/\r?\n/, shift));
		return ($v eq '') ? undef : $v;
	};
	# プラグインの情報（plugins.dat）。サイトの設定のイベント（event:）は、ここから作り直される（set_event_info）
	{
		my $pd = $self->load_plugins_dat();
		my $c  = 0;
		foreach(keys(%$pd)) {
			if ($_ !~ /:events$/ || $pd->{$_} !~ /$css_evt/m) { next; }
			my $v = &$strip($pd->{$_});
			if (defined $v) { $pd->{$_} = $v; } else { delete $pd->{$_}; }
			$c++;
		}
		if ($c) { $ROBJ->fwrite_hash($self->{blog_dir} . 'plugins.dat', $pd, { atomic => 1 }); }
	}

	my %up;
	foreach(keys(%$blog)) {
		# 設定
		if ($_ =~ /^p:([\w\-]+)((?:,\d+)?):(\w+)$/ && $del{$1} && $del{$1}->{$3}) {
			my ($n, $num, $k) = ($1, $2, $3);
			my $file = $blog->{$_};
			if ($is_image{"$n:$k"} && !ref($file) && $file =~ /^\Q$n$num\E-\Q$k\E\.\w+$/) {
				$ROBJ->file_delete( $self->plugin_image_dir($file) );
			}
			$up{$_} = undef;
			next;
		}
		# サイトの設定のイベント
		if ($_ =~ /^event:/ && !ref($blog->{$_}) && $blog->{$_} =~ /$css_evt/m) {
			$up{$_} = &$strip($blog->{$_});
		}
	}
	if (%up) { $self->update_blogset($blog, \%up); }

	# 作ったCSS（css.d/モジュール名-d.css）を消し、dynamic.cssを作り直す。ユーザーCSSの原本（_usercss-d.css）は残す
	my $dir   = $self->dynamic_css_dir();
	my $files = (-d $dir) ? $ROBJ->search_files($dir, {ext => '.css'}) : [];
	my $c = 0;
	foreach(@$files) {
		if ($_ !~ /^([\w\-]+)(?:,\d+)?-d\.css$/ || !$del{$1}) { next; }
		$ROBJ->file_delete("$dir$_");
		$c++;
	}
	if ($c) { $self->update_dynamic_css(); }
}

1;
