use strict;
use utf8;
#-------------------------------------------------------------------------------
# 主な操作の中身のテスト（記事、コメント、NSFW、アイキャッチ画像、エクスポートとインポート、再構築、ダッシュボード）
#-------------------------------------------------------------------------------
# 実行: prove t/operations_article.t
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
# 記事
#-------------------------------------------------------------------------------
subtest '記事を書く' => sub {
	my $r = $app->post('admin', '', { %ART, title => '新しい記事', body_txt => "新しい**本文**\n", tag_ary => '新しいタグ' });
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
	my $r = $app->post('admin', '', { %ART, title => '下書きの記事', body_txt => "下書き\n", enable => 0 });
	ok(AppTest::is_reload($r), '保存できる');
	is($app->get('guest', '/05')->{status}, 404, 'ログインしていない人には出ない');
	like($app->get('admin', '/05')->{title}, qr/^下書きの記事 - /, '管理者には出る');
	unlike(body($app->get('guest', '')), qr{下書きの記事}, 'トップに出ない');
	unlike(read_file("$dir/pub/rss.xml"), qr{下書きの記事}, 'RSSに出ない');
};

subtest '記事を直す' => sub {
	my $r = $app->post('admin', '', { %ART, edit_pkey_int => 1, title => '直した題名', body_txt => "直した本文\n", ymd => '2026-10-01' });
	ok(AppTest::is_reload($r), '保存できる');

	$r = $app->get('guest', '/01');
	like($r->{title}, qr/^直した題名 - /, '題名が変わる');
	like(body($r), qr{直した本文}, '本文が変わる');
	like(read_file("$dir/pub/rss.xml"), qr{直した題名}, 'RSSも変わる');

	$r = $app->post('admin', '', { action => 'ajax_revision', pkey => 1 });
	my $revs = $r->{json};
	my @revs = grep { !$_->{last} } @{ ref($revs) eq 'ARRAY' ? $revs : [] };
	is(scalar(@revs), 1, '更新履歴に、直す前の版が1つ残る');
	ok(ref($revs) eq 'ARRAY' && $revs->[0]->{last}, '一覧の先頭は直前の保存');
};

subtest '直前の保存' => sub {
	my $r = $app->post('admin', '', { %ART, edit_pkey_int => 1, title => 'もう一度直した題名', body_txt => "もう一度直した本文\n", ymd => '2026-10-01' });
	ok(AppTest::is_reload($r), '続けて保存できる');

	my $revs = $app->post('admin', '', { action => 'ajax_revision', pkey => 1 })->{json};
	is(scalar(grep { !$_->{last} } @$revs), 1, '続けて保存しても、更新履歴は増えない（rev_cycleでまとめる）');
	is(scalar(grep { $_->{last} } @$revs), 1, '直前の保存は1つだけ');

	my $last = $app->post('admin', '', { action => 'ajax_revision', last => 1 })->{json};
	is($last->{title}, '直した題名', '直前の保存は、1つ前に保存した題名');
	like($last->{text}, qr/^直した本文/, '直前の保存は、1つ前に保存した本文');

	my $g = $app->post('guest', '', { action => 'ajax_revision', last => 1 });
	ok(($g->{headers}->{'content-type'} // '') !~ m{json}, 'ログインしていない人は読めない');
	is($app->post('admin', '', { action => 'ajax_revision', last => 99999 })->{status}, 404, '無い記事は404');
};

subtest 'ゴミ箱' => sub {
	my $r = $app->post('admin', '', { action => 'delete', delete_pkey_ary => 1, title => '' });
	ok(AppTest::is_reload($r), 'ゴミ箱へ移せる');
	is($app->get('guest', '/01')->{status}, 404, '記事のページは出ない');
	like(body($app->get('admin', 'trash')), qr{直した題名}, 'ゴミ箱に出る');

	$r = $app->post('admin', '', { action => 'trash', mode => 'restore', pkey_ary => 1 });
	ok(AppTest::is_reload($r), '戻せる');
	is($app->get('guest', '/01')->{status}, 200, '記事のページがまた出る');

	$r = $app->post('admin', '', { action => 'trash', mode => 'purge_all' });
	ok(AppTest::is_reload($r), 'ゴミ箱を空にできる');
	unlike(body($app->get('admin', 'trash')), qr{消す記事}, 'ゴミ箱から消える');
	like(read_file("$dir/data/db/lastrev/#index.dat"), qr/^\d+\t1$/m, '戻した記事の直前の保存は残る');
};

subtest 'ゴミ箱を空にすると直前の保存も消える' => sub {
	# 記事の番号を後のテストとずらさないよう、別のブログで行う
	my $app  = AppTest->new()->setup()->seed();
	my $file = $app->dir . '/data/db/lastrev/#index.dat';
	$app->post('admin', '', { %ART, edit_pkey_int => 1, title => '直した題名', body_txt => "直した本文\n" });
	like(read_file($file), qr/^\d+\t1$/m, '直すと直前の保存ができる');
	$app->post('admin', '', { action => 'delete', delete_pkey_ary => 1, title => '' });
	like(read_file($file), qr/^\d+\t1$/m, 'ゴミ箱に入れても直前の保存は残る');
	my $r = $app->post('admin', '', { action => 'trash', mode => 'purge_all' });
	ok(AppTest::is_reload($r), 'ゴミ箱を空にできる');
	unlike(read_file($file), qr/^\d+\t1$/m, '直前の保存も消える');
};

subtest '記事一覧からのまとめての操作' => sub {
	my $r = $app->post('admin', 'artlist', [ action => 'articles_edit', mode => 'disable', pkey_ary => 1, pkey_ary => 2 ]);
	ok(AppTest::is_reload($r), '非公開にできる');
	is($app->get('guest', '/01')->{status}, 404, '記事1は出ない');
	is($app->get('guest', '/02')->{status}, 404, '記事2は出ない');

	$r = $app->post('admin', 'artlist', [ action => 'articles_edit', mode => 'enable', pkey_ary => 1, pkey_ary => 2 ]);
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
	like(body($app->get('admin', 'comlist')), qr{ゲストのコメント}, 'コメント一覧に出る');
};

subtest 'コメントの承認の取り消し・承認・削除' => sub {
	my $r = $app->post('admin', '', { action => 'comments_edit', disable => 1, pkey_ary => 1 });
	ok(AppTest::is_reload($r), '承認を取り消せる');
	unlike(body($app->get('guest', '/01')), qr{seedのコメント}, 'ログインしていない人には出ない');
	like(body($app->get('admin', '/01')), qr{seedのコメント}, '管理者には出る');

	$r = $app->post('admin', '', { action => 'comments_edit', enable => 1, pkey_ary => 1 });
	ok(AppTest::is_reload($r), '承認できる');
	like(body($app->get('guest', '/01')), qr{seedのコメント}, 'ログインしていない人にも出る');

	$r = $app->post('admin', '', { action => 'comments_edit', delete => 1, pkey_ary => 1 });
	ok(AppTest::is_reload($r), '削除できる');
	ok(!-e "$dir/data/db/com/00001.dat" || read_file("$dir/data/db/com/00001.dat") !~ /\S/, 'コメントが消える');
};

subtest 'コメントの承認待ちと記事の公開・非公開' => sub {
	# コメント一覧の、そのコメントの行の「状態」
	my $state = sub {
		my ($text, $q) = @_;
		my $b = body($app->get('admin', 'comlist' . ($q // '')));
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
		my ($n) = body($app->get('admin', 'mainte/blog_clear')) =~ m{<th>コメント</th>\s*<td>(\d+)件}s;
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

	my ($pkey) = body($app->get('admin', 'comlist')) =~ m{value="(\d+)" class="pkey-ary" id="com-\d+">.*?保留の人}s;
	$r = $app->post('admin', 'comlist', { action => 'comments_edit', enable => 1, pkey_ary => $pkey, from_comlist => 1 });
	ok(AppTest::is_reload($r), '承認できる');
	like(body($app->get('guest', '/02')), qr{保留のコメント}, '承認すると記事のページに出る');
	is($state->('保留のコメント'), '承認済み', '承認済みになる');
	like($recent->(), qr{保留の人}, '最近のコメントに出る');
	is($coms->(), 2, 'ブログのコメント数に入る');

	# 記事を非公開にしても、承認したことは残る。公開に戻すと、承認済みのコメントだけまた出る
	$r = $app->post('admin', '', { action => 'comments_edit', disable => 1, pkey_ary => $pkey });
	ok(AppTest::is_reload($r), '承認を取り消せる');
	is($state->('保留のコメント'), '承認待ち', '承認待ちに戻る');
	$r = $app->post('admin', 'artlist', [ action => 'articles_edit', mode => 'disable', pkey_ary => 2 ]);
	ok(AppTest::is_reload($r), '記事を非公開にできる');
	is($state->('ゲストのコメント'), '承認済み', '記事を非公開にしても承認済みのまま');
	unlike($recent->(), qr{通りすがり}, '非公開の記事のコメントは最近のコメントに出ない');
	is($coms->(), 0, '非公開の記事のコメントはブログのコメント数に入らない');

	$r = $app->post('admin', 'artlist', [ action => 'articles_edit', mode => 'enable', pkey_ary => 2 ]);
	ok(AppTest::is_reload($r), '記事を公開に戻せる');
	like(body($app->get('guest', '/02')), qr{ゲストのコメント}, '承認済みのコメントがまた出る');
	unlike(body($app->get('guest', '/02')), qr{保留のコメント}, '承認待ちのコメントは出ない');
	like($recent->(), qr{通りすがり}, '最近のコメントに戻る');
	is($coms->(), 1, 'ブログのコメント数に戻る');

	# 非公開の記事のコメントも承認できる。記事を公開したときに出る
	$r = $app->post('admin', '', { %ART, edit_pkey_int => 2, title => 'ownerの記事', body_txt => "本文2\n", tag_ary => 'タグ2', enable => 0 });
	ok(AppTest::is_reload($r), '編集画面で記事を非公開にできる');
	$r = $app->post('admin', '', { action => 'comments_edit', enable => 1, pkey_ary => $pkey });
	ok(AppTest::is_reload($r), '非公開の記事のコメントを承認できる');
	is($state->('保留のコメント'), '承認済み', '承認済みになる');
	is($coms->(), 0, '記事が非公開なので、ブログのコメント数には入らない');
	$r = $app->post('admin', '', { %ART, edit_pkey_int => 2, title => 'ownerの記事', body_txt => "本文2\n", tag_ary => 'タグ2', enable => 1 });
	ok(AppTest::is_reload($r), '編集画面で記事を公開にできる');
	like(body($app->get('guest', '/02')), qr{保留のコメント}, '承認したコメントが出る');
	is($coms->(), 2, 'ブログのコメント数に戻る');
};

#-------------------------------------------------------------------------------
# NSFW
#-------------------------------------------------------------------------------
subtest 'NSFWの記事' => sub {
	my $r = $app->post('admin', '', { %ART, title => '成人向けの記事', body_txt => "成人向けの本文\n", nsfw => 1 });
	ok(AppTest::is_reload($r), '保存できる');
	$r = $app->get('guest', '/06');
	like(body($r), qr{<meta name="rating" content="adult">}, 'ratingのmetaが出る');
	like(body($r), qr{nsfw}i, '年齢確認が出る');
	my $rss = read_file("$dir/pub/rss.xml");
	like($rss, qr{成人向けの記事}, 'RSSに題名は出る');
	unlike($rss, qr{成人向けの本文}, 'RSSに本文は出ない');
};

subtest 'アイキャッチ画像は選んだものだけを使う' => sub {
	my $img  = "$AppTest::IMAGE_FOLDER$AppTest::IMAGE_FILE";
	my $tag  = "[image:S:$AppTest::IMAGE_FOLDER:$AppTest::IMAGE_FILE]";
	my %EYE  = (%ART, title => 'アイキャッチの記事', body_txt => "$tag\n\n`$tag`\n\n```\n$tag\n```\n\n本文\n");
	my $og   = sub { (body($app->get('guest', '/07')) =~ m{<meta property="og:image" content="([^"]*)">})[0] // '' };
	my $rss  = sub { my ($item) = read_file("$dir/pub/rss.xml") =~ m{(<item>(?:(?!</item>).)*?アイキャッチの記事.*?</item>)}s; $item // '' };
	my $ogp  = sub { (body($app->get('admin', '/07?edit')) =~ m{<input type="hidden" name="ogp" id="ogp-input" value="([^"]*)">})[0] // '' };

	my $r = $app->post('admin', '', \%EYE);
	ok(AppTest::is_reload($r), '選ばずに保存できる');
	like($og->(), qr{/default-icon\.png$}, 'og:imageは本文の画像にならず、ブログの画像（設定していないので既定の画像）になる');
	like(body($app->get('guest', '/07')), qr{<meta name="twitter:card" content="summary">}, '記事の画像が無ければtwitter:cardはsummary');
	like(read_file("$dir/pub/rss.xml"), qr{<generator>[^<]*#\d+\.\d{2}</generator>}, 'RSSのgeneratorの版は小数2桁');
	unlike($rss->(), qr{<media:content}, 'RSSにアイキャッチを出さない');
	is($ogp->(), '', '編集画面の欄は空');

	$r = $app->post('admin', '', { action => 'mainte/blog_rebuild' });
	ok(AppTest::is_reload($r), 'ブログを再構築できる');
	is($ogp->(), '', '再構築しても本文の画像を拾わない');

	$r = $app->post('admin', '', { %EYE, edit_pkey_int => 7, ogp => $img });
	ok(AppTest::is_reload($r), '選んで保存できる');
	like($og->(), qr{/\Q$img\E$}, 'og:imageに選んだ画像を使う');
	like(body($app->get('guest', '/07')), qr{<meta name="twitter:card" content="summary_large_image">}, '記事の画像があればtwitter:cardはsummary_large_image');
	like($rss->(), qr{<media:content url="[^"]*/\Q$img\E"}, 'RSSにも出る');
	is($ogp->(), $img, '編集画面の欄に選んだ画像が入る');

	$r = $app->post('admin', '', { action => 'mainte/blog_rebuild' });
	ok(AppTest::is_reload($r), 'ブログを再構築できる');
	is($ogp->(), $img, '再構築しても選んだ画像が残る');

	$r = $app->post('admin', '', { %EYE, edit_pkey_int => 7, ogp => $img, body_txt => "[image:S:$AppTest::IMAGE_FOLDER:other.jpg]\n\n$EYE{body_txt}" });
	ok(AppTest::is_reload($r), '本文の先頭に別の画像を足して保存できる');
	is($ogp->(), $img, '選んだ画像は変わらない');

	$r = $app->post('admin', '', { %EYE, edit_pkey_int => 7, ogp => '' });
	ok(AppTest::is_reload($r), '選んだ画像を外して保存できる');
	like($og->(), qr{/default-icon\.png$}, 'ブログの画像に戻る');
	is($ogp->(), '', '編集画面の欄が空に戻る');
};

#-------------------------------------------------------------------------------
# エクスポートとインポート
#-------------------------------------------------------------------------------
subtest 'エクスポートとインポート' => sub {
	my $r = $app->post('admin', '', { action => 'mainte/export', file => '10_movable_type' });
	is($r->{status}, 200, 'エクスポートできる');
	my $data = $r->{body};
	like($data, qr/TITLE: /, 'Movable Typeの形式で出る');
	my @titles = $data =~ /^TITLE: (.*)$/mg;
	utf8::decode($_) foreach (@titles);

	$r = $app->post('admin', '', { action => 'mainte/blog_clear', yes => 'yes' });
	ok(AppTest::is_reload($r), '全記事を消せる');
	is($app->get('guest', '/02')->{status}, 404, '記事が無くなる');

	$r = $app->post('admin', '', [ action => 'mainte/import', type => 'MT',
		file => { filename => 'export.txt', content => $data, type => 'text/plain' } ]);
	like($r->{body}, qr/^ret=0$/m, 'インポートできる');
	like($r->{body}, qr/^articles=${\ scalar(@titles)}$/m, '応答の articles= はインポートできた記事の数');
	my $list = body($app->get('admin', 'artlist'));	# 下書きも出る
	is(scalar(grep { index($list, $_) >= 0 } @titles), scalar(@titles), '出した記事（' . scalar(@titles) . '件）がすべて記事一覧に出る');
};

#-------------------------------------------------------------------------------
# 再構築
#-------------------------------------------------------------------------------
subtest '再構築' => sub {
	unlink("$dir/pub/rss.xml");
	my $r = $app->post('admin', '', { action => 'mainte/blog_rebuild' });
	ok(AppTest::is_reload($r), 'ブログを再構築できる');
	ok(-s "$dir/pub/rss.xml", 'RSSが書き出し直される');
};

#-------------------------------------------------------------------------------
# ダッシュボード
#-------------------------------------------------------------------------------
subtest 'ダッシュボード' => sub {
	my $r = $app->post('admin', '', { %ART, title => '記事の下書き', body_txt => "下書き\n", draft => 1 });
	ok(AppTest::is_reload($r), '記事の下書きを保存できる');
	$r = $app->post('admin', '', { %ART, title => 'ページの下書き', body_txt => "下書き\n", draft => 1, wiki => 1, link_key_txt => 'draft-page' });
	ok(AppTest::is_reload($r), 'ページの下書きを保存できる');

	my $b = body($app->get('admin', 'menu'));
	unlike($b, qr{<p>ユーザー }, 'ユーザーのカードを出さない');
	unlike($b, qr{<h2>ダッシュボード</h2>}, 'ダッシュボードの見出しの箱を出さない');
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
		my $list = body($app->get('admin', $_->{query}));
		my ($n) = $list =~ m{<p>Total (\d+) (?:articles|comments)\.</p>};
		is($_->{count}, $n, "$_->{label}の件数は、一覧（?$_->{query}）と同じ");
	}
	is($count{'記事の下書き'},   1, '記事の下書きを数える');
	is($count{'ページの下書き'}, 1, 'ページの下書きを数える');

	# 記事一覧の「下書き」には、下書きだけが出る
	my $drafts = body($app->get('admin', 'artlist&enable=draft'));
	like($drafts, qr{記事の下書き}, '記事一覧の下書きに、記事の下書きが出る');
	like($drafts, qr{ページの下書き}, '記事一覧の下書きに、ページの下書きが出る');
	unlike($drafts, qr{editorの記事}, '記事一覧の下書きに、公開の記事は出ない');
	my $all = body($app->get('admin', 'artlist'));
	like($all, qr{記事の下書き}, '記事一覧の「すべて」には、下書きも出る');
	like($all, qr{ページの下書き}, '記事一覧の「すべて」には、ページの下書きも出る');
	like($all, qr{ownerの記事}, '記事一覧の「すべて」には、公開の記事も出る');

	# 公開列は、下書き・公開・非公開を文字で出す
	my %state = $all =~ m{>([^<]+)</a></td>\s*<td class="c"><label[^>]*>[^<]*</label></td>\s*<td class="c"><label[^>]*>([^<]*)</label></td>}g;
	is($state{'記事の下書き'}, '下書き', '下書きの公開状態は「下書き」');
	is($state{'ページの下書き'}, '下書き', 'ページの下書きの公開状態も「下書き」');
	is($state{'ownerの記事'}, '公開', '公開の記事の公開状態は「公開」');
	is($state{'下書きの記事'}, '非公開', '非公開の記事の公開状態は「非公開」');	# インポートした下書きは非公開になる
	unlike(body($app->get('admin', 'artlist&enable=0')), qr{記事の下書き}, '記事一覧の「非公開」には、下書きは出ない');

	# 書くは1つ
	my @write = $b =~ m{<a class="button-primary" href="([^"]*)">}g;
	is(scalar(@write), 1, '書くのボタンは1つ');
	like($write[0] // '', qr{\?edit$}, '書くの行き先は編集画面');
};

done_testing();
