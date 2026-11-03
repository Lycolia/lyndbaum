use strict;
use utf8;
#-------------------------------------------------------------------------------
# 主な操作の中身のテスト
#-------------------------------------------------------------------------------
# 実行: prove t/operations.t
#
# 操作をしてから画面やファイルを見て、思ったとおりに変わったかを確かめる。
# 権限は t/permission_*.t、画面のエラーは t/screens.t で確かめる。
#
use FindBin;
BEGIN { push(@INC, "$FindBin::Bin/lib", "$FindBin::Bin/../lib"); }
use Test::More;
our $TODO;
use AppTest;

binmode(Test::More->builder->$_, ':utf8') foreach (qw(output failure_output todo_output));

my $app = AppTest->new()->setup()->seed();
my $dir = $app->dir;

sub body {
	my $b = shift->{body} // '';
	utf8::decode($b);
	return $b;
}
sub read_file {
	my $file = shift;
	open(my $fh, '<:utf8', $file) || return '';
	local $/;
	return <$fh>;
}
sub json_ok {
	my $r = shift;
	return $r->{json} && defined $r->{json}->{ret} && $r->{json}->{ret} eq '0';
}
my %ART = (action => 'edit', parser => 'markdown', enable => 1, com_ok => 1, ymd => '2026-10-10');

#-------------------------------------------------------------------------------
# 記事
#-------------------------------------------------------------------------------
subtest '記事を書く' => sub {
	my $r = $app->post('editor', '', { %ART, title => '新しい記事', body_txt => "新しい**本文**\n", tag_ary => '新しいタグ' });
	ok(AppTest::is_reload($r), '保存できる');

	$r = $app->get('guest', '/04');
	is($r->{status}, 200, '記事のページが出る');
	like($r->{title}, qr/^新しい記事 - /, '題名');
	like(body($r), qr{新しい<strong>本文</strong>}, '本文はMarkdownからHTMLになる');
	like(body($r), qr{新しいタグ}, 'タグが出る');

	like(body($app->get('guest', '')), qr{新しい記事}, 'トップに出る');
	like(body($app->get('guest', '&t=' . AppTest::_uri_escape('新しいタグ'))), qr{新しい記事}, 'タグの一覧に出る');
	like(read_file("$dir/pub/rss.xml"), qr{新しい記事}, 'RSSに出る');
};

subtest '下書き' => sub {
	my $r = $app->post('editor', '', { %ART, title => '下書きの記事', body_txt => "下書き\n", enable => 0 });
	ok(AppTest::is_reload($r), '保存できる');
	is($app->get('guest', '/05')->{status}, 404, 'ログインしていない人には出ない');
	like($app->get('editor', '/05')->{title}, qr/^下書きの記事 - /, '編集者には出る');
	unlike(body($app->get('guest', '')), qr{下書きの記事}, 'トップに出ない');
	unlike(read_file("$dir/pub/rss.xml"), qr{下書きの記事}, 'RSSに出ない');
};

subtest '記事を直す' => sub {
	my $r = $app->post('editor', '', { %ART, edit_pkey_int => 1, title => '直した題名', body_txt => "直した本文\n", ymd => '2026-10-01' });
	ok(AppTest::is_reload($r), '保存できる');

	$r = $app->get('guest', '/01');
	like($r->{title}, qr/^直した題名 - /, '題名が変わる');
	like(body($r), qr{直した本文}, '本文が変わる');
	like(read_file("$dir/pub/rss.xml"), qr{直した題名}, 'RSSも変わる');

	$r = $app->post('editor', '', { action => 'ajax_revision', pkey => 1 });
	my $revs = $r->{json};
	ok(ref($revs) eq 'ARRAY' && @$revs == 1, '更新履歴に、直す前の版が1つ残る');
};

subtest '他人の記事' => sub {
	my $r = $app->post('owner', '', { %ART, edit_pkey_int => 1, title => 'ブログ管理者が直した', body_txt => "本文\n" });
	ok(AppTest::is_reload($r), 'ブログ管理者は、編集者の記事を直せる');

	# 自分の記事だけを直せる設定にすると、編集者はブログ管理者の記事を直せない
	$r = $app->post('owner', 'set/role', { action => 'set/role', admin_users => 'owner', editors => 'editor', viewers => '', view_pass => '', edit_by_author_only => 1 });
	ok(AppTest::is_reload($r), '「自分の記事だけ」にする');
	$r = $app->post('editor', '', { %ART, edit_pkey_int => 2, title => '編集者が直した', body_txt => "本文\n" });
	ok(!AppTest::is_reload($r), '編集者はブログ管理者の記事を直せない');
	unlike($app->get('guest', '/02')->{title}, qr/編集者が直した/, '題名は変わらない');

	$r = $app->post('owner', 'set/role', { action => 'set/role', admin_users => 'owner', editors => 'editor', viewers => '', view_pass => '' });
	ok(AppTest::is_reload($r), '元に戻す');
};

subtest 'ゴミ箱' => sub {
	my $r = $app->post('editor', '', { action => 'delete', delete_pkey_ary => 1, title => '' });
	ok(AppTest::is_reload($r), 'ゴミ箱へ移せる');
	is($app->get('guest', '/01')->{status}, 404, '記事のページは出ない');
	like(body($app->get('editor', 'trash')), qr{ブログ管理者が直した}, 'ゴミ箱に出る');

	$r = $app->post('editor', '', { action => 'trash', mode => 'restore', pkey_ary => 1 });
	ok(AppTest::is_reload($r), '戻せる');
	is($app->get('guest', '/01')->{status}, 200, '記事のページがまた出る');

	$r = $app->post('owner', '', { action => 'trash', mode => 'purge_all' });
	ok(AppTest::is_reload($r), 'ゴミ箱を空にできる');
	unlike(body($app->get('editor', 'trash')), qr{消す記事}, 'ゴミ箱から消える');
};

subtest '記事一覧からのまとめての操作' => sub {
	my $r = $app->post('editor', 'artlist', [ action => 'articles_edit', mode => 'disable', pkey_ary => 1, pkey_ary => 2 ]);
	ok(AppTest::is_reload($r), '非公開にできる');
	is($app->get('guest', '/01')->{status}, 404, '記事1は出ない');
	is($app->get('guest', '/02')->{status}, 404, '記事2は出ない');

	$r = $app->post('editor', 'artlist', [ action => 'articles_edit', mode => 'enable', pkey_ary => 1, pkey_ary => 2 ]);
	ok(AppTest::is_reload($r), '公開に戻せる');
	is($app->get('guest', '/01')->{status}, 200, '記事1が出る');
	is($app->get('guest', '/02')->{status}, 200, '記事2が出る');
};

#-------------------------------------------------------------------------------
# コメント
#-------------------------------------------------------------------------------
subtest 'ログインしていない人のコメント' => sub {
	# ブラウザーと同じく、記事のページのトークンを読み、3秒より後に送る
	my $r = $app->get('visitor', '/02');
	my ($secure) = body($r) =~ /data-secure="([^"]+)"/;
	ok($secure, 'コメント欄にトークンがある');
	my @ary = split(/,/, $secure);
	pop(@ary);
	my $sid = join('', map { chr($_ ^ (2 & 255)) } @ary);

	my %form = (action => 'comment_post', a_pkey => 2, secure_id => $sid, name => '通りすがり', comment_txt => 'ゲストのコメント', website => '');
	$r = $app->post('visitor', '/02', { %form });
	unlike(body($app->get('guest', '/02')), qr{ゲストのコメント}, 'トークンを出してからすぐに送ると、はじかれる');

	sleep(4);
	$r = $app->post('visitor', '/02', { %form, website => 'http://spam.example/' });
	unlike(body($app->get('guest', '/02')), qr{ゲストのコメント}, 'おとりの欄に入っていると、はじかれる');

	$r = $app->post('visitor', '/02', { %form });
	like($r->{title}, qr/^処理結果/, '投稿できる');
	like(body($app->get('guest', '/02')), qr{ゲストのコメント}, '記事のページに出る');
	like(body($app->get('editor', 'comlist')), qr{ゲストのコメント}, 'コメント一覧に出る');
};

subtest 'コメントの承認の取り消し・承認・削除' => sub {
	my $r = $app->post('editor', '', { action => 'comments_edit', disable => 1, pkey_ary => 1 });
	ok(AppTest::is_reload($r), '承認を取り消せる');
	unlike(body($app->get('guest', '/01')), qr{seedのコメント}, 'ログインしていない人には出ない');
	like(body($app->get('editor', '/01')), qr{seedのコメント}, '編集者には出る');

	$r = $app->post('editor', '', { action => 'comments_edit', enable => 1, pkey_ary => 1 });
	ok(AppTest::is_reload($r), '承認できる');
	like(body($app->get('guest', '/01')), qr{seedのコメント}, 'ログインしていない人にも出る');

	$r = $app->post('editor', '', { action => 'comments_edit', delete => 1, pkey_ary => 1 });
	ok(AppTest::is_reload($r), '削除できる');
	ok(!-e "$dir/data/db/com/00001.dat" || read_file("$dir/data/db/com/00001.dat") !~ /\S/, 'コメントが消える');
};

subtest 'コメントの承認待ちと記事の公開・非公開' => sub {
	# コメント一覧の、そのコメントの行の「状態」
	my $state = sub {
		my ($text, $q) = @_;
		my $b = body($app->get('editor', 'comlist' . ($q // '')));
		foreach ($b =~ m{<tr>\s*<td class="c"><input.*?</tr>}sg) {
			next if (index($_, $text) < 0);
			my @td = map { s/<[^>]*>//gr } /<td[^>]*>(.*?)<\/td>/sg;
			return $td[1];
		}
		return '';
	};
	my $recent = sub {
		my ($b) = body($app->get('guest', '')) =~ m{id="side-recent-comment"(.*?)</ul>}s;
		return $b // '';
	};
	my $coms = sub {
		# ブログのコメント数（v.blog.coms）。ダッシュボードには出さないので、全記事の削除の画面で見る
		my ($n) = body($app->get('owner', 'mainte/blog_clear')) =~ m{<th>コメント</th>\s*<td>(\d+)件}s;
		return $n;
	};

	# URLを書くと承認待ちになる（com_hold_url）
	my ($secure) = body($app->get('visitor', '/02')) =~ /data-secure="([^"]+)"/;
	my @ary = split(/,/, $secure);
	pop(@ary);
	my $sid = join('', map { chr($_ ^ (2 & 255)) } @ary);
	sleep(4);
	my $r = $app->post('visitor', '/02', { action => 'comment_post', a_pkey => 2, secure_id => $sid, name => '保留の人', comment_txt => '保留のコメント', url => 'http://example.com/', website => '' });
	like($r->{title}, qr/^処理結果/, '投稿できる');
	unlike(body($app->get('guest', '/02')), qr{保留のコメント}, '承認待ちは記事のページに出ない');
	is($state->('保留のコメント'), '承認待ち', 'コメント一覧で承認待ちと出る');
	is($state->('ゲストのコメント'), '承認済み', 'ほかのコメントは承認済み');
	is($state->('保留のコメント', '&hold=1'), '承認待ち', '承認待ちで絞り込むと出る');
	is($state->('ゲストのコメント', '&hold=1'), '', '承認待ちで絞り込むと、承認済みは出ない');
	is($state->('保留のコメント', '&hold=0'), '', '承認済みで絞り込むと、承認待ちは出ない');
	is($coms->(), 1, 'ブログのコメント数に入らない');

	my ($pkey) = body($app->get('editor', 'comlist')) =~ m{value="(\d+)" class="pkey-ary" id="com-\d+">.*?保留の人}s;
	$r = $app->post('editor', 'comlist', { action => 'comments_edit', enable => 1, pkey_ary => $pkey, from_comlist => 1 });
	ok(AppTest::is_reload($r), '承認できる');
	like(body($app->get('guest', '/02')), qr{保留のコメント}, '承認すると記事のページに出る');
	is($state->('保留のコメント'), '承認済み', '承認済みになる');
	like($recent->(), qr{保留の人}, '最近のコメントに出る');
	is($coms->(), 2, 'ブログのコメント数に入る');

	# 記事を非公開にしても、承認したことは残る。公開に戻すと、承認済みのコメントだけまた出る
	$r = $app->post('editor', '', { action => 'comments_edit', disable => 1, pkey_ary => $pkey });
	ok(AppTest::is_reload($r), '承認を取り消せる');
	is($state->('保留のコメント'), '承認待ち', '承認待ちに戻る');
	$r = $app->post('editor', 'artlist', [ action => 'articles_edit', mode => 'disable', pkey_ary => 2 ]);
	ok(AppTest::is_reload($r), '記事を非公開にできる');
	is($state->('ゲストのコメント'), '承認済み', '記事を非公開にしても承認済みのまま');
	unlike($recent->(), qr{通りすがり}, '非公開の記事のコメントは最近のコメントに出ない');
	is($coms->(), 0, '非公開の記事のコメントはブログのコメント数に入らない');

	$r = $app->post('editor', 'artlist', [ action => 'articles_edit', mode => 'enable', pkey_ary => 2 ]);
	ok(AppTest::is_reload($r), '記事を公開に戻せる');
	like(body($app->get('guest', '/02')), qr{ゲストのコメント}, '承認済みのコメントがまた出る');
	unlike(body($app->get('guest', '/02')), qr{保留のコメント}, '承認待ちのコメントは出ない');
	like($recent->(), qr{通りすがり}, '最近のコメントに戻る');
	is($coms->(), 1, 'ブログのコメント数に戻る');

	# 非公開の記事のコメントも承認できる。記事を公開したときに出る
	$r = $app->post('owner', '', { %ART, edit_pkey_int => 2, title => 'ownerの記事', body_txt => "本文2\n", tag_ary => 'タグ2', enable => 0 });
	ok(AppTest::is_reload($r), '編集画面で記事を非公開にできる');
	$r = $app->post('editor', '', { action => 'comments_edit', enable => 1, pkey_ary => $pkey });
	ok(AppTest::is_reload($r), '非公開の記事のコメントを承認できる');
	is($state->('保留のコメント'), '承認済み', '承認済みになる');
	is($coms->(), 0, '記事が非公開なので、ブログのコメント数には入らない');
	$r = $app->post('owner', '', { %ART, edit_pkey_int => 2, title => 'ownerの記事', body_txt => "本文2\n", tag_ary => 'タグ2', enable => 1 });
	ok(AppTest::is_reload($r), '編集画面で記事を公開にできる');
	like(body($app->get('guest', '/02')), qr{保留のコメント}, '承認したコメントが出る');
	is($coms->(), 2, 'ブログのコメント数に戻る');
};

#-------------------------------------------------------------------------------
# NSFW
#-------------------------------------------------------------------------------
subtest 'NSFWの記事' => sub {
	my $r = $app->post('owner', '', { %ART, title => '成人向けの記事', body_txt => "成人向けの本文\n", nsfw => 1 });
	ok(AppTest::is_reload($r), '保存できる');
	$r = $app->get('guest', '/06');
	like(body($r), qr{<meta name="rating" content="adult">}, 'ratingのmetaが出る');
	like(body($r), qr{nsfw}i, '年齢確認が出る');
	my $rss = read_file("$dir/pub/rss.xml");
	like($rss, qr{成人向けの記事}, 'RSSに題名は出る');
	unlike($rss, qr{成人向けの本文}, 'RSSに本文は出ない');
};

#-------------------------------------------------------------------------------
# ブログの設定
#-------------------------------------------------------------------------------
subtest 'ブログの基本設定' => sub {
	my $r = $app->post('owner', 'set/', { action => 'set/index', blog_name => 'テストのブログ', description_txt => 'ブログの説明' });
	ok(AppTest::is_reload($r), '保存できる');
	$r = $app->get('guest', '');
	is($r->{title}, 'テストのブログ', 'トップの題名が変わる');
	like(body($r), qr{ブログの説明}, '説明が出る');
	like(read_file("$dir/pub/rss.xml"), qr{テストのブログ}, 'RSSの題名も変わる');
};

subtest 'ブログの権限' => sub {
	is($app->get('user', 'edit')->{status}, 403, 'userは記事を書けない');
	my $r = $app->post('owner', 'set/role', { action => 'set/role', admin_users => 'owner', editors => 'editor, user', viewers => '', view_pass => '' });
	ok(AppTest::is_reload($r), 'userを編集者にする');
	is($app->get('user', 'edit')->{status}, 200, 'userが記事を書ける');

	$r = $app->post('owner', 'set/role', { action => 'set/role', admin_users => 'owner', editors => 'editor', viewers => '', view_pass => '' });
	ok(AppTest::is_reload($r), '元に戻す');
	is($app->get('user', 'edit')->{status}, 403, 'userはまた記事を書けない');
};

subtest 'プライベートモードと表示パスワード' => sub {
	# 表示パスワードは、プライベートモードのときだけ効く
	my $r = $app->post('owner', 'set/', { action => 'set/index', blog_name => 'テストのブログ', description_txt => 'ブログの説明', private => 1 });
	ok(AppTest::is_reload($r), 'プライベートモードにする');
	foreach my $q ('', '/02', '&t=' . AppTest::_uri_escape('タグ2'), '&q=owner') {
		$r = $app->get('guest', $q);
		my $b = body($r);
		ok($r->{status} == 403 && $b !~ /ownerの記事|本文2|タグ2/, "ログインしていない人には ?$q で記事が出ない（403）");
	}
	like(body($app->get('guest', '')), qr{ブログを見る権限がありません}, 'ログインしていない人には、権限が無いことを出す');
	is($app->get('guest', '/99999')->{status}, 403, '無い記事でも同じ403（記事があるかは分からない）');
	is($app->get('guest', 'login')->{status}, 200, 'ログインの画面は開ける');
	like(body($app->get('editor', '/02')), qr{本文2}, '編集者には記事が出る');

	# 公開フォルダのファイルは、推測できない名前のフォルダへ移る
	my ($private) = map { m{/(private\.[^/]+)$} } glob("$dir/pub/private.*");
	ok($private, '公開フォルダのファイルを、推測できない名前のフォルダへ移す');
	ok(!-e "$dir/pub/rss.xml" && -f "$dir/pub/$private/rss.xml", 'RSSが移る');
	ok(!-e "$dir/pub/attachments" && -f "$dir/pub/$private/attachments/test/a.png", '画像が移る');
	ok(-d "$dir/pub/assets", '配布物（pub/assets/）は移さない');
	like(body($app->get('editor', '')), qr{/pub/$private/rss\.xml}, '編集者の画面のRSSのURLも変わる');

	$r = $app->post('owner', 'set/role', { action => 'set/role', admin_users => 'owner', editors => 'editor', viewers => '', view_pass => 'secret' });
	ok(AppTest::is_reload($r), '表示パスワードを設定する');

	$r = $app->get('guest', '/02');
	is($r->{status}, 403, 'パスワードが無いと記事を見られない');
	unlike(body($r), qr{本文2}, '記事の中身は出ない');

	$app->set_cookie('reader', 'view-pass', 'wrong');
	is($app->get('reader', '/02')->{status}, 403, 'パスワードが違うと見られない');
	$app->set_cookie('reader', 'view-pass', 'secret');
	is($app->get('reader', '/02')->{status}, 200, 'パスワードが合うと見られる');

	$r = $app->post('owner', 'set/role', { action => 'set/role', admin_users => 'owner', editors => 'editor', viewers => '', view_pass => '' });
	ok(AppTest::is_reload($r), '表示パスワードを消す');
	$r = $app->post('owner', 'set/', { action => 'set/index', blog_name => 'テストのブログ', description_txt => 'ブログの説明', private => 0 });
	ok(AppTest::is_reload($r), 'プライベートモードを外す');
	is($app->get('guest', '/02')->{status}, 200, 'ログインしていない人も見られる');
	ok(!glob("$dir/pub/private.*") && -f "$dir/pub/rss.xml" && -f "$dir/pub/attachments/test/a.png", '公開フォルダのファイルが pub/ に戻る');
};

subtest 'タグの削除' => sub {
	# seed() のタグ1（pkey=1）は記事1に付いている
	my $r = $app->post('editor', 'set2/tag_edit', { action => 'set2/tag_edit', del_ary => 1 });
	ok(AppTest::is_reload($r), '削除できる');
	is($app->get('guest', '&t=' . AppTest::_uri_escape('タグ1'))->{status}, 404, 'タグの一覧に記事が出ない');
	like(body($app->get('guest', '&t=' . AppTest::_uri_escape('タグ2'))), qr{ownerの記事}, 'ほかのタグはそのまま');
};

#-------------------------------------------------------------------------------
# 画像アルバム
#-------------------------------------------------------------------------------
subtest '画像アルバム' => sub {
	my $png = do {
		open(my $fh, '<:raw', "$FindBin::Bin/../pub/assets/dist/default-icon.png") || die $!;
		local $/; <$fh>;
	};
	my $img = "$dir/pub/attachments/test";
	require Satsuki::ImageFormat;
	my $ext = Satsuki::ImageFormat::can_write_avif() ? 'avif' : 'jpg';	# 画像のサムネイルの形式

	my $r = $app->post('editor', '', [ action => 'media/upload_form', folder => 'test/', size => 120,
		file_ary => { filename => 'up.png', content => $png, type => 'image/png' } ]);
	like($r->{body}, qr/^ret=0$/m, 'アップロードできる');
	ok(-f "$img/up.png", 'ファイルが置かれる');
	ok(-f "$img/.thumbnail/up.png.$ext", "サムネイルが作られる（$ext）");
	ok($ext eq 'jpg' || !-e "$img/.thumbnail/up.png.jpg", 'JPEGのサムネイルは作らない');

	$r = $app->post('editor', '', { action => 'media/load_image_files', folder => 'test/' });
	my ($up) = grep { $_->{name} eq 'up.png' } @{ ref($r->{json}) eq 'ARRAY' ? $r->{json} : [] };
	is($up && $up->{thumb}, "up.png.$ext", 'ファイルの一覧にサムネイルの名前が入る');

	# 記事のサムネイルは、あるほうの形式を指す
	$r = $app->post('editor', '', { %ART, title => 'サムネイルの記事', body_txt => "[image:S:test/:up.png]\n" });
	ok(AppTest::is_reload($r), 'サムネイルを貼った記事を保存できる');
	like(body($app->get('guest', '')), qr{src="[^"]*/test/\.thumbnail/up\.png\.$ext"}, "記事のサムネイルが .$ext を指す");

	$r = $app->post('editor', '', { action => 'media/rename_file', folder => 'test/', old => 'up.png', name => 'renamed.png' });
	ok(json_ok($r), '名前を変えられる');
	ok(!-e "$img/up.png" && -f "$img/renamed.png", 'ファイルの名前が変わる');
	ok(!-e "$img/.thumbnail/up.png.$ext" && -f "$img/.thumbnail/renamed.png.$ext", 'サムネイルの名前も変わる');

	$r = $app->post('editor', '', { action => 'media/create_folder', folder => '/', name => 'other' });
	ok(json_ok($r), 'フォルダを作れる');
	$r = $app->post('editor', '', { action => 'media/move_files', from => 'test/', to => 'other/', file_ary => 'renamed.png' });
	ok(json_ok($r), '移せる');
	ok(!-e "$img/renamed.png" && -f "$dir/pub/attachments/other/renamed.png", 'ファイルが移る');
	ok(-f "$dir/pub/attachments/other/.thumbnail/renamed.png.$ext", 'サムネイルも移る');

	$r = $app->post('editor', '', { action => 'media/delete_files', folder => 'other/', file_ary => 'renamed.png' });
	ok(json_ok($r), '削除できる');
	ok(!-e "$dir/pub/attachments/other/renamed.png", 'フォルダから消える');
	ok(!-e "$dir/pub/attachments/other/.thumbnail/renamed.png.$ext", 'サムネイルも消える');
};

subtest 'アップロードした画像のメタ情報' => sub {
	require Image::Magick;
	my $im = Image::Magick->new(size => '40x30');
	$im->Read('xc:green');
	my ($jpeg) = $im->ImageToBlob(magick => 'JPEG');
	# Exif（中身が空のIFD）とXMPを足す
	my $exif = "Exif\0\0II*\0" . pack('V', 8) . pack('v', 0) . pack('V', 0);
	my $xmp  = "http://ns.adobe.com/xap/1.0/\0<x:xmpmeta xmlns:x='adobe:ns:meta/'/>";
	my $seg  = sub { "\xFF" . chr($_[0]) . pack('n', length($_[1]) + 2) . $_[1] };
	$jpeg = "\xFF\xD8" . $seg->(0xE1, $exif) . $seg->(0xE1, $xmp) . $seg->(0xE5, 'x' x 100) . substr($jpeg, 2);
	my $img = "$dir/pub/attachments/test";
	my $read = sub { open(my $fh, '<:raw', shift) || return ''; local $/; <$fh> };

	my $r = $app->post('editor', '', [ action => 'media/upload_form', folder => 'test/',
		file_ary => { filename => 'meta.jpg', content => $jpeg, type => 'image/jpeg' } ]);
	like($r->{body}, qr/^ret=0$/m, 'アップロードできる');
	my $saved = $read->("$img/meta.jpg");
	ok(index($saved, 'ns.adobe.com/xap') < 0, 'XMPは消える');
	ok(index($saved, "\xFF\xE5") < 0, 'APP5（機種独自の情報）は消える');
	ok(index($saved, "Exif\0\0") >= 0, 'Exifは残る');

	$r = $app->post('editor', '', [ action => 'media/upload_form', folder => 'test/',
		file_ary => { filename => 'meta.jpg', content => $jpeg, type => 'image/jpeg' } ]);
	like($r->{body}, qr/^ret=0$/m, '同じ画像をもう一度アップロードできる');
	ok(!grep({ /meta_\d/ } map { s|.*/||r } glob("$img/meta*")), 'メタ情報を消した後の中身で比べるので、別名で保存しない');

	$r = $app->post('editor', '', [ action => 'media/upload_form', folder => 'test/', del_exif => 1,
		file_ary => { filename => 'noexif.jpg', content => $jpeg, type => 'image/jpeg' } ]);
	like($r->{body}, qr/^ret=0$/m, 'Exifの削除を選んでアップロードできる');
	ok(index($read->("$img/noexif.jpg"), "Exif\0\0") < 0, 'Exifも消える');
};

subtest '動画のサムネイルの大きさの上限' => sub {
	require Image::Magick;
	require Satsuki::ImageFormat;
	# ブラウザーは動画の1コマをPNGで送る
	my $image = sub {
		my ($w, $h, $format) = @_;
		my $img = Image::Magick->new(size => "${w}x$h");
		$img->Read('xc:gray');
		return $img->ImageToBlob(magick => $format || 'png');
	};
	my $post_data = sub {
		return $app->post('editor', '', [ action => 'media/upload_video_thumbnail', folder => $AppTest::IMAGE_FOLDER, file => $AppTest::VIDEO_FILE,
			poster => { filename => 'poster.png', content => shift, type => 'image/png' } ]);
	};
	my $post = sub { return $post_data->( $image->(@_) ) };
	# 画像のサムネイルと同じく、AVIFを書けるならAVIF、書けなければJPEG
	my ($ext, $format) = Satsuki::ImageFormat::can_write_avif() ? ('avif', 'avif') : ('jpg', 'jpeg');
	my $th     = "$dir/pub/attachments/$AppTest::IMAGE_FOLDER.thumbnail/$AppTest::VIDEO_FILE";
	my $poster = "$th.poster.$ext";
	my $thumb  = "$th.$ext";

	ok(!json_ok($post->(961, 540)), '961pxなら受け付けない');
	ok(!-e $poster, '受け付けなければ、記事用のサムネイルは置かれない');
	ok(json_ok($post->(960, 540)), '960pxなら受け付ける');
	is(Satsuki::ImageFormat::detect($poster), $format, "記事用のサムネイルは、サーバーで画像のサムネイルと同じ形式（$format）にする");
	is(join('x', Satsuki::ImageFormat::get_size($poster)), '960x540', '記事用のサムネイルの大きさ');
	is(Satsuki::ImageFormat::detect($thumb), $format, '一覧用のサムネイルも同じ形式');
	is(join('x', Satsuki::ImageFormat::get_size($thumb)), '320x180', '一覧用のサムネイルは、設定の大きさに縮めて作る');
	ok(!glob("$th.*tmp") && !glob("$th.*new*"), '作業用のファイルが残らない');
	ok($ext eq 'jpg' || (!-e "$th.poster.jpg" && !-e "$th.jpg"), 'JPEGのサムネイルは残らない');

	# 記事には、記事用のサムネイルを出す
	my $r = $app->post('editor', '', { %ART, title => '動画の記事', body_txt => "[file:mp4:$AppTest::IMAGE_FOLDER:$AppTest::VIDEO_FILE]\n" });
	ok(AppTest::is_reload($r), '動画を貼った記事を保存できる');
	like(body($app->get('guest', '')), qr{class="video-thumb"[^>]*><img [^>]*src="[^"]*\.thumbnail/\Q$AppTest::VIDEO_FILE\E\.poster\.$ext"}, "記事のサムネイルが .poster.$ext を指す");
	ok(!json_ok($post->(540, 961)), '縦長でも、長い辺が961pxなら受け付けない');
	ok(!json_ok($post->(960, 540, 'jpeg')), 'JPEGは受け付けない（PNGだけ）');
	ok(!json_ok($post_data->('not an image')), '画像でなければ受け付けない');
	is(join('x', Satsuki::ImageFormat::get_size($poster)), '960x540', '受け付けなければ、前の記事用のサムネイルが残る');

	# アップデートの画面で作る動画の一覧
	my $listed = sub { return index(body($app->get('admin', 'system/update')), "data-name=\"$AppTest::VIDEO_FILE\"") >= 0; };
	ok(!$listed->(), '今の大きさのサムネイルがあれば、アップデートの画面の一覧に出ない');
	open(my $fh, '>:raw', $poster) || die "$poster: $!";
	print $fh $image->(1280, 720, 'jpeg');
	close($fh);
	ok($listed->(), '4.18より前の大きさ（1280px）のサムネイルなら、一覧に出る');
	unlink($poster);
	ok($listed->(), 'サムネイルが無ければ、一覧に出る');
	ok(json_ok($post->(960, 540)), '作り直せる');
	ok(!$listed->(), '作り直すと、一覧から消える');

	# v4.19のアップデート処理より前に作った記事用のサムネイル（ブラウザーが作ったJPEG）
	my $sys = "$dir/data/system_config.dat";
	my $time = time();
	open($fh, '>>', $sys) || die "$sys: $!";
	print $fh "video_poster_time=$time\n";
	close($fh);
	utime($time - 60, $time - 60, $poster);
	ok($listed->(), 'アップデート処理より前に作ったサムネイルなら、一覧に出る');
	ok(json_ok($post->(960, 540)), '作り直せる');
	ok(!$listed->(), '作り直すと、一覧から消える');

	# AVIFを書けるサーバーで、記事用のサムネイルがJPEG（4.25より前に作ったもの）
	SKIP: {
		skip('ImageMagickでAVIFを書けない', 4) if $ext ne 'avif';
		unlink($poster, $thumb);
		open($fh, '>:raw', "$th.poster.jpg") || die "$th.poster.jpg: $!";
		print $fh $image->(960, 540, 'jpeg');
		close($fh);
		ok($listed->(), '記事用のサムネイルがJPEGなら、一覧に出る');
		ok(json_ok($post->(960, 540)), '作り直せる');
		ok(-e $poster && !-e "$th.poster.jpg", '作り直すと、AVIFになり、JPEGは消える');
		ok(!$listed->(), '作り直すと、一覧から消える');
	}

	# 名前の変更、移動、削除で、記事用のサムネイルもついて行く
	my $tdir = "$dir/pub/attachments/$AppTest::IMAGE_FOLDER.thumbnail";
	$r = $app->post('editor', '', { action => 'media/rename_file', folder => $AppTest::IMAGE_FOLDER, old => $AppTest::VIDEO_FILE, name => 'v2.mp4' });
	ok(json_ok($r), '動画の名前を変えられる');
	ok(-e "$tdir/v2.mp4.poster.$ext" && -e "$tdir/v2.mp4.$ext" && !-e $poster, 'サムネイルの名前も変わる');
	$r = $app->post('editor', '', { action => 'media/move_files', from => $AppTest::IMAGE_FOLDER, to => 'other/', file_ary => 'v2.mp4' });
	ok(json_ok($r), '動画を移せる');
	ok(-e "$dir/pub/attachments/other/.thumbnail/v2.mp4.poster.$ext" && !-e "$tdir/v2.mp4.poster.$ext", '記事用のサムネイルも移る');
	$r = $app->post('editor', '', { action => 'media/delete_files', folder => 'other/', file_ary => 'v2.mp4' });
	ok(json_ok($r), '動画を削除できる');
	ok(!glob("$dir/pub/attachments/other/.thumbnail/v2.mp4.*"), 'サムネイルも消える');
};

#-------------------------------------------------------------------------------
# エクスポートとインポート
#-------------------------------------------------------------------------------
subtest 'エクスポートとインポート' => sub {
	my $r = $app->post('owner', '', { action => 'mainte/export', file => '10_movable_type' });
	is($r->{status}, 200, 'エクスポートできる');
	my $data = $r->{body};
	like($data, qr/TITLE: /, 'Movable Typeの形式で出る');
	my @titles = $data =~ /^TITLE: (.*)$/mg;
	utf8::decode($_) foreach (@titles);

	$r = $app->post('owner', '', { action => 'mainte/blog_clear', yes => 'yes' });
	ok(AppTest::is_reload($r), '全記事を消せる');
	is($app->get('guest', '/02')->{status}, 404, '記事が無くなる');

	$r = $app->post('owner', '', [ action => 'mainte/import', type => 'MT',
		file => { filename => 'export.txt', content => $data, type => 'text/plain' } ]);
	like($r->{body}, qr/^ret=0$/m, 'インポートできる');
	like($r->{body}, qr/^articles=${\ scalar(@titles)}$/m, '応答の articles= はインポートできた記事の数');
	my $list = body($app->get('editor', 'artlist'));	# 下書きも出る
	is(scalar(grep { index($list, $_) >= 0 } @titles), scalar(@titles), '出した記事（' . scalar(@titles) . '件）がすべて記事一覧に出る');
};

#-------------------------------------------------------------------------------
# 再構築
#-------------------------------------------------------------------------------
subtest '再構築' => sub {
	unlink("$dir/pub/rss.xml");
	my $r = $app->post('owner', '', { action => 'mainte/blog_rebuild' });
	ok(AppTest::is_reload($r), 'ブログを再構築できる');
	ok(-s "$dir/pub/rss.xml", 'RSSが書き出し直される');
};

subtest 'ダッシュボード' => sub {
	my $r = $app->post('editor', '', { %ART, title => '記事の下書き', body_txt => "下書き\n", draft => 1 });
	ok(AppTest::is_reload($r), '記事の下書きを保存できる');
	$r = $app->post('editor', '', { %ART, title => 'ページの下書き', body_txt => "下書き\n", draft => 1, wiki => 1, link_key_txt => 'draft-page' });
	ok(AppTest::is_reload($r), 'ページの下書きを保存できる');

	my $b = body($app->get('editor', 'menu'));
	my ($glance) = $b =~ m{<ul class="dashboard-glance">(.*?)</ul>}s;
	my @rows;
	while (($glance // '') =~ m{<li><a href="[^"]*\?([^"]*)">([^<]+)</a><span class="dashboard-count">(\d+)件</span></li>}g) {
		my ($query, $label, $count) = ($1, $2, $3);
		push(@rows, { query => $query =~ s/&amp;/&/gr, label => $label, count => $count });
	}
	is_deeply([ map { $_->{label} } @rows ], [qw(
		記事の下書き 公開中の記事 非公開の記事 ページの下書き 公開中のページ 非公開のページ
		ゴミ箱 承認待ちのコメント 承認済みのコメント
	)], '概要の項目と順番');

	# 件数は、行き先の一覧の件数と同じ
	my %count = map { $_->{label} => $_->{count} } @rows;
	foreach (@rows) {
		my $list = body($app->get('editor', $_->{query}));
		my ($n) = $list =~ m{<p>Total (\d+) (?:articles|comments)\.</p>};
		is($_->{count}, $n, "$_->{label}の件数は、一覧（?$_->{query}）と同じ");
	}
	is($count{'記事の下書き'},   1, '記事の下書きを数える');
	is($count{'ページの下書き'}, 1, 'ページの下書きを数える');

	# 記事一覧の「下書き」には、下書きだけが出る
	my $drafts = body($app->get('editor', 'artlist&enable=draft'));
	like($drafts, qr{記事の下書き}, '記事一覧の下書きに、記事の下書きが出る');
	like($drafts, qr{ページの下書き}, '記事一覧の下書きに、ページの下書きが出る');
	unlike($drafts, qr{editorの記事}, '記事一覧の下書きに、公開の記事は出ない');
	my $all = body($app->get('editor', 'artlist'));
	like($all, qr{記事の下書き}, '記事一覧の「すべて」には、下書きも出る');
	like($all, qr{ページの下書き}, '記事一覧の「すべて」には、ページの下書きも出る');
	like($all, qr{ownerの記事}, '記事一覧の「すべて」には、公開の記事も出る');

	# 公開列は、下書き・公開・非公開を文字で出す
	my %state = $all =~ m{>([^<]+)</a></td>\s*<td class="c"><label[^>]*>[^<]*</label></td>\s*<td class="c"><label[^>]*>([^<]*)</label></td>}g;
	is($state{'記事の下書き'}, '下書き', '下書きの公開状態は「下書き」');
	is($state{'ページの下書き'}, '下書き', 'ページの下書きの公開状態も「下書き」');
	is($state{'ownerの記事'}, '公開', '公開の記事の公開状態は「公開」');
	is($state{'下書きの記事'}, '非公開', '非公開の記事の公開状態は「非公開」');	# インポートした下書きは非公開になる
	unlike(body($app->get('editor', 'artlist&enable=0')), qr{記事の下書き}, '記事一覧の「非公開」には、下書きは出ない');

	# 書くは1つ
	my @write = $b =~ m{<a class="button-primary" href="([^"]*)">}g;
	is(scalar(@write), 1, '書くのボタンは1つ');
	like($write[0] // '', qr{\?edit$}, '書くの行き先は編集画面');
	unlike(body($app->get('user', 'menu')), qr{dashboard-glance}, '編集者でなければ概要は出ない');
};

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
# 公開画面のメタ情報とページ送り（PageSpeed Insights の指摘）
#-------------------------------------------------------------------------------
subtest 'メタディスクリプション' => sub {
	# 記事は、トップに出ている最初の記事（ほかのテストで公開の状態が変わるため）
	my ($art) = body($app->get('guest', '')) =~ m{<a href="[^"]*?(/\d+)" class="title">};
	ok($art, "記事のURLが取れる（$art）");
	foreach my $q ('', $art) {
		my $b = body($app->get('guest', $q));
		my @desc = $b =~ m{<meta name="description" content="([^"]*)">}g;
		my ($og) = $b =~ m{<meta property="og:description" content="([^"]*)">};
		is(scalar(@desc), 1, "?$q に1つだけ出る");
		ok($desc[0] ne '' && $desc[0] eq $og, "?$q の中身はog:descriptionと同じ（$og）");
	}
};

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
