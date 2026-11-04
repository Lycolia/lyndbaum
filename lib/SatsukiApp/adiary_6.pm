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
my @update_versions = (
	{ ver => 3.50, plugin=>1, func => 'sys_update_350', system=>1 },
	{ ver => 3.52, func => 'sys_update_352' },
	{ ver => 3.53, rebuild=>1, func => 'sys_update_353' },
	{ ver => 4.08, info=>1, func => 'sys_update_408' },
	{ ver => 4.09, plugin=>1, func => 'sys_update_409' },
	{ ver => 4.10, plugin=>1, theme=>1, rebuild=>1 },	# データの持ち方を変えた（migrate_410）。パスが変わるので全部作り直す
	{ ver => 4.11, plugin=>1, theme=>1, func => 'sys_update_411', system=>1, rebuild_cond=>[	# js/、pub-dist/、theme/ を pub/assets/ の下に移した
		'\[(?:mj|icon|pubdist)[:\]]'				# pub-dist/ のパスを出す記法
	]},
	{ ver => 4.12, plugin=>1, func => 'sys_update_412', system=>1 },	# 記事一覧とコメント一覧を管理画面に移した。デザインに残るリンクを作り直して消す
	{ ver => 4.13, plugin=>1, rebuild_cond=>[	# テーマのスケルトンのJSに更新日時を付けた
		'\[(?:video|audio|file:(?:mp4|m4v|webm|ogv|wav|wave|ogg|oga|mp3|aac|m4a)):',	# 動画と音声に preload="none" を付けた
		'\[image:'								# 画像に width と height を書くようにした
	]},
	{ ver => 4.14, info=>1 },	# RSSをRSS 2.0の仕様に合わせた。ブログ付加情報の再構築で書き出し直す
	{ ver => 4.15, plugin=>1, func => 'sys_update_415' },	# WebPushを削除した。デザインに残る登録ボタンは、デザインの作り直しで取り除く
	{ ver => 4.16, plugin=>1, func => 'sys_update_416', rebuild_cond=>[	# ソーシャルボタンに汎用の共有ボタンを足した。記事にNSFWのフラグを足した
		'\[youtube:', 'youtube\.com/watch',	# YouTubeはサムネイルだけを出す。動画は、アップデートの後にブラウザーでサムネイルを作ったときに作り直す
		'\(\('					# 注釈（(())）の一覧が出ない、番号が続く、同じidが重なる、を直した
	]},
	{ ver => 4.18, plugin=>1, func => 'sys_update_418' },	# 非公開コメントを廃止した。コメントフォームと記事のスケルトンは、デザインの作り直しで作り直す。コメントに承認待ち（hold）を足した
	{ ver => 4.19, func => 'sys_update_419' },	# 動画の記事用のサムネイルを、サーバーで作るようにした。前に作ったものは、アップデートの後にブラウザーで作り直す
	{ ver => 4.21, plugin=>1, theme=>1, func => 'sys_update_421', rebuild_cond=>[	# 古いテーマをレスポンシブにした。デザインのスケルトンを、今のテーマの雛形を外して作り直す。公開フォルダを整理し、テーマの色の調整をブログの設定に移した
		'\[(?:for-)?(?:sp|pc):'	# スマホとPCで出し分ける記法（[sp:]、[pc:]）を削除した。使っていた記事は、記法を文字のまま出す
	]},
	{ ver => 4.22, func => 'sys_update_422', system=>1 },	# 標準記法（default、default_p1、default_p2）を削除した。設定ファイルとブログの既定のパーサーから外す
	{ ver => 4.23, func => 'sys_update_423', system=>1 },	# パスワードをbcryptで保存するようにした。アップデートを行う管理者は、ここで新しいパスワードを決める（system_update）
	{ ver => 4.24, info=>1, func => 'sys_update_424' },	# RSSにチャンネル画像（サイトアイコン）と記事のアイキャッチを足し、2つ目のRSS（rss2.xml）を削除した。ブログ付加情報の再構築で書き出し直す
	{ ver => 4.25, func => 'sys_update_425', system=>1 },	# AVIFのサムネイルの画質の設定（album_avif_quality）を、設定ファイルに無ければ足す
	{ ver => 4.27, plugin=>1, func => 'sys_update_427' }	# プライベートモードを削除した。雛形から403の分岐を消したので、デザインのスケルトンを作り直す
);
#-------------------------------------------------------------------------------
# ●システムアップデート
#-------------------------------------------------------------------------------
sub system_update {
	my $self = shift;
	my $ROBJ = $self->{ROBJ};
	my $auth = $ROBJ->{Auth};
	if (!$auth->{isadmin}) { $ROBJ->message('Operation not permitted'); return 5; }

	my %opt;
	my $cur = $self->{sys}->{VERSION};

	# パスワードの再設定（Ver4.23）。bcryptで保存されていなければ、新しいパスワードが無いとアップデートしない
	# 保存すると自分のセッションも消えるので、保存はすべての処理の後に行う
	my $new_crypted;
	if ($cur < 4.23 && $auth->{need_pass_reset}) {
		my $form = $ROBJ->{Form};
		$ROBJ->clear_form_err();
		if ($form->{pass} eq '') {
			$ROBJ->form_err('pass', 'New password is empty');
		} elsif ($auth->check_new_pass($form->{pass}, $form->{pass2})) {
			$new_crypted = $auth->hash_pass($form->{pass});
			if (!defined $new_crypted) {
				$ROBJ->form_err('pass', 'bcrypt is not supported on this server');
			}
		}
		if ($ROBJ->form_err()) { return 10; }
	}

	# プライベートモードの削除（Ver4.27）。閉じていたブログが公開されるので、確認が無いとアップデートしない
	if ($cur < 4.27 && ($self->{blog} || {})->{private} && !$ROBJ->{Form}->{publish_private}) {
		$ROBJ->form_error('publish_private', 'Confirm that this blog will be published');
		return 10;
	}

	# データの持ち方の変更（Ver4.10）。各バージョンの処理は新しいテーブル名とパスで動くので、それより先に行う
	if ($cur < 4.10) {
		$self->migrate_410();
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

	# 新しいパスワードを保存する。セッションが消えるので、このあとログインし直す
	if (defined $new_crypted) {
		my $r = $auth->update_user_data({ id => $auth->{id}, crypted_pass => $new_crypted });
		if ($r->{ret}) {
			$ROBJ->message('Password save failed');
			return -1;
		}
		$self->{pass_reset_done} = 1;
	}
	return 0;
}

#-------------------------------------------------------------------------------
# ●システムアップデート for Ver3.50
#-------------------------------------------------------------------------------
sub sys_update_350 {
	my $self = shift;
	my $ROBJ = $self->{ROBJ};
	my $auth = $ROBJ->{Auth};

	# DB変更
	my $r = $auth->{DB}->add_column($auth->{table}, {name=>'email', type=>'text'});
	if ($r) { $ROBJ->message("ALTER TABLE $auth->{table} add column error($r)"); }
}

#-------------------------------------------------------------------------------
# ●システムアップデート for Ver3.52
#-------------------------------------------------------------------------------
sub sys_update_352 {
	my $self = shift;
	my $ROBJ = $self->{ROBJ};

	# 記事の更新履歴テーブル、ゴミ箱テーブル追加
	my $r = 0;
	$r += $self->create_rev_table();
	$r += $self->create_trash_tables();
	if ($r) { $ROBJ->message("Blog database error(%s)", $r); }
}

#-------------------------------------------------------------------------------
# ●システムアップデート for Ver3.53
#-------------------------------------------------------------------------------
# 記事の原文を書き換える（書き換えた後、全記事を再構築する）
# ・画像の代替テキストや添付ファイルの名前がファイル名と同じものを落とす。代替テキストの無い画像は末尾に : を付ける
# ・見出しに、今の見出しのIDを識別子[#id]として書き足す（Markdownの記事）
sub sys_update_353 {
	my $self = shift;
	$self->update_art_text_353();
}
sub update_art_text_353 {
	my $self   = shift;
	my $ROBJ   = $self->{ROBJ};
	my $DB     = $self->{DB};

	my $arts = $DB->select_match("art", '*cols', ['pkey', '_text', 'parser', 'link_key']);
	my %update;
	foreach(@$arts) {
		my $text = $self->normalize_file_alt( $_->{_text} );

		my $parser = $_->{parser} ne '' && $self->load_parser( $_->{parser} );
		if (ref($parser) && $_->{parser} eq 'markdown') {
			$self->post_process_link_key( $_ );
			$parser->{thisurl}  = $self->{myself2} . $_->{elink_key};
			$parser->{thispkey} = $_->{pkey};
			$text = $self->freeze_heading_ids_353( $parser, $text );
		}
		if ($text ne $_->{_text}) {
			$update{ $_->{pkey} } = { _text => $text };
		}
	}

	$DB->begin();
	foreach(keys(%update)) {
		$DB->update_match("art", $update{$_}, 'pkey', $_);
	}
	my $r = $DB->commit();
	if ($r) { $ROBJ->message("Blog database error(%s)", $r); }
}

#-------------------------------------------------------------------------------
# ●システムアップデート for Ver4.08
#-------------------------------------------------------------------------------
# 参照元（バックリンク）のテーブルとカラムを追加する
# ※参照元は、この後のブログ付加情報の再構築（ARTICLE_STATE_CHANGE）で作られる
sub sys_update_408 {
	my $self = shift;
	my $DB   = $self->{DB};
	my $ROBJ = $self->{ROBJ};
	my $r = 0;
	$r +=    $self->create_link_table();
	$r += 10*$DB->add_column("art",   {name=>'backlinks', type=>'text'});
	$r += 10*$DB->add_column("trash", {name=>'backlinks', type=>'text'});
	if ($r) { $ROBJ->message("Blog database error(%s)", $r); }
}

#-------------------------------------------------------------------------------
# ●システムアップデート for Ver4.09
#-------------------------------------------------------------------------------
# 履歴を残す間隔（rev_cycle）の単位を時間から分に変える
# 記事とゴミ箱のテーブルから、使われていなかったrevisionのカラムを消す
# ※コメントフォームのトークンを変えたため、プラグインの再インストールでデザインのスケルトンも作り直す
sub sys_update_409 {
	my $self = shift;
	my $DB   = $self->{DB};

	# 定義から外した後に作ったブログにはカラムが無く、エラーになるので出さない
	my $noerr = $DB->set_noerror(1);
	$DB->drop_column("art",   'revision');
	$DB->drop_column("trash", 'revision');
	$DB->set_noerror($noerr);

	my $blog = $self->{blog};
	if ($blog->{rev_cycle} ne '') {
		$self->update_blogset($blog, 'rev_cycle', int($blog->{rev_cycle}) * 60);
	}

	# 削除したプラグインを、入れたままのブログから外す
	# twitter_post : Twitter API v1.1が使えなくなったため削除
	# amp        : Googleの検索でAMPが有利でなくなり、手入れもされていないため削除
	# des_twitter: Xのタイムラインの埋め込みが、ログインしていない人に表示されなくなったため削除
	#              （デザインからは、デザインの作り直しで取り除く。reinstall_design_plugins）
	$self->uninstall_removed_plugins(qw(twitter_post amp des_twitter));
}

# プラグインの管理画面での保存（save_use_plugins）は、plugin/に今あるプラグインしか見ないので、
# フォルダを消したプラグインは外せない。ブログに写したファイルとイベントが残り、動き続けてしまう。
sub uninstall_removed_plugins {
	my $self = shift;
	my $ROBJ = $self->{ROBJ};
	my $pd   = $self->load_plugins_dat();

	my $flag;
	foreach my $name (@_) {
		# デザインモジュールは、複数置くと「名前,番号」の別名でも記録される
		my @names = sort { length($b) <=> length($a) } grep { $pd->{$_} && /^\Q$name\E(?:,\d+)?$/ } keys(%$pd);
		foreach my $n (@names) {
			# 外すときのイベント（ampは記事のテーブルに足したカラムを、デザインモジュールはCSSを消す）。
			# 処理はブログの側にあるので、プラグインのフォルダが無くても動く
			$self->call_event("UNINSTALL:$n");

			if ($self->plugin_uninstall($pd, { name => $n })) {
				$ROBJ->message("[plugin:%s] Uninstall failed", $n);
				next;
			}
			$flag = 1;
		}
	}
	if (!$flag) { return; }

	$ROBJ->fwrite_hash($self->{blog_dir} . 'plugins.dat', $pd);
	$self->set_event_info($self->{blog}, $pd);
}

#-------------------------------------------------------------------------------
# ●システムアップデート for Ver4.15
#-------------------------------------------------------------------------------
# WebPushを削除した。使う人がほとんどいないため
sub sys_update_415 {
	my $self = shift;
	my $ROBJ = $self->{ROBJ};
	$self->uninstall_removed_plugins('webpush');

	# 設定（送信用の鍵を含む）と、購読者の一覧を消す
	my $blog = $self->{blog};
	foreach(grep { substr($_,0,10) eq 'p:webpush:' } keys(%$blog)) {
		$self->update_blogset($blog, $_, undef);
	}
	$ROBJ->file_delete($self->{blog_dir} . 'webpush.dat');
}

#-------------------------------------------------------------------------------
# ●システムアップデート for Ver4.16
#-------------------------------------------------------------------------------
# 記事とゴミ箱のテーブルに、NSFWのフラグ（年齢確認を出す）のカラムを足す
# ※記事のスケルトンも変えたので、プラグインの再インストールでデザインのスケルトンも作り直す
sub sys_update_416 {
	my $self = shift;
	my $DB   = $self->{DB};
	my $ROBJ = $self->{ROBJ};
	my $r = 0;
	$r += $DB->add_column("art",   {name=>'nsfw', type=>'flag'});
	$r += $DB->add_column("trash", {name=>'nsfw', type=>'flag'});
	if ($r) { $ROBJ->message("Blog database error(%s)", $r); }

}

#-------------------------------------------------------------------------------
# ●システムアップデート for Ver4.18
#-------------------------------------------------------------------------------
# 非公開コメントを廃止した。書いた本人も見られず、やり取りもできないため
# 残っている非公開コメントを消し、記事とコメントのテーブルからカラムを消す
# コメントに承認待ち（hold）を足す。今あるコメントは承認済みとして扱うので、値は入れない
sub sys_update_418 {
	my $self = shift;
	my $DB   = $self->{DB};

	# 定義から外した後に作ったブログにはカラムが無く、エラーになるので出さない
	my $noerr = $DB->set_noerror(1);

	# 消した後は、edit_comment の削除と同じようにコメント数を数え直してイベントを呼ぶ
	my $ary = $DB->select_match("com", 'hidden', 1, '*cols', ['pkey', 'a_pkey']) || [];
	my @keylist = map { $_->{pkey} } @$ary;
	if (@keylist) {
		my %a_pkeys = map { $_->{a_pkey} => 1 } @$ary;
		my @a_pkeys = sort { $a <=> $b } keys(%a_pkeys);
		my $cnt = $DB->delete_match("com", 'pkey', \@keylist);
		foreach(@a_pkeys) {
			$self->calc_comments($_);
		}
		$self->call_event('COMMENTS_DELETE',      \@a_pkeys, \@keylist, $cnt);
		$self->call_event('COMMENT_STATE_CHANGE', \@a_pkeys, \@keylist);
		$self->call_event('ARTCOM_STATE_CHANGE',  \@a_pkeys, \@keylist);
	}
	$DB->delete_match("trashcom", 'hidden', 1);

	$DB->drop_column("com",      'hidden');
	$DB->drop_column("trashcom", 'hidden');
	$DB->drop_column("art",      'hcom_ok');
	$DB->drop_column("trash",    'hcom_ok');
	$DB->set_noerror($noerr);

	my $r = $DB->add_column("com",      {name=>'hold', type=>'flag'});
	$r   += $DB->add_column("trashcom", {name=>'hold', type=>'flag'});
	if ($r) { $self->{ROBJ}->message("Blog database error(%s)", $r); }

	my $blog = $self->{blog};
	foreach(qw(hcom_ok hcom_ok_force p:dec_comment-form:hidden_help)) {
		$self->update_blogset($blog, $_, undef);
	}
}

#-------------------------------------------------------------------------------
# ●システムアップデート for Ver4.19
#-------------------------------------------------------------------------------
# 動画の記事用のサムネイルを、ブラウザーのJPEG（品質0.85）ではなく、サーバーで作るようにした
# これより前に作ったものは、アップデートの後にブラウザーで作り直す（load_videos_need_thumbnail）
sub sys_update_419 {
	my $self = shift;
	$self->update_sysdat('video_poster_time', time());

	# 同時ログイン数を設定ファイルからシステム設定に移す。今の値を写して、動きを変えない
	if (!$self->{sys}->{max_sessions}) {
		my $max = int($self->{ROBJ}->{Auth}->{max_sessions});
		$self->update_sysdat('max_sessions', $max < 1 ? 1 : $max);
	}
}

#-------------------------------------------------------------------------------
# ●システムアップデート for Ver4.22
#-------------------------------------------------------------------------------
# 標準記法（default、default_p1、default_p2）のパーサーを削除した。
# ・設定ファイルの v.parsers から、スケルトンの無いパーサーの行を消す（4.11の書き換えと同じ処理。ほかの書き換えは済んでいれば何もしない）
# ・ブログの既定のパーサーが消したものなら、Markdownにする
# 標準記法で書いた記事は、作り直さない（保存してあるHTMLのまま出る）
sub sys_update_422 {
	my $self = shift;
	$self->update_conf_411('422');

	my $blog = $self->{blog};
	if (!$blog) { return; }
	if ($blog->{parser} ne '' && !$self->{ROBJ}->check_skeleton("_parser/$blog->{parser}")) {
		$self->update_blogset($blog, 'parser', 'markdown');
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
# ●システムアップデート for Ver4.25
#-------------------------------------------------------------------------------
# AVIFのサムネイルの画質を、JPEGと別の設定（album_avif_quality、既定65）にした。
# 設定ファイルに無ければ、album_jpeg_quality の行の後に足す（無いときも65で作るが、変えられることが分かるように）。
# # で止めてある行も、その人が決めたことなので、あれば触らない
sub sys_update_425 {
	my $self = shift;
	my $ROBJ = $self->{ROBJ};
	my $file = $ROBJ->{Conf_file};
	if (!-r $file) { return; }

	my $lines = $ROBJ->fread_lines($file);
	if (grep { /^#?\s*<\$v\.album_avif_quality\s*=/ } @$lines) { return; }

	my @add = ("# AVIFサムネイル生成時の品質\n", "<\$v.album_avif_quality = 65>\n");
	my @out;
	my $done;
	foreach my $line (@$lines) {
		push(@out, $line);
		if (!$done && $line =~ /^#?\s*<\$v\.album_jpeg_quality\s*=/) {
			push(@out, "\n", @add);
			$done = 1;
		}
	}
	if (!$done) {
		if (@out && $out[$#out] !~ /\n$/) { $out[$#out] .= "\n"; }
		push(@out, "\n", @add);
	}
	$self->write_conf_file($file, \@out, '425', "Can't update '%s'. Please add these lines by yourself.", \@add);
}

#-------------------------------------------------------------------------------
# ●システムアップデート for Ver4.24
#-------------------------------------------------------------------------------
# 2つ目のRSS（決めたタグの記事だけを rss2.xml に書き出す）を削除した。設定とファイルを消す。
# RSSの記録（rss_files）は、このあとの info=>1 の generate_rss で rss.xml だけになる
sub sys_update_424 {
	my $self = shift;
	my $ROBJ = $self->{ROBJ};
	my $blog = $self->{blog};
	foreach(qw(rss2_tag rss2_title rss2_no_comment)) {
		$self->update_blogset($blog, $_, undef);
	}
	$ROBJ->file_delete($self->{blogpub_dir} . 'rss2.xml');
}

#-------------------------------------------------------------------------------
# ●システムアップデート for Ver4.23
#-------------------------------------------------------------------------------
# パスワードをbcryptで保存するようにした。アップデートを行う管理者のパスワードは system_update で保存し直す。
# ほかのユーザーは、ハッシュがbcryptでないことで、次のログインの後に再設定を求める（force_pass_reset）
sub sys_update_423 {
	my $self = shift;
	my $ROBJ = $self->{ROBJ};
	my $auth = $ROBJ->{Auth};
	my $ary  = $auth->{DB}->select($auth->{table}, { cols => ['id', 'pass'] });
	my $cnt  = grep { $_->{id} ne $auth->{id} && $_->{pass} ne '*' && substr($_->{pass}, 0, 4) ne '$2b$' } @$ary;
	if ($cnt) {
		$ROBJ->message("%d users must reset the password at the next login", $cnt);
	}
}

#-------------------------------------------------------------------------------
# ●システムアップデート for Ver4.21
#-------------------------------------------------------------------------------
# ・公開フォルダを整理した。pub/css.d/ → data/blog/css.d/、pub/js/ → pub/plugin/js/、
#   pub/dynamic.css → pub/custom/dynamic.css（このあとのプラグインの入れ直しで作り直す）
# ・テーマの色の調整を、CSSファイル（pub/css/テンプレート.テーマ.css）からブログの設定（theme_custom:テーマ）に移した。
#   CSSは今のテーマの分だけ pub/custom/theme.css に、このあとの theme=>1 で作り直す
# ・消したテーマ（satsuki2-pop）のブログは、標準のテーマに戻す
# ・3カラムの選択肢（multi-sidebar）を選んでいたテーマは、3カラムのテーマ（-3col）の調整にし、
#   今のテーマならブログのテーマも切り替える
sub sys_update_421 {
	my $self = shift;
	my $ROBJ = $self->{ROBJ};
	my $blog = $self->{blog};
	if (!$blog) { return; }
	my $pub  = $self->blogpub_dir();
	$ROBJ->mkdir( $self->plugin_pub_dir() );

	# 消したテーマ
	if ($blog->{theme} =~ m|^satsuki2-pop/|) {
		$self->update_blogset($blog, 'theme', $self->{default_theme});
	}

	# テーマの色の調整を、ブログの設定に移す（読み方は前の load_theme_info と同じ）
	my $css_dir = "${pub}css/";
	foreach my $file (@{ -d $css_dir ? $ROBJ->search_files($css_dir, { ext => '.css' }) : [] }) {
		my $lines = $ROBJ->fread_lines("$css_dir$file");
		if (!grep { /\$c=/ } @$lines) {	# 色の調整でない（プラグインのCSS）
			$self->move_file_421($css_dir, $self->plugin_pub_dir() . 'css/', $file);
			next;
		}
		$ROBJ->file_delete("$css_dir$file");
		if ($file !~ /^([\w\-]+)\.([\w\-]+)\.css$/) { next; }
		my $theme = "$1/$2";
		if ($theme =~ m|^satsuki2-pop/|) { next; }

		my (%col, %opt);
		foreach(@$lines) {
			if ($_ =~ /\$(option\d*)=(.+)/) {
				my ($k, $v) = ($1, $2);
				$v =~ s|\s*\*/\s*$||;
				$opt{$k} = $v;
				next;
			}
			if ($_ !~ /(#[0-9A-Fa-f]+).*\$c=\s*(\w+)/) { next; }
			$col{$2} = $1;
		}
		if (($theme eq 'satsuki2/satsuki2' || $theme eq 'satsuki2/bigblue') && $opt{option} eq 'multi-sidebar') {
			delete $opt{option};
			if ($blog->{theme} eq $theme) {
				$self->update_blogset($blog, 'theme', "$theme-3col");
				$ROBJ->message("Change theme '%s' to '%s'", $theme, "$theme-3col");
			}
			$theme .= '-3col';
		}
		$self->save_theme_custom_values($theme, \%col, \%opt);
	}
	rmdir($css_dir);

	# 色の調整を使っているか（前はCSSのパスを入れていた）
	my $use = $blog->{theme_custom} ne '' && $blog->{"theme_custom:$blog->{theme}"} ne '';
	$self->update_blogset($blog, 'theme_custom', $use ? 1 : '');

	# 動的CSSの材料は公開しない。プラグインのJSの写しは pub/plugin/ へ（入れ直しで、ここから消して写し直す）
	$self->move_dir_files_410("${pub}css.d/", $self->dynamic_css_dir());
	$self->move_dir_files_410("${pub}js/",    $self->plugin_pub_dir() . 'js/');
	$ROBJ->file_delete("${pub}dynamic.css");
	$self->update_dynamic_css();
}
sub move_file_421 {
	my ($self, $src, $des, $file) = @_;
	my $ROBJ = $self->{ROBJ};
	$ROBJ->mkdir($des);
	if (-e "$des$file") {
		$ROBJ->message("Already exists '%s'", "$des$file");
		return;
	}
	rename("$src$file", "$des$file") || $ROBJ->message("Rename '%s' failed", "$src$file");
}

#-------------------------------------------------------------------------------
# ●データの持ち方の変更（Ver4.10）
#-------------------------------------------------------------------------------
# ブログは1つだけにしたので、ブログIDを使わない持ち方にする。
# ・テーブル    ブログID_art など → art など
# ・データ      data/blog/ブログID/ → data/blog/
# ・公開フォルダ pub/ブログID/ → pub/、画像は pub/ブログID/image/ → pub/attachments/（adiary/ は posts/ にする）
# ・記事の原文の記法（[image:…:adiary/…]）と、ブログの設定のパスを書き換える
# ・ブログ管理テーブル（_bloglist）とデフォルトブログ（default_blogid）を消す
# ※ブログIDのテーブルが無いとき（ブログを作る前など）は、_bloglistとdefault_blogidを消すだけ
sub migrate_410 {
	my $self = shift;
	my $ROBJ = $self->{ROBJ};
	my $DB   = $self->{DB};

	# 移すブログ（デフォルトブログ、無ければブログIDの順で最初のブログ）
	my $id = $self->{sys}->{default_blogid};
	if ($id !~ /^\w+$/ || !$DB->find_table("${id}_art")) {
		my $noerr = $DB->set_noerror(1);
		my $list  = $DB->select_match('_bloglist', '*cols', 'id');
		$DB->set_noerror($noerr);
		($id) = sort grep { /^\w+$/ && $DB->find_table("${_}_art") } map { $_->{id} } @$list;
	}
	if ($id ne '' && !$DB->find_table('art')) {
		$self->migrate_blog_410($id);
	}

	my $noerr = $DB->set_noerror(1);
	$DB->drop_table('_bloglist');
	$DB->set_noerror($noerr);
	$self->update_sysdat('default_blogid', undef);
	$self->update_sysdat('dir_postfix_len', undef);
	delete $self->{_cache_exists_blog};
}

sub migrate_blog_410 {
	my $self = shift;
	my $id   = shift;
	my $ROBJ = $self->{ROBJ};
	my $DB   = $self->{DB};
	$ROBJ->message("Migrate blog '%s'", $id);

	# テーブル
	foreach(qw(art com tag tagart rev trash trashcom link)) {
		if (!$DB->find_table("${id}_$_")) { next; }
		if ($DB->rename_table("${id}_$_", $_)) {
			$ROBJ->message("Rename table '%s' failed", "${id}_$_");
		}
	}
	my $noerr = $DB->set_noerror(1);
	$DB->drop_table("${id}_log");		# Ver2.97より前のもの
	$DB->set_noerror($noerr);

	# データ
	my $old_dir = "$self->{data_dir}blog/$id/";
	my $set     = $ROBJ->fread_hash("${old_dir}setting.dat");
	$self->move_dir_files_410($old_dir, $self->blog_dir());

	# 公開フォルダ（非公開モードで付けた文字列が付いていることがある）
	my $old_pub = "$self->{pub_dir}$id$set->{blogpub_dir_postfix}/";
	my $img_dir = $self->blogimg_dir();
	if (-d "${old_pub}image/") {
		rename("${old_pub}image/", $img_dir) || $ROBJ->message("Rename '%s' failed", "${old_pub}image/");
		if (-d "${img_dir}adiary/" && !-e "${img_dir}posts/") {
			rename("${img_dir}adiary/", "${img_dir}posts/") || $ROBJ->message("Rename '%s' failed", "${img_dir}adiary/");
		}
	}
	$self->move_dir_files_410($old_pub, $self->blogpub_dir());

	# ブログの設定のパス
	my %path = (
		"${old_pub}image/adiary/" => "${img_dir}posts/",
		"${old_pub}image/"        => $img_dir,
		$old_pub                  => $self->blogpub_dir()
	);
	my $re = join('|', map { quotemeta } sort { length($b) <=> length($a) } keys(%path));
	foreach(keys(%$set)) {
		$set->{$_} =~ s/($re)/$path{$1}/g;
	}
	$set->{edit_upload} =~ s|^adiary/|posts/|;
	delete $set->{blogpub_dir_postfix};
	$ROBJ->fwrite_hash($self->blog_dir() . 'setting.dat', $set);
	delete $self->{_cache_exists_blog};
	delete $self->{_loaded_bset};

	# 記事の原文の記法と、アイキャッチのパス
	foreach my $table (qw(art rev trash)) {
		if (!$DB->find_table($table)) { next; }
		my $cols = $table eq 'rev' ? ['pkey', '_text'] : ['pkey', '_text', 'main_image'];
		my $ary  = $DB->select_match($table, '*cols', $cols);
		$DB->begin();
		foreach(@$ary) {
			my %up;
			my $text = $_->{_text};
			if ($text =~ s/(\[(?:image|file):[^:\]\n]*:)adiary\//$1posts\//g) { $up{_text} = $text; }
			my $img  = $_->{main_image};
			if ($img ne '' && $img =~ s/($re)/$path{$1}/g) { $up{main_image} = $img; }
			if (%up) { $DB->update_match($table, \%up, 'pkey', $_->{pkey}); }
		}
		if ($DB->commit()) { $ROBJ->message("Blog database error(%s)", $table); }
	}

	# ブログに写したプラグインの処理が古いテーブル名を使っているので、先に入れ直す
	if ($self->select_blog()) {
		local($self->{stop_plugin_install_msg}) = 1;
		$self->reinstall_plugins();
	}
}

# $src の中身を $des に移し、$src を消す（同じ名前のものがあれば移さない）
sub move_dir_files_410 {
	my ($self, $src, $des) = @_;
	my $ROBJ = $self->{ROBJ};
	if (!-d $src) { return; }
	$ROBJ->mkdir($des);

	opendir(my $dh, $src) || return;
	my @files = grep { $_ ne '.' && $_ ne '..' } readdir($dh);
	closedir($dh);
	foreach(@files) {
		if (-e "$des$_") {
			$ROBJ->message("Already exists '%s'", "$des$_");
			next;
		}
		rename("$src$_", "$des$_") || $ROBJ->message("Rename '%s' failed", "$src$_");
	}
	rmdir($src);
}

#-------------------------------------------------------------------------------
# ●システムアップデート for Ver4.11
#-------------------------------------------------------------------------------
# 4.09〜4.11で消した機能の設定を片付ける
# ・設定ファイル（lyndbaum.conf.cgi）：公開フォルダのパスの定数、消したパーサー、消した設定
# ・ブログの設定とシステムの設定：消した機能のキー
# ・新しいブログの初期設定のファイル（data/default_setting.dat）
sub sys_update_411 {
	my $self = shift;
	$self->update_conf_411();

	# システムの設定と、新しいブログの初期設定のファイル（1つのadiaryで複数のブログを持つ機能。4.10）
	$self->update_sysdat('create_blog_only_admin', undef);
	my $file = $self->{data_dir} . 'default_setting.dat';
	if (-e $file) {
		my $ok = $self->{ROBJ}->file_delete($file);
		$self->{ROBJ}->message($ok ? "Delete '%s'" : "Delete '%s' failed", $file);
	}

	my $blog = $self->{blog};
	if (!$blog) { return; }
	# tw_ping：Twitterへの投稿（4.09）、gaid：Universal Analytics（4.09）
	# fb_admins、fb_app_id、asid：使われていなかった設定（4.09）
	# spmenu、spmenu_info_all：スマホ用のメニュー（4.09）
	# album_blogs：ブログを選ぶアルバム（4.10）、rst：reStructuredTextで入力する設定（4.10）
	# sysmode_notheme：システムモードでテーマを使わない警告（管理画面はテーマを使わなくなった）
	foreach(qw(tw_ping gaid fb_admins fb_app_id asid spmenu spmenu_info_all album_blogs rst sysmode_notheme)) {
		if (!exists($blog->{$_})) { next; }
		$self->update_blogset($blog, $_, undef);
	}
	# 消したパーサーが既定になっていたら、Markdownにする（標準記法は4.22で削除した）
	if ($blog->{parser} ne '' && !$self->{ROBJ}->check_skeleton("_parser/$blog->{parser}")) {
		$self->update_blogset($blog, 'parser', 'markdown');
	}
}

#-------------------------------------------------------------------------------
# ●設定ファイル（lyndbaum.conf.cgi）の書き換え（Ver4.11）
#-------------------------------------------------------------------------------
# 設定ファイルはgitで管理していないので、見本（lyndbaum.conf.cgi.sample）を変えても届かない。
# 書き換える前のファイルは、データのフォルダに写しておく。書き込めなければ、消す行を知らせる
my %Conf_path_411 = (
	pubdist_dir	=> [ 'pub-dist/', 'pub/assets/dist/'  ],
	theme_dir	=> [ 'theme/',    'pub/assets/theme/' ],
	script_dir	=> [ 'js/',       'pub/assets/js/'    ]
);
my $Conf_removed_411 = qr/^#?\s*<\$(?:Secure_time|v\.my_default_setting_file|v\.v2conf|v\.subdomain_mode|v\.subdomain_secure|v\.special_export)\s*=/;
my %Conf_removed_comment_411 = map { $_ => 1 } (
	'# ○Version2からの移行設定（絶対パスでも可）',
	'# ●サブドメインモードに設定し、ドメイン部を指定',
	'# サブドメインモード時、cookie の扱いを各ドメイン（ブログ）ごとに限定',
	'# セキュリティIDの有効期限',
	'# Sphinx連携機能など特殊export機能の許可（管理者のみ）'
);
sub update_conf_411 {
	my $self = shift;
	my $ver  = shift || '411';	# 書き換える前のファイルの控えの名前に付ける
	my $ROBJ = $self->{ROBJ};
	my $file = $ROBJ->{Conf_file};
	if (!-r $file) { return; }

	my $lines = $ROBJ->fread_lines($file);
	my @out;
	my @removed;
	my $in_parsers;
	my $skip_blank;
	foreach my $line (@$lines) {
		my $remove;
		if ($line =~ /^<\$v\.parsers\s*=\s*begin_hash/) {
			$in_parsers = 1;
		} elsif ($in_parsers && $line =~ /^<\$end>/) {
			$in_parsers = 0;
		} elsif ($in_parsers && $line =~ /^\s*(\w+)\s*=/) {
			# パーサーのスケルトン（skel/_parser/）が無いもの。reStructuredText（4.10）、標準記法（4.22）など
			$remove = !$ROBJ->check_skeleton("_parser/$1");
		} elsif ($line =~ $Conf_removed_411) {
			$remove = 1;
		} else {
			my $x = $line;
			$x =~ s/\s+$//;
			$remove = $Conf_removed_comment_411{$x};
		}
		if ($remove) {
			push(@removed, $line);
			$skip_blank = 1;
			next;
		}
		# 消したまとまりの後の空行は、前も空行なら詰める
		if ($skip_blank && $line =~ /^\s*$/ && (!@out || $out[$#out] =~ /^\s*$/)) {
			next;
		}
		$skip_blank = 0;

		# 公開フォルダのパス（4.11）。前の既定値のときだけ変える
		if ($line =~ /^<\$constant\((\w+)\)\s*=\s*'([^']*)'>/ && $Conf_path_411{$1} && $Conf_path_411{$1}->[0] eq $2) {
			my ($name, $old) = ($1, $2);
			my $new = $Conf_path_411{$name}->[1];
			push(@removed, $line);
			$line =~ s/'\Q$old\E'/'$new'/;
		}
		push(@out, $line);
	}
	if (!@removed) { return; }
	$self->write_conf_file($file, \@out, $ver, "Can't update '%s'. Please edit these lines by yourself.", \@removed);
}

#-------------------------------------------------------------------------------
# ○設定ファイルを書き換える
#-------------------------------------------------------------------------------
# 書き換える前のファイルを、データのフォルダに写してから書く。
# 書き込めなければ、$msg と、直す行（$lines）を知らせる
sub write_conf_file {
	my ($self, $file, $out, $ver, $msg, $lines) = @_;
	my $ROBJ = $self->{ROBJ};

	my $base   = $file =~ m|([^/]+)$| ? $1 : $file;
	my $backup = $self->{data_dir} . "$base.$ver.bak";
	my $err    = $ROBJ->file_copy($file, $backup);
	if (!$err) {
		$err = $ROBJ->fwrite_lines($file, $out);
	}
	if ($err) {
		$ROBJ->clear_error();
		$ROBJ->message($msg, $file);
		foreach(@$lines) {
			my $x = $_;
			$x =~ s/\s+$//;
			$ROBJ->message("  %s", $x);
		}
		return;
	}
	$ROBJ->message("Update '%s' (backup: '%s')", $file, $backup);
}

#-------------------------------------------------------------------------------
# ●システムアップデート for Ver4.12
#-------------------------------------------------------------------------------
# 4.11の片付け（sys_update_411）は後から足したので、4.11にしてあった環境ではここで行う
sub sys_update_412 {
	my $self = shift;
	if ($self->{sys}->{VERSION} >= 4.11) {
		$self->sys_update_411();
	}
	# アルバムモードと、アルバムを誰でも見られるようにする設定
	my $blog = $self->{blog};
	if (!$blog) { return; }
	foreach(qw(album_mode album_open_access)) {
		if (!exists($blog->{$_})) { next; }
		$self->update_blogset($blog, $_, undef);
	}
}

#-------------------------------------------------------------------------------
# ●見出しに、今の見出しのIDを識別子[#id]として書き足す（Ver3.53）
#-------------------------------------------------------------------------------
# 見出しは行を見て探す（引用とリストとコードフェンスの中は見ない）。
# 書き足す前と後で変換結果がまったく同じになる時だけ書き足し、違えば元の原文を返す。
sub freeze_heading_ids_353 {
	my $self   = shift;
	my $parser = shift;
	my $text   = shift;
	my $ID = qr/[^\x00-\x20\x7F\]]+/;	# 識別子に使える文字

	my @before = $parser->parse($text);
	my @ids    = @{ $parser->{heading_ids} || [] };
	if (!@ids) { return $text; }

	my $n = 0;
	my $added = 0;
	my $fence;
	my $quote;
	my $list;
	my $blank;
	my @lines = split(/\n/, $text, -1);
	foreach(@lines) {
		# 引用は空行まで続く（>の無い行も引用の中）。
		# リストは、空行の後に字下げの無い行が来るまで続く（字下げの無い行も、空行の前なら項目の続き）。
		if ($_ =~ /^\s*$/) {
			undef $quote;
			$blank = 1;
		} else {
			if (/^ ? ? ?>/) { $quote = 1; }
			if (/^\s*(?:[\*\+\-]|\d+\.) +/) { $list = 1; }
			elsif ($blank && /^\S/) { undef $list; }
			undef $blank;
		}
		# 引用の>とリストの記号を除く
		my $rest = $_;
		$rest =~ s/^(?: ? ? ?>\s?|\s*(?:[\*\+\-]|\d+\.) +)*\s*//;
		if (defined $fence) {
			if ($rest =~ /^\Q$fence\E[`~]*\s*$/) { undef $fence; }
			next;
		}
		if ($rest =~ /^(```+|~~~+)/) {
			$fence = $1;
			next;
		}
		if ($quote || $list) { next; }	# 引用とリストの中の#は見出しにならない
		if ($_ !~ /^#+\s+(.*?)$/) { next; }
		my $title = $1;
		my $id = $ids[$n++];
		if ($title =~ /^(?:(.*?)[ \t]+)?\[#$ID\][ \t]*$/) { next; }	# 識別子がある
		if (!defined $id || $id !~ /^$ID$/) { return $text; }
		$_ =~ s/[ \t]*$/ [#$id]/;
		$added++;
	}
	if (!$added || $n != @ids) { return $text; }

	my $new   = join("\n", @lines);
	my @after = $parser->parse($new);
	if ($before[0] ne $after[0] || $before[1] ne $after[1]) { return $text; }
	return $new;
}

#-------------------------------------------------------------------------------
# ●画像の代替テキストや添付ファイルの名前を整える
#-------------------------------------------------------------------------------
# ファイル名と同じ代替テキストや名前を落とす。画像は代替テキストを書きやすいよう、末尾に : を付ける。
# [image:S:folder/:x.png:x.png] → [image:S:folder/:x.png:]（image:Lも同じ）
# [image:S:folder/:x.png]       → [image:S:folder/:x.png:]
# [file:mp4:folder/:x.mp4:x.mp4] → [file:mp4:folder/:x.mp4]
# コードフェンスとコードスパンの中は書き換えない。
sub normalize_file_alt {
	my $self = shift;
	my $replace = sub {
		$_[0] =~ s/\[image:([SL]):([^\]:]*):([^\]:]+)(?::\3)?\]/[image:$1:$2:$3:]/g;
		$_[0] =~ s/\[file:([^\]:]*):([^\]:]*):([^\]:]+):\3\]/[file:$1:$2:$3]/g;
	};
	my $fence;
	my @lines = split(/\n/, shift, -1);
	foreach(@lines) {
		# コードフェンスの中は書き換えない
		if (defined $fence) {
			if (/^\s*\Q$fence\E[`~]*\s*$/) { undef $fence; }
			next;
		}
		if (/^\s*(```+|~~~+)/) { $fence = $1; next; }

		# コードスパンの中は書き換えない
		my @parts = split(/((?<!`)(`+)(?!`).*?(?<!`)\2(?!`))/, $_);
		my $out = '';
		while(@parts) {
			my $t = shift(@parts);
			&$replace($t);
			$out .= $t;
			if (@parts) {
				$out .= shift(@parts);	# コードスパン
				shift(@parts);		# splitの中の\2の分
			}
		}
		$_ = $out;
	}
	return join("\n", @lines);
}

1;
