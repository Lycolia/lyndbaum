use strict;
use utf8;
#-------------------------------------------------------------------------------
# 記事ヘッダ（dea_art-info、skel/_sub/art_info.html）の日付のテスト
#-------------------------------------------------------------------------------
# 実行: prove t/art_info.t
#
# 投稿日には、いつも記事の日付（yyyymmdd）を出す。
# 更新日は、通常記事はart_upd、固定ページはpage_upd を設定したときだけ出し、
# 出すときも、更新した日（update_tm、空ならtm）が記事の日付と違うときだけ出す。既定は出さない。
#
use FindBin;
BEGIN { push(@INC, "$FindBin::Bin/lib", "$FindBin::Bin/../lib"); }
use Test::More;
use POSIX ();
use AppTest;
use OpsTest;

binmode(Test::More->builder->$_, ':utf8') foreach (qw(output failure_output todo_output));

my $app = AppTest->new()->setup();
my $dir = $app->dir;

our $ROBJ;	# DB_textはROBJを弱い参照で持つので、使う間は持っておく
sub DB {
	require Satsuki::Base;
	$ROBJ = Satsuki::Base->new();
	return $ROBJ->loadpm('DB_text', "$dir/data/db/");
}
sub tm { my ($y, $m, $d) = @_; return POSIX::mktime(0, 0, 12, $d, $m - 1, $y - 1900); }	# その日の正午（サーバーの時刻）
sub set_art {
	my ($pkey, %h) = @_;
	my $db = DB();
	$db->update_match('art', \%h, 'pkey', $pkey);
}
# 記事のページの記事ヘッダの日付の部分
sub dates {
	my $path = shift;
	my $b = body($app->get('guest', $path));
	my ($info) = $b =~ m{<div class="art-info"[^>]*>(.*?)</div>\s*<div>}s;
	return $info // '';
}
sub setting {
	my %f = @_;
	my $r = $app->post('admin', '', { action => 'plugin/plugin_setting', module_name => 'dea_art-info', %f });
	like($r->{body}, qr/^ret=0$/m, '記事ヘッダの設定を保存できる');
}

# 記事（pkey=1）と固定ページ（pkey=2）。記事の日付は2026-10-10
ok(AppTest::is_reload($app->post('admin', '', { %ART, title => '通常記事', body_txt => "本文\n" })), '通常記事を書く');
ok(AppTest::is_reload($app->post('admin', '', { %ART, title => '固定ページ', body_txt => "本文\n", page => 1, link_key_txt => 'page1' })), '固定ページを書く');
set_art(1, update_tm => tm(2026, 11, 1));
set_art(2, update_tm => tm(2026, 11, 2));

my $posted = '<span>投稿：<time class="write-date" datetime="2026-10-10">2026/10/10</time></span>';
my $upd1   = '<span>更新：<time class="update-date" datetime="2026-11-01">2026/11/01</time></span><br>';
my $upd2   = '<span>更新：<time class="update-date" datetime="2026-11-02">2026/11/02</time></span><br>';

subtest '既定は更新日を出さない' => sub {
	my $d = dates('/01');
	like($d, qr/\Q$posted\E/, '投稿日に記事の日付を出す（今までと同じHTML）');
	unlike($d, qr/update-date/, '通常記事に更新日を出さない');
	unlike(dates('/page1'), qr/update-date/, '固定ページに更新日を出さない');
	like(dates('/page1'), qr/\Q$posted\E/, '固定ページにも投稿日を出す');
};

subtest '通常記事の更新日だけ出す' => sub {
	setting(art_upd => 1);
	like(dates('/01'), qr/\Q$posted\E\s*\Q$upd1\E/, '通常記事に更新日を出す');
	unlike(dates('/page1'), qr/update-date/, '固定ページには出さない');
	like(body($app->get('guest', '')), qr/\Q$upd1\E/, '一覧の記事にも出す');
	like(body($app->get('admin', 'plugin/plugin_setting&name=dea_art-info')), qr/name="art_upd" value="1" checked/, '設定の画面に保存した値が出る');
	unlike(body($app->get('admin', 'plugin/plugin_setting&name=dea_art-info')), qr/name="page_upd" value="1" checked/, '保存していない値にはチェックが付かない');

	set_art(1, update_tm => tm(2026, 10, 10));
	unlike(dates('/01'), qr/update-date/, '更新した日が記事の日付と同じなら出さない');
	set_art(1, update_tm => tm(2026, 11, 1));
};

subtest '固定ページの更新日だけ出す' => sub {
	setting(page_upd => 1);	# チェックの無いart_updは0になる
	unlike(dates('/01'), qr/update-date/, '通常記事には出さない');
	like(dates('/page1'), qr/\Q$posted\E\s*\Q$upd2\E/, '固定ページに更新日を出す');
};

subtest '更新日時が空の記事' => sub {
	setting(art_upd => 1);
	set_art(1, update_tm => '', tm => tm(2026, 11, 3));
	like(dates('/01'), qr{datetime="2026-11-03">2026/11/03</time>}, 'update_tmが空なら、tmの日を出す（今日の日付にしない）');
	set_art(1, update_tm => '', tm => tm(2026, 10, 10));
	unlike(dates('/01'), qr/update-date/, 'tmが記事の日付と同じ日なら出さない');
};

done_testing;
