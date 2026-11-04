use strict;
#-------------------------------------------------------------------------------
# adiary_2.pm (C)nabe@abk
#-------------------------------------------------------------------------------
# ・記事の管理
# ・コメント投稿
# ・RSS生成
#-------------------------------------------------------------------------------
use SatsukiApp::adiary ();
package SatsukiApp::adiary;
################################################################################
# ■情報表示関連
################################################################################
#-------------------------------------------------------------------------------
# ●記事リストのロード
#-------------------------------------------------------------------------------
sub load_arts_list {
	my ($self, $opt) = @_;
	my $ROBJ = $self->{ROBJ};
	my $DB   = $self->{DB};

	my $sort = $opt->{sort};
	my $rev  = $opt->{rev};

	# sortのチェック
	my %a = ('enable'=>1,'yyyymmdd'=>1,'ctype'=>1,'tm'=>1,'update_tm'=>1,'coms'=>1,'coms_all'=>1,'title'=>1);
	$sort =~ s/\W//g;
	if (!$a{$sort} || $sort eq '') { $sort='yyyymmdd'; }
	$rev = ($rev eq '' || $rev) ? 1 : 0;

	my %h;
	$h{sort} = [$sort];
	$h{sort_rev} = [$rev];
	if ($sort ne 'yyyymmdd') {
		push(@{$h{sort}}, 'yyyymmdd');
		push(@{$h{sort_rev}}, $rev);
	}
	if ($sort ne 'tm') {
		push(@{$h{sort}}, 'tm');
		push(@{$h{sort_rev}}, $rev);
	}
	# 検索
	if ($opt->{q} !~ /^\s*$/) {
		$h{search_words} = [split(/\s+/, $opt->{q})];
		$h{search_cols}  = ['title', 'tags'];
		# エスケープした状態で保存されているのでエスケープして検索する必要がある
		$ROBJ->tag_escape(@{ $h{search_words} });
	}
	# 種類で絞り込む（art:記事だけ、page:ページだけ、それ以外はすべて）
	my $type = $opt->{type};
	if ($type eq 'art') {
		$h{match}     = { ctype => '' };
	} elsif ($type eq 'page') {
		$h{not_match} = { ctype => '' };
	} else {
		$type = '';
	}

	# オフセット、ロード数
	if ($opt->{offset}) {
		$h{offset} = int($opt->{offset});
	}
	if ($opt->{loads}) {
		$h{limit} = int($opt->{loads});
	}

	# 公開・非公開で絞り込む（1:公開だけ、0:非公開だけ、draft:下書きだけ、それ以外は下書きも含めてすべて）
	my $enable = $opt->{enable};
	if ($enable ne '1' && $enable ne '0' && $enable ne 'draft') { $enable = ''; }

	# ロード対象記事オプション
	if (! $self->{blog_admin}) {
		$h{flag} = {enable => 1};
	} elsif ($opt->{draft_only} || $enable eq 'draft') {
		$h{is_null} = ['tm'];
	} elsif (!$opt->{load_draft} && $enable ne '') {
		# 公開・非公開で絞るときは下書きを除く（下書きは非公開として保存されている）
		$h{not_null} = ['tm'];
	}
	if ($self->{blog_admin} && ($enable eq '1' || $enable eq '0')) {
		$h{flag} = {enable => int($enable)};
	}

	# ロードカラム
	$h{cols} = [qw(pkey link_key title tags ctype yyyymmdd tm update_tm coms coms_all enable)];

	my ($logs,$hits) =  $DB->select("art", \%h);

	my %name;
	my %ctype;
	foreach(@$logs) {
		$self->post_process_link_key( $_ );
	}

	my %ret;
	$ret{hits} = $hits;
	$ret{sort} = $sort;
	$ret{rev}  = $rev;
	$ret{type} = $type;
	$ret{enable} = $enable;
	return wantarray ? ($logs, \%ret) : $logs;
}

#-------------------------------------------------------------------------------
# ●コメントリストのロード
#-------------------------------------------------------------------------------
sub load_coms_list {
	my ($self, $opt) = @_;
	my $ROBJ = $self->{ROBJ};
	my $DB   = $self->{DB};

	my $sort = $opt->{sort};
	my $rev  = $opt->{rev};

	# sortのチェック
	my %a = ('hold'=>1,'tm'=>1,'name'=>1,'a_yyyymmdd'=>1);
	$sort =~ s/\W//g;
	if (!$a{$sort} || $sort eq '') { $sort='tm'; }
	$rev = ($rev eq '' || $rev) ? 1 : 0;

	my %h;
	$h{sort} = [$sort];
	$h{sort_rev} = [$rev];

	# オフセット、ロード数
	if ($opt->{offset}) {
		$h{offset} = int($opt->{offset});
	}
	if ($opt->{loads}) {
		$h{limit} = int($opt->{loads});
	}

	# 承認待ちかどうかで絞り込む（1:承認待ちだけ、0:承認済みだけ、それ以外はすべて）
	my $hold = $opt->{hold};
	if ($hold ne '1' && $hold ne '0') { $hold = ''; }

	# ロード対象記事オプション
	if (! $self->{blog_admin}) {
		$h{flag} = {enable => 1};
	} elsif ($hold eq '1') {
		$h{flag} = {hold => 1};
	} elsif ($hold eq '0') {
		$h{not_match} = {hold => 1};	# holdが無い頃のコメントは空なので、1でないものを選ぶ
	}

	my ($logs,$hits) =  $DB->select("com", \%h);

	foreach(@$logs) {
		$_->{text_nobr} = $_->{text};
		$_->{text_nobr} =~ s/<br>/ /g;
	}
	$self->set_comment_by_admin($logs);

	my %ret;
	$ret{hits} = $hits;
	$ret{sort} = $sort;
	$ret{rev}  = $rev;
	$ret{hold} = $hold;
	return wantarray ? ($logs,\%ret) : $logs;
}

################################################################################
# ■編集・執筆関連
################################################################################
#-------------------------------------------------------------------------------
# ●記事を書く／編集する
#-------------------------------------------------------------------------------
sub edit_article {
	my ($self, $form) = @_;
	my $ROBJ = $self->{ROBJ};

	# 書き込み権限確認
	my $blog = $self->{blog};
	if (! $self->{blog_admin}) { $ROBJ->message('Operation not permitted'); return 5; }

	#-----------------------------------------------------------------------
	# データチェックなど
	#-----------------------------------------------------------------------
	my $ping    = $form->{ping}    ? 1:0;

	# 日付の分解
	if (exists $form->{ymd}) {
		my ($y,$m,$d) = split(m|[/-]|, $form->{ymd});
		if ($y =~ /^(\d\d\d\d)(\d\d)(\d\d)$/) {
			$y = $1; $m = $2; $d = $3;
		}
		$form->{year} = $y;
		$form->{mon}  = $m;
		$form->{day}  = $d;
	}

	# タグの解析
	if (exists $form->{tag_ary}) {
		$form->{tags} = join(',', @{ $form->{tag_ary} });
	}

	my %opt;
	$opt{edit_pkey} = $form->{edit_pkey_int};

	# ほかの画面（別のタブや端末）で先に保存されていたら、保存しない
	# ※プラグインに影響しないよう、イベントより前で確認する
	if ($opt{edit_pkey} && $form->{edit_digest} ne ''
	 && $form->{edit_digest} ne $self->article_digest($opt{edit_pkey})) {
		$ROBJ->message('This article has already been saved on another screen');
		return 6;
	}

	# イベント呼び出し
	my $er = $self->call_event('ARTICLE_BEFORE', $form);
	if ($er) { return; }
	if ($opt{edit_pkey})  { $er = $self->call_event('ARTICLE_BEFORE_EDIT', $form); }
			 else { $er = $self->call_event('ARTICLE_BEFORE_POST', $form); }
	if ($er) { return }

	#-----------------------------------------------------------------------
	# 書き込み
	#-----------------------------------------------------------------------
	my ($art, $elink_key) = $self->regist_article($form, \%opt);
	if (!ref($art)) {
		# エラー
		return $art;
	}

	#-----------------------------------------------------------------------
	# 後処理
	#-----------------------------------------------------------------------
	$art->{elink_key} = $elink_key;
	$art->{absolute_url}  = $ROBJ->{ServerURL} . $self->{myself2} . $elink_key;
	$art->{first_visible} = $opt{first_visible};

	# イベント呼び出しと固定の後処理
	$self->call_event('ARTICLE_AFTER', $art, $form);
	if ($opt{edit_pkey})  { $self->call_event('ARTICLE_AFTER_EDIT', $art, $form); }
			 else { $self->call_event('ARTICLE_AFTER_POST', $art, $form); }

	$self->call_event('ARTICLE_STATE_CHANGE', [ $art->{pkey} ], !$opt{tag_state_change});

	if ($opt{comment_edit}) {
		$self->call_event('COMMENTS_EDIT', [ $art->{pkey} ]);
		$self->call_event('COMMENT_STATE_CHANGE', [ $art->{pkey} ]);
	}
	$self->call_event('ARTCOM_STATE_CHANGE', [ $art->{pkey} ]);

	# 初公開
	if ($opt{first_visible}) {
		if ($form->{ping}) {
			$ROBJ->message("Ping sending");
			$self->call_event('ARTICLE_FIRST_VISIBLE_PING', $art, $form);
		}
		$self->call_event('ARTICLE_FIRST_VISIBLE', $art, $form);
	}

	# 正常終了
	return wantarray ? (0, $art) : 0;
}

#-------------------------------------------------------------------------------
# ●記事を登録する
#-------------------------------------------------------------------------------
# opt.edit_pkey		編集対象記事
# opt.iha_default	ip/host/agentのデフォルト値
# opt.save_pkey		pkeyを指定して保存する
# opt.tm		tmを直接指定する
#ret:
#	opt.first_visible	初めての公開
#	opt.comment_edit	コメントのキャッシュ情報を書き換えた
#	opt.comment_disable	コメントが非表示になった可能性がある
#
sub regist_article {
	my ($self, $form, $opt) = @_;
	my $ROBJ = $self->{ROBJ};
	my $DB   = $self->{DB};
	my $blog = $self->load_blogset();
	if (!$blog) {
		$ROBJ->message("Blog not found");
		return -1;
	}
	$ROBJ->clear_form_error();

	#-------------------------------------------------------------
	# フラグ
	#-------------------------------------------------------------
	my %art;
	$art{enable} = $form->{enable}  ? 1 : 0;
	$art{com_ok} = $form->{com_ok}  ? 1 : 0;
	$art{nsfw}   = $form->{nsfw}    ? 1 : 0;

	#-------------------------------------------------------------
	# 日付
	#-------------------------------------------------------------
	my $now   = $ROBJ->{Now};
	my $year  = int($form->{year}) || $self->{now}->{year};
	my $mon   = int($form->{mon})  || $self->{now}->{mon};
	my $day   = int($form->{day})  || $self->{now}->{day};
	my $r = $self->check_date($year, $mon, $day);
	if ($r ne '') {
		$ROBJ->form_error('ymd', $r);
	}
	$art{yyyymmdd} = sprintf("%04d%02d%02d", $year, $mon, $day);

	#-------------------------------------------------------------
	# テキスト
	#-------------------------------------------------------------
	my $title = $form->{title};
	my $tags = $form->{tags};
	$ROBJ->normalize_string($title, $tags);
	$ROBJ->tag_escape_amp($title, $tags);
	if ($title =~ /^\s*$/) {	# タイトルがない場合、タイトルを日付にする
		$title = sprintf("%04d-%02d-%02d", $year, $mon, $day);
	}
	$art{title}= $title;

	#-------------------------------------------------------------
	# タグ
	#-------------------------------------------------------------
	my @tag = $self->normalize_tag($tags);
	$art{tags} = $tags = join(",",@tag);

	#-------------------------------------------------------------
	# 古い記事内容を取得
	#-------------------------------------------------------------
	my $old = {};
	my $edit_pkey = int($opt->{edit_pkey});
	if ($edit_pkey) {
		$old = $DB->select_match_limit1("art", 'pkey', $edit_pkey);
		if (! $old) {
			$ROBJ->form_error('edit_pkey', "Can't find the article (key: %d)", $edit_pkey);
			return 10;
		}
	}

	#-------------------------------------------------------------
	# コンテンツタイプ処理
	#-------------------------------------------------------------
	my $ctype = $form->{ctype};
	$ctype =~ s/[^\w\-]//g;
	if ($ctype ne '') {
		# link_key/upnode の設定	※この２つは escpae しない
		my $link_key = $form->{link_key} || $form->{link_key_txt};
		# 前後の空白を除去
		$ROBJ->normalize_string($link_key);

		# 特殊文字除去		※ここを変更したら contents_edit も変更すること
		if ($link_key =~ /^["',]/) {
			$ROBJ->form_error('link_key', 'Can not use character "%s" in content key', '"\',');
		} elsif ($link_key =~ m!((?:^|/)\.+/)!) {
			$ROBJ->form_error('link_key', 'Can not use string "%s" in content key', "$1");
		} elsif ($link_key =~ /^\s*$/) {
			$ROBJ->form_error('link_key', 'Content key is empty');
		} elsif ($link_key =~ m|^0\d*$|) {
			$ROBJ->form_error('link_key', 'Content key can not numbers starting with "0"');
		} elsif (my @err = $self->check_link_key_path($link_key)) {
			$ROBJ->form_error('link_key', @err);
		}

		# link_key の重複回避
		my $cons = $self->load_contents_cache();
		my %h = map { $cons->{$_}->{link_key} => 1 } keys(%$cons);
		my $ary = $DB->select("art", {	# 非公開記事
			flag => {enable => 0},
			not_match => {ctype => ''},
			cols => ['link_key']
		});
		foreach(@$ary) {
			$h{ $_->{link_key} } = 1;
		}
		delete $h{ $old->{link_key} };	# この記事の旧keyを削除
		if ($h{$link_key}) {
			my $i=2;
			while ($h{"$link_key$i"}) { $i++; }
			$i && ($link_key .= "$i");
		}

		# upnode判定
		my $upnode = int($form->{upnode});
		if ($upnode && !$cons->{$upnode}) {
			$upnode = 0;
		}

		# 自己参照防止
		if ($upnode eq $link_key) { $upnode=""; }

		$art{link_key} = $link_key;
		$art{upnode}   = $upnode;
		$art{priority} = int($form->{priority});

		# ctype
		$ctype = 'wiki';
	}
	$art{ctype} = $ctype;
	if ($ctype eq '') {
		# 通常のblog記事
		$art{priority} = 0;
		$art{upnode}   = undef;
	}

	#-------------------------------------------------------------
	# エラー処理
	#-------------------------------------------------------------
	if ($ROBJ->form_error()) { return 2; }

	#-------------------------------------------------------------
	# 記事pkey生成
	#-------------------------------------------------------------
	my $pkey = $edit_pkey;
	if (!$pkey) {	# 記事の新規作成
		if ($opt->{save_pkey}) {
			$pkey = int($opt->{save_pkey});
		} else {
			$pkey = $DB->generate_pkey("art");
			if (!$pkey) {
				$ROBJ->message('Article post failed');
				return 9;
			}
		}
		# 初期値設定
		$art{coms}     = 0;
		$art{coms_all} = 0;
	}

	#-------------------------------------------------------------
	# 時刻設定と記事の初公開判定
	#-------------------------------------------------------------
	my $first_visible;
	# 最終更新日時。既存の記事で「更新日時を変えない」なら変えない（誤字の直しなど、更新として扱いたくないとき。Lyndbaumと同じ）
	if (!$edit_pkey || !$form->{keep_update_tm}) {
		$art{update_tm} = $ROBJ->{TM};
	}

	if ($form->{draft}) {
		$art{enable} = 0;
		$art{tm} = undef;
	} elsif ($art{enable} && !$old->{tm}) {
		$first_visible=1;
		$opt->{first_visible}=1;
		$art{tm} = $opt->{tm} || $ROBJ->{TM};
	} elsif (!$edit_pkey) {
		$art{tm} = $opt->{tm} || $ROBJ->{TM};

	} elsif (!$form->{draft} && !$art{enable} && !$old->{tm}) {
		# 下書きを非公開で保存したとき。
		# → 初公開してすぐ非公開にしたと解釈する。
		$art{tm} = $opt->{tm} || $ROBJ->{TM};
	}

	#-------------------------------------------------------------
	# link_keyの生成
	#-------------------------------------------------------------
	if ($ctype eq '') {
		$art{link_key} = "0$pkey";
	}
	my $elink_key = $art{link_key};
	$self->link_key_encode( $elink_key );

	#-------------------------------------------------------------
	# パーサー処理
	#-------------------------------------------------------------
	my $_text  = $form->{body_txt} ne '' ? $form->{body_txt} : $form->{text};
	$_text =~ s/^(.*?)\n*$/$1/s;	# 行末の改行を取る

	my $parser_name = $form->{parser};
	$art{parser} = $parser_name;

	my ($text, $short);
	if ($parser_name ne '') {
		my $parser = $self->load_parser( $parser_name );
		if (! ref($parser)) {
			$ROBJ->message("Load parser '%s' failed", $parser_name);
			return 3;
		}

		# パース準備
		$parser->{thisurl}  = $self->{myself2} . $elink_key;
		$parser->{thispkey} = $pkey;
		# 識別子の無い見出しに新しい識別子を書き足す（見出しの文字を変えてもIDが変わらないように）
		if ($parser->can('add_heading_ids')) {
			$_text = $parser->add_heading_ids( $_text );
		}
		($text, $short) = $parser->parse( $_text );
	} else {
		$text = "<section>\n$_text\n</section>";
	}
	if ($short eq '') { $short = $text; }

	# 許可タグ以外の除去処理
	my $escape = $self->load_tag_escaper( 'article' );
	$text  = $escape->escape($text);
	$escape->set_remove_attr('id');
	$short = $escape->escape($short);
	$escape->set_remove_attr();

	# 値保存
	$art{_text}  = $_text;		# source text
	$art{text}   = $text;
	$art{text_s} = ($text eq $short) ? '' : $short;

	# アイキャッチ画像（OGP）。編集画面で選んだものだけを使い、本文からは拾わない
	$self->set_description(\%art, $self->get_main_image_from_input($form->{ogp}));
	#-------------------------------------------------------------
	# DBに書き込み
	#-------------------------------------------------------------
	if ($edit_pkey) {
		my $r = $DB->update_match("art", \%art, 'pkey', $pkey);
		if (!$r) {
			$ROBJ->message('Article edit failed');
			return 11;
		}
		$art{pkey} = $pkey;

		# 本文かタイトルが変わったら、変更前の版を履歴に残す
		if ($old->{_text} ne $art{_text} || $old->{title} ne $art{title}) {
			$self->save_revision($old);
		}
	} else {
		$art{pkey} = $pkey;
		my $r = $DB->insert("art", \%art);
		if (!$r) {
			$ROBJ->message('Article post failed');
			return 12;
		}
	}

	#-------------------------------------------------------------
	# 変更があった場合のコメントデータの書き換え
	#-------------------------------------------------------------
	if ($edit_pkey) {
		my %update;
		if (!$art{enable}  && $old->{enable})   { $update{enable}      = 0; }
		if ($art{title}    ne $old->{title})    { $update{a_title}     = $art{title}; }
		if ($art{yyyymmdd} ne $old->{yyyymmdd}) { $update{a_yyyymmdd}  = $art{yyyymmdd}; }
		if ($art{link_key} ne $old->{link_key}) { $update{a_elink_key} = $elink_key; }

		# コメントの書き換え
		if (%update && $old->{coms_all}) {
			my $r = $DB->update_match("com", \%update, 'a_pkey', $pkey);
			if ($r) {
				$opt->{comment_edit}    = 1;
				$opt->{comment_disable} = exists($update{enable});
			 }
		}
		# 公開にしたら、承認済みのコメントを表示に戻す
		if ($art{enable} && !$old->{enable} && $old->{coms_all}) {
			my $r = $DB->update_match("com", { enable => 1 }, 'enable', 0, '-hold', 1, 'a_pkey', $pkey);
			if ($r) { $opt->{comment_edit} = 1; }
		}
		if ($art{enable} != $old->{enable} && $opt->{comment_edit}) {
			$self->calc_comments($pkey);
		}
	}

	#-------------------------------------------------------------
	# タグ情報の書き換え
	#-------------------------------------------------------------
	if ($old->{tags} ne $tags || $old->{enable} != $art{enable}) {
		my $pkeys = $self->regist_tags(\@tag);
		$edit_pkey && $DB->begin();
		if (ref($pkeys)) {
			if ($edit_pkey) {
				$DB->delete_match("tagart", 'a_pkey', $pkey);
			}
			foreach(@$pkeys) {
				$DB->insert("tagart", {
					'a_pkey'   => $pkey,
					'a_enable' => $art{enable},
					't_pkey'   => $_
				});
			}
		}
		$edit_pkey && $DB->commit();
		$opt->{tag_state_change}=1;
	}

	return wantarray ? (\%art, $elink_key) : \%art;	# 書き込み成功
}

#-------------------------------------------------------------------------------
# ●コンテンツkeyがURLとして使えるか
#-------------------------------------------------------------------------------
# 使えなければ、form_errorに渡すメッセージと引数を返す
#
# ・/で始まるkeyや、://を含むkeyは、URLとして組み立てられない
# ・数字だけのkeyは、記事番号（0始まり）か日付として解釈される
# ・&で始まるkeyは、コンテンツとして解釈されない
# ・先頭の階層がadiaryの置き場所にあるファイルやフォルダと同じだと、
#   Webサーバーがファイルを先に返すか、アクセスを拒否する
# ・nginxの設定（location /data、/__cache、~ \.cgi$）で拒否されるkey
#   locationは前方一致なので、dataや__cacheで始まるkeyはすべて拒否される
#
sub check_link_key_path {
	my ($self, $link_key) = @_;
	if ($link_key =~ m|^/|) {
		return ('Can not use character "%s" in content key', '/');
	}
	if ($link_key =~ m|://|) {
		return ('Can not use string "%s" in content key', '://');
	}
	if ($link_key =~ /^\d+$/) {
		return ('Content key can not be only numbers');
	}
	if ($link_key =~ /^&/) {
		return ('Can not use character "%s" in content key', '&');
	}
	if ($link_key =~ /^(data|__cache)/) {
		return ('Content key can not start with "%s"', $1);
	}
	if ($link_key =~ /(\.cgi)$/) {
		return ('Content key can not end with "%s"', $1);
	}
	my $top = $link_key =~ m|^([^/]+)| ? $1 : '';
	my %files = map { $_ => 1 } @{ $self->{ROBJ}->search_files('./', { dir => 1, all => 1 }) };	# フォルダは末尾に/が付く
	if ($files{$top} || $files{"$top/"}) {
		return ('"%s" is used by the system and can not be the top of a content key', $top);
	}
	return;
}

#-------------------------------------------------------------------------------
# ●編集画面で選んだメイン画像を取得
#-------------------------------------------------------------------------------
sub get_main_image_from_input {
        my ($self, $ogp) = @_;

        if ($ogp =~ /:([^:]+)/) {
			# 記法URLがあるとき(基本的にOGP欄を書き換えたとき)
			my @img_parts = $ogp =~ /:([^:]+)/g;
			return $img_parts[1] . $img_parts[2];
		} elsif ($ogp =~ /^[^:]+$/) {
			# 画像URLがあるとき(基本的に編集時)
			return $ogp;
        } else {
			# 画像なし
			return '';
        }
}

################################################################################
# ■記事の更新履歴
################################################################################
#-------------------------------------------------------------------------------
# ●履歴の保存
#-------------------------------------------------------------------------------
# $old : 更新前の記事データ
#
# PukiWikiのバックアップと同様に、前回履歴に追加してからrev_cycle分以内なら
# 追加しない（連続した保存を1つの版にまとめる）。rev_maxを超えた古い版は削除する。
#
sub save_revision {
	my ($self, $old) = @_;
	my $ROBJ = $self->{ROBJ};
	my $DB   = $self->{DB};
	if ($self->{require_update}) { return; }	# 履歴テーブル未作成

	my $blog  = $self->load_blogset();
	my $cycle = $blog->{rev_cycle} eq '' ? 180 : int($blog->{rev_cycle});
	my $max   = $blog->{rev_max}   eq '' ? 120 : int($blog->{rev_max});
	my $a_pkey= $old->{pkey};
	my $now   = $ROBJ->{TM};

	if ($cycle > 0) {
		my $last = $DB->select_match_limit1("rev", 'a_pkey', $a_pkey, '*sort', '-tm', '*cols', ['tm']);
		if ($last && $now - $last->{tm} < $cycle * 60) { return; }
	}

	$DB->insert("rev", {
		a_pkey    => $a_pkey,
		tm        => $now,
		update_tm => $old->{update_tm} || $old->{tm},
		title     => $old->{title},
		_text     => $old->{_text}
	});

	# 上限を超えた古い版を削除（0なら無制限）
	if ($max > 0) {
		my $revs = $DB->select_match("rev", 'a_pkey', $a_pkey, '*sort', '-tm', '*sort', '-pkey', '*cols', ['pkey']);
		if ($#$revs >= $max) {
			my @del = map { $_->{pkey} } @$revs[$max .. $#$revs];
			$DB->delete_match("rev", 'pkey', \@del);
		}
	}
}

#-------------------------------------------------------------------------------
# ●履歴一覧の取得（json）
#-------------------------------------------------------------------------------
sub load_revisions_json {
	my ($self, $a_pkey) = @_;
	my $DB = $self->{DB};
	$a_pkey = int($a_pkey);
	if (!$a_pkey || !$self->check_editor($a_pkey)) { return; }

	my $revs = $DB->select_match("rev", 'a_pkey', $a_pkey, '*sort', '-tm', '*sort', '-pkey',
		'*cols', ['pkey', 'tm', 'update_tm', 'title', '_text']);
	foreach(@$revs) {
		my $text = $_->{_text};
		utf8::decode($text);
		$_->{length} = length($text);
	}
	return $self->generate_json($revs, ['pkey', 'tm', 'update_tm', 'title', 'length']);
}

#-------------------------------------------------------------------------------
# ●履歴1件の取得（json）
#-------------------------------------------------------------------------------
sub load_revision_json {
	my ($self, $pkey) = @_;
	my $DB = $self->{DB};
	my $rev = $DB->select_match_limit1("rev", 'pkey', int($pkey));
	if (!$rev || !$self->check_editor($rev->{a_pkey})) { return; }

	my $ROBJ = $self->{ROBJ};
	my @ary = map { "\"$_\": " . $ROBJ->json_encode($rev->{$_}) } qw(pkey a_pkey tm update_tm title);
	push(@ary, '"text": ' . $ROBJ->json_string($rev->{_text}));
	return '{' . join(', ', @ary) . '}';
}

#-------------------------------------------------------------------------------
# ●今の記事の取得（json）
#-------------------------------------------------------------------------------
# 編集画面で保存する前に、ほかの画面で先に保存されていないかを見るため
sub load_article_now_json {
	my ($self, $pkey) = @_;
	$pkey = int($pkey);
	if (!$pkey || !$self->check_editor($pkey)) { return; }
	my $art = $self->{DB}->select_match_limit1("art", 'pkey', $pkey);
	if (!$art) { return; }

	my $ROBJ = $self->{ROBJ};
	my @ary = map { "\"$_\": " . $ROBJ->json_encode($art->{$_}) } qw(pkey update_tm title);
	push(@ary, '"digest": "' . $self->article_digest($art) . '"');
	push(@ary, '"text": ' . $ROBJ->json_string($art->{_text}));
	return '{' . join(', ', @ary) . '}';
}

#-------------------------------------------------------------------------------
# ●記事の中身の要約
#-------------------------------------------------------------------------------
# 編集画面に入れておき、保存するときに今の記事と比べて、
# ほかの画面（別のタブや端末）で先に保存されていないかを見る。
# 記事一覧やコンテンツの編集はupdate_tmを変えずに書き換えるので、中身で比べる。
# コメント数や変換後の本文は、記事を書き換えなくても変わるので入れない。
my @DigestCols = qw(title _text tags parser enable yyyymmdd tm update_tm com_ok nsfw
		    ctype link_key upnode priority main_image description);
sub article_digest {
	my ($self, $art) = @_;
	if (!ref $art) {
		$art = $self->{DB}->select_match_limit1("art", 'pkey', int($art));
		if (!$art) { return ''; }
	}
	my $str = join("\0", map { $art->{$_} } @DigestCols);
	utf8::encode($str) if utf8::is_utf8($str);
	require Digest::MD5;
	return Digest::MD5::md5_hex($str);
}

#-------------------------------------------------------------------------------
# ●記事の概要を生成
#-------------------------------------------------------------------------------
sub set_description {
	my ($self, $h, $img) = @_;
	my $ROBJ = $self->{ROBJ};
	my $text = $h->{text};

	$text = substr($text, 0, 4096);		# 長文への対策
	$ROBJ->tag_delete($text);
	$text =~ s/\s+/ /g;
	$text =~ s/^ //;
	$text =~ s/ $//;
	$h->{description} = $self->string_clip($text, $self->{blog}->{desc_len} || 64);
	if ($img ne '') {
		$h->{main_image} = $img;
	} else {
		$h->{main_image} = '';
	}
}

#-------------------------------------------------------------------------------
# ●メイン画像の取得
#-------------------------------------------------------------------------------
sub get_main_image_size {
	my $self = shift;
	my $art  = shift;
	my $ROBJ = $self->{ROBJ};

	my $img  = $art->{main_image};
	if (!$img || $art->{main_image_w} && $art->{main_image_h}) {
		return $img;
	}

	my $im = $self->load_image_magick();
	if (!$im) { return; }

	$img =~ s/\?.*//;

	my $file = $img;
	$file =~ s/%([0-9A-Fa-f][0-9A-Fa-f])/chr(hex($1))/eg;
	$file =~ s|^/+||g;
	$file =~ s|\.+/||g;

	$self->read_image( $im, $self->blogimg_dir() . $file );
	my ($w, $h) = $im->Get('width', 'height');

	$art->{main_image_w} = $w;
	$art->{main_image_h} = $h;

	# save
	my $DB = $self->{DB};
	$DB->update_match("art", {
		main_image => "$img?$w,$h"
	}, 'pkey', $art->{pkey});
	return $img;
}

#-------------------------------------------------------------------------------
# ●更新通知Pingの送信
#-------------------------------------------------------------------------------
sub send_update_ping {
	my $self = shift;
	my ($art, $form) = @_;
	if (!$form->{ping}) { return 0; }

	my $ROBJ = $self->{ROBJ};
	my $blog = $self->{blog};
	my @servers = split("\n", $self->{sys}->{ping_servers_txt});

	# 更新通知情報
	my %ping;
	$ping{blog_name} = $blog->{blog_name};	# blogタイトル
	$ping{url}       = $ROBJ->{ServerURL} . $self->{myself};
	$ping{rssurl}    = $ROBJ->{ServerURL} . $ROBJ->{Basepath} . $self->{pub_dir} . $self->load_rss_files()->[0];
	$ping{art_title} = $art->{title};

	# see http://www.xmlrpc.com/weblogsCom
	my $jcode;
	my $system_coding = $ROBJ->{SystemCode};
	if ($system_coding ne 'UTF-8') {
		$jcode = $ROBJ->load_codepm();
		$ping{blog_name} = $jcode->from_to($ping{blog_name}, $system_coding, 'UTF-8');
		$ping{art_title} = $jcode->from_to($ping{art_title}, $system_coding, 'UTF-8');
	}
	my $send;
	foreach(@servers) {
		$_ =~ s/[\r\n]+$//g;
		if ($_ eq '' || substr($_, 0, 1) eq '#') { next; }
		$ping{ping_server} = $_;
		my $xml = $self->send_weblogUpdates_Ping(\%ping);
		if (!ref $xml) {
			$ROBJ->notice('Error : %s (from %s)', $xml, $_);
			next;
		}
		if (! exists $xml->{flerror}) {
			$ROBJ->notice('Error : Illegal response "%s". (Is it ping server?)', $_);
			next;
		}
		if ($xml->{flerror} || $xml->{faultCode}) {
			my $err_msg = $xml->{message} || $xml->{faultString};
			$jcode && $jcode->from_to(\$err_msg, 'UTF-8', $ROBJ->{SystemCode});
			$ROBJ->notice('Error : %s (from %s)', $err_msg, $_);
			next;
		}
		my $msg = $xml->{message};
		$jcode && $jcode->from_to(\$msg, 'UTF-8', $ROBJ->{SystemCode});
		$ROBJ->notice("Ping sended : %s (from %s)", $msg, $_);
	}
	return 0;
}
#-------------------------------------------------------------------------------
# ●更新通知Pingを送信（拡張仕様準拠）
#-------------------------------------------------------------------------------
# Extended Ping XML-RPC Request
#	$data->{ping_server}	PingサーバURL
#	$data->{blog_name}	blogのタイトル
#	$data->{url}		blogのURL
#	$data->{rssurl}		RSSのURL
# 参考にした資料(Thanks)
#	http://isnot.jp/?p=XML-RPC%A1%F8%B9%B9%BF%B7Ping%A4%CE%C1%F7%BF%AE
#
sub send_weblogUpdates_Ping {
	my ($self, $data) = @_;
	my $ROBJ = $self->{ROBJ};

	# ライブラリロード
	my $http = $ROBJ->loadpm('Base::HTTP');
	$http->set_timeout( $self->{sys}->{http_timeout} );

	# option load
	my $post_url = $data->{ping_server};
	my ($option, $timeout);
	($post_url, $option) = split('#', $post_url);
	($option, $timeout)  = split(',', $option);
	if (0 < $timeout && $timeout < 61) { $http->set_timeout( $timeout ); }

	#-------------------------------------------------------------
	# POST bodyの生成
	#-------------------------------------------------------------
	my $url       = $data->{url};
	my $blog_name = $data->{blog_name};
	my $rssurl    = $data->{rssurl};
	my $method    = "weblogUpdates.ping";
	my $check_url = $url;
	if ($option eq 'ex')     { $method="weblogUpdates.extendedPing"; }
	if ($option eq 'adiary') {	# adiary extended
		$method    = "weblogUpdates.adiary-extendedPing";
		$check_url = $data->{art_title};
		# adiary向けはUAをadiaryとして送る（拒否されるため）
		$http->set_agent('adiary 3.52dev on on Satsuki-system 2.67');
	}
	# XML
	$ROBJ->tag_escape_for_xml($blog_name, $url, $check_url, $rssurl);
	my $post_body = <<POST_BODY;
<?xml version="1.0"?>
<methodCall>
	<methodName>$method</methodName>
	<params>
		<param><value>$blog_name</value></param>
		<param><value>$url</value></param>
		<param><value>$check_url</value></param>
		<param><value>$rssurl</value></param>
	</params>
</methodCall>
POST_BODY

	#-------------------------------------------------------------
	# POST の発行
	#-------------------------------------------------------------
	my ($status, $header, $res) = $http->post($post_url, undef, $post_body);
	if ($status != 200 || !defined $res) {
		return $http->{error} || "[$status] ping server access error";
	}

	#-------------------------------------------------------------
	# レスポンスの解析（注：手抜きです）
	#-------------------------------------------------------------
	my $data = join('', @$res);
	$data =~ s/[\r\n]//g;
	$data =~ s[\s*(?:<boolean>(.*?)</boolean>|<int>(.*?)</int>|<string>(.*?)</string>)\s*][$1$2$3]g;
	my %xml;
	while($data =~ m|<member>(.*?)</member>|sg) {
		my $member = $1;
		my ($name, $value);
		if ($member =~ /<name>(.*?)<\/name>/)   { $name =$1; }
		if ($member =~ /<value>(.*?)<\/value>/) { $value=$1; }
		$xml{$name} = $value;
	}
	return \%xml;		# 成功
}

################################################################################
# ■タグ関連
################################################################################
#-------------------------------------------------------------------------------
# ●タグの登録とpkeyリストの取得
#-------------------------------------------------------------------------------
sub regist_tags {
	my ($self, $tags, $esc_flag) = @_;
	my $ROBJ = $self->{ROBJ};
	my $DB   = $self->{DB};

	if ($esc_flag) {
		foreach(@$tags) {
			$ROBJ->tag_escape($_);
		}
	}

	# aaa::bbb を aaa と aaa::bbb に分解
	my @match;
	foreach my $tag (@$tags) {
		my $t;
		foreach(split('::',$tag)) {
			$t = $t ne '' ? "$t\::$_" : $_;
			push(@match, $t);
		}
	}
	my $db = $DB->select_match("tag", 'name', \@match, '*cols', ['pkey', 'name']);

	my %name2pkey = map {$_->{'name'} => $_->{'pkey'}} @$db;
	my @ary;
	foreach(@$tags) {
		if ($name2pkey{$_}) {
			push(@ary, $name2pkey{$_});
			next;
		}
		# 新たに登録
		my @x = split('::', $_);
		my $t;
		my $up= 0;
		my $lastpkey;
		foreach(@x) {
			$t = $t ? "$t\::$_" : $_;
			if ($name2pkey{$t}) {
				$up = $name2pkey{$t};
				next;
			}
			my %in;
			$in{name} = $t;
			$in{qt} = 0;
			$in{upnode} = $up==0 ? undef : $up;
			$in{priority} = $self->{default_tag_priority};
			my $pkey = $DB->insert("tag", \%in);
			if (!$pkey) {
				$ROBJ->error("Tag '%s' create fail", $t);
				return -1;
			}
			$lastpkey = $pkey;
			$name2pkey{$t} = $pkey;
			$up = $pkey;
		}
		push(@ary, $lastpkey);
	}

	return \@ary;
}

#-------------------------------------------------------------------------------
# ●タグ情報の更新
#-------------------------------------------------------------------------------
sub update_taglist {
	my $self = shift;
	my $ROBJ = $self->{ROBJ};
	my $DB   = $self->{DB};
	my $blog = $self->{blog};

	my $ary = $DB->select_match("tagart", 'a_enable', 1);
	my %tag;
	foreach(@$ary) {
		$tag{ $_->{t_pkey} }+=1;
	}
	$DB->begin();
	foreach(keys(%tag)) {
		$DB->update_match("tag", {qt => $tag{$_}}, 'pkey', $_, '-qt', $tag{$_});
	}
	$DB->update_match("tag", {qt => 0}, '-pkey', [ keys(%tag) ], '-qt', 0);
	$DB->commit();

	# タグツリーと、タグキャッシュ生成
	my $tree = $self->generate_tag_tree();

	# JSONの生成
	my $json = $self->generate_json($tree->{children}, ['sname', 'pkey', 'qt', 'children'], {sname=>'title', pkey=>'key'});
	$ROBJ->fwrite_lines( $self->{pub_dir} . 'taglist.json', $json);
	$self->update_cur_blogset('json_tm', $ROBJ->{TM});

	# イベント処理
	$self->call_event('TAG_STATE_CHANGE', $tree);

	return 0;
}

#-------------------------------------------------------------------------------
# ●タグリストの生成
#-------------------------------------------------------------------------------
sub generate_tag_tree {
	my $self = shift;
	my $ROBJ = $self->{ROBJ};
	my $DB   = $self->{DB};

	# 記事のpkeyリスト
	my @tagarts;
	{
		my $ary = $DB->select("tagart");
		foreach(@$ary) {
			push(@{ $tagarts[ $_->{t_pkey} ] ||= [] }, $_->{a_pkey});
		}
	}

	# 情報ファイルの生成
	my $tree = $self->load_tag_tree();
	my $all  = $tree->{_all};
	my @tags;
	foreach (@$all) {
		my $pkey = $_->{pkey};
		my $children = $_->{children};
		$children = $children ? join(',', map {$_->{pkey}} @$children):'';
		my $arts = join(',', @{ $tagarts[$pkey] || [] });
		$tags[ $pkey ] = int($_->{upnode}) . "\t" . int($_->{qt}) . "\t" . int($_->{qtall})
				. "\t$_->{priority}\t$children\t$arts\t$_->{name}\n";
	}
	@tags = map { defined $_  ? $_ : "\n" } @tags;
	$ROBJ->fwrite_lines($self->blog_dir() . "tag_cache.txt", \@tags);

	return $tree;
}

#-------------------------------------------------------------------------------
# ●タグツリーの取得
#-------------------------------------------------------------------------------
sub load_tag_tree {
	my $self = shift;
	my $DB = $self->{DB};

	my $taglist = $DB->select("tag", { sort=>['priority', 'pkey'] });
	my %tree = map { $_->{pkey} => $_ } @$taglist;
	$tree{0} = { children => [], _all=>$taglist, root=>1 };	# root node

	foreach(@$taglist) {
		my $x = rindex($_->{name},'::');
		$_->{sname} = $x<0 ? $_->{name} : substr($_->{name}, $x+2);
		my $up = int($_->{upnode});
		my $ary = $tree{$up}->{children} ||= [];
		push(@$ary, $_);
	}

	# リーフをすべて含む記事数を計算する
	foreach (@$taglist) {
		my $qt = $_->{qtall} = $_->{qt};
		my $up = $_->{upnode};
		while($up) {
			$tree{$up}->{qtall} += $qt;
			$up = $tree{$up}->{upnode};
		}
	}

	return $tree{0};	# root node
}

################################################################################
# ■コンテンツ関連
################################################################################
#-------------------------------------------------------------------------------
# ●blog/コンテンツツリーの生成
#-------------------------------------------------------------------------------
sub update_contents_list {
	my $self = shift;
	my $ROBJ = $self->{ROBJ};
	my $DB   = $self->{DB};

	# 情報のロード
	my ($tree, $arts, $pkey_max) = $self->load_contents_tree();

	# キャッシュ保存ディレクトリ
	my $dir = $self->{blog_dir} . 'arts/';
	$ROBJ->mkdir($dir);

	# コンテンツ情報JSON、キャッシュの生成
	{
		my $all = $tree->{_all};
		my $json= $self->generate_json($tree->{children}, ['title', 'pkey', 'upnode', 'link_key', 'children'], {pkey=>'key'});
		$ROBJ->fwrite_lines( $self->{pub_dir} . 'contents.json', $json);
		$self->update_cur_blogset('json_tm', $ROBJ->{TM});

		# upnode, children, titleのキャッシュ
		my @ary;
		foreach(@$all) {
			my $ch = $_->{children} ? join(',', map {$_->{pkey}} @{$_->{children}}) : '';
			push(@ary, "$_->{pkey}\t$_->{link_key}\t$_->{upnode}\t$_->{prev}\t$_->{next}\t$ch\t$_->{title}\n");
		}
		my $file = $dir . 'contents.dat';
		$ROBJ->fwrite_lines($file, \@ary);
	}

	# blog情報キャッシュの生成
	my %arts = map {$_->{pkey} => $_} @$arts;
	my $unit = $self->{blog_cache_unit} || $pkey_max;
	my $max  = int(($pkey_max+$unit-1)/$unit);
	for(my $cnt=0; $cnt<=$max; $cnt++) {
		my $base = $cnt*$unit;
		my $end  = $base+$unit;
		my %list;
		for(my $i=$base; $i<$end; $i++) {
			if (!exists($arts{$i})) { next; }
			my $h = $list{$i} = $arts{$i};
			foreach($h->{prev}, $h->{next}) {
				if (!$_ || !exists $arts{$_}) { next; }
				$list{$_} = $arts{$_};
			}
		}
		# 情報を加工して保存
		my $file = $dir . sprintf("%04d", $cnt) . '.dat';
		if (!%list) {
			$ROBJ->file_delete($file);
			next;
		}
		my @ary;
		foreach(sort {$a <=> $b} keys(%list)) {
			my $h = $list{$_};
			push(@ary, "$h->{pkey}\t$h->{prev}\t$h->{next}\t$h->{title}\n");
		}
		# ファイルに保存
		$ROBJ->fwrite_lines($file, \@ary);
	}

	# イベント処理
	$self->call_event('CONTENT_STATE_CHANGE', $tree);
	return $tree;
}

################################################################################
# ■参照元（バックリンク）
################################################################################
#-------------------------------------------------------------------------------
# ●参照元の更新
#-------------------------------------------------------------------------------
# 本文のリンクをlinkテーブルに入れ直し、リンク先の記事の参照元のHTML（_art.backlinks）
# を作り直す。表示のときはbacklinksを読むだけ（dea_backlinks）。
# ・$pkeysが配列refなら、その記事のリンクと、その記事が関わる参照元だけを作り直す
#   それ以外（引数なし、件数が渡されたとき）は、全記事を作り直す
# ・参照元に出すのは、公開中のブログ記事（コンテンツは除く）。新しい順
# ・コンテンツの記事には参照元を出さない
sub update_backlinks {
	my $self  = shift;
	my $pkeys = shift;
	my $DB    = $self->{DB};
	my $table  = "link";

	my $all = !ref($pkeys);
	if (!$all && !@$pkeys) { return 0; }

	#-------------------------------------------------------------
	# リンクの入れ直し
	#-------------------------------------------------------------
	my $keys = $DB->select_match("art", '*cols', ['link_key']);
	my %exists = map { $_->{link_key} => 1 } @$keys;

	my $arts = $DB->select_match("art", ($all ? () : ('pkey', $pkeys)), '*cols', ['pkey', 'link_key', 'text']);
	my %targets;	# 参照元を作り直す記事のlink_key
	if ($all) {
		%targets = %exists;
	} else {
		# 消えたリンクのリンク先
		my $old = $DB->select_match($table, 'a_pkey', $pkeys, '*cols', ['link_key']);
		foreach(@$old) { $targets{ $_->{link_key} }=1; }
	}

	$DB->begin();
	if ($all) {
		$DB->delete_match($table);
	} else {
		$DB->delete_match($table, 'a_pkey', $pkeys);
	}
	foreach my $art (@$arts) {
		# 自分自身（新規作成や、ゴミ箱から戻したとき）
		$targets{ $art->{link_key} } = 1;

		foreach( $self->extract_link_keys($art->{text}, \%exists) ) {
			if ($_ eq $art->{link_key}) { next; }	# 自分自身へのリンク
			$DB->insert($table, { a_pkey => $art->{pkey}, link_key => $_ });
			$targets{$_} = 1;
		}
	}
	my $r = $DB->commit();

	#-------------------------------------------------------------
	# 参照元のHTMLの生成
	#-------------------------------------------------------------
	my @keys = grep { $exists{$_} } keys(%targets);
	if (!@keys) { return $r; }

	my $dsts  = $DB->select_match("art", 'link_key', \@keys, '*cols', ['pkey', 'link_key', 'ctype', 'backlinks']);
	my $links = $DB->select_match($table, 'link_key', \@keys, '*cols', ['a_pkey', 'link_key']);
	my %from;	# link_key => { リンク元のpkey => 1 }
	foreach(@$links) {
		$from{ $_->{link_key} }->{ $_->{a_pkey} } = 1;
	}
	my %src = map { $_->{a_pkey} => 1 } @$links;
	my $srcs = %src ? $DB->select("art", {
		match    => { pkey => [ keys(%src) ], enable => 1, ctype => '' },
		cols     => ['pkey', 'link_key', 'title', 'yyyymmdd', 'tm'],
		sort     => ['yyyymmdd', 'tm'],
		sort_rev => [1, 1]
	}) : [];

	my $path = $self->{myself2};
	foreach(@$srcs) {
		$self->post_process_link_key( $_ );
		$_->{html} = "<li><a href=\"$path$_->{elink_key}\">$_->{title}</a></li>\n";
	}

	$DB->begin();
	foreach my $dst (@$dsts) {
		my $from = $from{ $dst->{link_key} } || {};
		my $html = $dst->{ctype} ne '' ? '' : join('', map { $_->{html} } grep { $from->{ $_->{pkey} } } @$srcs);
		if ($html eq $dst->{backlinks}) { next; }
		$DB->update_match("art", { backlinks => $html }, 'pkey', $dst->{pkey});
	}
	$r += $DB->commit();
	return $r;
}

#-------------------------------------------------------------------------------
# ●本文のHTMLから、ブログ内の記事へのリンクのlink_keyを取り出す
#-------------------------------------------------------------------------------
# $exists	今ある記事のlink_keyのハッシュ
#		これ以外は、まだ無いブログ記事のlink_key（"0"+pkey）の形のものだけ残す
sub extract_link_keys {
	my ($self, $text, $exists) = @_;
	my $path = $self->{myself2};
	my @base = ($path);
	if ($path =~ m|^/|) { unshift(@base, $self->{ROBJ}->{ServerURL} . $path); }

	my %keys;
	while ($text =~ /<a\s[^>]*?\bhref="([^"]*)"/g) {
		my $url = $1;
		my ($base) = grep { substr($url, 0, length($_)) eq $_ } @base;
		if (!defined $base) { next; }

		# link_key_encodeの逆
		my $key = substr($url, length($base));
		$key =~ s/[?#].*//s;
		$key =~ s|^\.//|/|;
		$key =~ s/%([0-9A-Fa-f]{2})/chr(hex($1))/eg;
		if ($key =~ /^0\d+$/) { $key = '0' . int($key); }

		if ($exists->{$key} || $key =~ /^0[1-9]\d*$/) { $keys{$key}=1; }
	}
	return keys(%keys);
}

#-------------------------------------------------------------------------------
# ●ブログ情報のjsonを生成する
#-------------------------------------------------------------------------------
sub generate_blog_json {
	my $self = shift;
	my $data = shift;
	my $zero = shift;
	my $ROBJ = $self->{ROBJ};
	my @ary;
	if ($zero) {
		push(@ary, "\"0\": $zero");
	}
	foreach(@$data) {
		my $title = $_->{title};
		my $lkey  = $_->{link_key};
		$ROBJ->tag_escape($lkey);
		$title =~ s/\\/&#92;/g;
		$lkey  =~ s/\\/&#92;/g;
		my $line = "\"title\": \"$title\", \"lkey\": \"$lkey\"";
		if ($_->{prev}) { $line .= ", \"prev\": $_->{prev}"; }
		if ($_->{next}) { $line .= ", \"next\": $_->{next}"; }
		push(@ary, "\"$_->{pkey}\": {$line}");
	}
	return "{\n" . join(",\n", @ary) . "\n}";
}

#-------------------------------------------------------------------------------
# ●コンテンツツリーの取得
#-------------------------------------------------------------------------------
sub load_contents_tree {
	my $self = shift;
	my $ROBJ = $self->{ROBJ};
	my $DB   = $self->{DB};
	my $blog = $self->load_blogset();

	# 全記事を取得
	my $ary = $DB->select_match("art",
		'enable', 1,
		'*sort', 'yyyymmdd',
		'*sort', 'tm',
		'*cols', ['pkey', 'title', 'link_key', 'priority', 'upnode', 'ctype']
	);
	my @contents;
	my @arts;
	my $pkey_max=0;
	foreach(@$ary) {
		my $a = $_->{ctype} eq '' ? \@arts : \@contents;
		push(@$a, $_);
		if ($pkey_max<$_->{pkey}) { $pkey_max=$_->{pkey}; }
	}

	# コンテンツツリーの生成
	@contents = sort {$a->{priority} <=> $b->{priority}} @contents;
	my %tree = map { $_->{pkey} => $_ } @contents;
	$tree{0} = { children => [], _all=>\@contents, root=>1 };		# root node
	my %lkeys;
	foreach(@contents) {
		$self->post_process_link_key($_);
		my $up = int($_->{upnode});
		if (!exists $tree{$up}) { $up=0; }
		my $ary = $tree{$up}->{children} ||= [];
		push(@$ary, $_);
		$lkeys{$_->{link_key}} = $_;
	}
	# FrontPage処理
	my $fp;
	foreach(qw(FrontPage top index)) {
		if ($lkeys{$_}) { $fp=$_; last; }
	}
	$self->update_blogset($blog, 'frontpage', $fp);

	# 前後リンクの生成
	my @cons;
	$self->tree2list(\@cons, $tree{0}->{children});
	$self->contents_next_prev_link(\@arts);
	$self->contents_next_prev_link(\@cons);

	return wantarray ? ($tree{0}, \@arts, $pkey_max) : $tree{0};
}

sub tree2list {
	my ($self,$ary,$tree) = @_;
	foreach(@$tree) {
		push(@$ary, $_);
		if ($_->{children}) { $self->tree2list($ary, $_->{children}); }
	}
}

sub contents_next_prev_link {
	my $self = shift;
	my $ary  = shift;
	my $max  = $#$ary;

	# ブログ記事の前後リンク
	for(my $i=1; $i<$#$ary; $i++) {
		$ary->[$i]->{next} = $ary->[$i+1]->{pkey};
		$ary->[$i]->{prev} = $ary->[$i-1]->{pkey};
	}
	# 最初と最後の記事の処理
	if ($max > 0) {
		$ary->[   0]->{next} = $ary->[     1]->{pkey};
		$ary->[$max]->{prev} = $ary->[$max-1]->{pkey};
	}
	return $ary;
}

################################################################################
# ■RSSの生成処理
################################################################################
#-------------------------------------------------------------------------------
# ●RSSを生成
#-------------------------------------------------------------------------------
# XML 1.0で使えない制御文字（タブ、改行以外）。UTF-8のバイト列のまま取り除く
my $XML_INVALID = qr/[\x00-\x08\x0B\x0C\x0E-\x1F]/;
# アイキャッチの media:content の type（拡張子から決める。無いものは type を書かない）
my %RSS_IMAGE_TYPE = (
	jpg  => 'image/jpeg',
	jpeg => 'image/jpeg',
	png  => 'image/png',
	gif  => 'image/gif',
	webp => 'image/webp',
	avif => 'image/avif',
	apng => 'image/apng'
);

sub generate_rss {
	my $self = shift;
	my $ROBJ = $self->{ROBJ};
	my $blog = $self->{blog};

	# 文字コード変換
	my $jcode = $ROBJ->load_codepm();

	#---------------------------------------------------
	# RSS生成
	#---------------------------------------------------
	my $ret;
	my @files;
	my $file = $self->{pub_dir} . "rss.xml";
	if ($blog->{rss_items_int}) {
		my $rss = $ROBJ->call( $self->{rss_skeleton}, {
			file  => 'rss.xml',
			no_comment => $blog->{rss_no_comment},
			items => $blog->{rss_items_int}
		});
		$jcode->from_to($rss, $ROBJ->{SystemCode}, 'UTF-8');
		$rss =~ s/$XML_INVALID//g;

		# ファイルに書き込み
		$ret = $ROBJ->fwrite_lines($file, $rss);
		push(@files, 'rss.xml');
	} else {
		$ROBJ->file_delete($file);
	}

	# RSSファイル情報記録（,区切り）
	$self->update_blogset($blog, 'rss_files', join(',', @files));

	return $ret;
}

#-------------------------------------------------------------------------------
# ●RSS用に記事をロード
#-------------------------------------------------------------------------------
sub load_arts_for_rss {
	my ($self, $opt) = @_;
	my $ROBJ = $self->{ROBJ};
	my $blog = $self->{blog};

	# load
	$opt->{loads} ||= $opt->{items} || 10;
	$opt->{blog_only} = $blog->{separate_blog};
	my $logs = $self->load_articles( '', undef, $opt );

	#---------------------------------------------------
	# RSSのタグエスケーパー
	#---------------------------------------------------
	my $escaper = $self->load_tag_escaper_force( 'rss' );

	# RSS のための加工処理
	my $tm_max     = 0;
	my $update_max = 0;
	foreach(@$logs) {	# ログ
		# 最終作成日 / 更新日
		if ($_->{tm}        > $tm_max)     { $tm_max     = $_->{tm};        }
		if ($_->{update_tm} > $update_max) { $update_max = $_->{update_tm}; }

		# 日付加工  (dc sample)2006-05-02T13:54:30+09:00
		$_->{dc_date}    = $ROBJ->w3c_date( $_->{tm} );
		$_->{rfc_date}   = $ROBJ->rfc_date( $_->{tm} );
		$_->{dc_update}  = $ROBJ->w3c_date( $_->{update_tm} );
		$_->{rfc_update} = $ROBJ->rfc_date( $_->{update_tm} );

		# テキストロード
		my $text = $escaper->escape( $_->{text_s} || $_->{text} );
		$text =~ s/\]\]>/]]&gt;/g;
		$_->{description} = $text;

		# link_keyの加工
		$self->post_process_link_key( $_ );

		# ページ内リンク（#見出し）は、リーダーが記事のページの外で開くので、記事のURLを付ける
		my $url = $ROBJ->{ServerURL} . $self->{myself2} . $_->{elink_key};
		$_->{description} =~ s/(\shref=")#/$1$url#/g;

		# アイキャッチ（media:content に出す）。main_image はURLエンコード済みの、添付フォルダからの相対パス
		if ($_->{main_image} ne '') {
			$_->{main_image_url} = $ROBJ->{ServerURL} . $ROBJ->{Basepath} . $self->blogimg_dir() . $_->{main_image};
			$_->{main_image_type} = $_->{main_image} =~ /\.(\w+)$/ ? $RSS_IMAGE_TYPE{lc($1)} : '';
			$ROBJ->tag_escape_for_xml($_->{main_image_url});
		}

		# & のエスケープ
		$ROBJ->tag_escape_for_xml($_->{title}, $_->{tags});
	}
	# 全体変数のセット
	my %h;
	$h{art_tm}     = $tm_max;
	$h{update_tm}  = $update_max;
	$h{dc_date}    = $ROBJ->w3c_date( $tm_max );
	$h{rfc_date}   = $ROBJ->rfc_date( $tm_max );
	$h{dc_update}  = $ROBJ->w3c_date( $update_max );
	$h{rfc_update} = $ROBJ->rfc_date( $update_max );
	return ($logs, \%h);
}

################################################################################
# ■コメント関連
################################################################################
#-------------------------------------------------------------------------------
# ●コメントを書く
#-------------------------------------------------------------------------------
sub post_comment {
	my ($self, $form) = @_;
	my $ROBJ = $self->{ROBJ};
	my $auth = $ROBJ->{Auth};
	my $blog = $self->{blog};
	if (! $self->{allow_com}) { $ROBJ->message('Operation not permitted'); return 5; }

	# 記事を確認
	my $a_pkey = int($form->{a_pkey});
	my $art = $self->load_article_current_blog("0$a_pkey");
	if (!$art) {
		$ROBJ->message("Article '0%d' not found", $a_pkey);
		return 11;
	}
	if (! $art->{com_ok} || $blog->{com_ok_force} eq '0') {
		# コメント不許可
		$ROBJ->message('This article not allow comments');
		return 12;
	}
	# データ整理
	if ($auth->{ok}) {
		$form->{name} = $auth->{name};
		$form->{id}   = $auth->{id};
	} else {
		delete $form->{id};
	}

	# スパム対策（編集権限者は対象外）
	my $hold;
	if (! $self->{blog_admin}) {
		my $reason;
		($reason, $hold) = $self->check_comment_spam($form, $a_pkey);
		if ($reason) {
			warn "コメントに失敗しました（$reason）: a_pkey=$a_pkey, ip=$ENV{REMOTE_ADDR}\n";
			$ROBJ->message('Comment post failed. Please reload the page and try again later.');
			return 9;
		}
		if ($ROBJ->form_error()) { return 99; }
	}

	# 実体参照の無効化
	$form->{name}        =~ s/&/&amp;/g;
	$form->{comment_txt} =~ s/&/&amp;/g;

	# フォーム値から値削除
	$self->delete_ip_host_agent($form);
	delete $form->{tm};

	# コメント保留
	$form->{enable} = 1;
	my $defer = int($blog->{defer_com});	# 0=off, 1=保留, 2=ユーザー以外保留
	if ($self->{blog_admin}) { $defer=0; }	# 編集権限者のコメントは保留しない
	if (!$self->{blog_admin} && $defer) {
		if ($defer==2 && $auth->{ok}) { $defer=0; }	# ユーザーのみ許可
	}
	if ($defer || $hold) { $form->{enable}=0; }	# コメント保留

	# コメント投稿前イベント
	my $er = $self->call_event('COMMENT_BEFORE', $form, $art);
	if ($er) { return $er; }

	# コメントの登録
	my ($r,$pkey) = $self->regist_comment($form, $art);
	if ($r) {
		return $r;	# error
	}
	$form->{pkey} = $pkey;

	# コメント数記録
	$self->calc_comments($a_pkey);

	# コメント投稿後イベント
	$self->call_event('COMMENT_AFTER', $form, $art);

	# 新着記録
	if (! $self->{blog_admin}) {
		my $ncom = $blog->{newcom_flag};
		$ncom = $ncom . ($ncom ? ',' : '') . $pkey;
		$self->update_blogset($blog, 'newcom_flag', $ncom);

		# 新着コメントイベント
		$self->call_event('COMMENT_NEW', $form, $art);
	}
	$self->call_event('COMMENT_STATE_CHANGE', [$a_pkey], [$pkey]);
	$self->call_event('ARTCOM_STATE_CHANGE',  [$a_pkey], [$pkey]);

	return 0;
}

#-------------------------------------------------------------------------------
# ●コメントのスパム対策
#-------------------------------------------------------------------------------
# 決まりはdocs/コメントのスパム対策.md
#
# ret = (はじく理由, 承認待ちにする理由)
#	はじく理由	記録用（人には見せない）。はじかないならundef
#	承認待ち	理由を「,」でつないだもの。承認待ちにしないならundef
# 長さの決まりに合わないときはform_errorを設定する。
#
my %COM_SPAM_DEFAULT = (
	com_hold_url   => 1,
	com_require_ja => 1,
	com_rate_count => 3,
	com_rate_min   => 10,
	com_name_max   => 32,
	com_body_min   => 5,
	com_body_max   => 3000,
	com_body_lines => 100
);
my $COM_TOKEN_MIN_AGE = 3;		# フォームを出してから、これより早い投稿ははじく（秒）
my $COM_TOKEN_MAX_AGE = 24*60*60;	# これより古いフォームからの投稿ははじく（秒）

sub check_comment_spam {
	my ($self, $form, $a_pkey) = @_;
	my $ROBJ = $self->{ROBJ};
	my $DB   = $self->{DB};
	my $auth = $ROBJ->{Auth};
	my $blog = $self->{blog};
	my %s = map { $_ => ($blog->{$_} eq '' ? $COM_SPAM_DEFAULT{$_} : int($blog->{$_})) } keys(%COM_SPAM_DEFAULT);

	# 文字の数で数えるためutf8の文字列にする。改行はLFにそろえ、前後の空白を除く
	my ($name, $text, $url) = ($form->{name}, $form->{comment_txt}, $form->{url});
	foreach($name, $text, $url) {
		utf8::decode($_);
		$_ =~ s/\r\n?/\n/g;
		$_ =~ s/^\s+|\s+$//g;
	}

	#-----------------------------------------------------------------------
	# はじくもの
	#-----------------------------------------------------------------------
	if ($form->{website} ne '') { return 'honeypot'; }
	if (! $auth->{ok}) {
		# ログインできる人はボットではないので、トークンは確かめない
		if (! $self->check_comment_token($form->{secure_id}, $a_pkey)) { return 'token'; }

		my $ip = $ENV{REMOTE_ADDR};
		if ($self->match_ip_rules($ip, $blog->{com_block_ips})) { return 'blocked_ip'; }

		if ($s{com_rate_count}) {
			my $coms = $DB->select("com", {
				match => { ip => $ip },
				min   => { tm => $ROBJ->{TM} - $s{com_rate_min}*60 },
				cols  => ['pkey']
			});
			if ($s{com_rate_count} <= @$coms) { return 'rate_limit'; }
		}
	}

	#-----------------------------------------------------------------------
	# 理由を書いて返すもの
	#-----------------------------------------------------------------------
	if (! $auth->{ok}) {
		if ($name eq '') {
			$ROBJ->form_error('name', 'name is empty');
		} elsif ($s{com_name_max} < length($name)) {
			$ROBJ->form_error('name', 'Name must be %d characters or less', $s{com_name_max});
		} elsif ($self->is_registered_user_name($name)) {
			$ROBJ->form_error('name', 'This name is used by a registered user. Please use another name');
		} elsif ($self->is_admin_like_name($name)) {
			$ROBJ->form_error('name', 'This name looks like an administrator. Please use another name');
		}
	}
	if ($text eq '') {
		$ROBJ->form_error('comment_txt', 'comment text is empty');
	} else {
		my $letters = () = $text =~ /[\p{L}\p{N}]/g;
		if (! $auth->{ok} && $letters < $s{com_body_min}) {
			$ROBJ->form_error('comment_txt', 'Comment text must be at least %d characters (spaces and symbols are not counted)', $s{com_body_min});
		}
		if ($s{com_body_max} < length($text)) {
			$ROBJ->form_error('comment_txt', 'Comment text must be %d characters or less', $s{com_body_max});
		}
		if ($s{com_body_lines} < 1 + ($text =~ tr/\n//)) {
			$ROBJ->form_error('comment_txt', 'Comment text must be %d lines or less', $s{com_body_lines});
		}
	}
	if ($ROBJ->form_error()) { return; }

	#-----------------------------------------------------------------------
	# 承認待ちにするもの
	#-----------------------------------------------------------------------
	if ($auth->{ok}) { return; }
	my @hold;
	if ($s{com_hold_url} && ("$name\n$text" =~ m{h?ttps?://}i || $url ne '')) {
		push(@hold, 'url');
	}
	my $folded = $self->fold_comment_text("$name\n$text");
	foreach(split(/\n/, $blog->{com_ng_words})) {
		my $word = $self->fold_comment_text( $ROBJ->tag_unescape($_) );
		if ($word ne '' && 0 <= index($folded, $word)) { push(@hold, 'ng_word'); last; }
	}
	if ($s{com_require_ja} && $text !~ /[\p{Hiragana}\p{Katakana}\p{Han}]/) {
		push(@hold, 'not_japanese');
	}
	return (undef, @hold ? join(',', @hold) : undef);
}

#-------------------------------------------------------------------------------
# ●登録ユーザーの名前か
#-------------------------------------------------------------------------------
# 全角と半角、大文字と小文字、空白の違いは無視して比べる（fold_comment_text）。
# IDとは比べない。なりすましで困るのは表に出る名前のほうで、IDと比べて理由を出すと、
# その文字列がログインのIDだと分かってしまうため
sub is_registered_user_name {
	my ($self, $name) = @_;
	my $auth   = $self->{ROBJ}->{Auth};
	my $folded = $self->fold_comment_text($name);
	my $users  = $auth->{DB}->select_match($auth->{table}, '*cols', ['name']);
	foreach(@$users) {
		if ($folded eq $self->fold_comment_text($_->{name})) { return 1; }
	}
	return 0;
}

#-------------------------------------------------------------------------------
# ●管理者を名乗るような名前か
#-------------------------------------------------------------------------------
# 記号と空白を除いて比べる。英語は名前全体が一致するときだけ（後ろの数字は無視する。
# "badminton"などをはじかないため）、日本語は名前に含まれるとき（「管理人です」などもはじくため）
my @ADMIN_LIKE_NAMES = qw(admin administrator administrater sysadmin sysop root webmaster moderator owner);
my @ADMIN_LIKE_WORDS = qw(管理人 管理者 運営);
sub is_admin_like_name {
	my ($self, $name) = @_;
	my $x = $self->fold_comment_text($name);
	$x =~ s/[^\p{L}\p{N}]//g;
	my $en = $x;
	$en =~ s/\d+$//;
	foreach(@ADMIN_LIKE_NAMES) {
		if ($en eq $_) { return 1; }
	}
	foreach(@ADMIN_LIKE_WORDS) {
		my $w = $_;
		utf8::decode($w);
		if (0 <= index($x, $w)) { return 1; }
	}
	return 0;
}

#-------------------------------------------------------------------------------
# ●コメントフォームのトークンを確かめる（作るのはmake_comment_token）
#-------------------------------------------------------------------------------
sub check_comment_token {
	my ($self, $token, $a_pkey) = @_;
	my ($ver, $pkey, $tm, $sig) = split(/\./, $token, 4);
	if ($ver ne 'v1' || $pkey ne int($a_pkey) || $tm !~ /^\d+$/) { return 0; }
	if ($sig ne $self->sign_comment_token("v1.$pkey.$tm")) { return 0; }

	my $age = $self->{ROBJ}->{TM} - $tm;
	return ($COM_TOKEN_MIN_AGE <= $age && $age <= $COM_TOKEN_MAX_AGE) ? 1 : 0;
}

#-------------------------------------------------------------------------------
# ●比べるための形にする
#-------------------------------------------------------------------------------
# 全角と半角をそろえ（NFKC）、小文字にし、空白を除く
sub fold_comment_text {
	my ($self, $x) = @_;
	require Unicode::Normalize;
	if (! utf8::is_utf8($x)) { utf8::decode($x); }
	$x = lc( Unicode::Normalize::NFKC($x) );
	$x =~ s/\s+//g;
	return $x;
}

#-------------------------------------------------------------------------------
# ●IPアドレスの規則
#-------------------------------------------------------------------------------
#	192.0.2.10 / 2001:db8::1	そのアドレスだけ
#	192.0.2.0/24 / 2001:db8::/32	CIDR
#	192.0.2. / 2001:db8:		前方一致（末尾が.か:のとき）
#
# $rulesは1行に1つ。どれかに当たれば真
sub match_ip_rules {
	my ($self, $ip, $rules) = @_;
	foreach(split(/\n/, $rules)) {
		my $r = $self->parse_ip_rule($_);
		if (!$r) { next; }
		if ($r->{prefix}) {
			if (index(lc($ip), lc($r->{prefix})) == 0) { return 1; }
			next;
		}
		my $packed = &pack_ip($ip);
		if (!$packed || length($packed) != length($r->{net})) { next; }

		my $bytes = int($r->{bits} / 8);
		if (substr($packed, 0, $bytes) ne substr($r->{net}, 0, $bytes)) { next; }
		my $rest = $r->{bits} % 8;
		if (!$rest) { return 1; }
		my $mask = (0xff << (8 - $rest)) & 0xff;
		if ((ord(substr($packed, $bytes, 1)) & $mask) == (ord(substr($r->{net}, $bytes, 1)) & $mask)) { return 1; }
	}
	return 0;
}
# 書き方が正しくなければundef
sub parse_ip_rule {
	my ($self, $rule) = @_;
	if ($rule =~ m|^([0-9A-Fa-f:\.]+)/(\d{1,3})$|) {
		my $bits = $2;
		my $net  = &pack_ip($1);
		if (!$net || length($net)*8 < $bits) { return; }
		return { net => $net, bits => $bits };
	}
	if ($rule =~ /^[0-9A-Fa-f:\.]+[\.:]$/ && $rule =~ /[0-9A-Fa-f]/) {
		return { prefix => $rule };
	}
	my $net = &pack_ip($rule);
	return $net && { net => $net, bits => length($net)*8 };
}
sub pack_ip {
	my $ip = shift;
	require Socket;
	return Socket::inet_pton($ip =~ /:/ ? Socket::AF_INET6() : Socket::AF_INET(), $ip);
}

#-------------------------------------------------------------------------------
# ●スパム対策の設定を整える（ブログの設定の保存時）
#-------------------------------------------------------------------------------
# 1行に1つの設定の、前後の空白と空行を除く。IPアドレスの書き方が正しくなければform_error
sub normalize_comment_spam_setting {
	my ($self, $h) = @_;
	my $ROBJ = $self->{ROBJ};
	foreach my $key (qw(com_ng_words com_block_ips)) {
		my @lines = split(/\r?\n/, $h->{$key});
		foreach(@lines) { $_ =~ s/^\s+|\s+$//g; }
		$h->{$key} = join("\n", grep { $_ ne '' } @lines);
	}
	foreach(split(/\n/, $h->{com_block_ips})) {
		if ($self->parse_ip_rule($_)) { next; }
		$ROBJ->form_error('com_block_ips', "Invalid IP address rule '%s'", $_);
	}
}

#-------------------------------------------------------------------------------
# ●コメントを登録する
#-------------------------------------------------------------------------------
# 以下に信頼できない情報が入力されないように注意すること。
#
sub regist_comment {
	my ($self, $form, $art, $opt) = @_;
	my $ROBJ = $self->{ROBJ};
	my $DB   = $self->{DB};

	my $name   = $form->{name};
	my $email  = $form->{email};	# 任意
	my $url    = $form->{url};	# 任意
	my $text   = $form->{comment_txt} ne '' ? $form->{comment_txt} : $form->{text};
	$text =~ s/^(?:\s*\n)*//;	# 先頭は空行のみ除去
	$text =~ s/[\s*\n]*$//;		# 末尾は\n\s全部除去
	$ROBJ->trim($name, $email, $url);
	$ROBJ->tag_escape( $name, $text );
	$ROBJ->clear_form_error();

	# データチェック
	if ($text eq '') { $ROBJ->form_error('text', 'comment text is empty'); }
	if ($name eq '') { $ROBJ->form_error('name', 'name is empty'); }
	$text =~ s/\r?\n/<br>/g;	# 改行を br に置換

	# URL/メールアドレスの安全確認
	if ($email !~ /^[-_\.a-zA-Z0-9]+\@[-_\.a-zA-Z0-9]+$/) { $email=undef; }
	if ($url =~ m|^https?://[-_\.a-zA-Z0-9]+|) {
		$ROBJ->encode_uri( $url );
	} else {
		$url='';
	}

	# 記事情報がなければロード
	if (!$art) {
		my $art = $self->load_article("0" . int($art->{a_pkey}));
		if (!$art) {
			$ROBJ->message('a_pkey', "Article '0%d' not found", int($art->{a_pkey}));
			return 11;
		}
	}
	my $a_pkey = $art->{pkey};

	# エラー処理
	if ($ROBJ->form_error()) { return 99; }	# エラーがあった

	# コメントの書き込み処理
	my %com;
	$com{text}  = $text;
	$com{email} = $email;
	$com{url}   = $url;
	$com{name}  = $name;
	my $id = $form->{id};
	if ($id ne '') {
		$id =~ s/\W//g;
		$com{id} = $id;
	}
	$self->set_ip_host_agent(\%com, $opt);

	$com{tm} = int($opt->{tm}) || $ROBJ->{TM};
	if ($opt->{num} != 0) {
		$com{num} = int($opt->{num});
	}
	# 表示しないもの（保留したもの、インポートで非表示だったもの）は承認待ちにする。承認済みでも記事が非公開なら出さない
	$com{hold}   = $form->{enable} ? 0 : 1;
	$com{enable} = (!$com{hold} && $art->{enable}) ? 1 : 0;

	# 記事の情報をキャッシュして保存
	$com{a_pkey}     = $a_pkey;
	$com{a_yyyymmdd} = $art->{yyyymmdd};
	$com{a_title}    = $art->{title};
	$com{a_elink_key}= $art->{link_key};
	$self->link_key_encode( $com{a_elink_key} );

	# save_pkey
	if ($opt->{save_pkey}) {
		my $pkey = int($form->{pkey});
		if ($pkey) { $com{pkey} = $pkey; }
	}

	my $com_pkey = $DB->insert("com", \%com);
	if (!$com_pkey) {
		$ROBJ->message('Comment post failed');
		return 20;
	}
	return wantarray ? (0,$com_pkey) : 0;
}

#-------------------------------------------------------------------------------
# ●コメント数を計算し記録（コメント番号も設定）
#-------------------------------------------------------------------------------
sub calc_comments {
	my ($self, $a_pkey) = @_;
	my $DB = $self->{DB};

	my %h;
	$h{match} = {a_pkey => $a_pkey};
	$h{cols}  = ['pkey', 'enable', 'num'];
	$h{sort}  = ['pkey'];
	my $com = $DB->select("com", \%h);
	my $c = 0;
	my $num=0;
	foreach(@$com) {
		if ($_->{enable}) { $c++; }
		if ($_->{num}) { $num=$_->{num}; next; }
		# コメント番号が未定義
		$DB->update_match("com", {num => ++$num}, 'pkey', $_->{pkey});
	}

	my %update;
	$update{coms}     = $c;
	$update{coms_all} = $#$com + 1;
	return $DB->update_match("art", \%update, 'pkey', $a_pkey);
}

#-------------------------------------------------------------------------------
# ●新着コメントから表示したものを除去
#-------------------------------------------------------------------------------
sub remove_newcom_flag {
	my $self = shift;
	my $coms = shift;
	my $blog = $self->{blog};

	# 権限がないか、新着コメントがないなら無視
	my $nc = $blog->{newcom_flag};
	if (!$self->{blog_admin} || !@$coms || !$nc) { return; }

	my %h = map {$_ => 1} split(',', $nc);
	foreach(@$coms) {
		delete $h{ $_->{pkey} };
	}
	my $n = join(',',keys(%h));
	if (length($n) < length($nc)) {
		$self->update_blogset($blog, 'newcom_flag', $n);
	}
}

################################################################################
# ■ブログ管理テーブル更新、ブログの設定保存、プラグイン設定保存
################################################################################
#-------------------------------------------------------------------------------
# ●記事数情報の更新
#-------------------------------------------------------------------------------
sub update_bloginfo_article {
	my $self = shift;
	my $DB = $self->{DB};

	my ($ary,$hits) = $DB->select("art",{
		flag     => { enable => 1 },
		cols     => [ 'pkey' ],
		limit    => 1
	});

	my $darts = $DB->select_by_group("art", {
		flag     => { enable => 0 }
	});

	my $blog = $self->load_blogset();
	$self->update_blogset($blog, 'arts',  ($ary && @$ary) ? $hits : 0);
	$self->update_blogset($blog, 'darts', $darts->[0]->{_count});
}

#-------------------------------------------------------------------------------
# ●コメント数情報の更新
#-------------------------------------------------------------------------------
sub update_bloginfo_comment {
	my $self = shift;
	my $DB = $self->{DB};

	my ($ary,$hits) = $DB->select("com",{
		flag     => { enable => 1 },
		cols     => [ 'pkey' ],
		limit    => 1
	});
	$self->update_blogset($self->load_blogset(), 'coms', ($ary && @$ary) ? $hits : 0);
}

#-------------------------------------------------------------------------------
# ●ブログの設定の変更
#-------------------------------------------------------------------------------
sub update_blogset {
	my ($self, $blog, $k, $v) = @_;
	$blog = $self->load_blogset() if (!ref($blog));
	$self->update_hash( $blog, $k, $v );
	$blog->{_update}=1;
}
sub update_cur_blogset {
	my $self = shift;
	$self->update_blogset( $self->{blog}, @_ );
}

#-------------------------------------------------------------------------------
# ●プラグイン用の設定の変更
#-------------------------------------------------------------------------------
sub update_plgset {
	my ($self,$name,$h,$val) = @_;
	if (!$h) { return; }
	if (ref($h) ne 'HASH') {	# $h is key
		return $self->update_cur_blogset("p:$name:$h", $val);
	}

	my $head = "p:$name";
	my %up;
	foreach(keys(%$h)) {
		$up{"$head:$_"} = $h->{$_};
	}
	$self->update_cur_blogset(\%up);
}

################################################################################
# ■編集ロック機能
################################################################################
#
# 同じ記事をロックしている場合に、警告を出すシステム
#
#-------------------------------------------------------------------------------
# ●ロックをかける
#-------------------------------------------------------------------------------
sub edit_lock {
	my $self = shift;
	my $pkey = shift;
	my $sid  = shift;
	my $opt  = shift || {};

	my $ROBJ = $self->{ROBJ};
	my $id   = $ROBJ->{Auth}->{id};
	$sid  =~ s/[\x00-\x1f]//g;

	if (!$self->{blog_admin}) { return -1; }
	if ($pkey eq ''){ return -2; }
	if ($self->{sys}->{edit_lock_interval} < 1) { return 1; }

	# lock処理
	my ($fh, $ary) = $self->load_lock_file( $pkey );
	if (!$fh) { return 7; }
	$ary = [ grep {$_->{id} ne $id || $_->{sid} ne $sid} @$ary ];

	if($opt->{unlock}) {
		$self->update_lock_file($fh, $ary);
	} elsif ($sid ne '' && (!@$ary || $opt->{force})) {
		push(@$ary, {
			id => $id,
			sid=> $sid,
			tm => $ROBJ->{TM}
		});
		$self->update_lock_file($fh, $ary);
		pop(@$ary);
	} else {
		close($fh);
	}

	# ロック状況を返す
	my $json= $self->generate_json($ary, ['id', 'sid', 'tm']);
	return (0, $json);
}

#-------------------------------------------------------------------------------
# ●ロックファイルのロード
#-------------------------------------------------------------------------------
sub load_lock_file {
	my $self = shift;
	my $pkey = shift;
	my $ROBJ = $self->{ROBJ};
	$pkey =~ s/[^\w\-:]//g;

	# 時間
	my $interval = $self->{sys}->{edit_lock_interval};

	# tmpwatch
	my $dir =  $self->{blog_dir} . 'lock/';
	$ROBJ->mkdir($dir);
	$ROBJ->tmpwatch( $dir, $interval+10 );

	# lock処理
	my $file = $dir . $pkey;
	my ($fh,$lines) = $ROBJ->fedit_readlines($file);
	if (!$fh) { return; }

	my @ary;
	my $obs_time = $ROBJ->{TM} - ($interval + 5);
	foreach(@$lines) {
		my %h;
		chomp($_);
		($h{id}, $h{sid}, $h{tm}) = split("\t", $_);
		if ($h{tm} < $obs_time) { next; }
		push(@ary, \%h);
	}
	return ($fh, \@ary);
}

#-------------------------------------------------------------------------------
# ●ロックファイルのアップデート
#-------------------------------------------------------------------------------
sub update_lock_file {
	my $self = shift;
	my $fh   = shift;
	my $ary  = shift;
	my $ROBJ = $self->{ROBJ};

	my @lines = map { "$_->{id}\t$_->{sid}\t$_->{tm}\n" } @$ary;
	return $ROBJ->fedit_writelines($fh, \@lines);
}

################################################################################
# ■サブルーチン
################################################################################
#-------------------------------------------------------------------------------
# ●特別なシステムモードへ
#-------------------------------------------------------------------------------
sub special_system_mode {
	my $self = shift;
	$self->system_mode(@_);

	# フラグ設定
	$self->{special_system_mode} = 1;

	# デザイン編集など。外フレームは公開画面のものを使う（テーマのCSSの代わりに design.css を読む）
	if ($self->{frame_skeleton}) {
		$self->{frame_skeleton} = '_frame';
	}
}

#-------------------------------------------------------------------------------
# ●メンテナンスモード
#-------------------------------------------------------------------------------
sub mainte_mode {
	my $self = shift;
	my $ROBJ = $self->{ROBJ};
	my $auth = $ROBJ->{Auth};

	# 管理者
	# アップデートが必要なときは、メッセージではなく、リンク付きの知らせを出す（_sub/require_update_notice、_sub/admin_bar）
	if ($auth->{isadmin}) {
		# ブログが無いままアップデート待ちなら、アップデート処理しかできない（処理の後にブログを作る）
		if ($self->{require_update} && !$self->{allow_view}) {
			if ($ROBJ->{Form}->{action} ne 'system/update') {
				$ROBJ->{POST} = 0;
				$ROBJ->{Form} = {};
			}
			if ($self->{skeleton} !~ m!^(?:system/update|login\w*|logout)$!) {
				$ROBJ->redirect( $self->{myself} . '?system/update' );
			}
			return;
		}
		if (!$ROBJ->{POST} && !$self->{require_update}) {
			$ROBJ->message('Now maintenance mode');
		}
		return ;
	}
	# POSTはログインのみ許可
	my $form = $ROBJ->{Form};
	if ($form->{action} ne 'login') {
		$ROBJ->{POST} = 0;
		$ROBJ->{Form} = {};
	}
	if (!$ROBJ->{POST} && $self->{skeleton} !~ /^login\w*$/) {
		$ROBJ->set_status(503);
		$self->{skeleton} = '_sub/maintenance_msg';
	} else {
			# 動かないプラグインがあってもログインできるよう、プラグインが作ったものを使わない
		$self->{blog_admin} = undef;
		$self->{blog_admin} = undef;
		$self->{allow_com}  = undef;
		$self->{stop_all_plugins} = 1;
		$self->delete_blog_skeleton();
	}
	return;
}

#-------------------------------------------------------------------------------
# ●hash/arrayツリーからjsonを生成する
#-------------------------------------------------------------------------------
sub generate_json {
	my $self = shift;
	my $data = shift;
	my $cols = shift;	# データカラム
	my $ren  = shift || {};	# カラムのリネーム情報
	return $self->{ROBJ}->generate_json($data, {cols => $cols, rename => $ren});
}

#-------------------------------------------------------------------------------
# ●タグのノーマライズ
#-------------------------------------------------------------------------------
# aaa,,bbb::ccc,bbb,ddd,aaa → aaa,bbb::ccc,ddd
sub normalize_tag {
	my $self = shift;
	my $tags = shift;
	if (!ref($tags)) {
		$tags =~ s/^\s*(.*)?\s*$/$1/g;
		$tags = [ split(/\s*,\s*/, $tags) ];
	}
	# 重複除去
	my %h;
	my @ary;
	foreach(@$tags) {
		if ($_ eq '') { next; }
		$_ =~ s/\s+/ /g;	# space 1個に
		if (0 <= index(":$_:", ':::')) { next; }
		if ($h{$_}) { next; }	# 重複

		push(@ary, $_);
		# 重複除去のためのフラグ
		$h{$_}=1;
		my @x = split('::', $_);
		my $s = shift(@x);
		foreach(@x) {	# aa::bb::ccのときの aa と aa::bb が -1 になる
			$h{$s}=-1;
			$s .= "::$_";
		}
	}
	return grep { $h{$_} != -1 } @ary;
}

#-------------------------------------------------------------------------------
# ●parserのロード
#-------------------------------------------------------------------------------
sub load_parser {
	my $self = shift;
	my $name = shift;
	if ($name =~ /\W/) { return; }

	my $cache = $self->{__parser_cache} ||= {};
	if ($cache->{$name}) { return $cache->{$name}; }

	return ($cache->{$name} = $self->{ROBJ}->call( '_parser/' . $name ));
}

#-------------------------------------------------------------------------------
# ●TagEscapeのロード
#-------------------------------------------------------------------------------
sub load_tag_escaper {
	my $self = shift;
	my $obj  = $self->load_tag_escaper_force(@_);
	$obj->anytag( $self->{trust_mode} );
	return $obj;
}
sub load_tag_escaper_force {
	my $self = shift;

	my $head = $self->{allow_tags_head};
	my @ary  = map { "$head$_.txt" } @_;
	my $obj  = $self->_load_tag_escaper(@ary);
	return $obj;
}
sub _load_tag_escaper {
	my $self  = shift;
	my $key   = join('*',@_);
	my $cache = $self->{__tag_escaper_cache} ||= {};
	my $obj   = $cache->{$key} || $self->{ROBJ}->loadpm('TextParser::TagEscape', @_);
	return ($cache->{$key} = $obj);
}

#-------------------------------------------------------------------------------
# ●指定文字数でクリップする
#-------------------------------------------------------------------------------
sub string_clip {
	my ($self, $string, $j_len) = @_;
	my $jcode = $self->{ROBJ}->load_codepm();
	my $len_orig = length($string);
	$string = $jcode->jsubstr($string, 0, $j_len);
	if ($len_orig > length($string)) {	# 省略時 ... を付加
		$string .= $self->{sys}->{clip_append} || '...';
	}
	return $string;
}

#-------------------------------------------------------------------------------
# ●IP, HOST, AGENTを安全に設定する
#-------------------------------------------------------------------------------
sub set_ip_host_agent {
	my ($self, $h, $default) = @_;
	my $ROBJ = $self->{ROBJ};

	if ($ENV{REMOTE_ADDR} =~ /:/) {
		# IPv6なら強制的に空文字にする
		$ENV{REMOTE_HOST} = '';
	}

	my $flag = $default->{ip};
	$h->{ip}    = $flag ? $default->{ip}    : $ENV{REMOTE_ADDR};
	$h->{host}  = $flag ? $default->{host}  : $ENV{REMOTE_HOST};
	$h->{agent} = $flag ? $default->{agent} : $ENV{HTTP_USER_AGENT};

	$ROBJ->tag_escape($h->{ip}, $h->{host}, $h->{agent});
}

#-------------------------------------------------------------------------------
# ●フォームのIP, HOST, AGENT情報を削除
#-------------------------------------------------------------------------------
sub delete_ip_host_agent {
	my ($self, $h) = @_;
	delete $h->{ip};
	delete $h->{host};
	delete $h->{agent};
}

#-------------------------------------------------------------------------------
# ●#a0b0c0 → 160, 176, 192
#-------------------------------------------------------------------------------
sub hex2rgb {
	my ($self, $hex) = @_;
	if ($hex !~ /#([0-9A-Fa-f][0-9A-Fa-f])([0-9A-Fa-f][0-9A-Fa-f])([0-9A-Fa-f][0-9A-Fa-f])/) { return ; }
	return hex($1) . ',' . hex($2) . ',' . hex($3);
}

#-------------------------------------------------------------------------------
# ●セッションログのオープン
#-------------------------------------------------------------------------------
sub open_session {
	my $session = &open_session_for_load(@_);
	$session->open();
	return $session;
}

sub open_session_for_load {
	my ($self, $snum) = @_;
	my $ROBJ = $self->{ROBJ};
	my $session = $ROBJ->loadpm("Base::SessionFile", $ROBJ->{Cookie}->{session}->{sid}, int($snum));
}

#-------------------------------------------------------------------------------
# ●コールバックの登録
#-------------------------------------------------------------------------------
sub regist_end_callback {
	my $self = shift;
	my $k = shift;
	$self->{end_callback}->{$k} = shift;
}

#-------------------------------------------------------------------------------
# ●プラグイン番号の取得（プラグイン側から呼ばれる）
#-------------------------------------------------------------------------------
sub plugin_num {
	my $self = shift;
	return ($_[0] =~ /^(?:[A-Za-z][\w\-]*),(\d+)$/) ? $1 : undef;
}

1;
