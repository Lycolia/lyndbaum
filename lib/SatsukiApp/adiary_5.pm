use strict;
#-------------------------------------------------------------------------------
# adiary_4.pm (C)nabe@abk
#-------------------------------------------------------------------------------
# ・ユーザー管理
# ・システム管理
# ・インポート、エクスポート
#-------------------------------------------------------------------------------
use SatsukiApp::adiary ();
use SatsukiApp::adiary_2 ();
use SatsukiApp::adiary_3 ();
use SatsukiApp::adiary_4 ();
package SatsukiApp::adiary;
################################################################################
# ■ユーザー管理
################################################################################
#-------------------------------------------------------------------------------
# ●初期セットアップ（最初の管理者とブログ名）
#-------------------------------------------------------------------------------
# ユーザーは管理者1人だけ。管理者がいないときだけ作り、そのままログインする。
# ログインしていなくても呼べるので（do_ajax_function）、管理者がいないことをここで確かめる。
sub _ajax_setup {
	my $self = shift;
	my $form = shift;
	my $ROBJ = $self->{ROBJ};

	# 同時に送られても、作る管理者は1人だけ
	$ROBJ->mkdir( $self->{data_dir} );
	my $lock = $self->{data_dir} . 'setup.lock';
	sysopen(my $fh, $lock, Fcntl::O_CREAT() | Fcntl::O_RDWR()) || return { ret=>-1, msg => 'Internal Error' };
	flock($fh, Fcntl::LOCK_EX()) || return { ret=>-1, msg => 'Internal Error' };

	my $r = $self->do_setup($form);

	unlink($lock);
	close($fh);
	return $r;
}

sub do_setup {
	my ($self, $form) = @_;
	my $ROBJ = $self->{ROBJ};
	my $auth = $ROBJ->{Auth};
	my $DB   = $self->{DB};

	# ロックを待っている間に作られていないか、ユーザーのテーブルを読み直して確かめる
	$DB->clear_cache( $auth->{table} );
	$auth->{exists_admin} = -1;
	$auth->userdb_init();
	if ($auth->{ok} || $auth->{exists_admin}) {
		return { ret=>1, msg => $ROBJ->translate('Operation not permitted') };
	}

	my %user = (
		id    => $form->{adiary_id},
		name  => $form->{name},
		pass  => $form->{pass},
		pass2 => $form->{pass2}
	);

	# ブログ名（基本設定の画面と同じ決まり。skel/set/_action/index.html）
	my $blog = $self->{blog};
	my $blog_name = $form->{blog_name};
	$blog_name =~ s/[\r\n\0]//g;
	$ROBJ->trim($blog_name);
	my $jcode = $ROBJ->load_codepm_if_needs( $blog_name );
	my $len   = $jcode ? $jcode->jlength($blog_name) : length($blog_name);
	my @name_err = $blog_name eq '' ? ("'%s' is empty", 'ブログ名')
		     : $len > 48        ? ("'%s' is too long. (maximum %d chars)", 'ブログ名', 48)
		     : ();
	if (@name_err) {
		# 管理者の欄の誤りも、まとめて知らせる（check_user_data()はフォームのエラーを消してから調べる）
		$ROBJ->clear_form_err();
		my %h = (%user, new_user => 1);
		$auth->check_user_data(\%h);
		$ROBJ->form_err('blog_name', @name_err);
		return { ret=>10, errs => $ROBJ->form_err() };
	}
	$ROBJ->tag_escape($blog_name);

	# 管理者を作る。user_add()は管理者だけが呼べるので、ここだけ権限を与える
	my $r;
	{
		local($auth->{isadmin}) = 1;
		$r = $auth->user_add(\%user);
	}
	if ($r->{ret}) { return $r; }
	$auth->{exists_admin} = 1;

	# ログインする（_ajax_login と同じ）
	my $login = $auth->login($user{id}, $form->{pass});
	if ($login->{ret}) { return $login; }
	$ROBJ->set_cookie('session', {
		id  => $user{id},
		sid => $login->{sid}
	}, $auth->{expires});

	# ブログ名を保存する。アップデートの処理の前でブログがまだ無いときは、保存しない
	if ($blog) {
		local($self->{blog_admin}) = 1;
		$self->save_blogset({ blog_name => $blog_name });
		$self->call_event('BLOG_SETTING');
		$self->generate_rss();		# ブログ名はRSSにも出る
	}
	return { ret=>0, _no_debug=>1 };
}

#-------------------------------------------------------------------------------
# ●ユーザー自身によるパスワード, ユーザー名の変更
#-------------------------------------------------------------------------------
sub _ajax_self_change_name {
	my $self = shift;
	my $auth = $self->{ROBJ}->{Auth};
	return $auth->change_user_info(@_);
}
sub _ajax_self_change_pass {
	my $self = shift;
	my $auth = $self->{ROBJ}->{Auth};
	return $auth->change_pass(@_);
}

################################################################################
# ■ブログの作成と削除
################################################################################
#-------------------------------------------------------------------------------
# ●ブログが無ければ作る
#-------------------------------------------------------------------------------
# リクエストの最初に、権限によらず呼ばれる。失敗してもブログが無いまま返り、呼び出し元が503にする。
# 残っているものを消さないよう、テーブルや設定の一部だけがあるときは作らず、失敗しても消さない
sub blog_auto_create {
	my $self = shift;
	my $ROBJ = $self->{ROBJ};
	my $DB   = $self->{DB};

	# 同時のリクエストがあっても1回だけ作る
	$ROBJ->mkdir( $self->{data_dir} );
	my $lock = $self->{data_dir} . 'blog_create.lock';
	sysopen(my $fh, $lock, Fcntl::O_CREAT() | Fcntl::O_RDWR()) || return;
	flock($fh, Fcntl::LOCK_EX()) || return;

	delete $self->{_cache_exists_blog};
	my $r = $self->do_blog_auto_create();
	delete $self->{_cache_exists_blog};

	unlink($lock);
	close($fh);
	if ($r) { print STDERR "$self->{SYSTEM_NAME}: blog create failed ($r)\n"; }
}

sub do_blog_auto_create {
	my $self = shift;
	my $ROBJ = $self->{ROBJ};
	my $DB   = $self->{DB};
	if ($self->exists_blog()) { return 0; }	# 待っている間に作られた

	foreach(qw(art com tag tagart rev lastrev trash trashcom link)) {
		if ($DB->find_table($_)) { return "table '$_' already exists"; }
	}
	if (-e $self->blog_dir() . 'setting.dat') { return 'setting.dat already exists'; }

	my $r = $self->create_tables();
	if ($r) { return "create tables: $r"; }
	$ROBJ->mkdir( $self->blog_dir() );
	$ROBJ->mkdir( $self->{pub_dir} );
	if (!-d $self->blog_dir()) { return 'mkdir ' . $self->blog_dir(); }

	delete $self->{_cache_exists_blog};
	if (!$self->exists_blog()) { return "table 'art' was not created"; }
	if (!$self->select_blog())  { return 'select blog'; }

	# 標準のデザインを入れる。作っているのは利用者の操作ではないので、権限を確かめない
	local($self->{blog_admin}) = 1;
	$r = $self->load_default_design();
	if ($r) { return "load default design: $r"; }
	return 0;
}

#-------------------------------------------------------------------------------
# ●すべての記事の削除
#-------------------------------------------------------------------------------
sub blog_clear {
	my ($self) = @_;
	my $ROBJ   = $self->{ROBJ};
	my $DB     = $self->{DB};
	if (! $self->{blog_admin} ) { $ROBJ->message('Operation not permitted'); return 5; }

	# テーブルから記事などの削除
	$DB->delete_match("com");
	$DB->delete_match("tagart");
	$DB->delete_match("tag");
	$DB->delete_match("art");

	# イベント処理
	$self->call_event('BLOG_CLEAR');
	$self->call_event('ARTICLE_STATE_CHANGE');
	$self->call_event('COMMENT_STATE_CHANGE');
	$self->call_event('ARTCOM_STATE_CHANGE');

	return 0;
}

################################################################################
# ■再構築機能
################################################################################
#-------------------------------------------------------------------------------
# ●ブログの全記事の再構築
#-------------------------------------------------------------------------------
sub rebuild_blog {
	my $self = shift;
	my $opt  = shift;
	my $ROBJ = $self->{ROBJ};
	my $DB   = $self->{DB};
	if (! $self->{blog_admin} ) { $ROBJ->message('Operation not permitted'); return 5; }

	my $arts = $opt->{logs} || $DB->select_match("art", '*cols', ['pkey', '_text', 'text', 'parser', 'yyyymmdd', 'tm', 'link_key', 'main_image']);
	my $filter = $opt->{filter};
	my %update;
	my $r=0;
	foreach(@$arts) {
		if ($filter && !&$filter($_)) { next; }		# rebuild filter

		my $parser_name = $_->{parser};
		if ($parser_name eq '') { next; }

		my $parser = $self->load_parser( $parser_name );
		if (! ref($parser)) {
			$ROBJ->message("Load parser '%s' failed", $parser);
			$r++;
			next;
		}
		# プリプロセッサはブログ環境で処理内容が異なることはないので
		# 再構築時は実行しない。

		# パース準備
		$self->post_process_link_key( $_ );
		$parser->{thisurl}  = $self->{myself2} . $_->{elink_key};
		$parser->{thispkey} = $_->{pkey};
		# リンクカードは今のHTMLのものを使い、取得しない。取り直すのは、再構築の画面で選んだときだけ
		# （docs/仕様/機能一覧.md「リンクカード」）
		if (!$opt->{refetch_link_cards}) {
			$parser->{link_cards} = $self->extract_link_cards( $_->{text} );
			$parser->{link_cards_offline} = 1;
		}
		my ($text, $text_s) = $parser->parse( $_->{_text} );
		delete $parser->{link_cards};		# パーサーは使い回されるので、他の記事や保存に残さない
		delete $parser->{link_cards_offline};
		if ($text eq $text_s) { $text_s=""; }

		# 許可タグ以外の除去処理
		my $escape = $self->load_tag_escaper( 'article' );
		$text   = $escape->escape($text);
		$text_s = $escape->escape($text_s);

		# 値保存
		my %h;
		$h{text}   = $text;
		$h{text_s} = $text_s;	# 短いtext
		if ($opt->{logs}) {
			$h{_text} = $_->{_text};
		}
		# 記事概要の生成。アイキャッチ画像（main_image）は今のものを残す
		# ※set_description()は画像を渡さないとmain_imageを空にする
		$self->set_description(\%h, $_->{main_image});

		$update{ $_->{pkey} } = \%h;
	}

	#---------------------------------------------------
	# DBに対するupdateを一気に発行する
	#---------------------------------------------------
	$DB->begin();
	foreach(keys(%update)) {
		$DB->update_match("art", $update{$_}, 'pkey', $_);
	}
	$r += $DB->commit();

	# タグ情報の再構築
	$self->tagart_rebuild();

	# イベント処理
	$self->call_event('BLOG_REBUILD');
	$self->call_event('ARTICLE_STATE_CHANGE');
	$self->call_event('COMMENT_STATE_CHANGE');
	$self->call_event('ARTCOM_STATE_CHANGE');
	return $r;
}

#-------------------------------------------------------------------------------
# ●付加情報の再生成
#-------------------------------------------------------------------------------
sub blog_info_rebuild {
	my $self = shift;
	my $ROBJ = $self->{ROBJ};
	if (!$self->{blog_admin} ) { $ROBJ->message('Operation not permitted'); return 5; }

	# タグ情報の再構築
	$self->tagart_rebuild();

	# イベント処理
	$self->call_event('BLOG_INFO_REBUILD');
	$self->call_event('ARTICLE_STATE_CHANGE');
	$self->call_event('COMMENT_STATE_CHANGE');
	$self->call_event('ARTCOM_STATE_CHANGE');
	return 0;
}

#-------------------------------------------------------------------------------
# ●全タグ情報の再生成
#-------------------------------------------------------------------------------
sub tagart_rebuild {
	my $self = shift;
	my $ROBJ = $self->{ROBJ};
	my $DB   = $self->{DB};
	if (!$self->{blog_admin} ) { $ROBJ->message('Operation not permitted'); return 5; }

	my $ary = $DB->select_match("art",
			'*cols', ['pkey', 'enable', 'tags']
		);

	$DB->begin();
	$DB->delete_match("tagart");
	foreach my $art (@$ary) {
		my $tag = $art->{tags};
		if ($tag eq '') { next; }

		my $pkeys = $self->regist_tags([split(',', $tag)]);
		$pkeys = ref($pkeys) ? $pkeys : [];
		foreach(@$pkeys) {
			$DB->insert("tagart", {
				'a_pkey'   => $art->{pkey},
				'a_enable' => $art->{enable},
				't_pkey'   => $_
			});
		}
	}
	$DB->commit();
}

################################################################################
# ■プラグイン/デザイン関連
################################################################################
#-------------------------------------------------------------------------------
# ●全プラグインの再インストール
#-------------------------------------------------------------------------------
sub reinstall_plugins {
	my $self = shift;
	my $pd = $self->load_plugins_dat();

	my $r1 = $self->reinstall_normal_plugins($pd);
	my $r2 = $self->reinstall_design_plugins($pd);
	return ($r1 || $r2);
}
#-------------------------------------------------------------------------------
# ●通常プラグインの再インストール
#-------------------------------------------------------------------------------
sub reinstall_normal_plugins {
	my $self = shift;
	my $pd   = shift;
	my $plgs = $self->load_plugins_info();

	my %h;
	foreach(@$plgs) {
		$h{ $_->{name} } = 0;	# uninstall
	}
	$self->save_use_plugins(\%h);
	foreach(@$plgs) {
		$h{ $_->{name} } = $pd->{ $_->{name} } ? 1 : 0;	# reinstall
	}
	return $self->save_use_plugins(\%h);
}

#-------------------------------------------------------------------------------
# ●デザインモジュールの再インストール
#-------------------------------------------------------------------------------
sub reinstall_design_plugins {
	my $self = shift;
	my $pd   = shift;
	my $ROBJ = $self->{ROBJ};
	my $plgs = $self->load_plugins_info();

	# デザインモジュールの現在の状態をロードしておく
	my $des = $self->load_design_info();
	if (! %$des) { return 0; }

	# reinistall
	my $h = $self->parse_design_dat( $des );
	if ($des->{version}<6) {
		$h->{save_ary} = [ '_sidebar', '_header' ];
		if (!$des->{header}) { return -1; }
	}
	if ($des->{version}<7) {
		$h->{mart_h_ary} = $h->{art_h_ary};
		$h->{mart_f_ary} = [ 'dea_com-count' ];
	}
	# uninstall
	$self->reset_design({no_event => 1});

	# 削除したモジュールを取り除く（別名の「名前,番号」も）
	my $removed = qr/^(?:dem_footer|des_twitter)(?:,\d+)?$/;
	foreach(keys(%$h)) {
		if (ref($h->{$_}) ne 'ARRAY') { next; }
		$h->{$_} = [ grep { $_ !~ $removed } @{$h->{$_}} ];
	}

	return $self->save_design($h);
}

#-------------------------------------------------------------------------------
# ●設定の存在するプラグイン一覧
#-------------------------------------------------------------------------------
sub get_plugins_setting {
	my $self = shift;
	my $set  = $self->{blog};
	my %p;
	foreach(keys(%$set)) {
		if ($_ !~ /^p:([\w\-]+(?:,\d+)?)/) { next; }
		$p{$1}=1;
	}
	return [ sort(keys(%p)) ];
}

#-------------------------------------------------------------------------------
# ●設定の存在するプラグイン一覧
#-------------------------------------------------------------------------------
sub reset_plugins {
	my $self = shift;
	my $ary  = shift || [];

	# delete setting
	my $set = $self->{blog};
	my %n   = map {$_ => 1} @$ary;
	my %del;
	foreach(keys(%$set)) {
		if ($_ !~ /^p:([\w\-]+(?:,\d+)?)/) { next; }
		if (!$n{$1}) { next; }
		$del{$1}=1;
		$self->update_blogset($set, $_, undef);
	}

	my $cnt=0;
	foreach(keys(%del)) {
		$self->reset_plugin_setting($_);
		$cnt++;
	}

	return wantarray ? (0, $cnt) : 0;
}

#-------------------------------------------------------------------------------
# ●design.datの解析
#-------------------------------------------------------------------------------
sub parse_design_dat {
	my $self = shift;
	my $dat  = shift;
	my %h;
	foreach(keys(%$dat)) {
		$h{"${_}_ary"} = [ split(/\n/, $dat->{$_}) ];
	}
	$h{version} = $dat->{version};
	return \%h;
}

#-------------------------------------------------------------------------------
# ●テーマカスタム情報の再生成
#-------------------------------------------------------------------------------
# 色の調整の値（ブログの設定）と今のテーマのCSSから、pub/custom/theme.css を作り直す
sub remake_theme_custom_css {
	my $self  = shift;
	my $theme = $self->{blog}->{theme};
	if (!$theme || !$self->{blog}->{theme_custom}) { return 0; }	# 色の調整を使っていない
	return $self->write_theme_custom_css($theme);
}

################################################################################
# ■データベースがらみサブルーチン
################################################################################
#-------------------------------------------------------------------------------
# ●ブログテーブルの作成
#-------------------------------------------------------------------------------
sub create_tables {
	my $self = shift;
	my $DB = $self->{DB};
	my $r=0;

  { # 記事テーブル
	$r = $DB->create_table_wrapper("art", $self->art_table_info());
	if ($r) { return 100 + $r; }
  }

  { # タグテーブル
	my %info;
	$info{text}    = [ qw(name) ];
	$info{int}     = [ qw(qt upnode priority) ];
	$info{idx}     = [ qw(name qt upnode priority) ];
	$info{unique}  = [ qw(name) ];
	$info{notnull} = [ qw(name qt priority) ];
	$info{ref}     = { upnode => "tag.pkey" };
	$r = $DB->create_table_wrapper("tag", \%info);
	if ($r) { return 200 + $r; }
  }

  { # タグマッチングテーブル
	my %info;
	$info{int}     = [ qw(a_pkey t_pkey) ];
	$info{flag}    = [ qw(a_enable) ];
	$info{idx}     = [ qw(a_pkey t_pkey a_enable) ];
	$info{notnull} = [ qw(a_pkey t_pkey a_enable) ];
	$info{ref}     = { a_pkey => "art.pkey", t_pkey => "tag.pkey"  };
	$r = $DB->create_table_wrapper("tagart", \%info);
	if ($r) { return 300 + $r; }
  }

  { # コメントテーブル
	$r = $DB->create_table_wrapper("com", $self->com_table_info());
	if ($r) { return 800 + $r; }
  }

	# 記事の更新履歴テーブル
	$r = $self->create_rev_table();
	if ($r) { return 900 + $r; }

	# 記事の直前の保存のテーブル
	$r = $self->create_lastrev_table();
	if ($r) { return 1200 + $r; }

	# 記事のリンクテーブル
	$r = $self->create_link_table();
	if ($r) { return 1100 + $r; }

	# ゴミ箱テーブル
	$r = $self->create_trash_tables();
	if ($r) { return 1000 + $r; }

	return 0;
} # End of create_table

#-------------------------------------------------------------------------------
# ●記事テーブル、コメントテーブルの定義
#-------------------------------------------------------------------------------
# ※ゴミ箱テーブルも同じ定義から作る。
#   既存ブログにカラムを追加するとき（sys_update_* の add_column）は、
#   ゴミ箱テーブル（_trash, _trashcom）にも同じカラムを追加すること。
sub art_table_info {
	my $self = shift;
	my %info;
	$info{text}    = [ qw(title parser tags link_key ctype main_image description backlinks) ];
	$info{ltext}   = [ qw(text text_s _text) ];
	$info{int}     = [ qw(yyyymmdd tm update_tm coms coms_all upnode priority) ];
	$info{flag}    = [ qw(enable com_ok nsfw) ];
	$info{idx}     = [ qw(link_key ctype upnode yyyymmdd tm update_tm coms coms_all enable priority) ];
	$info{idx_tdb} = [ qw(title tags) ];
	$info{unique}  = [ qw(link_key) ];
	$info{notnull} = [ qw(enable com_ok coms coms_all yyyymmdd link_key) ];
	$info{ref}     = { };	# upnode => "art.pkey" をすると記事が削除できなくなる
	return \%info;
}
sub com_table_info {
	my $self = shift;
	my %info;
	$info{text}    = [ qw(text email url name id ip host agent a_title a_elink_key) ];
	$info{int}     = [ qw(tm num a_pkey a_yyyymmdd) ];
	$info{flag}    = [ qw(enable hold) ];	# enable:公開の画面に出す（承認済みで記事が公開）、hold:承認待ち
	$info{idx}     = [ qw(name id enable tm a_pkey) ];
	$info{idx_tdb} = [ qw(ip num a_yyyymmdd) ];
	$info{unique}  = [ ];
	$info{notnull} = [ qw(enable text tm a_pkey a_yyyymmdd) ];
	$info{ref}     = { a_pkey => "art.pkey" };
	return \%info;
}
# 定義からカラム名の一覧を得る
sub table_info_cols {
	my ($self, $info) = @_;
	return [ 'pkey', map { @{ $info->{$_} || [] } } qw(text ltext int float flag) ];
}

#-------------------------------------------------------------------------------
# ●ゴミ箱テーブルの作成
#-------------------------------------------------------------------------------
# 記事テーブル、コメントテーブルと同じカラム構成。pkeyは元の記事/コメントのpkey。
# 同じcontent keyの記事を複数入れられるよう、unique制約や参照制約は付けない。
sub create_trash_tables {
	my $self = shift;
	my $DB = $self->{DB};

	my $art = $self->art_table_info();
	push(@{ $art->{int}  }, 'deleted_tm');	# 削除日時
	$art->{idx}     = [ qw(deleted_tm) ];
	$art->{idx_tdb} = [ ];
	$art->{unique}  = [ ];
	$art->{notnull} = [ ];
	$art->{ref}     = { };
	my $r = $DB->create_table_wrapper("trash", $art);
	if ($r) { return 10 + $r; }

	my $com = $self->com_table_info();
	$com->{idx}     = [ qw(a_pkey) ];
	$com->{idx_tdb} = [ ];
	$com->{unique}  = [ ];
	$com->{notnull} = [ ];
	$com->{ref}     = { };
	$r = $DB->create_table_wrapper("trashcom", $com);
	if ($r) { return 20 + $r; }
	return 0;
}

#-------------------------------------------------------------------------------
# ●記事の更新履歴テーブルの作成
#-------------------------------------------------------------------------------
# tm        履歴に追加した日時
# update_tm その版が保存された日時
# ※記事を削除しても履歴は残す（ゴミ箱から戻すため）ので、記事pkeyへの参照は張らない
sub create_rev_table {
	my $self = shift;
	my %info;
	$info{text}    = [ qw(title) ];
	$info{ltext}   = [ qw(_text) ];
	$info{int}     = [ qw(a_pkey tm update_tm) ];
	$info{idx}     = [ qw(a_pkey tm) ];
	$info{notnull} = [ qw(a_pkey tm) ];
	$info{ref}     = { };
	return $self->{DB}->create_table_wrapper("rev", \%info);
}

#-------------------------------------------------------------------------------
# ●記事の直前の保存のテーブルの作成
#-------------------------------------------------------------------------------
# 記事を保存するたびに、保存する前の版を記事ごとに1つだけ入れる（上書き）。
# 更新履歴（rev）はrev_cycleの間は版を入れないので、直前の保存に戻すために使う。
# 列はrevと同じ。記事を削除しても残す（ゴミ箱から戻すため）ので、参照は張らない
sub create_lastrev_table {
	my $self = shift;
	my %info;
	$info{text}    = [ qw(title) ];
	$info{ltext}   = [ qw(_text) ];
	$info{int}     = [ qw(a_pkey tm update_tm) ];
	$info{idx}     = [ qw(a_pkey) ];
	$info{unique}  = [ qw(a_pkey) ];
	$info{notnull} = [ qw(a_pkey tm) ];
	$info{ref}     = { };
	return $self->{DB}->create_table_wrapper("lastrev", \%info);
}

#-------------------------------------------------------------------------------
# ●記事のリンクテーブルの作成
#-------------------------------------------------------------------------------
# a_pkey    リンク元の記事
# link_key  リンク先の記事のlink_key（まだ無い記事も持っておく）
# ※参照元の生成に使う（update_backlinks）。記事を削除した後に消すので、参照は張らない
sub create_link_table {
	my $self = shift;
	my %info;
	$info{text}    = [ qw(link_key) ];
	$info{int}     = [ qw(a_pkey) ];
	$info{idx}     = [ qw(a_pkey link_key) ];
	$info{notnull} = [ qw(a_pkey link_key) ];
	$info{ref}     = { };
	return $self->{DB}->create_table_wrapper("link", \%info);
}

################################################################################
# ■データインポータ
################################################################################
sub art_import {
	my ($self, $form) = @_;
	my $ROBJ = $self->{ROBJ};
	my $DB   = $self->{DB};
	if (! $self->{blog_admin} ) { $ROBJ->message('Operation not permitted'); return 5; }

	#-------------------------------------------------------------
	# セッション開始
	#-------------------------------------------------------------
	my $session = $self->open_session( $form->{snum} );

	# データ形式
	my $type = $form->{type};
	$type =~ s/\W//g;
	my $importer;
	eval { $importer = $ROBJ->loadapp("adiary::Import$type"); };
	if ($@) {
		$ROBJ->message($@);
		$session->msg('Data type error (%s)', $type);
		return -1;
	}

	# ファイル選択チェック
	if (! ref($form->{file}) || ! $form->{file}->{size}) {
		$session->msg('Not selected file'); return -2;
	}
	$session->msg("Import file size: %f KB", int($form->{file}->{size}/1024 + 0.5));

	# ファイルがメモリになかったら読み込む
	if (!$form->{file}->{data}) {
		sysopen(my $fh, $form->{file}->{tmp}, O_RDONLY);
		sysread($fh, $form->{file}->{data}, $form->{file}->{size});
		close($fh);
	}

	# クラスオプション（$type:xxx=val を xxx=val として取り出す）
	my %opt;
	{
		my %h;
		foreach(keys(%$form)) {
			my $x = index($_,':');
			if ($x<0) {		# クラス表記を含まない
				$h{$_}=$opt{$_}=$form->{$_};
				next;
			}
			if (substr($_,0,$x) ne $type) { next; }
			my $y = substr($_,$x);
			$opt{$y} = $form->{$_};
			$h  {$y} = $form->{$_};
		}
		delete $h{file};
		delete $h{action};
		delete $h{ajax};
		delete $h{class};
		foreach(sort(keys(%h))) {
			$session->say("[option] $_=$h{$_}");
		}
	}
	$form = 'undef';	# 間違って -> で参照しないように文字列を入れる

	# 付加タグとデフォルトタグをtrimしておく
	$ROBJ->trim( $opt{append_tags}, $opt{default_tags} );

	# キー重複チェック用
	{
		my $cols = ['pkey', 'link_key'];
		my $data = $DB->select("art", {cols => $cols});
		$opt{unique_pkeys} = { map { $_->{pkey}     => 1 } @$data };
	}

	#-------------------------------------------------------------
	# インポートの実行
	#-------------------------------------------------------------
	$opt{import_arts} = 0;
	$opt{find_arts}   = 0;
	$opt{a_pkeys} = [];
	$opt{c_pkeys} = [];
	# インポート時のupnode対応用
	$opt{pkey2pkey} = {};
	$opt{upnodes}   = [];

	$ROBJ->{Timer} && $ROBJ->{Timer}->start('import');
	my $tr = ! $opt{stop_transaction};	# トランザクションを使用し、高速処理
	if ($tr) {
		$session->say("[DB] BEGIN");
		$DB->begin();
	}
	my $r = $importer->import_arts($self, \%opt, $session);
	if ($r) {
		$session->msg("Error exit(%d)", $r);
		$session->close();
	}

	# upnode対応処理
	$self->import_build_tree($DB, \%opt);

	if ($tr) {
		if ($DB->commit()) {
			$session->say("[DB] ROLLBACK");
			$opt{import_arts} = 0;	# インポート件数=0
		} else {
			$session->say("[DB] COMMIT");
		}
	}
	$session->msg("Import %d articles (find %d articles)", $opt{import_arts}, $opt{find_arts});

	#-------------------------------------------------------------
	# イベント処理
	#-------------------------------------------------------------
	if ($opt{import_arts}) {
		$self->import_events( \%opt );
	}

	#-------------------------------------------------------------
	# インポート終了
	#-------------------------------------------------------------
	$session->msg("Import finish");
	if ($ROBJ->{Timer}) {
		$session->msg("Import time %.2f sec", $ROBJ->{Timer}->stop('import'));
		$session->msg("Total time %.2f sec",  $ROBJ->{Timer}->check());
	}
	$session->close();

	return wantarray ? ($r, $opt{import_arts}) : $r;
}

sub import_build_tree {
	my $self = shift;
	my $DB   = shift;
	my $opt  = shift;
	my $p2p = $opt->{pkey2pkey};
	foreach(@{$opt->{upnodes}}) {
		my $pkey    = $_->{pkey};
		my $up_pkey = $p2p->{ $_->{upnode} };
		if ($up_pkey) {
			$DB->update_match("art", {upnode => $up_pkey}, 'pkey', $pkey);
		}
	}
}

sub import_events {
	my $self = shift;
	my $opt  = shift;
	$self->call_event('IMPORT_AFTER',         $opt->{a_pkeys}, $opt->{c_pkeys});
	$self->call_event('ARTICLE_STATE_CHANGE', $opt->{a_pkeys}, $opt->{c_pkeys});
	$self->call_event('COMMENT_STATE_CHANGE', $opt->{a_pkeys}, $opt->{c_pkeys});
	$self->call_event('ARTCOM_STATE_CHANGE' , $opt->{a_pkeys}, $opt->{c_pkeys});
}

#-------------------------------------------------------------------------------
# ●記事を１件保存する
#-------------------------------------------------------------------------------
# $self->save_article(\%art, \@coms, \@tbs, \%opt, $session);
# Ret:	0:成功  0以外:失敗
#
# $art->{enable}	1:表示許可 0:表示不可
# $art->{year}		1980～（年）
# $art->{mon}		1～12（月）
# $art->{day}		1～31（日）
# $art->{tm}		書き込み日時（UTC）
# $art->{tags}		タグ(「,」区切り）
# $art->{title}		タイトル
# $art->{text}		記事本文（※必須）
# $art->{parser}	パーサー指定
#
# $art->{com_ok}	コメント受け付け
# $art->{allow_com}	※コメント受け付け（互換性のため）
#
# $art->{ctype}		コンテンツタイプ
# $art->{priority}	優先度, 重要度（整数値）
# $art->{upnode}	親記事
# $art->{link_key}	パーマリンク
#
#
# $c = $coms->[$n]	$n 番目の書き込み
# $c->{enable}		コメントが有効か？ 1:enable 0:disable（省略時:1）
# $c->{name}		名前（※必須）
# $c->{text}		コメント本文（※必須） ※タグ無効、改行→<br>に変換される
# $c->{tm}		コメントが投稿された日時（UTC）
# $c->{email}		メールアドレス
# $c->{url}		URL
# $c->{ip}		IPアドレス(optional)
# $c->{host}		HOST名(optional)
# $c->{agent}		USER AGENT(optional)
#
#
# $tb=$tbs->[$n]	$n 番目のトラックバック
# $tb->{enable}		トラックバックが有効か？
# $tb->{blog_name}	トラックバック元のblog名
# $tb->{title}		トラックバックのタイトル
# $tb->{url}		トラックバック元URL（※必須）
# $tb->{tm}		TBが送信された日時（UTC）
# $tb->{author}		元記事の執筆者
# $tb->{excerpt}	概要  ※タグ無効
# $tb->{ip}		IPアドレス
# $tb->{host}		HOST名
# $tb->{agent}		USER AGENT
#
# ※タグを入力する必要のない（入力できない）カラムでは、
# 　&gt; &lt; &quot; を < > " に戻す必要はない。
#
sub save_article {
	my ($self, $art, $coms, $tbs, $opt, $session) = @_;
	my $ROBJ = $self->{ROBJ};
	my $DB   = $self->{DB};

	my $blog   = $self->{blog};
	if (! $self->{blog_admin} ) { $ROBJ->message('Operation not permitted'); return 5; }

	# コメントをインポートしない？
	if ($opt->{no_comment}) { $coms = []; }

	# トラックバックをコメントとしてインポート？
	if (!$opt->{tb_as_comment}) { $tbs = []; }

	# 記事発見数
	$opt->{find_arts}++;

	##############################################################
	# データ整形処理
	##############################################################
	my $now_tm = $ROBJ->{TM};
	# 記法の指定が無い、または選べない記法（4.22で削除した標準記法など）なら、HTML（改行処理）で取り込む
	if ($art->{parser} eq '' || !$ROBJ->check_skeleton("_parser/$art->{parser}")) {
		$art->{parser} = 'simple_br';
	}
	$art->{tm}     ||= $now_tm;

	# タグを設定する
	if ($opt->{force_tag} || $art->{tags} eq '') {
		$art->{tags} = $opt->{default_tags};
	}
	# インポート記事付加タグ
	if ($opt->{append_tags}) {
		$art->{tags} = $art->{tags} eq '' ? $opt->{append_tags} : "$art->{tags},$opt->{append_tags}" ;
	}

	# コメントの投稿時刻
	foreach(@$coms) { $_->{tm} ||= $now_tm; }

	#-------------------------------------------------------------
	# 日付の確認
	#-------------------------------------------------------------
	{
		$art->{tm} = int( $art->{tm} );
		my $year = int( $art->{year} );
		my $mon  = int( $art->{mon}  );
		my $day  = int( $art->{day}  );
		my $err = $self->check_date($year, $mon, $day);
		if ($err ne '') {	# エラーあり
			my $h = $ROBJ->time2timehash( $art->{tm} );
			$art->{year} = $h->{year};
			$art->{mon}  = $h->{mon};
			$art->{day}  = $h->{day};
		}
	}

	#-------------------------------------------------------------
	# pkey, link_key の重複チェック
	#-------------------------------------------------------------
	my $pkey  = $opt->{save_pkey} && $art->{pkey};
	my $pkeys = $opt->{unique_pkeys};
	{
		my $ctype    = $art->{ctype};
		my $priority = int( $art->{priority} );
		my $upnode   = $art->{upnode};
		if ($priority && $ctype eq '') { $art->{ctype}=$ctype='wiki'; }

		# save pkey
		$pkey = ($pkey<1 || ($pkeys->{$pkey} && $opt->{avoid_pkey_collision})) ? 0 : $pkey;
		if ($pkey) {
			if ($pkeys->{$pkey}) {
				$session && $session->msg("'%s' is duplicate : %s", 'pkey', $pkey);
				return 10;
			}
			$pkeys->{$pkey}=1;
		}
	}

	#-------------------------------------------------------------
	# フラグチェック
	#-------------------------------------------------------------
	$art->{com_ok} = defined $art->{com_ok} ? $art->{com_ok} : $art->{allow_com};

	my @flags = qw(enable com_ok);
	foreach(@flags) {
		if (!defined $art->{$_}) { $art->{$_} = $blog->{$_}; }
	}

	#-------------------------------------------------------------
	# 記事の書き込み処理
	#-------------------------------------------------------------
	{
		my %op;
		$op{save_pkey} = $pkey;
		$op{tm} = $art->{tm};
		$op{import} = 1;	# 固定ページのパーマリンクは、元のまま受ける
		my $ret = $self->regist_article( $art, \%op );
		if (!ref($ret)) {
			$session && $session->msg("Save article failed(%d) : %s", $ret, $art->{title} );
			return 11;
		}
		$pkey = $ret->{pkey};
		$pkeys->{ $pkey } = 1;
		push(@{ $opt->{a_pkeys} }, $pkey);

		# upnode対策用の処理
		if ($opt->{upnodes} && $ret->{ctype} && $art->{pkey}) {
			$opt->{pkey2pkey}->{ $art->{pkey}     } = $pkey;
			$opt->{pkey2pkey}->{ $art->{link_key} } = $pkey;
			push(@{$opt->{upnodes}}, {pkey=>$pkey, upnode=>$art->{upnode}});
		}

		# 書込済記事データに置き換える
		$art = $ret;
	}
	#-------------------------------------------------------------
	# 記事保存メッセージ
	#-------------------------------------------------------------
	$session && $session->msg("[import] %s", $art->{title});
	$opt->{import_arts}++;

	my %info;
	##############################################################
	# コメント、トラックバックの処理
	##############################################################
	#---------------------------------------------------
	# コメントとトラックバックを混ぜる
	#---------------------------------------------------
	my @ary = @$coms;
	foreach(@$tbs){
		$_->{_tb}=1;
		push(@ary, $_);
	}
	if (@$tbs) {
		# まぜた場合は時刻でソートする
		@ary = sort {$a->{tm} cmp $b->{tm}} @ary;
	}
	
	#---------------------------------------------------
	# 取り込み処理
	#---------------------------------------------------
	my $com_flag;
	foreach(@ary) {
		# 非公開コメントは廃止したので取り込まない
		if ($_->{hidden}) { next; }
		if ($_->{_tb}) {
			$_->{name} = $_->{author} ne '' ? $_->{author} : '(trackback)';
			my $text = '[Trackback]';
			if ($_->{title} ne '') {
				$text .= ' ' . $_->{title};
			}
			if ($_->{blog_name} ne '') {
				$text .= ' from ' . $_->{blog_name};
			}
			$_->{text} = $text . "\n\n" . $_->{excerpt};
		}
		# 公開設定処理
		$_->{enable} = $_->{enable} ne '' ? $_->{enable} : 1;
		# コメント投稿名
		$_->{name} = $_->{name} ne '' ? $_->{name} : '(no name)';

		#-----------------------------------------------------
		# オプション構成
		#-----------------------------------------------------
		my %op;
		$op{ip}    = $_->{ip};
		$op{host}  = $_->{host};
		$op{agent} = $_->{agent};
		$op{tm}    = $_->{tm};
		$op{num}   = $_->{num};
		if ($opt->{save_com_pkey} && !$_->{_tb}) {
			$opt->{save_pkey} = 1;
		}

		#-----------------------------------------------------
		# 投稿処理
		#-----------------------------------------------------
		my ($r,$c_pkey) = $self->regist_comment( $_, $art, \%op );
		if ($r) {
			my $type = $_->{_tb} ? 'Trackback' : 'Comment';
			$session && $session->msg("$type import failed(%d) : %s", $r, "$art->{yyyymmdd} - $pkey");
		} else {
			# 成功
			push(@{ $opt->{c_pkeys} }, $c_pkey);
			$com_flag = 1;
		}
	}

	if ($com_flag) {
		# 記事のコメント数キャッシュを書き換え
		$self->calc_comments($art->{pkey});
	}

	return 0;
}

#-------------------------------------------------------------------------------
# ●インポートエラー
#-------------------------------------------------------------------------------
sub import_error {
	my $self = shift;
	my $head = shift;
	my $msg  = shift;
	my $ROBJ = $self->{ROBJ};
	if (ref $self->{import_error} ne 'ARRAY') { $self->{import_error}=[]; }
	$msg = $ROBJ->translate($msg, @_);
	$ROBJ->tag_escape($msg);
	$ROBJ->error("$head $msg");
}


################################################################################
# ■外部画像の取り込み
################################################################################
#-------------------------------------------------------------------------------
# ●記事データロード
#-------------------------------------------------------------------------------
sub import_img_init {
	my ($self, $form) = @_;
	my $ROBJ = $self->{ROBJ};
	my $DB   = $self->{DB};
	if (! $self->{blog_admin} ) { $ROBJ->message('Operation not permitted'); return 5; }

	#-------------------------------------------------------------
	# 取得する記事の条件生成
	#-------------------------------------------------------------
	my %q;
	if ($form->{enable_only}) {
		$q{flag} = {enable => 1};
	}
	if ($form->{tag} ne '') {
		#---------------------------------
		# タグ指定
		#---------------------------------
		my $taglist = $self->load_tag_cache();
		my $name2pkey = $taglist->[0];
		my $tag = $taglist->[ $name2pkey->{ $form->{tag} } ];

		# そのタグを持つ記事一覧
		my $arts = $tag->{arts};
		$q{match}->{pkey} = $arts ? $arts : -1;
	}

	#-------------------------------------------------------------
	# 記事の取得
	#-------------------------------------------------------------
	$q{sort} = ['yyyymmdd', 'tm'];	# ソート
	$q{cols} = ['pkey', 'yyyymmdd', 'tm', 'title', 'parser'];

	my $logs = $DB->select("art", \%q);

	if ($form->{html_only}) {
		$logs = [ grep { $_->{parser} =~ /^simple/  } @$logs ];
	}
	return $logs;
}

#-------------------------------------------------------------------------------
# ●記事の画像データを外部ロード
#-------------------------------------------------------------------------------
sub import_img {
	my ($self, $form) = @_;
	my $ROBJ = $self->{ROBJ};
	my $DB   = $self->{DB};
	if (! $self->{blog_admin}) { $ROBJ->message('Operation not permitted'); return 5; }

	my $pkey = int($form->{pkey});

	my $log = $DB->select_match_limit1("art", 'pkey', $pkey);
	if (!$log) { return $ROBJ->message('Article not found.(pkey=%d)', $pkey); return 21; }

	my $tag   = $self->load_tag_escaper();
	my $html  = $tag->parse( $log->{_text} );
	my $media = $form->{media} ? 1 : 0;
	my $base  = $form->{base};
	if ($base !~ m|^(https?://\w+(?:\.\w+)*)/|i) {
		$base = undef;
	}
	my $base0 = $1;		# http://example.com まで

	my $folder= $form->{folder};
	$folder =~ s/%y/substr($log->{yyyymmdd},0,4)/eg;
	$folder =~ s/%m/substr($log->{yyyymmdd},4,2)/eg;

	$self->init_image_dir();
	my $dir  = $self->image_folder_to_dir_and_create( $folder );

	my $blogimg_url = $ROBJ->{ServerURL} . $ROBJ->{Basepath} . $self->blogimg_dir();

	my $msg = '';
	my $http = $ROBJ->loadpm("Base::HTTP");
	my %rep;
	my $error;
	foreach my $e ($html->getAll) {
		my $type = $e->type();
		if ($type ne 'tag') { next; }

		my $tag = $e->tag();
		if (!($tag eq 'img' || $media && ($tag eq 'source' || $tag eq 'audio'))) {
			next;
		}
		my $url_s = $e->attr->{src};
		my $prev  = $e->prev;
		my $url_l = ($prev->tag eq 'a') ? $prev->attr->{href} : '';
		if ($url_l eq $url_s) {
			$url_s = undef;
		}
		$url_s = $url_s =~ m!^(?:|http:|https:)//! ? $url_s : ($base && $url_s ? (substr($url_s,0,1) eq '/' ? $base0 : $base) . $url_s : '');
		$url_l = $url_l =~ m!^(?:|http:|https:)//! ? $url_l : ($base && $url_l ? (substr($url_l,0,1) eq '/' ? $base0 : $base) . $url_l : '');

		my $img_s;
		my $img_l;
		if ($url_s && index($url_s, $blogimg_url) != 0) {
			$img_s = $self->get_imgdata($http, $url_s);
			$msg  .= '  Download ' . ($img_s ? 'success' : 'fail!  ') . ' : ' . $url_s . "\n";
			if ($http->{error}) { $error = $http->{error}; }
		}
		if ($url_l && index($url_l, $blogimg_url) != 0) {
			$img_l = $self->get_imgdata($http, $url_l);
			$msg  .= '  Download ' . ($img_l ? 'success' : 'fail!  ') . ' : ' . $url_l . "\n";
			if ($http->{error}) { $error = $http->{error}; }
		}
		if ($img_s && !$img_l) {
			$url_l = $url_s;
			$img_l = $img_s;
			$url_s = undef;
			$img_s = undef;
		}

		# 保存ファイル名
		my $fname = $url_l =~ m|([^/]*)$| ? $1 : '';
		$ROBJ->tag_unescape($fname);
		$fname =~ s/%([0-9A-Fa-f][0-9A-Fa-f])/$1/g;

		if (!$img_l) { next; }
		my ($r, $saved) = $self->save_image_to_media($dir, $fname, $img_l);
		if ($r) {
			$msg  .= "  Save '$fname' fail!\n";
			next;	# save fail
		}
		# 同じ名前のファイルがあると別名で保存するので、保存した名前で書き換える
		$fname = $saved;
		my $file = $fname;
		$ROBJ->tag_escape($file);
		$file = "$dir$file";

		# サムネイル保存
		my $thumb;
		my $thumb_file = $self->get_thumbnail_file($dir, $fname);
		while ($img_s) {
			if ($url_s !~ /\.jpe?g/i) {
				my ($fh, $file) = $ROBJ->open_tmpfile();
				if (!$fh) { last; }
				syswrite($fh, $img_s, length($img_s));
				close($fh);

				my $img = $self->load_image_magick();
				eval {
					$self->read_image( $img, $file );
					$img->Set( quality => ($self->{media_jpeg_quality} || 80) );
					$img->Write( $thumb_file );
				};
				if ($@) { last; }
				$thumb = 1;
			} else {
				$thumb = $ROBJ->fwrite_lines( $thumb_file, $img_s ) ? 1 : 0;
			}
			last;
		}

		$rep{$url_l} = $file;
		if ($img_s) {
			$rep{$url_s} = $thumb_file;
		}
	}

	#---------------------------------------------------
	# HTMLの書き換え
	#---------------------------------------------------
	my $data  = $self->{blog}->{image_data};
	$data =~ s/%k/$log->{pkey}/g;
	my @ary = split(/\s+/, $data);
	my $data = '';
	foreach(@ary) {
		if ($_ !~ /^([A-Za-z][\w\-]*)=(.*)$/) { next; }
		my $n = $1;
		my $v = $2;
		$ROBJ->tag_escape($v);
		$data .=" data-$n=\"$v\"";
	}

	my $rewrite = 0;
	if (%rep) {
		$log->{_text} =~ s{(<a\b[^>]*?\shref\s*=\s*)(["'])(.*?)\2}{
			my $url = $3;
			if ($rep{$3}) {
				$url = $rep{$url};
				$rewrite++;
			}
			"$1$2$url$2" . ($rep{$3} ? $data : '');
		}iseg;
		$log->{_text} =~ s{(<[^>]*?\ssrc\s*=\s*)(["'])(.*?)\2}{
			my $url = $3;
			if ($rep{$3}) {
				$url = $rep{$url};
				$rewrite++;
			}
			"$1$2$url$2";
		}iseg;

		if ($rewrite) {
			$msg .= "  Rewrite : $rewrite urls\n";
			$self->rebuild_blog({ logs => [ $log ] });
		}
	}
	if ($error) {
		$msg .= "\n(ERROR) $error\n";
	}
	chomp($msg);
	return (0,$msg);
}

#-------------------------------------------------------------------------------
# ●指定したURLの画像データを取得
#-------------------------------------------------------------------------------
sub get_imgdata {
	my $self = shift;
	my $http = shift;
	my ($st, $h, $res) = $http->get(@_);
	if (!$res || $st>299) { return ; }

	return join('', @$res);
}

#-------------------------------------------------------------------------------
# ●画像データをメディア管理に保存
#-------------------------------------------------------------------------------
sub save_image_to_media {
	my $self = shift;
	my $dir  = shift;
	my $name = shift;
	my $data = shift;

	my $h = {
		name => $name,
		size => length($data),
		data => $data
	};
	my $r = $self->do_upload( $dir, $h );
	return wantarray ? ($r, $h->{name}) : $r;	# 保存した名前（別名のこともある）
}

################################################################################
# ■データエクスポート
################################################################################
#-------------------------------------------------------------------------------
# ●エクスポート実行
#-------------------------------------------------------------------------------
sub art_export {
	my ($self, $form) = @_;
	my $ROBJ = $self->{ROBJ};
	my $DB   = $self->{DB};
	if (! $self->{blog_admin} ) { $ROBJ->message('Operation not permitted'); return 5; }

	# 出力形式確認
	my $skel = $form->{file};
	$skel =~ s/\W//g;
	if ($skel eq '') {
		$ROBJ->message('Please select export type(skeleton)');
		return 11;
	}

	# オプション
	my %opt;
	{
		my $type = $form->{type};
		if ($type eq '') {
			$type = $skel;
			$type =~ s/[\d_]//g;
		}
		$opt{type} = $type;

		foreach(keys(%$form)) {
			my $x = index($_, ':');
			if ($x<0) { $opt{$_}=$form->{$_}; next; }
			if (substr($_,0,$x) ne $type) { next; }
			$opt{ substr($_,$x+1) } = $form->{$_};
		}
	}

	#-------------------------------------------------------------
	# 取得する記事の条件生成
	#-------------------------------------------------------------
	my %q;
	my $filename = 'adiary';
	if ($opt{enable_only}) {
		$q{flag} = {enable => 1};
	}
	{
		#---------------------------------
		# 日付指定
		#---------------------------------
		my $year = $opt{year};
		if ($year =~ /^\d\d\d\d$/) {
			$q{min} = {yyyymmdd => "${year}0000"};
			$q{max} = {yyyymmdd => "${year}1231"};
			$filename .= "-$year";
		} elsif ($year =~ m|^(\d\d\d\d)[/-]?(\d?\d)$|) {	# YYYYMM
			my $mon = sprintf("%02d", $2);
			$q{min} = {yyyymmdd => "$1${mon}00"};
			$q{max} = {yyyymmdd => "$1${mon}31"};
			$filename .= "-$1$mon";
		} elsif ($year =~ m|^(\d\d\d\d)(\d\d)(\d\d)$|
		      || $year =~ m|^(\d\d\d\d)[/-](\d?\d)[/-](\d?\d)$|) {	# YYYYMMDD
			my $yyyymmdd = sprintf("$1%02d%02d", $2, $3);
			$q{match}->{yyyymmdd} = $yyyymmdd;
			$filename .= "-$yyyymmdd";
		}
	}
	if ($opt{tag} ne '') {
		#---------------------------------
		# タグ指定
		#---------------------------------
		my $taglist = $self->load_tag_cache();
		my $name2pkey = $taglist->[0];
		my $tag = $taglist->[ $name2pkey->{ $opt{tag} } ];

		# そのタグを持つ記事一覧
		my $arts = $tag->{arts};
		$q{match}->{pkey} = $arts ? $arts : -1;
	}

	# コンテンツタイプ
	if ($opt{article_type} ne '*all*') {
		$q{match}->{ctype} = $opt{article_type};
	}

	#-------------------------------------------------------------
	# 記事の取得
	#-------------------------------------------------------------
	$q{sort} = ['yyyymmdd', 'tm'];	# ソート

	my $logs = $DB->select("art", \%q);
	if ($#$logs == -1) {
		$ROBJ->message('Not exists article');
		return 12;
	}

	#-------------------------------------------------------------
	# エクスポートの実行
	#-------------------------------------------------------------
	$opt{base_filename} = $filename;
	$opt{aobj} = $self;
	$ROBJ->call( $self->{skel_dir} . "_export/$skel", $logs, \%opt );

	return $ROBJ->{export_return};
}

#-------------------------------------------------------------------------------
# ●textの分割・加工処理（エクスポート処理から呼ばれる）
#-------------------------------------------------------------------------------
sub export_text_split {
	my $self = shift;
	my $h    = shift;

	my $parser = $h->{parser};
	if ($parser =~ /^simple/) {
		my $text = $h->{_text};
		my $append;
		if ($text =~ /^(.*?)\n====*\n(.*)/s) {
			$text   = $1;
			$append = $2;
		}
		$h->{body}    = $text;
		$h->{ex_body} = $append;
		$h->{convert_breaks} = 0;
		if ($parser eq 'simple_p' || $parser eq 'simple_br') {
			$h->{convert_breaks} = 1;
		}
	} else {
		my $text = $h->{text};

		# 続きを読む、処理
		my $append;
		if ($text =~ /^(.*?)<!--%SeeMore%-->(.*)$/s) {	# Seemore
			$text   = $1;
			$append = $2;

			if ($text =~ m|^.*<section>(.*)$|si && index($1, '</section>')<=0) {
				$text .= "\n</section>";
			}
			if ($append =~ m|^(.*?)</section>.*$|si && index($1, '<section>')<=0) {
				$append = "<section>\n$append";
			}
		}
		$h->{body}    = $text;
		$h->{ex_body} = $append;
		$h->{convert_breaks} = 0;
	}
	
	# タグの分割
	$h->{tags_ary} = [ split(',', $h->{tags}) ];
	return $h;
}

#-------------------------------------------------------------------------------
# ●ファイル名の加工
#-------------------------------------------------------------------------------
sub export_escape_filename {
	my $self = shift;
	foreach(@_) {
		$_ =~ s![\\/:\*\?\"<>|]!-!g;
	}
	return $_[0];
}

1;
