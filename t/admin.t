# 管理画面のログイン、ログアウト、CSRF対策
use strict;
use warnings;
use utf8;
use Test::More;

use JSON::PP ();
use Lyndbaum::App;
use Lyndbaum::Config;
use Lyndbaum::Model::Admin;
use Lyndbaum::Password;
use AdminTest;

my $t   = AdminTest->new;
my $app = $t->app;
my $dbh = $t->dbh;
my $ORIGIN = $AdminTest::ORIGIN;

sub request { $t->request(@_) }
sub login   { $t->login(@_) }
sub csrf_of { $t->csrf_of(@_) }
sub header  { AdminTest::header(@_) }

subtest 'ログインしていなければログインの画面へ' => sub {
	my $res = request(GET => '/admin');
	is $res->status, 303;
	is header($res, 'Location'), '/admin/login';
	is header($res, 'Cache-Control'), 'no-store';

	$res = request(GET => '/admin/login');
	is $res->status, 200;
	like $res->body, qr{<input type="password" name="password"}, 'ログインのフォーム';
	unlike $res->body, qr{ログアウト}, 'ログアウトのボタンは出さない';
	is header($res, 'Cache-Control'), 'no-store', '管理画面は保存させない';
	is header($res, 'X-Frame-Options'), 'DENY', '枠の中に表示させない';
	like $res->body, qr{<meta name="robots" content="noindex, nofollow">};
};

subtest 'ログイン' => sub {
	my ($cookie, $res) = login();
	is $res->status, 303;
	is header($res, 'Location'), '/admin';
	my $set_cookie = header($res, 'Set-Cookie');
	like $set_cookie, qr{\Alyndbaum_session=[A-Za-z0-9_-]{43}; Max-Age=1209\d{3}; Path=/; HttpOnly; SameSite=Lax; Secure\z}, 'Cookie の属性。期限は14日';

	my ($token) = $cookie =~ /=(.+)/;
	is $dbh->selectrow_array('SELECT COUNT(*) FROM sessions WHERE token_hash = ?', undef, $token), 0, 'DB にはトークンそのものを保存しない';

	$res = request(GET => '/admin', cookie => $cookie);
	is $res->status, 200;
	like $res->body, qr{<h1>ダッシュボード</h1>};
	like $res->body, qr{<button type="submit">ログアウト</button>};
	is request(GET => '/admin/login', cookie => $cookie)->status, 303, 'ログイン中にログインの画面を開くとダッシュボードへ';

	is request(GET => '/admin', cookie => 'lyndbaum_session=wrong')->status, 303, '知らないトークン';
	$dbh->do('UPDATE sessions SET expires_at = ?', undef, time - 1);
	is request(GET => '/admin', cookie => $cookie)->status, 303, '期限切れ';
};

subtest 'ログインの失敗' => sub {
	my $res = request(POST => '/admin/login', body => [ login => 'admin', password => 'wrong' ], ip => '192.0.2.10');
	is $res->status, 401;
	like $res->body, qr{ログイン名かパスワードが違います。};
	like $res->body, qr{name="login" value="admin"}, 'ログイン名は残す';
	is_deeply [ $res->headers_of('Set-Cookie') ], [], 'Cookie は送らない';
	is request(POST => '/admin/login', body => [ login => 'other', password => 'correct horse battery' ], ip => '192.0.2.10')->status, 401, 'ログイン名が違う';

	my ($cookie, $other) = login(origin => 'https://evil.example');
	is $other->status, 403, 'ほかのサイトからのログインは受け付けない';
	(undef, $other) = login(origin => undef);
	is $other->status, 403, 'Origin も Referer も無ければ受け付けない';
	(undef, $other) = login(origin => undef, env => { HTTP_REFERER => "$ORIGIN/admin/login" });
	is $other->status, 303, 'Origin が無ければ Referer を見る';
};

subtest 'パスワードの決まりに合わなければ、bcrypt をかけずに断る' => sub {
	my $ip = '192.0.2.30';
	local $Lyndbaum::Password::COST = 31;   # bcrypt をかけたら、テストが終わらなくなる
	my $start = time;
	my $res = request(POST => '/admin/login', body => [ login => 'admin', password => 'x' x 100_000 ], ip => $ip);
	is $res->status, 401, '長すぎるパスワード';
	is request(POST => '/admin/login', body => [ login => 'admin', password => "nul\0inside-password" ], ip => $ip)->status, 401, 'NUL を含む';
	is request(POST => '/admin/login', body => [ login => 'nobody', password => 'x' x 100_000 ], ip => $ip)->status, 401, 'ログイン名が違っても同じ';
	ok time - $start < 5, 'すぐに返す';
	is $dbh->selectrow_array('SELECT COUNT(*) FROM login_failures WHERE ip = ?', undef, $ip), 3, '失敗としては数える';
	eval { Lyndbaum::Model::Admin->set_password($dbh, 'admin', 'x' x 73, cost => 4) };
	like $@, qr{72バイトまで}, '決まりに合わないパスワードは登録できない';
	ok(Lyndbaum::Password->verify('correct horse battery', Lyndbaum::Model::Admin->find($dbh)->{password_hash}), '今のパスワードはそのまま');
};

subtest 'ログインの失敗が続いたら受け付けない' => sub {
	my $ip = '192.0.2.20';
	request(POST => '/admin/login', body => [ login => 'admin', password => "wrong$_" ], ip => $ip) for 1 .. 5;
	my ($cookie, $res) = login(ip => $ip);
	is $res->status, 429, '正しいパスワードでも受け付けない';
	is $cookie, undef;
	like $res->body, qr{しばらく受け付けません};
	(undef, $res) = login(ip => '192.0.2.21');
	is $res->status, 303, 'ほかの IP からは受け付ける';

	$dbh->do('UPDATE login_failures SET failed_at = failed_at - ? WHERE ip = ?', undef, 15 * 60, $ip);
	(undef, $res) = login(ip => $ip);
	is $res->status, 303, '15分たてば受け付ける';
	is $dbh->selectrow_array('SELECT COUNT(*) FROM login_failures WHERE ip = ?', undef, $ip), 0, '成功したら失敗の記録を消す';
};

subtest 'ログアウト' => sub {
	my ($cookie) = login();
	my $csrf = csrf_of($cookie);
	ok $csrf, 'フォームに CSRF トークンがある';

	is request(POST => '/admin/logout', cookie => $cookie, body => [ csrf_token => 'wrong' ])->status, 403, 'CSRF トークンが違う';
	is request(POST => '/admin/logout', cookie => $cookie)->status, 403, 'CSRF トークンが無い';
	is request(POST => '/admin/logout', cookie => $cookie, body => [ csrf_token => $csrf ], origin => 'https://evil.example')->status, 403,
		'ほかのサイトから';
	is request(GET => '/admin', cookie => $cookie)->status, 200, '受け付けなかった操作ではログアウトしない';

	my $res = request(POST => '/admin/logout', cookie => $cookie, body => [ csrf_token => $csrf ]);
	is $res->status, 303;
	is header($res, 'Location'), '/admin/login';
	like header($res, 'Set-Cookie'), qr{\Alyndbaum_session=; Max-Age=0; }, 'Cookie を消す';
	is request(GET => '/admin', cookie => $cookie)->status, 303, 'セッションを消す';
};

subtest 'パスワードを変えたら、今のセッションをすべて消す' => sub {
	my ($cookie) = login();
	is request(GET => '/admin', cookie => $cookie)->status, 200;
	Lyndbaum::Model::Admin->set_password($dbh, 'admin', 'correct horse battery', cost => 4);
	is request(GET => '/admin', cookie => $cookie)->status, 303, '盗まれたセッションも使えなくなる';
	is $dbh->selectrow_array('SELECT COUNT(*) FROM sessions'), 0;
	my ($again) = login();
	is request(GET => '/admin', cookie => $again)->status, 200, 'ログインし直せる';
};

subtest 'cookie_secure を false にすると Secure を付けない（手元の http で試すとき）' => sub {
	my $config = Lyndbaum::Config->new(%{ $app->config }, cookie_secure => JSON::PP::false());
	my $local = Lyndbaum::App->new(root => $app->{root}, config => $config);
	unlike $local->session_cookie('token', time + 60), qr{Secure};
};

subtest '/admin はコンテンツページの slug に使えない' => sub {
	TestUtil::insert_article($dbh, id => 50, kind => 'page', slug => 'admin', title => '管理');
	is request(GET => '/admin')->status, 303, '管理画面になる';
};

done_testing;
