use strict;
use utf8;
#-------------------------------------------------------------------------------
# 主な操作の中身のテスト（ユーザー、パスワード、アップデート処理、システムの設定、編集画面の設定、ページ送り）
#-------------------------------------------------------------------------------
# 実行: prove t/operations_user.t
#
# 操作をしてから画面やファイルを見て、思ったとおりに変わったかを確かめる。
# 権限は t/permission_*.t、画面のエラーは t/screens_*.t で確かめる。
# 並べて動かしたときに早く終わるよう、t/operations_*.t に分けてある。
# どれも、AppTestのsetup()とseed()の後から始める。共通のものは t/lib/OpsTest.pm。
#
use FindBin;
BEGIN { push(@INC, "$FindBin::Bin/lib", "$FindBin::Bin/../lib"); }
use Test::More;
our $TODO;
use AppTest;
use OpsTest;

binmode(Test::More->builder->$_, ':utf8') foreach (qw(output failure_output todo_output));

my $app = AppTest->new()->setup()->seed();
my $dir = $app->dir;

#-------------------------------------------------------------------------------
# ユーザー
#-------------------------------------------------------------------------------
subtest 'ユーザー' => sub {
	$app->insert_user('user');
	$app->login('user');

	my $r = $app->post('user', '', { action => '_ajax_self_change_name', name => '新しい名前' });
	ok(json_ok($r), '自分の名前を変えられる');
	like(body($app->get('user', 'menu')), qr{新しい名前}, '変えた名前が出る');

	$r = $app->post('user', '', { action => '_ajax_self_change_pass', now_pass => 'wrong', pass => 'new-pass-5678', pass2 => 'new-pass-5678' });
	ok(!json_ok($r), '今のパスワードが違うと変えられない');
	$r = $app->post('user', '', { action => '_ajax_self_change_pass', now_pass => $AppTest::PASS, pass => 'new-pass-5678', pass2 => 'new-pass-5678' });
	ok(json_ok($r), 'パスワードを変えられる');
	is($app->get('user', 'menu')->{status}, 403, 'パスワードを変えると、ログインしていたセッションが切れる');

	$r = $app->post('user', '', { action => '_ajax_login', adiary_id => 'user', pass => $AppTest::PASS });
	ok(!json_ok($r), '前のパスワードではログインできない');
	$r = $app->post('user', '', { action => '_ajax_login', adiary_id => 'user', pass => 'new-pass-5678' });
	ok(json_ok($r), '新しいパスワードでログインできる');

	# 管理者がいるときは、ユーザーを作れない
	$r = $app->post('admin', '', { action => '_ajax_user_add', adiary_id => 'newuser', name => 'newuser', pass => $AppTest::PASS, pass2 => $AppTest::PASS, email => '', isadmin => 1 });
	ok(!json_ok($r), '管理者はユーザーを作れない');
	is($app->get('admin', 'user/add')->{status}, 302, '作成の画面は開けない');
};

subtest 'パスワード' => sub {
	my $pass_of = sub {
		my $id = shift;
		foreach my $file (glob("$dir/data/db/_users/0*.dat")) {
			my $t = read_file($file);
			return $1 if ($t =~ /^id=\Q$id\E$/m && $t =~ /^pass=(.*)$/m);
		}
		return '';
	};
	like($pass_of->('admin'), qr/^\$2b\$12\$[.\/A-Za-z0-9]{53}$/, 'bcryptで保存する');

	$app->insert_user('reset');
	$app->login('reset');
	my $change = sub {
		my ($pass, $pass2) = @_;
		return $app->post('reset', '', { action => '_ajax_self_change_pass', now_pass => $AppTest::PASS, pass => $pass, pass2 => $pass2 // $pass });
	};
	ok(!json_ok($change->('abcdefg')), '7文字では変えられない');
	ok(!json_ok($change->('a' x 73)), '72バイトを超えると変えられない');
	ok(!json_ok($change->('abcdefgh', 'abcdefgx')), '確認用と違うと変えられない');
	ok(json_ok($change->('abcdefgh')), '8文字なら変えられる');
	like($pass_of->('reset'), qr/^\$2b\$/, '変えたパスワードもbcrypt');
	isnt($pass_of->('reset'), $pass_of->('admin'), 'saltは毎回違う');
};

subtest 'ページキャッシュの設定は画面に出ない' => sub {
	unlike(body($app->get('admin', 'system/setting')), qr{html_cache|search_cache}, 'キャッシュの欄が無い');
};

subtest '同時ログイン数' => sub {
	# システム設定の画面のフォームの値に、変えたい値を重ねて保存する
	my $save = sub {
		my %set = @_;
		my $b = body($app->get('admin', 'system/setting'));
		my %form;
		while ($b =~ m{<input\b([^>]*)>}g) {
			my $a = $1;
			my ($name) = $a =~ /\bname="([^"]*)"/ or next;
			my ($type) = $a =~ /\btype="([^"]*)"/;
			my ($val)  = $a =~ /\bvalue="([^"]*)"/;
			next if (($type // '') eq 'checkbox' && $a !~ /\bchecked\b/);
			$form{$name} = $val // '';
		}
		while ($b =~ m{<textarea\b[^>]*\bname="([^"]*)"[^>]*>(.*?)</textarea>}sg) { $form{$1} = $2; }
		return $app->post('admin', 'system/setting', { %form, %set, action => 'system/setting' });
	};
	# 同じユーザーで、別の端末（Cookie）からログインする
	$app->insert_user('multi');
	# ログインの時刻（login_tm）は秒単位なので、どれが古いか分かるよう1秒あける
	my $login = sub {
		my $who = shift;
		sleep(1);
		return json_ok($app->post($who, '', { action => '_ajax_login', adiary_id => 'multi', pass => $AppTest::PASS }));
	};
	my $alive = sub { $app->get(shift, 'menu')->{status} == 200 };

	like(body($app->get('admin', 'system/setting')), qr{name="max_sessions"[^>]*value="1"}, '設定ファイルに書いていなければ1');

	ok(AppTest::is_reload($save->(max_sessions => 2)), '2にできる');
	like(body($app->get('admin', 'system/setting')), qr{name="max_sessions"[^>]*value="2"}, '保存した値が出る');
	ok($login->("multi-$_"), "${_}回目のログイン") foreach (1..3);
	ok(!$alive->('multi-1'), '3回目のログインで、いちばん古いログインが切れる');
	ok($alive->('multi-2') && $alive->('multi-3'), '新しい2つは残る');

	ok(AppTest::is_reload($save->(max_sessions => 1)), '1にできる');
	ok($login->('multi-4'), 'もう一度ログインする');
	ok(!$alive->('multi-2') && !$alive->('multi-3'), '1にすると、前のログインがすべて切れる');
	ok($alive->('multi-4'), '新しいログインは残る');

	foreach (0, 11) {
		ok(!AppTest::is_reload($save->(max_sessions => $_)), "${_}は保存できない");
	}
	like(body($app->get('admin', 'system/setting')), qr{name="max_sessions"[^>]*value="1"}, '保存できなかったときは前の値のまま');
	unlike(body($app->get('guest', '')), qr{メンテナンス}, 'ほかの設定は変わらない');
};

subtest 'アップデートが必要なときの知らせ' => sub {
	# 公開している記事（アップデートが必要なときも、記事のページが404にならないことを確かめる）
	ok(AppTest::is_reload($app->post('admin', '', { %ART, title => 'アップデート待ちの記事', body_txt => "本文\n" })), '記事を書く');
	my ($pkey) = body($app->get('admin', 'artlist')) =~ m{href="[^"]*/0(\d+)\?edit"[^>]*>アップデート待ちの記事<};
	my $art = "/0$pkey";
	is($app->get('admin', $art)->{status}, 200, '書いた記事は見られる');

	my $sys = "$dir/data/system_config.dat";
	my $conf = read_file($sys);
	$conf =~ s/^VERSION=.*$/VERSION=4.31/m;
	open(my $fh, '>:utf8', $sys) || die "$sys: $!";
	print $fh $conf;
	close($fh);

	my $link = qr{href="[^"]*\?system/update"};
	foreach my $p ('menu', 'artlist', 'system/setting') {
		my $b = body($app->get('admin', $p));
		like($b, qr{<article class="system notice require-update">.*?アップデート処理が必要です。.*?$link}s, "管理画面（?$p）に、知らせとアップデート処理の画面へのリンクが出る");
		unlike($b, qr{アップデートが必要です。}, "管理画面（?$p）に、リンクの無いメッセージは出ない");
	}
	unlike(body($app->get('admin', 'system/update')), qr{require-update}, 'アップデート処理の画面には、知らせを出さない');

	foreach my $p ('', $art) {
		my $r = $app->get('admin', $p);
		is($r->{status}, 200, "公開画面（$p）は、システム管理者には200");
		like(body($r), qr{<a class="admin-bar-update" $link}, "公開画面（$p）の管理バーに、アップデート処理の画面へのリンクが出る");
		unlike(body($r), qr{require-update|アップデートが必要です。}, "公開画面（$p）の本文には出さない");
		is($r->{headers}->{'cache-control'}, 'private, no-store', "ログイン中の公開画面（$p）は保存させない");
	}
	is($app->get('admin', 'menu')->{headers}->{'cache-control'}, 'private, no-store', 'ログイン中の管理画面は保存させない');

	foreach my $who ('guest') {
		foreach my $p ('', $art, 'menu') {
			my $r = $app->get($who, $p);
			is($r->{status}, 503, "$who には、?$p はメンテナンスの画面");
			unlike(body($r), qr{system/update}, "$who には、?$p にアップデート処理の画面へのリンクを出さない");
		}
	}
	is($app->get('guest', $art)->{headers}->{'cache-control'}, 'no-cache', 'ログインしていない人の画面は今までどおり');

	ok(AppTest::is_reload($app->post('admin', 'system/update', { action => 'system/update' })), 'アップデート処理を行える');
	unlike(body($app->get('admin', 'menu')), qr{require-update}, 'アップデート処理の後は、管理画面に知らせが出ない');
	unlike(body($app->get('admin', $art)), qr{admin-bar-update}, 'アップデート処理の後は、管理バーにリンクが出ない');
	is($app->get('guest', $art)->{headers}->{'cache-control'}, 'no-cache', 'ログインしていない人の記事は、no-cacheのまま');
};

subtest '4.31より古いデータからのアップデート' => sub {
	my $sys = "$dir/data/system_config.dat";
	my $set_version = sub {
		my $conf = read_file($sys);
		$conf =~ s/^VERSION=.*$/VERSION=$_[0]/m;
		open(my $fh, '>:utf8', $sys) || die "$sys: $!";
		print $fh $conf;
		close($fh);
	};
	my $update = sub { return $app->post('admin', 'system/update', { action => 'system/update' }); };

	$set_version->('4.30');
	my $b = body($app->get('admin', 'system/update'));
	like($b, qr{このデータの版（4\.30）からは、直接アップデートできません}, '画面で知らせる');
	like($b, qr{value="system/update"[^>]*disabled}, 'ボタンを押せない');

	ok(!AppTest::is_reload($update->()), '直接送っても断る');
	like(read_file($sys), qr/^VERSION=4\.30$/m, '版はそのまま');

	$set_version->('4.31');
	unlike(body($app->get('admin', 'system/update')), qr{直接アップデートできません}, '4.31なら知らせない');
	ok(AppTest::is_reload($update->()), '4.31からはアップデートできる');
	like(read_file($sys), qr/^VERSION=4\.39$/m, '版が上がる');
};

#-------------------------------------------------------------------------------
# 画面で変える設定（ログイン、アップロード、画像）
#-------------------------------------------------------------------------------
subtest 'システム設定：ログイン、アップロード、画像' => sub {
	my $sys = "$dir/data/system_config.dat";
	my $form = sub {
		my $b = body($app->get('admin', 'system/setting'));
		my %f = map { $_ => '' } qw(mainte_txt);
		while ($b =~ /<input[^>]*type="number"[^>]*>/g) {
			my $t = $&;
			my ($n) = $t =~ /name="(\w+)"/;
			my ($v) = $t =~ /value="([^"]*)"/;
			if (defined $n) { $f{$n} = $v; }
		}
		return %f;
	};
	my $save = sub {
		my %set = @_;
		return $app->post('admin', 'system/setting', { $form->(), %set, action => 'system/setting' });
	};
	my $field = sub {
		my ($name, $val, $msg) = @_;
		like(body($app->get('admin', 'system/setting')), qr{name="$name"[^>]*value="$val"}, $msg);
	};

	$field->('pass_min', 8, 'パスワードの最低文字数は、何も保存していなければ既定値');
	$field->('session_days', 14, 'ログインの保持日数は、何も保存していなければ既定値');
	$field->('fail_count_ip', 15, '同じIPからの失敗の回数は、何も保存していなければ既定値');
	$field->('fail_count', 100, 'アカウントの失敗の回数は、何も保存していなければ既定値');
	$field->('upload_max_mb', 64, 'アップロードの上限は、何も保存していなければ既定値');
	$field->('album_avif_quality', 65, 'AVIFの品質は、何も保存していなければ既定値');

	# 範囲の外は保存できない（ほかの欄は今の値のまま送る。前のテストの保存で、今の値が入っていることがある）
	$app->insert_user('syslock');
	$app->insert_user('passmin');
	$app->login('passmin');
	# 書き戻すと行の順番が変わるので、この項目の行だけを比べる
	my $saved = sub { join("\n", sort grep { /^(?:pass_min|session_days|all_logout|fail_count_ip|fail_count|fail_minute|upload_max_mb|album_jpeg_quality|album_avif_quality)=/ } split(/\n/, read_file($sys))) };
	my $before = $saved->();
	foreach my $bad ([pass_min => 7], [pass_min => 65], [session_days => 0], [session_days => 366],
		[fail_count_ip => 0], [fail_count_ip => 2], [fail_count_ip => 101],
		[fail_count => 0], [fail_count => 2], [fail_count => 101], [fail_minute => 0], [fail_minute => 1441],
		[upload_max_mb => 0], [upload_max_mb => 2049], [album_jpeg_quality => 0], [album_avif_quality => 101]) {
		ok(!AppTest::is_reload($save->(@$bad)), "$bad->[0]=$bad->[1] は保存できない");
	}
	$field->('pass_min', 8, '保存できなかったときは前の値のまま');
	is($saved->(), $before, '保存できなかったときは、ファイルを変えない');

	# 管理者以外は保存できない
	$app->post('guest', 'system/setting', { action => 'system/setting', pass_min => 20 });
	is($saved->(), $before, '管理者でなければ保存できない');

	# 値が効く
	ok(AppTest::is_reload($save->(pass_min => 20, fail_count_ip => 4, fail_count => 3, fail_minute => 5, upload_max_mb => 1, album_avif_quality => 40, session_days => 30, all_logout => 1)), '保存できる');
	$field->('pass_min', 20, '保存した値が欄に出る');
	like(read_file($sys), qr/^session_days=30$/m, '保存した値がファイルに入る');
	like(body($app->get('admin', 'system/setting')), qr{name="all_logout"[^>]*checked}, 'ONにした項目が欄に出る');

	# パスワードの最低文字数は、新しいパスワードに効く
	my $change = sub {
		my $pass = shift;
		return ($app->post('passmin', '', { action => '_ajax_self_change_pass', now_pass => $AppTest::PASS, pass => $pass, pass2 => $pass })->{json} || {})->{ret};
	};
	isnt($change->('abcdefgh1'), '0', '最低文字数より短いパスワードには変えられない');
	is($change->('abcdefgh1abcdefgh1ab'), '0', '最低文字数を満たせば、変えられる');

	# ログインの失敗の回数
	my $try = sub { ($app->post('guest', '', { action => '_ajax_login', adiary_id => 'syslock', pass => shift })->{json} || {})->{ret} };
	{
		local $app->{env} = { REMOTE_ADDR => '10.1.0.1' };
		$try->('wrong-pass') foreach (1..3);
		isnt($try->($AppTest::PASS), '0', '保存した回数（3回）で、正しいパスワードでも止まる');
	}

	# 同じIPからの失敗の回数
	$app->insert_user('sysip');
	my $try_ip = sub {
		my ($ip, $id, $pass) = @_;
		local $app->{env} = { REMOTE_ADDR => $ip };
		return ($app->post('guest', '', { action => '_ajax_login', adiary_id => $id, pass => $pass })->{json} || {})->{ret};
	};
	$field->('fail_count_ip', 4, '保存した値が欄に出る（同じIP）');
	$try_ip->('10.1.0.2', 'no-such-user', 'wrong-pass') foreach (1..4);
	isnt($try_ip->('10.1.0.2', 'sysip', $AppTest::PASS), '0', '保存した回数（4回）で、そのIPからは正しいパスワードでも止まる');
	is($try_ip->('10.1.0.3', 'sysip', $AppTest::PASS), '0', 'ほかのIPからは入れる');

	# アップロードの上限
	my $r = $app->post('admin', '', [ action => 'media/upload_form', folder => 'test/', size => 120,
		file_ary => { filename => 'sysmax.txt', content => 'x' x (1048576 + 1024), type => 'text/plain' } ]);
	ok(!-e "$dir/pub/attachments/test/sysmax.txt", '保存した上限（1MB）を超えると受け付けない');

	# 空にすると既定値に戻す
	ok(AppTest::is_reload($save->(pass_min => '', fail_count_ip => '', fail_count => '', fail_minute => '', upload_max_mb => '', album_avif_quality => '', session_days => '', all_logout => 0)), '空で保存できる');
	$field->('pass_min', 8, '空にすると既定値に戻る');
	$field->('upload_max_mb', 64, '空にすると既定値に戻る（上限）');
	$field->('fail_count_ip', 15, '空にすると既定値に戻る（同じIP）');
	unlike(body($app->get('admin', 'system/setting')), qr{name="all_logout"[^>]*checked}, 'OFFにできる');
};

#-------------------------------------------------------------------------------
# 標準記法で書いた古い記事
#-------------------------------------------------------------------------------
subtest '標準記法の記事' => sub {
	my $write = sub {
		my ($file, $text) = @_;
		open(my $fh, '>:utf8', $file) || die "$file: $!";
		print $fh $text;
		close($fh);
	};

	my $b = body($app->get('admin', 'edit'));
	unlike($b, qr{<option value="default}, '記事の作成画面で、標準記法を選べない');
	unlike($b, qr{この記事の記法（}, '新しい記事では、選べない記法の知らせを出さない');

	# 標準記法で書いた古い記事は、黙ってMarkdownに変わらないように知らせる
	ok(AppTest::is_reload($app->post('admin', '', { %ART, title => '標準記法の記事', body_txt => "本文\n" })), '記事を書く');
	my ($pkey) = body($app->get('admin', 'artlist')) =~ m{href="[^"]*/0(\d+)\?edit"[^>]*>標準記法の記事<};
	my $af = sprintf("$dir/data/db/art/%05d.dat", $pkey);
	my $a = read_file($af);
	ok($a =~ s/^parser=.*$/parser=default/m, '記事の記法を標準記法にする');
	$write->($af, $a);
	like(body($app->get('admin', "/0$pkey?edit")), qr{この記事の記法（default）は選べません。}, '標準記法の記事の編集画面に、知らせを出す');
};

subtest 'マルチサイトと複数ユーザーの列を消すアップデート（4.33）' => sub {
	my $snap = $app->snapshot();
	my $write = sub {
		my ($file, $text) = @_;
		open(my $fh, '>:utf8', $file) || die "$file: $!";
		print $fh $text;
		close($fh);
	};
	require Satsuki::Base;
	my $ROBJ = Satsuki::Base->new();
	my $DB   = $ROBJ->loadpm('DB_text', "$dir/data/db/");
	my $header = sub { (split(/\n/, read_file("$dir/data/db/$_[0]/#index.dat")))[3] };

	# 4.32のデータの形にする。列を足し、記事、ゴミ箱の記事、ユーザーに値を入れる
	ok(AppTest::is_reload($app->post('admin', '', { %ART, title => '4.32の記事', body_txt => "本文\n" })), '記事を書く');
	ok(AppTest::is_reload($app->post('admin', '', { %ART, title => '4.32のゴミ箱の記事', body_txt => "本文\n" })), 'ゴミ箱に入れる記事を書く');
	my %pkey;
	my $list = body($app->get('admin', 'artlist'));
	foreach my $t ('4.32の記事', '4.32のゴミ箱の記事') {
		($pkey{$t}) = $list =~ m{href="[^"]*/0(\d+)\?edit"[^>]*>\Q$t\E<};
	}
	ok(AppTest::is_reload($app->post('admin', '', { action => 'delete', delete_pkey_ary => $pkey{'4.32のゴミ箱の記事'}, title => '' })), 'ゴミ箱に入れる');
	foreach(qw(name id ip host agent)) {
		$DB->add_column('art',   { name => $_, type => 'text', index => ($_ eq 'name' || $_ eq 'id') });
		$DB->add_column('trash', { name => $_, type => 'text' });
	}
	$DB->add_column('trash', { name => 'deleted_id', type => 'text' });
	$DB->add_column('_users', { name => 'isadmin', type => 'flag', index => 1 });
	$DB->add_column('_users', { name => 'disable', type => 'flag' });
	my %old = (name => 'old name', id => 'admin', ip => '192.0.2.1', host => 'old.example', agent => 'OldAgent');
	$DB->begin();
	$DB->update_match('art',   { %old }, 'pkey', $pkey{'4.32の記事'});
	$DB->update_match('trash', { %old, deleted_id => 'admin' }, 'pkey', $pkey{'4.32のゴミ箱の記事'});
	$DB->update_match('_users', { isadmin => 1, disable => 0 }, 'id', 'admin');
	is($DB->commit(), 0, '古い値を入れる');
	like($header->('art'), qr/\bagent\b/, '作った状態の確認：列がある');

	my $sys = "$dir/data/system_config.dat";
	my $sc  = read_file($sys);
	$sc =~ s/^VERSION=.*$/VERSION=4.32/m;
	$write->($sys, $sc);
	my $bs  = "$dir/data/blog/setting.dat";
	$write->($bs, "p:dea_art-info:author=1\n" . read_file($bs));

	# アップデート処理の前も、新しいコードで動く
	is($app->get('admin', 'system/update')->{status}, 200, 'アップデート処理の画面が出る');

	ok(AppTest::is_reload($app->post('admin', 'system/update', { action => 'system/update' })), 'アップデート処理を行える');
	like(read_file($sys), qr/^VERSION=4\.39$/m, '版が上がる');

	unlike(read_file($bs), qr/^p:dea_art-info:author=/m, '「投稿者の表示」の設定が消える');
	foreach my $t (qw(art trash)) {
		my $h = "\t" . $header->($t) . "\t";
		unlike($h, qr/\t(?:name|id|ip|host|agent|deleted_id)\t/, "$t の列が消える");
		my $file = sprintf("$dir/data/db/$t/%05d.dat", $pkey{ $t eq 'art' ? '4.32の記事' : '4.32のゴミ箱の記事' });
		my $row = read_file($file);
		unlike($row, qr/^(?:name|id|ip|host|agent|deleted_id)=/m, "$t の行から値が消える");
		like($row, qr/^title=4\.32の/m, "$t の行の題名は残る");
	}
	unlike("\t" . $header->('_users') . "\t", qr/\t(?:isadmin|disable)\t/, '_users の列が消える');
	like(read_file("$dir/data/db/_users/00001.dat"), qr/^id=admin$/m, '管理者の行は残る');

	# 処理の後も動く
	is($app->get('admin', 'menu')->{status}, 200, '管理者として動く');
	my $edit = body($app->get('admin', "/0$pkey{'4.32の記事'}?edit"));
	unlike($edit, qr/OldAgent|192\.0\.2\.1/, '編集画面に古い値が出ない');
	ok(AppTest::is_reload($app->post('admin', '', { %ART, title => '4.33の記事', body_txt => "本文\n" })), '記事を書ける');
	ok(AppTest::is_reload($app->post('admin', '', { %ART, edit_pkey_int => $pkey{'4.32の記事'}, title => '4.32の記事を直した', body_txt => "本文2\n" })), '記事を直せる');
	like(body($app->get('admin', 'trash')), qr{4\.32のゴミ箱の記事}, 'ゴミ箱に出る');
	ok(AppTest::is_reload($app->post('admin', '', { action => 'trash', mode => 'restore', pkey_ary => $pkey{'4.32のゴミ箱の記事'} })), 'ゴミ箱から戻せる');
	is($app->get('guest', "/0$pkey{'4.32のゴミ箱の記事'}")->{status}, 200, '戻した記事が見られる');
	like(read_file("$dir/pub/rss.xml"), qr{<dc:creator>[^<]+</dc:creator>}, 'RSSに管理者の名前が出る');

	ok(!json_ok($app->post('guest', '', { action => '_ajax_login', adiary_id => 'admin', pass => 'wrong-pass' })), '違うパスワードではログインできない');
	$app->restore($snap);
};

subtest '操作の記録の削除の記録を消すアップデート（4.34）' => sub {
	my $snap = $app->snapshot();
	require Satsuki::Base;
	my $ROBJ = Satsuki::Base->new();
	my $DB   = $ROBJ->loadpm('DB_text', "$dir/data/db/");
	my $count = sub {
		my $ROBJ = Satsuki::Base->new();	# アップデート処理は別のプロセスなので、毎回読み直す
		my $DB   = $ROBJ->loadpm('DB_text', "$dir/data/db/");
		return scalar(@{ $DB->select_match('_users_log', 'type', $_[0]) });
	};

	$DB->begin();
	foreach(qw(login logout regist update delete)) {
		$DB->insert('_users_log', { id => 'admin', type => $_, tm => 1000000000 });
	}
	is($DB->commit(), 0, '各種類の記録を入れる');
	my %before = map { $_ => $count->($_) } qw(login logout regist update);
	foreach(qw(login logout regist update delete)) {
		ok(0 < $count->($_), "作った状態の確認：$_ の記録がある");
	}

	my $sys  = "$dir/data/system_config.dat";
	my $conf = read_file($sys);
	$conf =~ s/^VERSION=.*$/VERSION=4.33/m;
	open(my $fh, '>:utf8', $sys) || die "$sys: $!";
	print $fh $conf;
	close($fh);

	ok(AppTest::is_reload($app->post('admin', 'system/update', { action => 'system/update' })), 'アップデート処理を行える');
	like(read_file($sys), qr/^VERSION=4\.39$/m, '版が上がる');

	is($count->('delete'), 0, 'delete の記録が消える');
	foreach(qw(login logout regist update)) {
		is($count->($_), $before{$_}, "$_ の記録は残る");
	}

	my $b = body($app->get('admin', 'user/log'));
	like($b, qr{<option value="regist"}, '種類の選択肢に追加が残る');
	like($b, qr{<option value="update"}, '種類の選択肢に変更が残る');
	unlike($b, qr{<option value="delete"}, '種類の選択肢から削除が消える');
	$app->restore($snap);
};

subtest '目次のある記事を作り直すアップデート（4.37）' => sub {
	my $snap = $app->snapshot();
	ok(AppTest::is_reload($app->post('admin', '', { %ART, title => '目次の記事', body_txt => "[*toc]\n\n# 見出し\n" })), '目次のある記事を書く');
	ok(AppTest::is_reload($app->post('admin', '', { %ART, title => '目次の無い記事', body_txt => "本文\n" })), '目次の無い記事を書く');

	require Satsuki::Base;
	require Encode;
	my $load = sub {	# DBの値はバイト列なので、文字列にして比べる
		my $ROBJ = Satsuki::Base->new();	# アップデート処理は別のプロセスなので、毎回読み直す
		my $DB   = $ROBJ->loadpm('DB_text', "$dir/data/db/");
		return ($DB, { map { Encode::decode_utf8($_->{title}) => { pkey => $_->{pkey}, text => Encode::decode_utf8($_->{text}), description => Encode::decode_utf8($_->{description}) } } @{ $DB->select_match('art', '*cols', ['pkey', 'title', 'text', 'description']) } }, $ROBJ);
	};
	my ($DB, $arts, $ROBJ) = $load->();	# $ROBJ は $DB が使うので持っておく
	my $toc   = $arts->{'目次の記事'};
	my $plain = $arts->{'目次の無い記事'};
	like($toc->{text}, qr{<nav class="toc-box" aria-label="目次">\s*<div class="toc-title">目次</div>\s*<ul class="toc">}, '書いた記事の目次は、見出し付きの nav で囲まれる');
	is($toc->{description}, '見出し 見出し', '記事の概要に「目次」の見出しは入れない');
	like(body($app->get('guest', "/0$toc->{pkey}")), qr{<nav class="toc-box" aria-label="目次">\s*<div class="toc-title">目次</div>}, '公開画面にも出る');

	# 4.36までの形の目次に戻す
	(my $old = $toc->{text}) =~ s{<nav class="toc-box" aria-label="目次">\s*<div class="toc-title">目次</div>\s*(.*?)\s*</nav>}{$1}s;
	unlike($old, qr{toc-box|toc-title}, '作った状態の確認：古い形の目次にした');
	like($old, qr{<ul class="toc">}, '作った状態の確認：目次の箇条書きは残す');
	$DB->begin();
	$DB->update_match('art', { text => Encode::encode_utf8($old) }, 'pkey', $toc->{pkey});
	$DB->update_match('art', { text => Encode::encode_utf8('<p>作り直さない</p>') }, 'pkey', $plain->{pkey});
	is($DB->commit(), 0, '保存したHTMLを古い形にする');

	my $sys  = "$dir/data/system_config.dat";
	my $conf = read_file($sys);
	$conf =~ s/^VERSION=.*$/VERSION=4.36/m;
	open(my $fh, '>:utf8', $sys) || die "$sys: $!";
	print $fh $conf;
	close($fh);

	ok(AppTest::is_reload($app->post('admin', 'system/update', { action => 'system/update' })), 'アップデート処理を行える');
	like(read_file($sys), qr/^VERSION=4\.39$/m, '版が上がる');

	(undef, $arts) = $load->();
	like($arts->{'目次の記事'}->{text}, qr{<nav class="toc-box" aria-label="目次">\s*<div class="toc-title">目次</div>}, '目次のある記事は作り直す');
	is($arts->{'目次の無い記事'}->{text}, '<p>作り直さない</p>', '目次の無い記事は作り直さない');
	$app->restore($snap);
};

subtest '直前の保存のテーブルを作るアップデート（4.38）' => sub {
	my $snap = $app->snapshot();
	require File::Path;
	File::Path::remove_tree("$dir/data/db/lastrev");
	ok(!-e "$dir/data/db/lastrev", '作った状態の確認：テーブルが無い');

	my $sys  = "$dir/data/system_config.dat";
	my $conf = read_file($sys);
	$conf =~ s/^VERSION=.*$/VERSION=4.37/m;
	open(my $fh, '>:utf8', $sys) || die "$sys: $!";
	print $fh $conf;
	close($fh);

	ok(AppTest::is_reload($app->post('admin', '', { %ART, edit_pkey_int => 1, title => '処理の前に直す', body_txt => "処理の前\n" })), '処理の前でも記事を直せる');
	ok(!-e "$dir/data/db/lastrev", '処理の前には直前の保存を入れない');

	ok(AppTest::is_reload($app->post('admin', 'system/update', { action => 'system/update' })), 'アップデート処理を行える');
	like(read_file($sys), qr/^VERSION=4\.39$/m, '版が上がる');
	ok(-e "$dir/data/db/lastrev/#index.dat", 'テーブルができる');

	$app->post('admin', '', { %ART, edit_pkey_int => 1, title => '処理の後に直す', body_txt => "処理の後\n" });
	my $last = $app->post('admin', '', { action => 'ajax_revision', last => 1 })->{json};
	is($last->{title}, '処理の前に直す', '処理の後は直前の保存を入れる');
	$app->restore($snap);
};

subtest '注釈のある記事を作り直すアップデート（4.39）' => sub {
	my $snap = $app->snapshot();
	ok(AppTest::is_reload($app->post('admin', '', { %ART, title => '注釈の記事', body_txt => "# 大\n\n## 中1\n\n本文((注釈A))\n\n## 中2\n\n本文((注釈B))\n" })), '注釈のある記事を書く');
	ok(AppTest::is_reload($app->post('admin', '', { %ART, title => '注釈の無い記事', body_txt => "本文\n" })), '注釈の無い記事を書く');

	require Satsuki::Base;
	require Encode;
	my $load = sub {	# DBの値はバイト列なので、文字列にして比べる
		my $ROBJ = Satsuki::Base->new();	# アップデート処理は別のプロセスなので、毎回読み直す
		my $DB   = $ROBJ->loadpm('DB_text', "$dir/data/db/");
		return ($DB, { map { Encode::decode_utf8($_->{title}) => { pkey => $_->{pkey}, text => Encode::decode_utf8($_->{text}) } } @{ $DB->select_match('art', '*cols', ['pkey', 'title', 'text']) } }, $ROBJ);
	};
	my ($DB, $arts, $ROBJ) = $load->();	# $ROBJ は $DB が使うので持っておく
	my $note  = $arts->{'注釈の記事'};
	my $plain = $arts->{'注釈の無い記事'};
	my $new_form = qr{注釈A</p>\s*</footer>\s*<h4 id="[^"]+"><a [^>]+>中2</a>};	# 見出しのIDは保存のときに付く
	like($note->{text}, $new_form, '書いた記事の注釈の一覧は、次の見出しの手前に出る');
	like(body($app->get('guest', "/0$note->{pkey}")), $new_form, '公開画面にも出る');

	# 4.38までの形（#の節の終わりにまとめて出す）に戻す
	(my $old = $note->{text}) =~ s{\s*<footer>\s*(<p class="footnote">.*?注釈A</p>)\s*</footer>}{}s;
	my $first = $1;
	$old =~ s{<footer>}{<footer>\n$first};
	unlike($old, $new_form, '作った状態の確認：古い形の注釈の一覧にした');
	$DB->begin();
	$DB->update_match('art', { text => Encode::encode_utf8($old) }, 'pkey', $note->{pkey});
	$DB->update_match('art', { text => Encode::encode_utf8('<p>作り直さない</p>') }, 'pkey', $plain->{pkey});
	is($DB->commit(), 0, '保存したHTMLを古い形にする');

	my $sys  = "$dir/data/system_config.dat";
	my $conf = read_file($sys);
	$conf =~ s/^VERSION=.*$/VERSION=4.38/m;
	open(my $fh, '>:utf8', $sys) || die "$sys: $!";
	print $fh $conf;
	close($fh);

	ok(AppTest::is_reload($app->post('admin', 'system/update', { action => 'system/update' })), 'アップデート処理を行える');
	like(read_file($sys), qr/^VERSION=4\.39$/m, '版が上がる');

	(undef, $arts) = $load->();
	like($arts->{'注釈の記事'}->{text}, $new_form, '注釈のある記事は作り直す');
	is($arts->{'注釈の無い記事'}->{text}, '<p>作り直さない</p>', '注釈の無い記事は作り直さない');
	$app->restore($snap);
};

subtest 'RSSと書き出しの投稿者は管理者の表示名' => sub {
	my $snap = $app->snapshot();
	ok(json_ok($app->post('admin', '', { action => '_ajax_self_change_name', name => 'A&B 管理者' })), '管理者の名前を変える');
	ok(AppTest::is_reload($app->post('admin', '', { %ART, title => '名前の確かめ', body_txt => "本文\n" })), '記事を書く');
	like(read_file("$dir/pub/rss.xml"), qr{<dc:creator>A&amp;B 管理者</dc:creator>}, 'RSSはエスケープして出す');

	my $mt = $app->post('admin', '', { action => 'mainte/export', file => '10_movable_type' })->{body};
	utf8::decode($mt);
	like($mt, qr/^AUTHOR: A&B /m, 'Movable Typeの形式のAUTHORに出る');
	foreach my $f (qw(20_jugem 25_sb)) {
		my $x = $app->post('admin', '', { action => 'mainte/export', file => $f })->{body};
		utf8::decode($x);
		like($x, qr{<author>A&amp;B }, "$f の<author>に出る");
	}
	my $ad = $app->post('admin', '', { action => 'mainte/export', file => '00_adiary' })->{body};
	unlike($ad, qr/^\s*(?:name|id|ip|host|agent)="/m, 'adiary形式の記事に投稿者の項目が出ない');
	$app->restore($snap);
};

subtest 'パスワードを忘れたときの復旧' => sub {
	my $fresh = AppTest->new()->setup();
	system('rm', '-rf', map { "$fresh->{dir}/data/db/$_" } qw(_users _users_sid _users_log)) == 0 || die;
	$fresh->{cookie} = {};
	$fresh->get('root*', 'login_auto');
	ok($fresh->{cookie}->{'root*'}->{session}, 'ユーザーのフォルダを消すと、root*で入れる');
	$fresh->user_add('root*', 'again', 1);
	$fresh->login('again');
	is($fresh->get('again', 'menu')->{status}, 200, '管理者を作り直せる');
	is($fresh->get('again', 'set/')->{status}, 200, 'ブログの設定はそのまま使える');
};

subtest '操作の記録' => sub {
	# 無いIDでの失敗を12件。タグになる文字を混ぜて、エスケープとURLのエンコードも確かめる
	{
		local $app->{env} = { REMOTE_ADDR => '10.1.0.4' };	# 同じIPの回数制限に当たらないように
		$app->post('admin', '', { action => '_ajax_login', adiary_id => 'nobody<x>', pass => 'wrong' }) foreach (1..12);
	}
	my $rows = sub { my @r = (shift =~ m{<td>nobody&lt;x&gt;</td>\s*<td>ログイン</td>\s*<td><strong class="warning">失敗</strong></td>}g); scalar(@r) };

	my $b = body($app->get('admin', 'user/log&loads=10&result=fail&id=' . AppTest::_uri_escape('nobody<x>')));
	is($rows->($b), 10, '1ページ目に10件出る');
	like($b, qr{全12件}, '絞り込んだ件数が出る');
	unlike($b, qr{>user<}, '成功の記録やほかのIDは出ない');

	# 画面のページ送りのリンクをそのまま辿る
	my ($link) = $b =~ m{<a href="[^"?]*\?([^"]*page=2)">};
	ok($link, '2ページ目へのリンクがある');
	$link =~ s/&amp;/&/g;
	unlike($link, qr{<|>}, 'リンクにテンプレートの書きかけが残っていない');
	$b = body($app->get('admin', $link));
	is($rows->($b), 2, '2ページ目に残りの2件が出る');
	like($b, qr{全12件}, '2ページ目でも絞り込みが引き継がれる');
};

#-------------------------------------------------------------------------------
# 編集画面の設定（保存すると、送らなかったflagが0になるので最後に置く）
#-------------------------------------------------------------------------------
subtest '編集画面の画像の既定値とサムネイルの大きさ' => sub {
	# 編集画面のUploadボタン（貼り付けが使う値）と、アップロードのダイアログ
	my $edit = sub {
		my $b = body($app->get('admin', 'edit'));
		my ($btn)  = $b =~ m{(<button type="button" id="edit-file-upload"[^>]*>)};
		my ($form) = $b =~ m{(<form id="upload-form">.*?</form>)}s;
		return ($btn, $form);
	};

	my ($btn, $form) = $edit->();
	like($btn, qr{data-paste="" data-exif="0" data-class=""}, '設定していないときの貼り付けの値');
	unlike($form, qr{name="size"}, 'ダイアログでサムネイルの大きさを選ばせない');
	unlike($form, qr{ selected>(?:大きい画像|センタリング|左寄せ|右寄せ)|paste-to-exif" checked}, '設定していないときは、サムネイル、そのまま、Exifなし');
	my @saves = $form =~ m{class="([^"]*\bjs-save\b[^"]*)"}g;
	is_deeply(\@saves, ['js-switch js-save'], 'ダイアログの欄はブラウザに覚えさせない（覚えるのは「詳細」の開閉だけ）');

	# 選択肢に無い大きさも保存できる
	my %SET = (action => 'set/editor', edit_thumb_size => 200, edit_paste => 'large', edit_paste_exif => 1, edit_paste_class => 'float-r');
	my $r = $app->post('admin', 'set/editor', \%SET);
	ok(AppTest::is_reload($r), '保存できる');
	($btn, $form) = $edit->();
	like($btn, qr{data-paste="large" data-exif="1" data-class="float-r"}, '貼り付けの値が設定になる');
	like($form, qr{<option value="0" selected>大きい画像を貼付</option>}, 'ダイアログが大きい画像になる');
	like($form, qr{id="paste-to-exif" checked}, 'ダイアログのExifが付く');
	like($form, qr{<option value="float-r" selected>}, 'ダイアログの表示が右寄せになる');
	like(body($app->get('admin', 'set/editor')), qr{<option value="200" selected>200px</option>}, '設定の画面にも出る');

	# 範囲外や、選択肢に無い値は拒む
	foreach my $bad ([ edit_thumb_size => 50 ], [ edit_thumb_size => 900 ], [ edit_paste => 'xx' ], [ edit_paste_class => 'xx' ]) {
		$r = $app->post('admin', 'set/editor', { %SET, @$bad });
		ok(!AppTest::is_reload($r), "$bad->[0]=$bad->[1] は保存できない");
	}
	($btn) = $edit->();
	like($btn, qr{data-paste="large"}, '拒んだ後も前の設定のまま');

	# サムネイルは、送られた大きさではなく設定の大きさで作る（元の画像は192px）
	$r = $app->post('admin', 'set/editor', { %SET, edit_thumb_size => 100 });
	ok(AppTest::is_reload($r), '大きさを100にする');
	my $png = do {
		open(my $fh, '<:raw', "$FindBin::Bin/../pub/assets/dist/default-icon.png") || die $!;
		local $/; <$fh>;
	};
	require Satsuki::ImageFormat;
	my $thumb = "$dir/pub/attachments/test/.thumbnail/size.png." . (Satsuki::ImageFormat::can_write_avif() ? 'avif' : 'jpg');
	$r = $app->post('admin', '', [ action => 'media/upload_form', folder => 'test/', size => 640,
		file_ary => { filename => 'size.png', content => $png, type => 'image/png' } ]);
	like($r->{body}, qr/^ret=0$/m, 'アップロードできる');
	is(join('x', Satsuki::ImageFormat::get_size($thumb)), '100x100', 'アップロードでは設定の大きさで作る');

	$r = $app->post('admin', 'set/editor', { %SET, edit_thumb_size => 150 });
	$r = $app->post('admin', '', { action => 'media/remake_thumbnail', folder => 'test/', file_ary => 'size.png', size => 640 });
	ok(json_ok($r), '再生成できる');
	is(join('x', Satsuki::ImageFormat::get_size($thumb)), '150x150', '再生成でも設定の大きさで作る');
	unlike(body($app->get('admin', 'media/')), qr{name="size"|thumbnail-size}, 'メディアでサムネイルの大きさを選ばせない');
};

#-------------------------------------------------------------------------------
# 公開画面のページ送り（PageSpeed Insights の指摘）
#-------------------------------------------------------------------------------
# 保存すると、送らなかったflagが0になるので最後に置く
subtest 'ページ送りの行けない方向はリンクにしない' => sub {
	my $r = $app->post('admin', 'set/detail', { action => 'set/detail', load_items => 1 });
	ok(AppTest::is_reload($r), '1ページ1件にする');

	# 前後だけの形（トップ）と、番号付きの形（検索）。最後のページまで「次のページ」を辿る
	foreach my $base ('', '&q=' . AppTest::_uri_escape('記事')) {
		my ($nav, @nohref, $first, $last);
		for (my $p=1; $p<20; $p++) {
			my $b = body($app->get('guest', "$base&p=$p"));
			$nav = join('', $b =~ m{(<nav class="page-nav.*?</nav>)}sg);
			push(@nohref, map { "p=$p $_" } $nav =~ m{(<a(?![^>]*\bhref=)[^>]*>)}g);
			$first //= $nav;
			$last = $p;
			last if ($nav !~ /class="next-page" rel="next"/);
		}
		ok(1 < $last, "?$base は$last ページある");
		is_deeply(\@nohref, [], "?$base のどのページのページ送りにも、hrefの無いaが無い");
		like($first, qr{<span class="prev-page" aria-hidden="true">前のページ</span>}, "?$base の1ページ目の「前のページ」は見えないspan");
		like($first, qr{<a href="[^"]+" class="next-page" rel="next">次のページ</a>},  "?$base の1ページ目の「次のページ」はリンク");
		like($nav, qr{<a href="[^"]*" class="prev-page" rel="prev">前のページ</a>},    "?$base の最後のページの「前のページ」はリンク");
		like($nav, qr{<span class="next-page" aria-hidden="true">次のページ</span>},  "?$base の最後のページの「次のページ」は見えないspan");
	}
};

done_testing();
