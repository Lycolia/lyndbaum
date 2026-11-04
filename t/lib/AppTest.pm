use strict;
use utf8;
#-------------------------------------------------------------------------------
# 画面と操作のテスト用ヘルパー
#-------------------------------------------------------------------------------
# 一時フォルダに空のデータでlyndbaumを組み立て、lyndbaum.cgiをCGIとして呼ぶ。
# 本物の data/ や pub/ には触らない。
#
#	my $app = AppTest->new();		# 空のデータで作る
#	my $app = AppTest->new(develop => 1);	# 開発モード（テンプレートのエラーを画面に出す）
#	$app->setup();				# ユーザーとブログを作る
#	my $r = $app->get('admin', 'menu');	# adminでログインして?menuを開く
#	my $r = $app->post('admin', 'set/detail', { action => 'set/detail', ... });
#
package AppTest;
use File::Basename ();
use File::Spec ();
use File::Temp ();
use File::Find ();
use Digest::MD5 ();
use IPC::Open3 ();
use Symbol ();
use Cwd ();

my $ROOT = File::Spec->rel2abs( File::Basename::dirname(__FILE__) . '/../..' );

# setup()で作るユーザー
#	admin  : システム管理者
#	guest  : ログインしていない人（Cookieなし）
our @USERS = qw(admin);
our $PASS  = 'test-pass-1234';

#-------------------------------------------------------------------------------
# ●空のデータで組み立てる
#-------------------------------------------------------------------------------
sub new {
	my $class = shift;
	my %opt   = @_;
	my $dir   = File::Temp::tempdir('adiary-test-XXXXXX', TMPDIR => 1, CLEANUP => 1);
	my $self  = bless({ dir => $dir, cookie => {} }, $class);

	# 書き換えないものはリンクで置く
	foreach (qw(lib skel plugin info)) {
		symlink("$ROOT/$_", "$dir/$_") || die "symlink $_: $!";
	}
	mkdir("$dir/pub");
	symlink("$ROOT/pub/assets", "$dir/pub/assets") || die "symlink pub/assets: $!";

	# 設定はコードの既定値だけで動かす（手元のlyndbaum.user.cgiに左右されないように）
	_copy("$ROOT/lyndbaum.cgi", "$dir/lyndbaum.cgi");
	if ($opt{develop}) {
		open(my $fh, '>', "$dir/lyndbaum.user.cgi") || die "lyndbaum.user.cgi: $!";
		print $fh "<\$Develop=1>\n";
		close($fh);
	}
	mkdir("$dir/data");
	return $self;
}

sub _copy {
	my ($from, $to) = @_;
	open(my $in,  '<:raw', $from) || die "$from: $!";
	open(my $out, '>:raw', $to)   || die "$to: $!";
	local $/;
	print {$out} scalar(<$in>);
	close($out);
}

sub dir { $_[0]->{dir} }

#-------------------------------------------------------------------------------
# ●リクエスト
#-------------------------------------------------------------------------------
# $whoはユーザーのID。'guest'ならCookieを送らない
# $queryは ? の後ろ。記事などは'/01'や'/01?edit'のように/から書く（PATH_INFO）
# $formはハッシュか、同じ名前を何度も送るときは配列（[ name => value, ... ]）。
# 値を{ filename => 'a.png', content => '...' }にすると、ファイルとしてmultipartで送る
sub get {
	my ($self, $who, $query) = @_;
	return $self->request($who, 'GET', $query);
}
sub post {
	my ($self, $who, $query, $form) = @_;
	return $self->request($who, 'POST', $query, $form);
}

sub request {
	my ($self, $who, $method, $query, $form) = @_;
	$query = '' if (!defined $query);
	my $path = '';
	if ($query =~ m{^(/[^?]*)\??(.*)$}) {
		($path, $query) = ($1, $2);
	}

	my $body = '';
	my $content_type = 'application/x-www-form-urlencoded';
	if ($form) {
		my @ary = ref($form) eq 'ARRAY' ? @$form : map { ($_, $form->{$_}) } sort keys(%$form);
		my %h = @ary;
		if (grep { ref($_) } values(%h)) {
			my $boundary = '----AppTestBoundary' . int(rand(1e9));
			$content_type = "multipart/form-data; boundary=$boundary";
			while(@ary) {
				my $k = shift(@ary);
				my $v = shift(@ary);
				$body .= "--$boundary\r\n";
				if (ref($v)) {
					$body .= qq{Content-Disposition: form-data; name="$k"; filename="$v->{filename}"\r\n};
					$body .= 'Content-Type: ' . ($v->{type} || 'application/octet-stream') . "\r\n\r\n";
					my $content = $v->{content};
					utf8::encode($content) if (utf8::is_utf8($content));
					$body .= $content . "\r\n";
				} else {
					utf8::encode($v) if (utf8::is_utf8($v));
					$body .= qq{Content-Disposition: form-data; name="$k"\r\n\r\n$v\r\n};
				}
			}
			$body .= "--$boundary--\r\n";
		} else {
			my @list;
			while(@ary) {
				my $k = shift(@ary);
				my $v = shift(@ary);
				push(@list, _uri_escape($k) . '=' . _uri_escape($v));
			}
			$body = join('&', @list);
		}
	}

	local %ENV = (
		PATH            => $ENV{PATH},
		TZ              => 'JST-9',
		GATEWAY_INTERFACE => 'CGI/1.1',
		REQUEST_METHOD  => $method,
		QUERY_STRING    => $query,
		REQUEST_URI     => "/lyndbaum.cgi$path" . ($query ne '' ? "?$query" : ''),
		SCRIPT_NAME     => '/lyndbaum.cgi',
		PATH_INFO       => $path,
		SERVER_NAME     => 'localhost',
		SERVER_PORT     => 80,
		HTTP_HOST       => 'localhost',
		REMOTE_ADDR     => '127.0.0.1',
		HTTP_USER_AGENT => 'AppTest',
		HTTP_ACCEPT_LANGUAGE => 'ja',
		%{ $self->{env} || {} },	# テストで足す環境変数（HTTPS => 'on' など）
		($method eq 'POST' ? (
			CONTENT_TYPE   => $content_type,
			CONTENT_LENGTH => length($body),
		) : ()),
		($who ne 'guest' && $self->{cookie}->{$who} ? (
			HTTP_COOKIE => join('; ', map { "$_=$self->{cookie}->{$who}->{$_}" } sort keys(%{$self->{cookie}->{$who}})),
		) : ()),
	);

	# 組み立てたフォルダで動かす
	my $cwd = Cwd::getcwd();
	chdir($self->{dir}) || die "chdir $self->{dir}: $!";
	my $err = Symbol::gensym();
	my $pid = IPC::Open3::open3(my $in, my $out, $err, $^X, 'lyndbaum.cgi');
	chdir($cwd);
	binmode($in);
	binmode($out);
	print $in $body;
	close($in);
	my $raw    = do { local $/; <$out> };
	my $stderr = do { local $/; <$err> };
	waitpid($pid, 0);

	return $self->_parse_response($who, $raw, $stderr);
}
sub _uri_escape {
	my $s = shift;
	utf8::encode($s) if (utf8::is_utf8($s));
	$s =~ s/([^\w\-\.\~ ])/sprintf('%%%02X', ord($1))/eg;
	$s =~ tr/ /+/;
	return $s;
}

sub _parse_response {
	my ($self, $who, $raw, $stderr) = @_;
	my ($head, $body) = split(/\r?\n\r?\n/, $raw, 2);
	my %r = (status => 200, headers => {}, cookies => [], body => $body, raw => $raw, stderr => $stderr);
	foreach (split(/\r?\n/, $head)) {
		my ($k, $v) = /^([\w\-]+):\s*(.*)$/ or next;
		$k = lc($k);
		if ($k eq 'status') {
			($r{status}) = $v =~ /^(\d+)/;
		} elsif ($k eq 'set-cookie') {
			push(@{$r{cookies}}, $v);
		} else {
			$r{headers}->{$k} = $v;
		}
	}
	if ($r{headers}->{location} && $r{status} == 200) { $r{status} = 302; }

	# Cookieを覚える（guestは覚えない）。期限切れにされたものは消す
	foreach (@{$r{cookies}}) {
		my ($pair, @attr) = split(/;\s*/, $_);
		my ($name, $val) = split(/=/, $pair, 2);
		next if ($who eq 'guest');
		if (grep { /^expires=.*19[0-9]{2}/i } @attr) {
			delete $self->{cookie}->{$who}->{$name};
			next;
		}
		$self->{cookie}->{$who}->{$name} = $val;
	}
	if ($r{headers}->{'content-type'} =~ m|application/json|) {
		require JSON::PP;
		$r{json} = eval { JSON::PP->new->utf8->decode($body) };
	}
	($r{title}) = $body =~ m|<title>\s*(.*?)\s*</title>|is;
	utf8::decode($r{title}) if (defined $r{title});
	return \%r;
}

#-------------------------------------------------------------------------------
# ●ユーザーとブログを作る
#-------------------------------------------------------------------------------
sub setup {
	my $self = shift;

	# 初期セットアップ：システム管理者がいないのでroot*で自動ログインする
	my $r = $self->get('root*', 'login_auto');
	die "login_auto failed: $r->{status}" if (!$self->{cookie}->{'root*'}->{session});

	$self->user_add('root*', 'admin', 1);
	$self->login('admin');
	delete $self->{cookie}->{'root*'};

	# ブログを作る
	$r = $self->post('admin', '', { action => 'etc/myblog_create', load_design => 1 });
	die "blog create failed: $r->{title}" if (!is_reload($r));

	# 最初に管理画面を開いたときに書くもの（システムの情報のmyselfなど）を、先に書かせておく
	$self->get($_, 'menu') foreach (@USERS);
	return $self;
}

#-------------------------------------------------------------------------------
# ●記事、コメント、画像を置く
#-------------------------------------------------------------------------------
# 記事（pkey=1、2）、ゴミ箱の記事（pkey=3）、
# 記事1へのコメント（pkey=1）、アルバムのフォルダtest/と画像test/a.png、
# 動画test/v.mp4（中身は動画ではない。名前で動画として扱われる）を作る
our $IMAGE_FOLDER = 'test/';
our $IMAGE_FILE   = 'a.png';
our $VIDEO_FILE   = 'v.mp4';
sub seed {
	my $self = shift;
	my %art = (parser => 'markdown', enable => 1, com_ok => 1, ymd => '2026-10-01');
	my $r;
	$r = $self->post('admin', '', { %art, action => 'edit', title => 'editorの記事', body_txt => "本文1\n", tag_ary => 'タグ1' });
	die "edit 1 failed: $r->{title}" if (!is_reload($r));
	$r = $self->post('admin',  '', { %art, action => 'edit', title => 'ownerの記事',  body_txt => "本文2\n", tag_ary => 'タグ2' });
	die "edit 2 failed: $r->{title}" if (!is_reload($r));
	$r = $self->post('admin',  '', { %art, action => 'edit', title => '消す記事',     body_txt => "本文3\n" });
	die "edit 3 failed: $r->{title}" if (!is_reload($r));
	$r = $self->post('admin',  '', { action => 'delete', delete_pkey_ary => 3, title => '消す記事' });
	die "delete 3 failed: $r->{title}" if (!is_reload($r));

	# 管理者のコメントは、スパム対策の判定の対象外
	$r = $self->post('admin', '', { action => 'comment_post', a_pkey => 1, comment_txt => 'seedのコメント', name => 'admin' });
	die "comment failed: $r->{title}" if (($r->{title} // '') !~ /^処理結果/);	# 公開画面の処理結果（_sub/reload_message_public）

	# アルバムの根元は、画像を初めて置くときに作られる。ここでは先に作っておく
	mkdir("$self->{dir}/pub/attachments");
	$r = $self->post('admin', '', { action => 'media/create_folder', folder => '/', name => 'test' });
	die "create_folder failed: $r->{body}" if (!$r->{json} || $r->{json}->{ret} ne '0');
	_copy("$ROOT/pub/assets/dist/default-icon.png", "$self->{dir}/pub/attachments/$IMAGE_FOLDER$IMAGE_FILE");
	_copy("$ROOT/pub/assets/dist/default-icon.png", "$self->{dir}/pub/attachments/$IMAGE_FOLDER$VIDEO_FILE");
	$r = $self->post('admin', '', { action => 'media/refresh' });
	return $self;
}

# 操作が通ると、処理結果の画面（_sub/reload_message）が出る
sub is_reload {
	my $r = shift;
	return ($r->{title} // '') =~ /^reload\b/ ? 1 : 0;
}

sub user_add {
	my ($self, $by, $id, $isadmin) = @_;
	my $r = $self->post($by, '', {
		action    => '_ajax_user_add',
		adiary_id => $id,
		name      => $id,
		pass      => $PASS,
		pass2     => $PASS,
		email     => '',
		isadmin   => $isadmin ? 1 : 0,
	});
	if (!$r->{json} || $r->{json}->{ret} ne '0') {
		die "user_add $id failed: $r->{body}";
	}
}

#-------------------------------------------------------------------------------
# ●管理者でないユーザーをDBに直接入れる（パスワードは管理者と同じ）
#-------------------------------------------------------------------------------
# 画面からは作れない。4.31より前のデータと、ログインの試験に使う
sub insert_user {
	my ($self, $id) = @_;
	require Satsuki::Base;
	my $ROBJ = Satsuki::Base->new();
	my $DB   = $ROBJ->loadpm('DB_text', "$self->{dir}/data/db/");
	my $admin = $DB->select_match_limit1('_users', 'id', 'admin');
	$DB->begin();
	$DB->insert('_users', { id => $id, name => $id, email => '', pass => $admin->{pass}, isadmin => 0 });
	if ($DB->commit()) { die "insert_user $id failed"; }
}

sub login {
	my ($self, $id) = @_;
	my $r = $self->post($id, '', { action => '_ajax_login', adiary_id => $id, pass => $PASS });
	if (!$r->{json} || $r->{json}->{ret} ne '0' || !$self->{cookie}->{$id}->{session}) {
		die "login $id failed: $r->{body}";
	}
}

#-------------------------------------------------------------------------------
# ●データの指紋
#-------------------------------------------------------------------------------
# data/と pub/のファイルの中身のハッシュ。権限の無い操作で何も変わらないことを確かめる。
# ログインのたびに変わるもの（セッション、ログインの記録、作業用）は除く。
# 設定のファイルは保存のたびに行の順番が変わるので、行を並べ替えてから比べる。
our @IGNORE = (
	qr{^data/db/_users(?:_sid|_log)?/},	# セッション、ログインの記録、ログインの回数
	qr{^data/tmp/},
	qr{^pub/assets(?:/|$)},
);
sub fingerprint {
	my $self = shift;
	my $dir  = $self->{dir};
	my %h;
	foreach my $top (qw(data pub)) {
		File::Find::find({ no_chdir => 1, wanted => sub {
			return if (-d $_);
			my $rel = File::Spec->abs2rel($_, $dir);
			return if (grep { $rel =~ $_ } @IGNORE);
			open(my $fh, '<:raw', $_) || return;
			my @lines = sort <$fh>;
			$h{$rel} = Digest::MD5::md5_hex(join('', @lines));
		}}, "$dir/$top");
	}
	return \%h;
}

# 2つの指紋で違うファイルの一覧
sub diff_fingerprint {
	my ($a, $b) = @_;
	my %all = (%$a, %$b);
	return sort grep { ($a->{$_} // '') ne ($b->{$_} // '') } keys(%all);
}

#-------------------------------------------------------------------------------
# ●今の状態を写す、戻す
#-------------------------------------------------------------------------------
# setup()の後の状態を写しておき、壊す操作のたびに戻す
sub snapshot {
	my $self = shift;
	my $snap = File::Temp::tempdir('adiary-snap-XXXXXX', TMPDIR => 1, CLEANUP => 1);
	system('cp', '-a', "$self->{dir}/data", "$self->{dir}/pub", $snap) == 0 || die "snapshot failed";
	return { dir => $snap, cookie => _copy_cookie($self->{cookie}) };
}
sub restore {
	my ($self, $snap) = @_;
	foreach (qw(data pub)) {
		system('rm', '-rf', "$self->{dir}/$_") == 0 || die "restore failed";
		system('cp', '-a', "$snap->{dir}/$_", "$self->{dir}/") == 0 || die "restore failed";
	}
	$self->{cookie} = _copy_cookie($snap->{cookie});
}
sub _copy_cookie {
	my $c = shift;
	return { map { $_ => { %{$c->{$_}} } } keys(%$c) };
}

1;
