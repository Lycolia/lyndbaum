use strict;
#-------------------------------------------------------------------------------
# HTTPモジュール
#						(C)2006-2019 nabe / nabe@abk
#-------------------------------------------------------------------------------
# 簡易実装の HTTP モジュールです。
#
package Satsuki::Base::HTTP;
our $VERSION = '1.40';
#-------------------------------------------------------------------------------
use Socket qw(:DEFAULT AF_INET6 AI_ADDRCONFIG getaddrinfo inet_pton unpack_sockaddr_in6);
use Fcntl qw(F_GETFL F_SETFL O_NONBLOCK);
use Errno qw(EINPROGRESS EWOULDBLOCK EINTR);
use Time::HiRes ();
################################################################################
# ■基本処理
################################################################################
#-------------------------------------------------------------------------------
# ●【コンストラクタ】
#-------------------------------------------------------------------------------
sub new {
	my $self = bless({}, shift);
	my $ROBJ = shift;
	$self->{ROBJ} = $ROBJ;

	$self->{cookie}     = {};
	$self->{use_cookie} = 0;
	$self->{timeout}    = 30;
	$self->{redirect}   = 5;	# リダイレクト処理を行う回数
	$self->{use_sni}    = 1;	# use SNI
	$self->{max_size}   = 100*1024*1024;	# 受信する大きさの上限（ヘッダを含む）
	# $self->{allow_internal} = 1;	# 内部のアドレスとほかのポートへの接続を許す（テスト用）

	$self->{http_agent} = $ROBJ->{HttpAgent} || "Simple HTTP agent $VERSION";
	# $self->{log_file} = 'http.log';	# (DEBUG) connection log

	return $self;
}

################################################################################
# ■メインルーチン
################################################################################
#-------------------------------------------------------------------------------
# ●ホストに対して処理する
#-------------------------------------------------------------------------------
sub get_data {
	my $self = shift;
	return $self->do_get_data('send_http_request',  @_);
}
sub get_data_ssl {
	my $self = shift;
	return $self->do_get_data('send_https_request', @_);
}
sub do_get_data {
	my $self = shift;
	my $func = shift;
	my $host = shift;
	my $port = shift;
	$self->{error} = undef;

	my $sock = $self->connect_host($host, $port);
	if (!defined $sock) { return ; }
	my $res = $self->$func($sock, $host, @_);
	if (!defined $res) { return ; }
	close($sock);

	return $res;
}

#-------------------------------------------------------------------------------
# ●指定ホストに接続する
#-------------------------------------------------------------------------------
sub connect_host {
	my ($self, $host, $port) = @_;

	# リダイレクト先もここを通る。名前解決の結果へそのまま接続するので、解決し直して内部へ向けることもできない
	if (!$self->{allow_internal} && $port != 80 && $port != 443) {
		return $self->error(undef, "Can't connect to port %d", $port);
	}
	my ($err, @addrs);
	if ($host ne '') {	# 空の名前はgetaddrinfoがループバックにしてしまう
		($err, @addrs) = getaddrinfo($host, $port, { socktype => SOCK_STREAM, flags => AI_ADDRCONFIG });
	}
	if ($err || !@addrs) {
		return $self->error(undef, "Can't find host '%s'", $host);
	}
	if (!$self->{allow_internal} && !$self->is_self_host($host)) {
		@addrs = grep { !$self->is_internal_ip( &addr_to_ip($_) ) } @addrs;
		if (!@addrs) {
			return $self->error(undef, "Can't connect to internal address '%s'", $host);
		}
	}

	# 不通のアドレスで時間を使い切らないよう、残り時間を残りのアドレスで割る
	my $limit = Time::HiRes::clock_gettime(Time::HiRes::CLOCK_MONOTONIC()) + $self->{timeout};
	while (@addrs) {
		my $now = Time::HiRes::clock_gettime(Time::HiRes::CLOCK_MONOTONIC());
		my $sh  = $self->connect_addr(shift(@addrs), $now + ($limit - $now) / (@addrs + 1));
		if ($sh) { return $sh; }
	}
	return $self->error(undef, "Can't connect %s", $host);
}

# getaddrinfoの結果の1つへ接続する。失敗したらundefを返す
sub connect_addr {
	my ($self, $addr, $deadline) = @_;

	my $sh;
	if (! socket($sh, $addr->{family}, $addr->{socktype}, $addr->{protocol})) { return; }

	my $flags = fcntl($sh, F_GETFL, 0);
	if (!defined($flags) || !fcntl($sh, F_SETFL, $flags | O_NONBLOCK)) { close($sh); return; }

	if (!connect($sh, $addr->{addr})) {
		if ($! != EINPROGRESS && $! != EWOULDBLOCK) { close($sh); return; }

		my $ready = $self->wait_socket($sh, 0, $deadline);
		my $error = getsockopt($sh, SOL_SOCKET, SO_ERROR);
		if ($ready != 1 || !defined($error) || unpack('i', $error)) { close($sh); return; }
	}
	if (!fcntl($sh, F_SETFL, $flags)) { close($sh); return; }

	binmode($sh);
	return $sh;
}

# getaddrinfoの結果のアドレス（IPv4は4バイト、IPv6は16バイト）
sub addr_to_ip {
	my $addr = shift;
	if ($addr->{family} == AF_INET6) {
		return (unpack_sockaddr_in6($addr->{addr}))[1];
	}
	return (unpack_sockaddr_in($addr->{addr}))[1];
}

# インターネットの宛先ではないアドレスか（RFC 6890）
my @INTERNAL_NET = map {
	my ($ip, $bits) = split('/', $_);
	[ unpack('N', inet_aton($ip)), (0xffffffff << (32-$bits)) & 0xffffffff ];
} qw(	0.0.0.0/8	10.0.0.0/8	100.64.0.0/10	127.0.0.0/8
	169.254.0.0/16	172.16.0.0/12	192.0.0.0/24	192.0.2.0/24
	192.168.0.0/16	198.18.0.0/15	198.51.100.0/24	203.0.113.0/24
	224.0.0.0/4	240.0.0.0/4 );

# ::ffff:0:0/96（IPv4射影）と64:ff9b::/96（NAT64）はIPv4へ届くので、IPv4の判定をすり抜けないよう断る
my @INTERNAL_NET6 = map {
	my ($ip, $bits) = split('/', $_);
	my $mask = pack('B128', ('1' x $bits) . ('0' x (128-$bits)));
	[ inet_pton(AF_INET6, $ip) & $mask, $mask ];
} qw(	::/128		::1/128		::ffff:0:0/96	64:ff9b::/96
	2001:db8::/32	fc00::/7	fe80::/10	ff00::/8 );

sub is_internal_ip {
	my ($self, $ip_bin) = @_;
	if (length($ip_bin) == 16) {
		foreach(@INTERNAL_NET6) {
			if (($ip_bin & $_->[1]) eq $_->[0]) { return 1; }
		}
		return 0;
	}
	if (length($ip_bin) != 4) { return 1; }

	my $ip = unpack('N', $ip_bin);
	foreach(@INTERNAL_NET) {
		if (($ip & $_->[1]) == $_->[0]) { return 1; }
	}
	return 0;
}

# ブログ自身のホスト名か。自分のドメインが内部アドレスに解決される環境でも、自分へのリンクは取得できるようにする
# ServerURLはHostヘッダーの偽装から守られている（adiary.pm secure_http_host）
sub is_self_host {
	my ($self, $host) = @_;
	my $ROBJ = $self->{ROBJ};
	if (!$ROBJ || $host eq '') { return 0; }
	return $ROBJ->{ServerURL} =~ m!^https?://([^/:]+)!i && lc($1) eq lc($host) ? 1 : 0;
}

# ソケットが読み取り／書き込み可能になるまで待つ。1:準備完了、0:期限切れ、-1:エラー
# タイマーとシグナルはプロセス全体で共有されるので、スレッドごとの期限で待つ
sub wait_socket {
	my ($self, $sock, $read, $deadline) = @_;
	while (1) {
		my $left = $deadline - Time::HiRes::clock_gettime(Time::HiRes::CLOCK_MONOTONIC());
		return 0 if ($left <= 0);
		my ($rin, $win) = ('', '');
		if ($read) { vec($rin, fileno($sock), 1) = 1; }
		else       { vec($win, fileno($sock), 1) = 1; }
		my $ready = select($rin, $win, undef, $left);
		next if ($ready < 0 && $! == EINTR);
		return $ready < 0 ? -1 : $ready ? 1 : 0;
	}
}

# TLSが必要とする読み書きの方向で待つ。戻り値は wait_socket と同じ
sub wait_ssl {
	my ($self, $ssl, $sock, $ret, $deadline) = @_;
	my $error = Net::SSLeay::get_error($ssl, $ret);
	if ($error == Net::SSLeay::ERROR_WANT_READ()) {
		return $self->wait_socket($sock, 1, $deadline);
	}
	if ($error == Net::SSLeay::ERROR_WANT_WRITE()) {
		return $self->wait_socket($sock, 0, $deadline);
	}
	return -1;
}

#-------------------------------------------------------------------------------
# ●GET, POST, HEAD などを送り、データを受信する
#-------------------------------------------------------------------------------
sub send_http_request {
	my $self = shift;
	my $sock = shift;
	my $host = shift;

	$self->save_log_spliter();
	$self->save_log(\@_);

	{
		my $request = join('', @_);
		syswrite($sock, $request, length($request));
	}
	# 受信に期限を設ける。切断されるか期限が来るまで読む
	my $deadline = Time::HiRes::clock_gettime(Time::HiRes::CLOCK_MONOTONIC()) + $self->{timeout};
	my $data = '';
	my $timeout;
	while (1) {
		my $ready = $self->wait_socket($sock, 1, $deadline);
		if ($ready != 1) {
			$timeout = ($ready == 0);
			last;
		}
		my $got = sysread($sock, $data, 32768, length($data));
		next if (!defined($got) && $! == EINTR);
		last if (!$got);
		if (length($data) > $self->{max_size}) {
			close($sock);
			return $self->error(undef, "Response too large '%s'", $host);
		}
	}
	close($sock);

	# 途中まで受信していても、切れたデータは成功として扱わない
	if ($timeout) {
		return $self->error(undef, "Connection timeout '%s' (timeout %d sec)", $host, $self->{timeout});
	}

	my @response = split(/^/, $data);
	$self->save_log(\@response);
	$self->save_log_spliter();
	if (! @response) {
		return $self->error(undef, "Connection closed by '%s'", $host);
	}

	$self->parse_status_line($response[0], $host);
	return \@response;
}

#-------------------------------------------------
# ●status lineの処理
#-------------------------------------------------
sub parse_status_line {
	my $self   = shift;
	my $status = int( (split(' ', shift))[1] );
	my $host   = shift;
	$self->{status} = $status;
	if ($status != 200 && ($status<301 || 304<$status)) {
		return $self->error(undef, "Error response from '%s' (status %d)", $host, $status);
	}
}

#-------------------------------------------------------------------------------
# ●https 
#-------------------------------------------------------------------------------
sub send_https_request {
	my $self = shift;
	my $sock = shift;
	my $host = shift;

	$self->save_log_spliter();
	$self->save_log(\@_);

	eval { require Net::SSLeay; };
	if ($@) {
		return $self->error(undef, "Net::SSLeay module not found (please install this server)");
	}
	if ($Net::SSLeay::VERSION < 1.92) {
		return $self->error($sock, "Net::SSLeay Ver%s is too old (1.92 or later required)", $Net::SSLeay::VERSION);
	}
	#-----------------------------------------------------------------------
	my ($data, $errs, $verify_err, $timeout, $too_large);

	my $ctx = Net::SSLeay::new_x_ctx();
	goto cleanup2 if $errs = Net::SSLeay::print_errs('CTX_new') or !$ctx;

	Net::SSLeay::CTX_set_options($ctx, &Net::SSLeay::OP_ALL);
	goto cleanup2 if $errs = Net::SSLeay::print_errs('CTX_set_options');

	# 証明書の信頼チェーンを検証する（サーバーのCA証明書を使う）
	Net::SSLeay::CTX_set_verify($ctx, &Net::SSLeay::VERIFY_PEER);
	Net::SSLeay::CTX_set_default_verify_paths($ctx);
	goto cleanup2 if $errs = Net::SSLeay::print_errs('CTX_set_default_verify_paths');

	my $ssl = Net::SSLeay::new($ctx);
	goto cleanup if $errs = Net::SSLeay::print_errs('SSL_new') or !$ssl;

	# IPアドレスにはSNIを送らない（RFC 6066）。URLにIPv6アドレスは書けない（do_request）のでIPv4だけを見る
	my $is_ip = ($host =~ /^\d{1,3}(?:\.\d{1,3}){3}$/);
	if ($self->{use_sni} && !$is_ip) {
		Net::SSLeay::set_tlsext_host_name($ssl, $host);
	}

	# 証明書のホスト名かIPアドレスを検証する
	my $param = Net::SSLeay::get0_param($ssl);
	if (!($is_ip ? Net::SSLeay::X509_VERIFY_PARAM_set1_ip_asc($param, $host)
	             : Net::SSLeay::X509_VERIFY_PARAM_set1_host($param, $host))) {
		$errs = Net::SSLeay::print_errs('X509_VERIFY_PARAM_set1') || 'X509_VERIFY_PARAM_set1 failed';
		goto cleanup;
	}

	Net::SSLeay::set_fd($ssl, fileno($sock));
	goto cleanup if $errs = Net::SSLeay::print_errs('set_fd');

	# ノンブロッキングで読み書きし、ハンドシェイク、送信、受信の合計に期限を設ける
	my $flags = fcntl($sock, F_GETFL, 0);
	goto cleanup if (!defined($flags) || !fcntl($sock, F_SETFL, $flags | O_NONBLOCK));
	my $deadline = Time::HiRes::clock_gettime(Time::HiRes::CLOCK_MONOTONIC()) + $self->{timeout};
	while (1) {
		if (Time::HiRes::clock_gettime(Time::HiRes::CLOCK_MONOTONIC()) >= $deadline) { $timeout=1; goto cleanup; }
		my $connected = Net::SSLeay::connect($ssl);
		last if ($connected == 1);
		my $ready = $self->wait_ssl($ssl, $sock, $connected, $deadline);
		next if ($ready == 1);
		$timeout = ($ready == 0);
		my $verify = Net::SSLeay::get_verify_result($ssl);
		if ($verify) { $verify_err = Net::SSLeay::X509_verify_cert_error_string($verify); }
		$errs = Net::SSLeay::print_errs('SSL_connect');
		goto cleanup;
	}

	{
		use bytes;
		my $request = join('', @_);
		my $written = 0;
		while ($written < length($request)) {
			if (Time::HiRes::clock_gettime(Time::HiRes::CLOCK_MONOTONIC()) >= $deadline) { $timeout=1; goto cleanup; }
			my $ret = Net::SSLeay::write_partial($ssl, $written, length($request)-$written, $request);
			if (defined($ret) && $ret > 0) { $written += $ret; next; }
			my $ready = $self->wait_ssl($ssl, $sock, $ret, $deadline);
			next if ($ready == 1);
			$timeout = ($ready == 0);
			$errs = Net::SSLeay::print_errs('SSL_write');
			goto cleanup;
		}
	}
	$data = '';
	while (1) {
		if (Time::HiRes::clock_gettime(Time::HiRes::CLOCK_MONOTONIC()) >= $deadline) { $timeout=1; last; }
		my ($got, $ret) = Net::SSLeay::read($ssl, 32768);
		if (defined($got)) {
			last if ($got eq '');
			$data .= $got;
			if (length($data) > $self->{max_size}) { $too_large=1; last; }
			next;
		}
		my $ready = $self->wait_ssl($ssl, $sock, $ret, $deadline);
		next if ($ready == 1);
		$timeout = ($ready == 0);
		$errs = Net::SSLeay::print_errs('SSL_read');
		last;
	}

cleanup:
	Net::SSLeay::free($ssl);

cleanup2:
	Net::SSLeay::CTX_free($ctx);
	close($sock);

	# 途中まで受信していても、切れたデータは成功として扱わない
	if ($timeout) {
		return $self->error(undef, "Connection timeout '%s' (timeout %d sec)", $host, $self->{timeout});
	}
	if ($too_large) {
		return $self->error(undef, "Response too large '%s'", $host);
	}

	#-----------------------------------------------------------------------
	# parse
	#-----------------------------------------------------------------------
	my @response;
	while($data =~ /([^\n]*\n)(.*)/s) {
		push(@response, $1);
		$data = $2;
		if ($1 eq "\n") { last; }
	}
	if ($data ne '') {
		push(@response, $data)
	}
	#-----------------------------------------------------------------------
	$self->save_log(\@response);
	if (! @response) {
		if ($verify_err ne '') {
			return $self->error(undef, "Certificate verification failed '%s' (%s)", $host, $verify_err);
		}
		return $self->error(undef, "Net::SSLeay Ver$Net::SSLeay::VERSION fail connection: '%s'", $host);
	}

	$self->parse_status_line($response[0], $host);
	return \@response;
}

################################################################################
# ■上位サービスルーチン
################################################################################
# Cookie実装ポリシー
#	・expires は無視（すべてsession cookieとして処理）
#-------------------------------------------------------------------------------
# ●cookieのon/off（デフォルト:off）
#-------------------------------------------------------------------------------
sub cookie_on {
	my $self = shift;
	$self->{use_cookie} = 1;
}
sub cookie_off {
	my $self = shift;
	$self->{use_cookie} = 0;
}

#-------------------------------------------------------------------------------
# ●指定したURLからGET/POSTし、中身データを返す
#-------------------------------------------------------------------------------
#-----------------------------------------------------------
# GET/POSTとRedirect処理
#-----------------------------------------------------------
sub get {
	my $self = shift;
	return $self->request('GET',  @_);
}
sub post {
	my $self = shift;
	return $self->request('POST', @_);
}
sub request {
	my $self = shift;
	my $method = shift;
	my $url = shift;
	$self->{redirect_cnt} = 0;
	while (1) {
		my $r = $self->do_request($method, $url, @_);
		# 正常終了
		my $status = $self->{status};
		if (!$self->{location} || $status<301 || 303<$status || (++$self->{redirect_cnt}) > $self->{redirect}) {
			return wantarray ? ($status, $self->{header}, $r) : $r;
		}
		# Redirect
		$url = $self->{location};
	}
}
#-----------------------------------------------------------
# リクエスト処理本体
#-----------------------------------------------------------
sub do_request {
	my $self = shift;
	my $ROBJ = $self->{ROBJ};

	# 失敗したときに前回のリダイレクト先を辿り直したり、前回の結果を返したりしないよう、先に消す
	delete $self->{location};
	delete $self->{error};
	delete $self->{status};

	my ($method, $url, $_header, $post_data) = @_;
	my $cookie = $self->{cookie};
	my $https = ($url =~ m|^https://|i);

	if ($url !~ m|^https?://([^/:]*)(:(\d+))?(.*)|) {
		return $self->error(undef, "URL format error '%s'", $url);
	}
	my $host = $1;
	my $port = $3 || ($https ? 443 : 80);
	my $path = $4 || '/';
	$self->{url} = $url;	# 最後に要求したURL
	#-----------------------------------------------------------------------
	# Cookieの処理
	#-----------------------------------------------------------------------
	my $http_cookie;
	if ($self->{use_cookie}) {
		my @send_cookies;
		while(my ($k,$v) = each(%$cookie)) {
			$k =~ /(.*);/;
			my $chost = $1;
			my $dom   = $1;
			$dom =~ s/^\.*/./;
			if ($chost eq $host || index($host, $dom)>0 ) {
			 	if ($v->{path} && index($path, $v->{path}) < 0) { next; }
			 	if ($v->{value} eq '') { next; }	# 空のcookieは無視
				$http_cookie .= "$v->{name}=$v->{value};";
				# print "Cookie : $v->{name}=$v->{value}\n";
			}
		}
		if ($http_cookie) { $http_cookie = "Cookie: $http_cookie\r\n"; }
	}

	#-----------------------------------------------------------------------
	# ヘッダの初期処理
	#-----------------------------------------------------------------------
	my %header;
	if (ref($_header) eq 'HASH') { %header = %$_header; }	# copy
	$header{Host} ||= $host;
	$header{'User-Agent'} ||= $self->{http_agent};

	#-----------------------------------------------------------------------
	# POSTリクエスト
	#-----------------------------------------------------------------------
	my $content;
	if ($method eq 'POST') {
		if (ref($post_data) eq 'HASH') {
			while(my ($k,$v) = each(%$post_data)) {
				$ROBJ->encode_uricom($k,$v);
				$content .= "$k=$v&";
			}
			chop($content);
		} else {
			$content = $post_data;
		}

		# Net::SSLeay::post_https は自動付加するので付けない
		$header{'Content-Length'} = length($content);
		$header{'Content-Type'} ||= 'application/x-www-form-urlencoded';
	}

	#-----------------------------------------------------------------------
	# ヘッダの構成初期処理
	#-----------------------------------------------------------------------
	my $header;
	foreach(keys(%header)) {
		if ($_ eq '' || $_ =~ /[^\w\-]/) { next; }
		my $v = $header{$_};
		$v =~ s/^\s*//;
		$v =~ s/[\s\r\n]*$//;
		$header .= "$_: $v\r\n";
	}
	$header .= "Connection: close\r\n";
	$header .= $http_cookie;

	#-----------------------------------------------------------------------
	# HTTPリクエストの発行
	#-----------------------------------------------------------------------
	# $self->{ROBJ}->debug($header);
	# $self->{ROBJ}->debug($content);
	my $res;
	{
		my $func = $https ? 'get_data_ssl' : 'get_data';
		# Only HTTP/1.0, because chunked not support.
		my $request = "$method $path HTTP/1.0\r\n$header\r\n$content";

		$res = $self->$func($host, $port, $request);
		if (ref($res) ne 'ARRAY') { return $res; }	# fail to return
	}

	#-----------------------------------------------------------------------
	# ヘッダの解析
	#-----------------------------------------------------------------------
	my $header= $self->{header} = [];
	my ($content_length, $chunked);
	while(@$res) {
		my $line = shift(@$res);
		$line =~ s/[\r\n]//g;		# 改行除去
		if ($line eq '') { last; }	# ヘッダの終わり
		push(@$header, $line);
		if ($line =~ /^content-length:\s*(\d+)\s*$/i) { $content_length = $1; }
		if ($line =~ /^transfer-encoding:/i) { $chunked = 1; }
		# Cookie
		if ($self->{use_cookie} && $line =~ /^set-cookie:\s*(.*)$/i) {
			my @cookie = split(/\s*;\s*/, $1);
			my %h;
			my $cookie_dom = $host;
			my ($name, $value) = split("=", shift(@cookie));
			$h{name}  = $name;
			$h{value} = $value;
			foreach(@cookie) {
				if ($_ !~ /(.*?)=(.*)/) { next; }
				$h{$1} = $2;
				if ($1 eq 'domain') {
					my $dom = $2;
					if ($dom =~ /\.?([\w\-]+\.[\w\-]+\.[\w\-]+)\.?/) {
						$cookie_dom = '.' . $1;
					}
				}
			}
			$cookie->{"$cookie_dom;$h{name}"} = \%h;	# cookie保存
		}
		# Redirect 
		if ($line =~ /^location:\s*(.*)$/i) {
			$self->{location} = $1;
		}
	}

	#-----------------------------------------------------------------------
	# 途中で切れた本文を成功として扱わない
	#-----------------------------------------------------------------------
	# close_notifyなしで閉じるサーバーがあるので、切断のしかたではなく長さで判定する
	if ($self->{status} == 200 && $method ne 'HEAD' && defined $content_length && !$chunked) {
		my $size = 0;
		foreach(@$res) { $size += length($_); }
		if ($size < $content_length) {
			return $self->error(undef, "Connection closed by '%s'", $host);
		}
	}
	return $res;
}

################################################################################
# ■サブルーチン
################################################################################
#-------------------------------------------------------------------------------
# ●タイムアウトの設定
#-------------------------------------------------------------------------------
sub set_timeout {
	my ($self, $timeout) = @_;
	$self->{timeout} = $timeout+0 || 30;
}

#-------------------------------------------------------------------------------
# ●USER-AGENTの設定
#-------------------------------------------------------------------------------
sub set_agent {
	my $self = shift;
	$self->{http_agent} = shift || "Simple HTTP agent $VERSION";
}

#-------------------------------------------------------------------------------
# ●USER-AGENTの設定
#-------------------------------------------------------------------------------
sub save_log {
	my $self = shift;
	my $file = $self->{log_file};
	if (!$file) { return; }
	$self->{ROBJ}->fappend_lines($file, shift);
}
sub save_log_spliter {
	my $self = shift;
	$self->save_log("\n" . ('-' x 80) . "\n");
}

################################################################################
# ■エラー処理
################################################################################
sub error_to_root {
	my $self = shift;
	$self->{error_to_root} = shift;
}

sub error {
	my $self  = shift;
	my $sock  = shift;
	my $error = shift;
	my $ROBJ  = $self->{ROBJ};
	if (defined $sock) { close($sock); }
	if (defined $ROBJ) {
		if ($self->{error_to_root}) { return $ROBJ->error($error, @_); }
		$error = $ROBJ->translate($error, @_);
	} elsif (@_) {
		$error = sprintf($error, @_);
	}
	$self->{error} = $error;
	$self->save_log("\n[ERROR] $error\n");
	return undef;
}


1;
