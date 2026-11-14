use strict;
use utf8;
#-------------------------------------------------------------------------------
# IndexNow（変わった記事のURLを検索エンジンに知らせる）のテスト
#-------------------------------------------------------------------------------
# 実行: prove t/indexnow.t
#
# lyndbaum.cgiのBase::HTTPのpostを差し替える（t/lib/HTTPPostStub.pm）ので、外部のネットワークは要らない。
#
use FindBin;
BEGIN { push(@INC, "$FindBin::Bin/lib", "$FindBin::Bin/../lib"); }
use Test::More;
use JSON::PP ();
use AppTest;
use OpsTest;

binmode(Test::More->builder->$_, ':utf8') foreach (qw(output failure_output todo_output));

my $app = AppTest->new()->setup();
my $dir = $app->dir;
my $log = "$dir/post.log";
my $sys = "$dir/data/system_config.dat";
my $SERVER = 'http://localhost/lyndbaum.cgi/';	# テストはmod_rewrite無しのCGIなので、myself2は /lyndbaum.cgi/
our $status = 202;	# 受け口が返す状態

# 送ったもの。呼ぶたびに記録を空にする
sub posts {
	my @ary;
	if (open(my $fh, '<:raw', $log)) {
		while(<$fh>) {
			chomp;
			my ($url, $ctype, $body) = split(/\t/, $_, 3);
			push(@ary, { url => $url, ctype => $ctype, json => eval { JSON::PP::decode_json($body) } });
		}
		close($fh);
	}
	unlink($log);
	return @ary;
}
# 送ったURLの一覧（並べ替えたもの）
sub sent_urls {
	return [ sort map { @{ ($_->{json} || {})->{urlList} || [] } } posts() ];
}
sub post {
	local $app->{env} = { PERL5OPT => "-I$FindBin::Bin/lib -MHTTPPostStub", STUB_POST_LOG => $log, STUB_POST_STATUS => $status };
	return $app->post(@_);
}
sub key { return (read_file($sys) =~ /^indexnow_key=(.*)$/m)[0]; }

# システム設定を保存する（数の欄は今の値のまま送る）
sub save_setting {
	my %set = @_;
	my $b = body($app->get('admin', 'system/setting'));
	my %f = (mainte_txt => '');
	while ($b =~ /<input[^>]*type="number"[^>]*>/g) {
		my $t = $&;
		my ($n) = $t =~ /name="(\w+)"/;
		my ($v) = $t =~ /value="([^"]*)"/;
		if (defined $n) { $f{$n} = $v; }
	}
	return $app->post('admin', 'system/setting', { %f, %set, action => 'system/setting' });
}
# 記事の番号（記事一覧のリンクから）
sub pkey_of {
	my $title = shift;
	my ($pkey) = body($app->get('admin', 'artlist&enable=')) =~ m{href="[^"]*/0(\d+)\?edit"[^>]*>\Q$title\E<};
	return $pkey;
}

subtest '無効のときは送らない' => sub {
	ok(AppTest::is_reload(post('admin', '', { %ART, title => '無効のときの記事', body_txt => "本文\n" })), '記事を書く');
	is(scalar(posts()), 0, '送らない');
	unlike(read_file($sys), qr/^indexnow_key=/m, '鍵は作らない');
};

subtest '有効にすると鍵を作る' => sub {
	ok(AppTest::is_reload(save_setting(indexnow => 1)), '有効にして保存できる');
	like(key(), qr/^[0-9a-f]{32}$/, '32文字の16進数の鍵を作る');
	my $key = key();
	like(body($app->get('admin', 'system/setting')), qr{<code>$key</code>}, '設定の画面に鍵が出る');

	ok(AppTest::is_reload(save_setting(indexnow => 1)), 'もう一度保存する');
	is(key(), $key, '鍵は変わらない');
	unlike(read_file($sys), qr/^indexnow_renew=/m, '作り直しのチェックは保存しない');
};

subtest '鍵ファイル' => sub {
	my $key = key();
	my $r = $app->get('guest', "/$key.txt");
	is($r->{status}, 200, '鍵の文字列に.txtを付けた名前で返す');
	like($r->{headers}->{'content-type'}, qr{^text/plain}, 'text/plainで返す');
	like(body($r), qr/^\s*$key\s*$/, '中身は鍵だけ');
	is($app->get('guest', '/' . ('0' x 32) . '.txt')->{status}, 404, '違う名前は今までどおり（記事が無いので404）');
};

subtest '記事を公開、更新したとき' => sub {
	my $key = key();
	my $r = post('admin', '', { %ART, title => '公開する記事', body_txt => "本文\n" });
	ok(AppTest::is_reload($r), '記事を公開する');
	like(body($r), qr{IndexNowで1件のURLを知らせました}, '知らせたことを画面に出す');
	my $pkey = pkey_of('公開する記事');
	my @p = posts();
	is(scalar(@p), 1, '1回送る');
	is($p[0]->{url}, 'https://api.indexnow.org/indexnow', 'IndexNowの受け口に送る');
	like($p[0]->{ctype}, qr{^application/json}, 'JSONで送る');
	is_deeply($p[0]->{json}, {
		host        => 'localhost',
		key         => $key,
		keyLocation => "$SERVER$key.txt",
		urlList     => [ "${SERVER}0$pkey" ],
	}, '送る中身');

	ok(AppTest::is_reload(post('admin', '', { %ART, edit_pkey_int => $pkey, title => '公開する記事', body_txt => "直した本文\n" })), '公開中の記事を直す');
	is_deeply(sent_urls(), [ "${SERVER}0$pkey" ], '記事のURLを送る');

	ok(AppTest::is_reload(post('admin', '', { %ART, edit_pkey_int => $pkey, title => '公開する記事', body_txt => "本文\n", enable => 0 })), '非公開にする');
	is_deeply(sent_urls(), [ "${SERVER}0$pkey" ], '前に公開していた記事のURLを送る');

	ok(AppTest::is_reload(post('admin', '', { %ART, edit_pkey_int => $pkey, title => '公開する記事', body_txt => "本文\n", enable => 0 })), '非公開のまま直す');
	is(scalar(posts()), 0, '送らない');
};

subtest '下書き' => sub {
	ok(AppTest::is_reload(post('admin', '', { %ART, title => '下書きの記事', body_txt => "下書き\n", draft => 1 })), '下書きを作る');
	is(scalar(posts()), 0, '下書きは送らない');
	my $pkey = pkey_of('下書きの記事');

	ok(AppTest::is_reload(post('admin', 'artlist', [ action => 'articles_edit', mode => 'enable', pkey_ary => $pkey ])), '一覧から公開にしても');
	is(scalar(posts()), 0, '下書きは公開にならないので送らない');

	ok(AppTest::is_reload(post('admin', '', { %ART, edit_pkey_int => $pkey, title => '下書きの記事', body_txt => "公開\n" })), '下書きを公開する');
	is_deeply(sent_urls(), [ "${SERVER}0$pkey" ], '公開したら送る');

	ok(AppTest::is_reload(post('admin', '', { %ART, edit_pkey_int => $pkey, title => '下書きの記事', body_txt => "公開\n", draft => 1 })), '下書きに戻す');
	is_deeply(sent_urls(), [ "${SERVER}0$pkey" ], '前に公開していた記事のURLを送る');
};

subtest 'link_keyを変えたとき' => sub {
	ok(AppTest::is_reload(post('admin', '', { %ART, title => '名前の付いたページ', body_txt => "本文\n", page => 1, link_key_txt => 'old-page' })), 'ページを公開する');
	is_deeply(sent_urls(), [ "${SERVER}old-page" ], 'ページのURLを送る');
	my $pkey = pkey_of('名前の付いたページ');

	ok(AppTest::is_reload(post('admin', '', { %ART, edit_pkey_int => $pkey, title => '名前の付いたページ', body_txt => "本文\n", page => 1, link_key_txt => 'new-page' })), 'link_keyを変える');
	is_deeply(sent_urls(), [ "${SERVER}new-page", "${SERVER}old-page" ], '古いURLと新しいURLを1回で送る');
};

subtest '記事一覧からのまとめての操作' => sub {
	ok(AppTest::is_reload(post('admin', '', { %ART, title => '一覧の記事A', body_txt => "A\n" })), '記事Aを書く');
	ok(AppTest::is_reload(post('admin', '', { %ART, title => '一覧の記事B', body_txt => "B\n" })), '記事Bを書く');
	posts();
	my $a = pkey_of('一覧の記事A');
	my $b = pkey_of('一覧の記事B');

	ok(AppTest::is_reload(post('admin', 'artlist', [ action => 'articles_edit', mode => 'disable', pkey_ary => $a, pkey_ary => $b ])), '非公開にする');
	my @p = posts();
	is(scalar(@p), 1, '1回にまとめて送る');
	is_deeply([ sort @{ $p[0]->{json}->{urlList} } ], [ sort("${SERVER}0$a", "${SERVER}0$b") ], '2つの記事のURLを送る');

	ok(AppTest::is_reload(post('admin', 'artlist', [ action => 'articles_edit', mode => 'disable', pkey_ary => $a ])), 'もう一度非公開にする');
	is(scalar(posts()), 0, '前から非公開なら送らない');

	ok(AppTest::is_reload(post('admin', 'artlist', [ action => 'articles_edit', mode => 'enable', pkey_ary => $a ])), '公開にする');
	is_deeply(sent_urls(), [ "${SERVER}0$a" ], '公開した記事のURLを送る');

	ok(AppTest::is_reload(post('admin', '', { action => 'delete', delete_pkey_ary => $a, title => '' })), '公開中の記事を削除する');
	is_deeply(sent_urls(), [ "${SERVER}0$a" ], '削除した記事のURLを送る');

	ok(AppTest::is_reload(post('admin', '', { action => 'delete', delete_pkey_ary => $b, title => '' })), '非公開の記事を削除する');
	is(scalar(posts()), 0, '非公開の記事は送らない');

	ok(AppTest::is_reload(post('admin', 'artlist', [ action => 'articles_edit', mode => 'tagset', pkey_ary => pkey_of('公開する記事'), tags => 'タグ' ])), 'タグを付ける');
	is(scalar(posts()), 0, 'タグの付け替えでは送らない');
};

subtest '送れなかったとき' => sub {
	local $status = 500;
	my $r = post('admin', '', { %ART, title => '送れない記事', body_txt => "本文\n" });
	ok(AppTest::is_reload($r), '記事は保存できる');
	like(body($r), qr{IndexNowで知らせられませんでした：status 500}, '送れなかったことを画面に出す');
	is(scalar(posts()), 1, '送ろうとはする');
	ok(pkey_of('送れない記事'), '記事一覧に出る');
};

subtest '鍵を作り直す' => sub {
	my $old = key();
	ok(AppTest::is_reload(save_setting(indexnow => 1, indexnow_renew => 1)), '作り直して保存する');
	my $new = key();
	like($new, qr/^[0-9a-f]{32}$/, '新しい鍵');
	isnt($new, $old, '前の鍵と違う');
	is($app->get('guest', "/$old.txt")->{status}, 404, '前の鍵ファイルは返さない');
	is($app->get('guest', "/$new.txt")->{status}, 200, '新しい鍵ファイルを返す');
};

subtest '無効に戻す' => sub {
	my $key = key();
	ok(AppTest::is_reload(save_setting(indexnow => 0)), '無効にして保存する');
	is(key(), $key, '鍵は残す');
	is($app->get('guest', "/$key.txt")->{status}, 404, '鍵ファイルは返さない');
	ok(AppTest::is_reload(post('admin', '', { %ART, title => '無効に戻した後の記事', body_txt => "本文\n" })), '記事を書く');
	is(scalar(posts()), 0, '送らない');
};

done_testing();
