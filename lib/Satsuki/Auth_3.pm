use strict;
package Satsuki::Auth;
################################################################################
# ■ユーザーの管理
################################################################################
#-------------------------------------------------------------------------------
# ●ユーザーの追加
#-------------------------------------------------------------------------------
sub user_add {
	my ($self, $form, $ext) = @_;
	my $ROBJ  = $self->{ROBJ};
	my $DB    = $self->{DB};
	my $table = $self->{table};
	if (! $self->{isadmin}) {
		return { ret=>1, msg => $ROBJ->translate('Operation not permitted') };
	}

	$ROBJ->clear_form_err();

	# データチェック
	$form->{new_user} = 1;
	my $insert = $self->check_user_data( $form, $ext );

	# 追加チェック（上と順番を入れ替えないこと）
	my $id = $form->{id};
	if ($DB->select_match_pkey1($table, 'id', $id)) {
		$ROBJ->form_err('id', "ID '%s' already exists", $id);
	}
	if ($form->{pass} eq '' && $form->{crypted_pass} eq '') {
		$ROBJ->form_err('pass', 'Password is empty');
	}

	# エラー終了
	my $errs = $ROBJ->form_err();
	if (!$insert || $errs) {
		return { ret=>10, errs => $errs };
	}

	# ユーザーデータの追加
	$insert->{login_c} = 0;
	$insert->{fail_c}  = 0;
	my $r = $DB->insert( $table, $insert );
	if ($r) {
		$self->log_save($id, 'regist');
		return { ret => 0 };
	}
	return { ret => -1, msg => 'Internal Error' };
}

#-------------------------------------------------------------------------------
# ●削除処理
#-------------------------------------------------------------------------------
sub user_delete {
	my $self = shift;
	my $del  = ref($_[0]) ? shift : (defined($_[0]) ? [shift] : []);
	my $col  = shift || 'id';
	my $ROBJ = $self->{ROBJ};

	if (! $self->{isadmin}) {
		return { ret=>1, msg => $ROBJ->translate('Operation not permitted') };
	}
	if (!@$del) {
		return { ret=>10, msg => $ROBJ->translate('No assignment delete user') };
	}

	my $DB    = $self->{DB};
	my $table = $self->{table};
	my $ary   = $DB->select_match($table, $col, $del, '*sort', 'pkey');

	$DB->begin();
	$DB->delete_match($table . '_sid', $col, $del);
	my $r1 = $DB->delete_match($table, $col, $del);
	my $r2 = $DB->commit();

	if ($r1 != $#$del+1 || $r2) {
		$DB->rollback();
		return { ret=>-1, msg => "DB delete error: $r1 / " . ($#$del+1) };
	}
	foreach(@$ary) {
		$self->log_save($_->{id}, 'delete');
	}
	return { ret => 0 };
}

################################################################################
# ■ユーザー本人による変更
################################################################################
#-------------------------------------------------------------------------------
# ●ユーザー情報の変更（ユーザー本人）
#-------------------------------------------------------------------------------
sub change_user_info {
	my ($self, $form, $ext) = @_;
	my $ROBJ = $self->{ROBJ};
	if (! $self->{ok}) { return { ret=>1, msg => $ROBJ->translate('No login') }; }
	if ($self->{auto}) { return { ret=>2, msg => $ROBJ->translate("Can't execute with 'root*'") }; }

	my %update = (id => $self->{id});

	my $ary = $self->allow_user_change_columns();
	foreach(@$ary) {
		if (exists($form->{$_})) {
			$update{$_} = $form->{$_};
		}
	}

	#
	# パスワード変更確認
	#
	if ($form->{now_pass} ne '') {
		if (! $self->check_pass_by_id($self->{id}, $form->{now_pass})) {
			return { ret=>10, msg => $ROBJ->translate('Incorrect password') };
		}
		if (exists($form->{pass} )) { $update{pass}  = $form->{pass};  }
		if (exists($form->{pass2})) { $update{pass2} = $form->{pass2}; }
	}

	return $self->update_user_data( \%update, $ext );
}

#-------------------------------------------------------------------------------
# ●セキュアな変更
#-------------------------------------------------------------------------------
sub change_pass {
	my ($self, $form) = @_;
	my $ROBJ = $self->{ROBJ};
	if (! $self->{ok}) { return { ret=>1, msg => $ROBJ->translate('No login') }; }
	if ($self->{auto}) { return { ret=>2, msg => $ROBJ->translate("Can't execute with 'root*'") }; }
	if ($form->{pass} eq '') {
		return { ret=>3, msg => $ROBJ->translate('New password is empty') };
	}

	my $id = $self->{id};
	if (! $self->check_pass_by_id($id, $form->{now_pass})) {
		return { ret=>10, msg => $ROBJ->translate('Incorrect password') };
	}

	return $self->update_user_data( {
		id    => $id,
		pass  => $form->{pass},
		pass2 => $form->{pass2}
	} );
}

################################################################################
# ■スケルトンルーチン
################################################################################
#-------------------------------------------------------------------------------
# ●全ユーザー情報のロード
#-------------------------------------------------------------------------------
sub load_users {
	my ($self, $sort) = @_;
	if (!$self->{isadmin}) { return []; }
	my $DB = $self->{DB};

	my $list = $DB->select_match($self->{table}, '*sort', $sort || 'id');
	foreach(@$list) {
		delete $_->{pass};
	}
	return $list;
}

#-------------------------------------------------------------------------------
# ●ユーザー情報のロード（パスワード以外）
#-------------------------------------------------------------------------------
sub load_user_info {
	my $self = shift;
	my $id   = shift;
	my $col  = shift || 'id';
	if (!$self->{isadmin}) { return; }

	my $DB = $self->{DB};
	my $h  = $DB->select_match_limit1( $self->{table}, $col, $id );
	if (!$h) { return; }

	delete($h->{pass});
	return $h;
}

#-------------------------------------------------------------------------------
# ●ログのロード
#-------------------------------------------------------------------------------
sub load_logs {
	my $self  = shift;
	my $query = shift;
	if (!$self->{isadmin}) { return wantarray ? ([], 0) : []; }
	my $DB    = $self->{DB};
	my $table = $self->{table} . '_log';

	my %h = (
		limit	=> int($query->{limit}) || 100,
		offset	=> int($query->{offset}),
		sort	=> $query->{sort} || ['-tm', '-pkey']
	);
	if ($query->{id} ne '') {
		$h{match}->{id} = $query->{id};
	}
	if ($query->{type} ne '') {
		$h{match}->{type} = $query->{type};
	}
	# 失敗はmsgに'fail'などが入る。成功は空
	if ($query->{result} eq 'ok') {
		$h{is_null}  = ['msg'];
	} elsif ($query->{result} eq 'fail') {
		$h{not_null} = ['msg'];
	}

	my $y = int($query->{year});
	my $m = int($query->{mon});
	(1969<$y) && eval {
		require Time::Local;
		if (0<$m && $m<13) {
			$h{min}->{tm} = Time::Local::timelocal(0,0,0,1,$m-1,$y-1900);
			if ($m==12) { $m=1; $y++; }
			$h{max}->{tm} = Time::Local::timelocal(0,0,0,1,$m,  $y-1900) -1;
		} else {
			$h{min}->{tm} = Time::Local::timelocal(0,0,0,1,0,$y-1900);
			$h{max}->{tm} = Time::Local::timelocal(0,0,0,1,0,$y-1900 +1) -1;
		}
	};

	my ($logs, $hits) = $DB->select($table, \%h);
	return wantarray ? ($logs, $hits) : $logs;
}

################################################################################
# ■サブルーチン
################################################################################
#-------------------------------------------------------------------------------
# ●ユーザーデータの整合性確認
#-------------------------------------------------------------------------------
sub check_user_data {
	my ($self, $user, $ext) = @_;
	my $ROBJ = $self->{ROBJ};
	my $DB   = $self->{DB};

	$ROBJ->clear_form_err();

	# 整形済ユーザーデータ
	if (! ref $user eq 'HASH') {
		$ROBJ->form_err('', 'Internal Error(%s)', 'in check_user_data()');
		return undef;
	}

	# update用データ
	my %update;

	# IDの確認
	my $id = $user->{id};
	$id =~ s/[\r\n\0]//g;
	$ROBJ->trim($id);
	$user->{id} = $id;
	if ($id eq '') {
		$ROBJ->form_err('id', 'ID is empty');
	} else {
		if ($self->{uid_lower_rule}) {
			   if ($id =~ /\W/)     { $ROBJ->form_err('id',"ID's character allowed \"%s\" only", "0-9, a-z" . ($self->{uid_underscore} ? ', _':'')); }
			elsif ($id =~ /[A-Z]/)  { $ROBJ->form_err('id',"Don't use upper case in ID"); }
			elsif ($id =~ /^[\d_]/) { $ROBJ->form_err('id','ID first character must be lower case between "a" to "z"'); }
		} else {
			if ($id =~ /\W/) { $ROBJ->form_err('id',"ID's character allowed \"%s\" only", "0-9, A-Z, a-z" . ($self->{uid_underscore} ? ', _':'')); }
		}
		if (!$self->{uid_underscore} && $id =~ /_/) {
			if ($id =~ /^[\d_]/) { $ROBJ->form_err('id',"Don't use `_' in ID"); }
		}
		if ($id =~ /[\"\'<> ]/) {
			$ROBJ->form_err('id','ID not allow ", \', <, >, space character');
		}
		if (length($id) > $self->{uid_max_length}) {
			$ROBJ->form_err('id',"Too long ID (max %d)", $self->{uid_max_length});
		}
	}

	# ユーザー名の確認
	if (exists($user->{name})) {
		my $name = $user->{name};
		$ROBJ->trim($name);
		$name =~ s/[\r\n\0]//g;

		if ($name eq '') { $ROBJ->form_err('name','Name is empty'); }
		if ($self->{name_notag} && $name =~ /[\"\'<>]/) {
			$ROBJ->form_err('name','Name not allow ", \', <, > charcteor');
		}
		if (length($name) > $self->{name_max_length}) {
			$ROBJ->form_err('name',"Too long name (max %d)", $self->{name_max_length});
		}
		$update{name} = $name;
	}

	# emailカラム
	if (exists($user->{email})) {
		my $email = $user->{email};
		$email =~ s/[<>\"\'\r\n\s]//g;

		$update{email} = $email;
	}

	# 拡張カラム
	if ($ext) {
		my %h = map { $_ => 1 } @{ $self->load_main_table_columns() };
		foreach(keys(%$ext)) {
			if ($h{$_}) {
				$ROBJ->form_err('', "'%s' are not allowed in the forced column", $_);
				next;
			}
			$update{$_} = $ext->{$_};
		}
	}

	# パスワードの確認
	my $pass = $user->{pass};
	if ($pass ne '' && $self->check_new_pass($pass, $user->{pass2})) {	# パスワードを変更する
		my $crypted = $self->hash_pass($pass);
		if (defined $crypted) {
			$update{pass} = $crypted;
		} else {
			$ROBJ->form_err('pass', "bcrypt is not supported on this server");
		}
	}
	if ($user->{crypted_pass}) { $update{pass}=$user->{crypted_pass}; }
	if ($user->{disable_pass}) { $update{pass}='*'; }

	# エラー処理
	if ($ROBJ->form_err()) { return undef; }	# エラーがあった

	# ユーザーデータ生成
	if ($user->{new_user}) {
		$update{id}    = $id;
	}

	return \%update;
}

#-------------------------------------------------------------------------------
# ●ユーザーデータのアップデート
#-------------------------------------------------------------------------------
sub update_user_data {
	my ($self, $_update, $force) = @_;
	my $ROBJ = $self->{ROBJ};
	$ROBJ->clear_form_err();

	my $id = $_update->{id};
	my $update = $self->check_user_data($_update, $force);

	# エラー終了
	my $errs = $ROBJ->form_err();
	if (!$update || $errs) {
		return { ret=>10, errs => $errs };
	}

	my $DB = $self->{DB};
	my $r  = $DB->update_match( $self->{table}, $update, 'id', $id);
	if ($r != 1) {
		return { ret=>-1, msg => 'DB update error' };
	}
	# パスワード変更時は全セッションを削除（盗まれたセッションを使えなくするため）
	if (exists($update->{pass})) {
		$DB->delete_match($self->{table} . '_sid', 'id', $id);
	}

	$self->log_save($id, 'update');
	return { ret => 0 };
}

#-------------------------------------------------------------------------------
# ●新しいパスワードが規則に合うか確かめる
#-------------------------------------------------------------------------------
# 合わなければform_errを積んで偽を返す。$pass2がundefなら確認用との比較はしない
sub check_new_pass {
	my ($self, $pass, $pass2) = @_;
	my $ROBJ = $self->{ROBJ};

	my $ok = 1;
	if ($self->{disallow_num_pass} && $pass =~ /^\d+$/) {
		$ROBJ->form_err('pass', "Not allow password is number only");
		$ok = 0;
	}
	if (length($pass) < $self->{pass_min}) {
		$ROBJ->form_err('pass',"Too short password (min %d)", $self->{pass_min});
		return 0;
	}
	# bcryptは72バイトより後を無視するので、長すぎるものは断る
	if (do { use bytes; length($pass) } > 72) {
		$ROBJ->form_err('pass',"Too long password (max %d bytes)", 72);
		return 0;
	}
	if (defined $pass2 && $pass ne $pass2) {
		$ROBJ->form_err('pass2',"Mismatch password and retype password");
		return 0;
	}
	return $ok;
}

#-------------------------------------------------------------------------------
# ●パスワードをbcryptでハッシュにする
#-------------------------------------------------------------------------------
# OSのcrypt()の$2b$を使う。対応していなければundef
my $BCRYPT_COST = 12;
my $BCRYPT_B64  = './ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789';
sub hash_pass {
	my ($self, $plain) = @_;

	# 16バイトの乱数を、bcryptのBase64で22文字にする
	my $raw;
	if (open(my $fh, '<:raw', '/dev/urandom')) {
		read($fh, $raw, 16);
		close($fh);
	}
	if (length($raw) != 16) { return; }
	my $bits = unpack('B*', $raw) . '0000';		# 128bit → 132bit（6bit×22）
	my $salt = join('', map { substr($BCRYPT_B64, oct("0b$_"), 1) } ($bits =~ /(.{6})/g));

	my $prefix = sprintf('$2b$%02d$', $BCRYPT_COST);
	my $crypted = crypt($plain, $prefix . $salt);
	if (!defined $crypted || substr($crypted, 0, length($prefix)) ne $prefix || length($crypted) != 60) { return; }
	return $crypted;
}

#-------------------------------------------------------------------------------
# ●パスワードを確認する
#-------------------------------------------------------------------------------
sub check_pass_by_id {
	my ($self, $id, $pass) = @_;
	my $DB = $self->{DB};

	my $h = $DB->select_match_limit1($self->{table}, 'id', $id, '*cols', 'pass');
	if (!$h || $h->{'pass'} eq '*') { return; }
	return $self->check_pass($h->{'pass'}, $pass);
}

#-------------------------------------------------------------------------------
# ●sudo機能
#-------------------------------------------------------------------------------
sub sudo {
	my $self = shift;
	my $func = shift;
	my @bak = ($self->{ok}, $self->{isadmin});
	$self->{ok} = $self->{isadmin} = 1;
	my $r = $self->$func(@_);
	($self->{ok}, $self->{isadmin}) = @bak;
	return $r;
}

################################################################################
# ■ユーザーデータベースの作成
################################################################################
sub load_main_table_columns {
	my $self = shift;
	return [ qw(pkey  id name pass email  login_c login_tm fail_c fail_tm) ];
}
sub allow_user_change_columns {
	my $self = shift;
	return [ qw(name email) ];
}
sub create_user_table {
	my $self  = shift;
	my $DB    = $self->{DB};
	my $table = $self->{table};

	$DB->begin();

	my %cols;
	$cols{text}    = [ qw(id name pass email) ];
	$cols{int}     = [ qw(login_c login_tm fail_c fail_tm) ];
	$cols{flag}    = [ qw() ];
	$cols{idx}     = [ qw(id email) ];
	$cols{unique}  = [ qw(id email) ];
	$cols{notnull} = [ qw(id name) ];
	$DB->create_table_wrapper($table, \%cols, $self->{extcol});

	undef %cols;
	$cols{text}    = [ qw(id sid) ];
	$cols{int}     = [ qw(login_tm) ];
	$cols{flag}    = [ qw() ];
	$cols{idx}     = [ qw(id sid login_tm) ];
	$cols{unique}  = [ qw() ];
	$cols{notnull} = [ qw(id sid login_tm) ];
	$cols{ref}     = { id => "$table.id" };
	$DB->create_table_wrapper("${table}_sid", \%cols);

	undef %cols;
	$cols{text}    = [ qw(id type msg ip host agent) ];
	$cols{int}     = [ qw(tm) ];
	$cols{flag}    = [ qw() ];
	$cols{idx}     = [ qw(id type ip tm) ];
	$cols{unique}  = [ qw() ];
	$cols{notnull} = [ qw(tm) ];
	# 不正IDを記録できるように、参照制約は付けない
	# $cols{ref}     = { id => "$table.id" };
	$DB->create_table_wrapper("${table}_log", \%cols);

	$DB->commit();
}

#-------------------------------------------------------------------------------
# ●カラムの追加
#-------------------------------------------------------------------------------
sub add_column {
	my $self  = shift;
	my $h     = shift;
	my $DB    = $self->{DB};
	my $table = $self->{table};

	return $DB->add_column($table, $h);
}

1;
