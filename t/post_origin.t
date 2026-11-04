use strict;
use utf8;
#-------------------------------------------------------------------------------
# POSTの送信元の確認のテスト
#-------------------------------------------------------------------------------
# 実行: prove t/post_origin.t
#
# ほかのOriginからのPOSTは、ログイン中でも通らないことを確かめる。
# 仕様は docs/仕様/機能一覧.md の「CSRFの対策」のとおり。
#
use FindBin;
BEGIN { push(@INC, "$FindBin::Bin/lib", "$FindBin::Bin/../lib"); }
use Test::More;
use Encode ();
use AppTest;

binmode(Test::More->builder->$_, ':utf8') foreach (qw(output failure_output todo_output));

my $app = AppTest->new()->setup()->seed();

# AppTestのHTTP_HOSTはlocalhost
my @ALLOW = (
	[ 'Sec-Fetch-Siteがsame-origin' => { HTTP_SEC_FETCH_SITE => 'same-origin' } ],
	[ 'Sec-Fetch-Siteがnone'        => { HTTP_SEC_FETCH_SITE => 'none' } ],
	[ 'Sec-Fetch-SiteもOriginも無い' => {} ],
	[ 'Originが同じ'                => { HTTP_ORIGIN => 'http://localhost' } ],
	[ 'Originの大文字と小文字が違う' => { HTTP_ORIGIN => 'HTTP://LOCALHOST' } ],
	[ 'Sec-Fetch-Siteを先に見る'    => { HTTP_SEC_FETCH_SITE => 'same-origin', HTTP_ORIGIN => 'null' } ],
);
my @DENY = (
	[ 'Sec-Fetch-Siteがsame-site'  => { HTTP_SEC_FETCH_SITE => 'same-site' } ],
	[ 'Sec-Fetch-Siteがcross-site' => { HTTP_SEC_FETCH_SITE => 'cross-site' } ],
	[ 'Sec-Fetch-Siteを先に見る'   => { HTTP_SEC_FETCH_SITE => 'cross-site', HTTP_ORIGIN => 'http://localhost' } ],
	[ 'Originのホストが違う'       => { HTTP_ORIGIN => 'http://other.example.com' } ],
	[ 'Originのポートが違う'       => { HTTP_ORIGIN => 'http://localhost:8080' } ],
	[ 'Originの前方だけ同じ'       => { HTTP_ORIGIN => 'http://localhost.example.com' } ],
	[ 'Originがnull'               => { HTTP_ORIGIN => 'null' } ],
);

# data/に書き込む操作。fingerprintはファイルだけを見るので、ファイルが変わる操作を使う
sub write_form {
	my $txt = shift;
	return { action => 'comment_post', a_pkey => 1, name => 'admin', comment_txt => $txt };
}

sub send_post {
	my ($env, $who, $query, $form) = @_;
	local $app->{env} = $env;
	return $app->post($who, $query, $form);
}

sub is_denied {
	my ($r, $name) = @_;
	is($r->{status}, 403, "$name：403を返す");
	like(Encode::decode_utf8($r->{body}), qr/ほかのサイトから送られた/, "$name：知らせを出す");
}

#-------------------------------------------------------------------------------
# 管理者の書き込み操作
#-------------------------------------------------------------------------------
subtest '断るものはdata/とpub/が変わらない' => sub {
	my $n = 0;
	foreach (@DENY) {
		my ($name, $env) = @$_;
		my $before = $app->fingerprint();
		my $r = send_post($env, 'admin', '', write_form("deny" . $n++));
		is_denied($r, $name);
		is_deeply([ AppTest::diff_fingerprint($before, $app->fingerprint()) ], [], "$name：何も変わらない");
	}
};

subtest '通すものは操作が動く' => sub {
	my $n = 0;
	foreach (@ALLOW) {
		my ($name, $env) = @$_;
		my $before = $app->fingerprint();
		my $r = send_post($env, 'admin', '', write_form("allow" . $n++));
		isnt($r->{status}, 403, "$name：断らない");
		my @changed = AppTest::diff_fingerprint($before, $app->fingerprint());
		ok(scalar(@changed), "$name：data/かpub/が変わる");
	}
};

subtest 'HTTPSの既定のポートでも、Originとホストで比べる' => sub {
	my $r = send_post({ HTTPS => 'on', SERVER_PORT => 443, HTTP_ORIGIN => 'https://localhost' },
		'admin', '', write_form("https"));
	isnt($r->{status}, 403, '同じホストなら断らない');
};

#-------------------------------------------------------------------------------
# ログインしていない人の操作
#-------------------------------------------------------------------------------
subtest 'ログインも断る' => sub {
	my %form = (action => '_ajax_login', adiary_id => 'admin', pass => $AppTest::PASS);
	my $r = send_post({ HTTP_SEC_FETCH_SITE => 'same-site' }, 'visitor', '', { %form });
	is_denied($r, 'same-site');
	ok(!(grep { /^session=/ } @{ $r->{cookies} }), 'セッションのCookieを出さない');

	$r = send_post({ HTTP_SEC_FETCH_SITE => 'same-origin' }, 'visitor', '', { %form });
	ok($r->{json} && $r->{json}->{ret} eq '0', '同じOriginならログインできる');
};

subtest 'ゲストのコメントも断る' => sub {
	my $before = $app->fingerprint();
	my $r = send_post({ HTTP_ORIGIN => 'http://other.example.com' }, 'guest', '/01',
		{ action => 'comment_post', a_pkey => 1, name => 'ゲスト', comment_txt => '送信元の確認' });
	is_denied($r, 'ほかのOrigin');
	is_deeply([ AppTest::diff_fingerprint($before, $app->fingerprint()) ], [], '何も変わらない');
};

#-------------------------------------------------------------------------------
# GETは今までどおり
#-------------------------------------------------------------------------------
subtest 'GETには関係しない' => sub {
	my $r;
	{
		local $app->{env} = { HTTP_SEC_FETCH_SITE => 'cross-site' };
		$r = $app->get('guest', '');
	}
	is($r->{status}, 200, 'ほかのサイトのリンクから開ける');
};

done_testing();
