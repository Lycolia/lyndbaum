use strict;
package Satsuki::Auth;
################################################################################
# ■認証ルーチン
################################################################################
#-------------------------------------------------------------------------------
# ●ログイン
#-------------------------------------------------------------------------------
sub login {
	my $self   = shift;
	my $id     = shift;
	my $pass   = shift;
	my $secret = shift;
	my $ROBJ   = $self->{ROBJ};
	my $DB     = $self->{DB};
	$self->userdb_init();

	# IP/HOST制限
	if (! $ROBJ->check_ip_host($self->{allow_ip}, $self->{allow_host})) {
		$self->log_save($id, 'login', 'fail (IP)');
		return { ret=>1, msg=>'security error' };
	}

	# ID確認
	my $table = $self->{table};
	my $udata;
	if ($id ne '' && $self->{uid_alt_col} ne '') {
		# idではないカラムをid代わりに利用する
		$udata = $DB->select_match_limit1($table, $self->{uid_alt_col}, $id);
	}
	if (!$udata) {
		$udata = $DB->select_match_limit1($table, 'id', $id);
	}
	# 失敗したときのメッセージ。IDが無い・パスワードが違う・ロック中を見分けられないよう同じにする
	my $fail_msg = $ROBJ->translate('Username or password incorrect, or too many failed. Please retry in %d minutes.', $self->{fail_minute});

	# 同じIPからの失敗が多ければ止める。アカウントの失敗の回数には足さない
	if (0 < $self->{fail_count_ip} && $self->count_ip_fails() >= $self->{fail_count_ip}) {
		$self->dummy_check_pass($pass);
		$self->log_save($id, 'login', 'fail (IP limit)');
		return { ret=>12, msg => $fail_msg };
	}

	if (!$udata || !%$udata) {	# uid が存在しない
		$self->dummy_check_pass($pass);		# 応答時間でIDの有無が分からないように
		$self->log_save_fail($id, 'login');
		return { ret=>10, msg => $fail_msg };
	}
	$id = $udata->{id};

	# 失敗カウントを参照
	# 一定時間経過したら、失敗カウンタを 0 に初期化
	my $fails = $udata->{fail_c};
	if ($udata->{fail_tm} + $self->{fail_minute}*60 < $ROBJ->{TM}) { $fails=0; }
	if (0 < $self->{fail_count} && $fails >= $self->{fail_count}) {
		$self->dummy_check_pass($pass);
		$self->log_save_fail($id, 'login');
		return { ret=>11, msg => $fail_msg };
	}
	if (!$self->check_pass($udata->{pass}, $pass)) {
		$fails++;
		$DB->update_match($table, {fail_c => $fails, fail_tm => $ROBJ->{TM}}, 'id', $id);
		$self->log_save_fail($id, 'login');
		return { ret=>10, msg => $fail_msg };
	}

	# 既にログイン済の場合、ログアウト
	if ($self->{id}) {
		$self->logout();
	}

	# ログイン成功
	$self->set_logininfo($udata, $secret);

	# 期限切れセッションを削除（全ユーザー分）
	my $expires = $self->{expires};
	if (0<$expires) {
		my $old = $DB->select($table.'_sid', {
			lt   => { login_tm => $ROBJ->{TM} - $expires },
			cols => ['pkey']
		});
		if (@$old) {
			$DB->delete_match($table.'_sid', 'pkey', [ map { $_->{pkey} } @$old ]);
		}
	}

	# 同一IDの古いログインセッションを削除
	my @del_pkeys;
	my $sessions = $DB->select_match($table.'_sid', 'id', $id);
	if ($#$sessions >= $self->{sessions}-1) {	# セッションが多い
		# 降順ソート
		$sessions = [ sort {$b->{login_tm} <=> $a->{login_tm}} @$sessions ];
		my $max = $self->{max_sessions}-1;	# 最大ログイン数
		if ($max<0) { $max=0; }			# safety logic
		while($#$sessions >= $max) {
			my $x = pop(@$sessions);
			push(@del_pkeys, $x->{pkey});
		}
		if (@del_pkeys) {
			$DB->delete_match($table.'_sid', 'pkey', \@del_pkeys);
		}
	}

	# セッションIDの生成と保存
	my $sid = $ROBJ->generate_nonce(32);
	$DB->insert("${table}_sid", {
		id       => $id,
		sid      => $sid,
		login_tm => $ROBJ->{TM},
	});
	# ログイン回数加算
	my $login_c = ++$self->{ext}->{login_c};
	# 成功したら失敗カウントを戻す
	$DB->update_match($table, { login_c=>$login_c, login_tm=>$ROBJ->{TM}, fail_c=>0 }, 'id', $id);

	# ログ保存
	$self->log_save($id, 'login');
	return { ret=>0, sid=>$sid };
}

#-------------------------------------------------------------------------------
# ●同じIPからのログインの失敗を数える
#-------------------------------------------------------------------------------
# 直近fail_minute分のログから数える。同じIPで成功していたら、それより前は数えない
sub count_ip_fails {
	my $self = shift;
	my $ROBJ = $self->{ROBJ};
	my $ip   = $self->ip_group($ENV{REMOTE_ADDR});

	my $logs = $self->{DB}->select($self->{table} . '_log', {
		match => { type => 'login' },
		min   => { tm => $ROBJ->{TM} - $self->{fail_minute}*60 },
		sort  => ['-tm', '-pkey'],
		cols  => [ qw(pkey tm ip msg) ]
	});

	my $fails = 0;
	foreach(@$logs) {
		if ($self->ip_group($_->{ip}) ne $ip) { next; }
		if ($_->{msg} eq '') { last; }
		if ($_->{msg} eq 'fail') { $fails++; }
	}
	return $fails;
}
# 同じ接続元として数える単位。IPv6は上位64bit（1回線に/64が割り当てられるため）
sub ip_group {
	my ($self, $ip) = @_;
	if ($ip !~ /:/) { return $ip; }

	require Socket;
	my $bin = Socket::inet_pton(Socket::AF_INET6(), $ip);
	if (!defined $bin) { return $ip; }

	# ::ffff:1.2.3.4 はIPv4。上位64bitで比べると全員が同じになる
	if (substr($bin, 0, 12) eq ("\0" x 10) . "\xff\xff") {
		return join('.', unpack('C4', substr($bin, 12)));
	}
	return unpack('H16', $bin) . '::/64';
}

#-------------------------------------------------------------------------------
# ●セッションの認証
#-------------------------------------------------------------------------------
sub session_auth {
	my $self = shift;
	my $ROBJ = $self->{ROBJ};

	# IP/HOST制限
	if (! $ROBJ->check_ip_host($self->{allow_ip}, $self->{allow_host})) { return ; }

	# 認証処理
	return $self->do_session_auth(@_);
}

sub do_session_auth {
	my ($self, $id, $session_id, $secret) = @_;
	my $ROBJ = $self->{ROBJ};
	my $DB   = $self->{DB};

	if ($id eq '' || $session_id eq '') { return; }

	# セッションの認証
	my $bak = $DB->set_noerror(1);
	my $session = $DB->select_match_limit1($self->{table}.'_sid', 'id', $id, 'sid', $session_id);
	$DB->set_noerror($bak);
	if (! $session) { return; }

	my $expires = $self->{expires};
	if (0<$expires && $session->{login_tm} + $expires < $ROBJ->{TM}) {	# 期限切れ
		$DB->delete_match($self->{table}.'_sid', 'pkey', $session->{pkey});
		return;
	}

	# user data load
	my $auth = $DB->select_match_limit1($self->{table}, 'id', $id);

	# ログイン成功
	$self->set_logininfo($auth, $secret);
	$self->{_sid} = $session_id;		# ログアウトで使用
	return 1;
}

#-------------------------------------------------------------------------------
# ●ログアウト
#-------------------------------------------------------------------------------
sub logout {
	my ($self) = @_;
	my $ROBJ = $self->{ROBJ};
	my $DB   = $self->{DB};
	my $id   = $self->{id};

	# ログアウト
	undef $self->{ok};
	undef $self->{pkey};
	undef $self->{id};
	undef $self->{name};
	undef $self->{isadmin};
	undef $self->{isroot};
	undef $self->{disabled_admin};
	$self->{ext} = {};

	# セッション情報の消去
	my $table = $self->{table} . '_sid';
	if ($self->{all_logout} || $self->{max_sessions} < 2) {
		$DB->delete_match($table, 'id', $id);
	} else {
		$DB->delete_match($table, 'id', $id, 'sid', $self->{_sid});
	}

	# ログ
	$self->log_save($id, 'logout');
	return ;
}

################################################################################
# ■サブルーチン
################################################################################
#-------------------------------------------------------------------------------
# ●ログイン情報を内部変数に設定する
#-------------------------------------------------------------------------------
sub set_logininfo {
	my $self   = shift;
	my $user   = shift;
	my $secret = shift;
	my $ROBJ   = $self->{ROBJ};
	my $id     = $user->{id};

	# ログイン成功
	$self->{ok}    = 1;
	$self->{pkey}  = $user->{pkey};
	$self->{id}    = $id;
	$self->{name}  = $user->{name};
	$self->{email} = $user->{email};
	$self->{isadmin} = 1;	# ユーザーは管理者だけ。下のセキュリティ拡張で0になることがある
	$self->{isroot}  = 0;
	$self->{disabled_admin} = 0;

	# 拡張カラム
	my %h = %$user;
	foreach(qw(pass pkey id name email)) {
		delete $h{$_};
	}
	$self->{ext} = \%h;

	# セキュリティ拡張
	if ($self->{root_list} && $self->{root_list}->{$id}) {
		$self->{isroot}  = 1;

	} elsif ($self->{admin_list} && ! $self->{admin_list}->{ $id }) {
		$self->{isadmin} = 0;
	}

	# admin権限の承認
	if ($self->{admin_allow_ip} || $self->{admin_allow_host} || $self->{admin_secret} ne '') {
		my $ok;
		if ($self->{admin_secret} ne '' && $self->{admin_secret} eq $secret) { $ok=1; }
		if (($self->{admin_allow_ip} || $self->{admin_allow_host})
		 && $ROBJ->check_ip_host($self->{admin_allow_ip}, $self->{admin_allow_host})) { $ok=1; }

		if (!$ok) {
			$self->{isroot}  = 0;
			$self->{isadmin} = 0;
			$self->{disabled_admin} = 1;
		}
	}
}

#-------------------------------------------------------------------------------
# ●ユーザーデータベースの初期化
#-------------------------------------------------------------------------------
sub userdb_init {
	my $self = shift;
	if (0<=$self->{exists_admin}) { return; }	# 初期値 -1

	my $DB = $self->{DB};

	# 管理者の存在確認（ユーザーは管理者1人だけ。いなければ初期セットアップの前）
	my $bak  = $DB->set_noerror(1);
	my $pkey = $DB->select_match_pkey1( $self->{table}, '*NoError', 1, '*cols', 'pkey' );
	$DB->set_noerror($bak);
	$self->{exists_admin} = $pkey ? 1 : 0;

	# テーブルがなければ自動生成
	if (!$DB->find_table( $self->{table} )) {
		$self->create_user_table();
	}
}

#-------------------------------------------------------------------------------
# ●DBにログの記録
#-------------------------------------------------------------------------------
sub log_save_fail {
	&log_save($_[0], $_[1], $_[2], 'fail')
}
sub log_save {
	my $self = shift;
	if ($self->{log_func}) {
		&{ $self->{log_func} }(@_);
	}
	if ($self->{log_stop}) { return; }

	my $id   = shift;
	my $type = shift;
	my $msg  = shift;
	my $DB   = $self->{DB};
	my $ROBJ = $self->{ROBJ};

	my $h = {id => $id, type => $type, msg => $msg};
	$h->{agent} = $ENV{HTTP_USER_AGENT};
	$h->{ip}    = $ENV{REMOTE_ADDR};
	$h->{host}  = $ENV{REMOTE_HOST};
	$h->{tm}    = $ROBJ->{TM};

	foreach(keys(%$h)) {
		$h->{$_} = substr($h->{$_}, 0, $self->{logtext_max});
		$ROBJ->tag_escape( $h->{$_} );
	}

	$DB->insert($self->{table} . '_log', $h);
}

#-------------------------------------------------------------------------------
# ●パスワードを認証する
#-------------------------------------------------------------------------------
sub check_pass {
	my ($self, $crypted, $plain) = @_;
	if (crypt($plain, $crypted) eq $crypted) { return 1; }	# auth
	return 0;
}
# パスワードを確かめたときと同じだけ時間をかける（結果は使わない）
sub dummy_check_pass {
	my ($self, $plain) = @_;
	crypt($plain, '$2b$12$' . ('.' x 22));
	return 0;
}

1;
