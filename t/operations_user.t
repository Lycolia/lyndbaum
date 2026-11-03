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

	$r = $app->post('admin', '', { action => '_ajax_user_edit', id => 'user', disable => 1 });
	ok(json_ok($r), 'システム管理者がユーザーを無効にできる');
	is($app->get('user', 'menu')->{status}, 403, '無効にすると、セッションが切れる');
	$r = $app->post('user', '', { action => '_ajax_login', adiary_id => 'user', pass => 'new-pass-5678' });
	ok(!json_ok($r), '無効にしたユーザーはログインできない');

	$r = $app->post('admin', '', { action => '_ajax_user_delete', id => 'user' });
	ok(json_ok($r), 'ユーザーを削除できる');
	unlike(body($app->get('admin', 'user/')), qr{>user<}, 'ユーザーの一覧から消える');
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

	my $add = sub {
		my ($id, $pass, $pass2) = @_;
		return $app->post('admin', '', { action => '_ajax_user_add', adiary_id => $id, name => $id, pass => $pass, pass2 => $pass2 // $pass, email => '', isadmin => 0 });
	};
	ok(!json_ok($add->('short', 'abcdefg')), '7文字では追加できない');
	ok(!json_ok($add->('longpass', 'a' x 73)), '72バイトを超えると追加できない');
	ok(!json_ok($add->('mismatch', 'abcdefgh', 'abcdefgx')), '確認用と違うと追加できない');
	ok(json_ok($add->('reset', 'abcdefgh')), '8文字なら追加できる');
	like($pass_of->('reset'), qr/^\$2b\$/, '追加したユーザーもbcrypt');
	isnt($pass_of->('reset'), $pass_of->('admin'), 'saltは毎回違う');

	# 前のSHA-512のハッシュに戻す（4.22までに保存したユーザー）
	my $sha = crypt('old-pass-1234', '$6$abcdefghijklmnop$');
	foreach my $file (glob("$dir/data/db/_users/0*.dat")) {
		my $t = read_file($file);
		next if ($t !~ /^id=reset$/m);
		$t =~ s/^pass=.*$/pass=$sha/m;
		open(my $fh, '>:utf8', $file) || die; print $fh $t; close($fh);
	}
	my $r = $app->post('reset', '', { action => '_ajax_login', adiary_id => 'reset', pass => 'old-pass-1234' });
	ok(json_ok($r), 'SHA-512のハッシュでもログインできる');

	$r = $app->get('reset', 'menu');
	is($r->{status}, 302, '再設定するまで、ほかの画面は開けない');
	like($r->{headers}->{location} // '', qr{\?personal/$}, 'パスワードの変更画面へ送る');
	$r = $app->get('reset', 'personal/');
	is($r->{status}, 200, 'パスワードの変更画面は開ける');
	like(body($r), qr{パスワードの保存方式を変えました}, '再設定の知らせが出る');
	ok(!json_ok($app->post('reset', '', { action => '_ajax_self_change_name', name => 'x' })), 'ほかの操作はできない');

	$r = $app->post('reset', '', { action => '_ajax_self_change_pass', now_pass => 'old-pass-1234', pass => 'new-pass-5678', pass2 => 'new-pass-5678' });
	ok(json_ok($r), 'パスワードを変えられる');
	like($pass_of->('reset'), qr/^\$2b\$/, '変えるとbcryptになる');
	ok(json_ok($app->post('reset', '', { action => '_ajax_login', adiary_id => 'reset', pass => 'new-pass-5678' })), '新しいパスワードでログインできる');
	is($app->get('reset', 'menu')->{status}, 200, '再設定の後は、ほかの画面も開ける');

	ok(json_ok($app->post('admin', '', { action => '_ajax_user_delete', id => 'reset' })), '後片付け');
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
	$app->user_add('admin', 'multi', 0);
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

	# v4.19のアップデート処理で、設定ファイルの値（ここでは書いていないので1）をシステム設定に写す
	my $sys = "$dir/data/system_config.dat";
	my $conf = read_file($sys);
	$conf =~ s/^max_sessions=.*\n//m;
	$conf =~ s/^VERSION=.*$/VERSION=4.18/m;
	open(my $fh, '>:utf8', $sys) || die "$sys: $!";
	print $fh $conf;
	close($fh);
	ok(AppTest::is_reload($app->post('admin', 'system/update', { action => 'system/update' })), 'アップデート処理を行える');
	like(read_file($sys), qr/^max_sessions=1$/m, 'アップデート処理で、同時ログイン数がシステム設定に入る');
	like(read_file($sys), qr/^VERSION=4\.25$/m, 'バージョンが今のデータのバージョン（4.25）になる');
};

subtest 'アップデートが必要なときの知らせ' => sub {
	# システム管理者でないログイン中の人は、前のテストの multi（multi-4 でログインしている）を使う
	# （メンテナンスの画面はCookieを消すので、ほかのテストのユーザーは使わない）
	ok($app->get('multi-4', 'menu')->{status} == 200, 'システム管理者でない人がログインしている');

	# 公開している記事（アップデートが必要なときも、記事のページが404にならないことを確かめる）
	ok(AppTest::is_reload($app->post('owner', '', { %ART, title => 'アップデート待ちの記事', body_txt => "本文\n" })), '記事を書く');
	my ($pkey) = body($app->get('owner', 'artlist')) =~ m{href="[^"]*/0(\d+)\?edit"[^>]*>アップデート待ちの記事<};
	my $art = "/0$pkey";
	is($app->get('admin', $art)->{status}, 200, '書いた記事は見られる');

	my $sys = "$dir/data/system_config.dat";
	my $conf = read_file($sys);
	$conf =~ s/^VERSION=.*$/VERSION=4.18/m;
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

	foreach my $who ('multi-4', 'guest') {
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

#-------------------------------------------------------------------------------
# パスワードのbcrypt化（4.23）
#-------------------------------------------------------------------------------
subtest 'アップデート処理でのパスワードの再設定' => sub {
	my $user_file = sub {
		my $id = shift;
		foreach my $file (glob("$dir/data/db/_users/0*.dat")) {
			return $file if (read_file($file) =~ /^id=\Q$id\E$/m);
		}
	};
	my $file = $user_file->('admin');
	my $write = sub {
		my ($f, $text) = @_;
		open(my $fh, '>:utf8', $f) || die "$f: $!";
		print $fh $text;
		close($fh);
	};
	# 4.22までのデータ（管理者のパスワードがSHA-512）にする
	my $t = read_file($file);
	my $sha = crypt($AppTest::PASS, '$6$abcdefghijklmnop$');
	$t =~ s/^pass=.*$/pass=$sha/m;
	$write->($file, $t);
	my $sys = "$dir/data/system_config.dat";
	my $conf = read_file($sys);
	$conf =~ s/^VERSION=.*$/VERSION=4.22/m;
	$write->($sys, $conf);

	like(body($app->get('admin', 'system/update')), qr{name="pass".*name="pass2"}s, 'アップデート処理の画面に、新しいパスワードの欄が出る');
	is($app->get('admin', 'menu')->{status}, 200, 'アップデートが要るときの管理者は、パスワードの変更画面へ送らない');

	foreach my $f ({}, { pass => 'abcdefg', pass2 => 'abcdefg' }, { pass => 'abcdefgh', pass2 => 'abcdefgx' }) {
		my $r = $app->post('admin', 'system/update', { action => 'system/update', %$f });
		ok(!AppTest::is_reload($r), 'パスワードが規則に合わなければ、アップデート処理を行わない（' . ($f->{pass} // '空') . '）');
		like(read_file($sys), qr/^VERSION=4\.22$/m, '版はそのまま');
	}

	my $r = $app->post('admin', 'system/update', { action => 'system/update', pass => $AppTest::PASS, pass2 => $AppTest::PASS });
	ok(AppTest::is_reload($r), '新しいパスワードを入れると、アップデート処理を行える');
	like(body($r), qr{\?login}, '終わるとログインの画面へ送る');
	like(read_file($sys), qr/^VERSION=4\.25$/m, '版が今のデータのバージョン（4.25）になる');
	like(read_file($file), qr/^pass=\$2b\$12\$/m, '管理者のパスワードがbcryptになる');
	is($app->get('admin', 'menu')->{status}, 403, 'セッションが切れる');
	$app->login('admin');
	is($app->get('admin', 'menu')->{status}, 200, '新しいパスワードでログインし直せる');
	unlike(body($app->get('admin', 'system/update')), qr{name="pass"}, 'アップデート処理の後は、パスワードの欄を出さない');
};

#-------------------------------------------------------------------------------
# AVIFのサムネイルの画質の設定（4.25）
#-------------------------------------------------------------------------------
subtest 'アップデート処理で、設定ファイルにAVIFの画質を足す' => sub {
	my $write = sub {
		my ($f, $text) = @_;
		open(my $fh, '>:utf8', $f) || die "$f: $!";
		print $fh $text;
		close($fh);
	};
	my $sys  = "$dir/data/system_config.dat";
	my $file = "$dir/lyndbaum.conf.cgi";
	my $update = sub {
		my $t = read_file($sys);
		$t =~ s/^VERSION=.*$/VERSION=4.24/m;
		$write->($sys, $t);
		return $app->post('admin', 'system/update', { action => 'system/update' });
	};

	# 4.24までの設定ファイル（AVIFの画質の行が無い）にする
	my $conf = read_file($file);
	ok($conf =~ s/\n# AVIFサムネイル生成時の品質\n<\$v\.album_avif_quality = 65>\n//, '見本からAVIFの画質の行を消す');
	$write->($file, $conf);

	ok(AppTest::is_reload($update->()), 'アップデート処理を行える');
	my $new = read_file($file);
	like($new, qr{^<\$v\.album_jpeg_quality = 80>\n\n# AVIFサムネイル生成時の品質\n<\$v\.album_avif_quality = 65>\n}m, 'JPEGの画質の行の後に、AVIFの画質の行が入る');
	is(scalar(() = $new =~ /album_avif_quality/g), 1, 'AVIFの画質の行は1つ');
	is(read_file("$dir/data/lyndbaum.conf.cgi.425.bak"), $conf, '書き換える前のファイルを写しておく');

	ok(AppTest::is_reload($update->()), 'もう一度アップデート処理を行える');
	is(read_file($file), $new, '行があれば、設定ファイルは変わらない');

	# # で止めてある行も、その人が決めたことなので触らない
	(my $off = $conf) =~ s/^(<\$v\.album_jpeg_quality = 80>\n)/$1#<\$v.album_avif_quality = 50>\n/m;
	$write->($file, $off);
	ok(AppTest::is_reload($update->()), '止めてある行があってもアップデート処理を行える');
	is(read_file($file), $off, '止めてある行があれば、設定ファイルは変わらない');
	$write->($file, $new);	# 後のテストのために戻す
};

#-------------------------------------------------------------------------------
# 標準記法の削除（4.22）
#-------------------------------------------------------------------------------
subtest '標準記法の削除' => sub {
	my $write = sub {
		my ($file, $text) = @_;
		open(my $fh, '>:utf8', $file) || die "$file: $!";
		print $fh $text;
		close($fh);
	};

	# 4.21までの設定ファイルと、標準記法を既定にしたブログ
	my $cf = "$dir/lyndbaum.conf.cgi";
	my $conf = read_file($cf);
	$conf =~ s/^(\tmarkdown\s*=.*\n)/$1\tdefault       = 標準（改行処理）\n\tdefault_p1    = １行＝１段落\n\tdefault_p2    = 空行で段落処理\n/m;
	$write->($cf, $conf);
	my $bs = "$dir/data/blog/setting.dat";
	my $set = read_file($bs);
	$set =~ s/^parser=.*$/parser=default/m;
	$write->($bs, $set);
	my $sys = "$dir/data/system_config.dat";
	my $sc = read_file($sys);
	$sc =~ s/^VERSION=.*$/VERSION=4.21/m;
	$write->($sys, $sc);

	ok(AppTest::is_reload($app->post('admin', 'system/update', { action => 'system/update' })), 'アップデート処理を行える');
	unlike(read_file($cf), qr/^\tdefault/m, '設定ファイルの v.parsers から標準記法の行が消える');
	like(read_file($cf), qr/^\tmarkdown\s*=/m, 'Markdownの行は残る');
	ok(-e "$dir/data/lyndbaum.conf.cgi.422.bak", '書き換える前の設定ファイルの控えを残す');
	like(read_file($bs), qr/^parser=markdown$/m, 'ブログの既定のパーサーがMarkdownになる');

	my $b = body($app->get('owner', 'edit'));
	unlike($b, qr{<option value="default}, '記事の作成画面で、標準記法を選べない');
	unlike($b, qr{この記事の記法（}, '新しい記事では、選べない記法の知らせを出さない');

	# 標準記法で書いた古い記事は、黙ってMarkdownに変わらないように知らせる
	ok(AppTest::is_reload($app->post('owner', '', { %ART, title => '標準記法の記事', body_txt => "本文\n" })), '記事を書く');
	my ($pkey) = body($app->get('owner', 'artlist')) =~ m{href="[^"]*/0(\d+)\?edit"[^>]*>標準記法の記事<};
	my $af = sprintf("$dir/data/db/art/%05d.dat", $pkey);
	my $a = read_file($af);
	ok($a =~ s/^parser=.*$/parser=default/m, '記事の記法を標準記法にする');
	$write->($af, $a);
	like(body($app->get('owner', "/0$pkey?edit")), qr{この記事の記法（default）は選べません。}, '標準記法の記事の編集画面に、知らせを出す');
};

subtest '操作の記録' => sub {
	# 無いIDでの失敗を12件。タグになる文字を混ぜて、エスケープとURLのエンコードも確かめる
	$app->post('editor', '', { action => '_ajax_login', adiary_id => 'nobody<x>', pass => 'wrong' }) foreach (1..12);
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
		my $b = body($app->get('editor', 'edit'));
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
	my $r = $app->post('owner', 'set/editor', \%SET);
	ok(AppTest::is_reload($r), '保存できる');
	($btn, $form) = $edit->();
	like($btn, qr{data-paste="large" data-exif="1" data-class="float-r"}, '貼り付けの値が設定になる');
	like($form, qr{<option value="0" selected>大きい画像を貼付</option>}, 'ダイアログが大きい画像になる');
	like($form, qr{id="paste-to-exif" checked}, 'ダイアログのExifが付く');
	like($form, qr{<option value="float-r" selected>}, 'ダイアログの表示が右寄せになる');
	like(body($app->get('owner', 'set/editor')), qr{<option value="200" selected>200px</option>}, '設定の画面にも出る');

	# 範囲外や、選択肢に無い値は拒む
	foreach my $bad ([ edit_thumb_size => 50 ], [ edit_thumb_size => 900 ], [ edit_paste => 'xx' ], [ edit_paste_class => 'xx' ]) {
		$r = $app->post('owner', 'set/editor', { %SET, @$bad });
		ok(!AppTest::is_reload($r), "$bad->[0]=$bad->[1] は保存できない");
	}
	($btn) = $edit->();
	like($btn, qr{data-paste="large"}, '拒んだ後も前の設定のまま');

	# サムネイルは、送られた大きさではなく設定の大きさで作る（元の画像は192px）
	$r = $app->post('owner', 'set/editor', { %SET, edit_thumb_size => 100 });
	ok(AppTest::is_reload($r), '大きさを100にする');
	my $png = do {
		open(my $fh, '<:raw', "$FindBin::Bin/../pub/assets/dist/default-icon.png") || die $!;
		local $/; <$fh>;
	};
	require Satsuki::ImageFormat;
	my $thumb = "$dir/pub/attachments/test/.thumbnail/size.png." . (Satsuki::ImageFormat::can_write_avif() ? 'avif' : 'jpg');
	$r = $app->post('editor', '', [ action => 'media/upload_form', folder => 'test/', size => 640,
		file_ary => { filename => 'size.png', content => $png, type => 'image/png' } ]);
	like($r->{body}, qr/^ret=0$/m, 'アップロードできる');
	is(join('x', Satsuki::ImageFormat::get_size($thumb)), '100x100', 'アップロードでは設定の大きさで作る');

	$r = $app->post('owner', 'set/editor', { %SET, edit_thumb_size => 150 });
	$r = $app->post('editor', '', { action => 'media/remake_thumbnail', folder => 'test/', file_ary => 'size.png', size => 640 });
	ok(json_ok($r), '再生成できる');
	is(join('x', Satsuki::ImageFormat::get_size($thumb)), '150x150', '再生成でも設定の大きさで作る');
	unlike(body($app->get('editor', 'media/')), qr{name="size"|thumbnail-size}, 'メディアでサムネイルの大きさを選ばせない');
};

#-------------------------------------------------------------------------------
# 公開画面のページ送り（PageSpeed Insights の指摘）
#-------------------------------------------------------------------------------
# 保存すると、送らなかったflagが0になるので最後に置く
subtest 'ページ送りの行けない方向はリンクにしない' => sub {
	my $r = $app->post('owner', 'set/detail', { action => 'set/detail', load_items => 1 });
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
