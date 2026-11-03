use strict;
use utf8;
#-------------------------------------------------------------------------------
# 画面がエラーにならずに出るかのテスト
#-------------------------------------------------------------------------------
# 実行: prove t/screens_admin.t t/screens_public.t
#
# 開発モード（Develop）で動かし、次のどれも出ないことを確かめる。
#	・テンプレートのエラー（画面の下の output-error の欄、出力の後ろの (ERROR)）
#	・Perlの警告などの標準エラー出力
#	・500番台のステータス
# あわせて、画面が参照する配布物のファイル（/pub/assets/ の下）が、すべてあることを確かめる。
# 管理画面はすべてシステム管理者で開く。公開画面は、すべてのテーマで、
# ログインしていない人と編集者（管理バーが出る）で開く。
# あわせて、画面を開いても data/ と pub/ が変わらないことを確かめる（公開画面は最初のテーマでだけ）。
# ログインのCookieはSameSite=Laxで、ほかのサイトのリンクから開くGETにはCookieが乗るため
# （docs/仕様/機能一覧.md の「CSRFの対策」）。開くと書き込む画面は %GET_WRITES に理由と書く。
#
# 並べて動かしたときに早く終わるよう、2つのファイルに分けてある。表と確かめの関数は t/lib/ScreensTest.pm。
#	t/screens_admin.t  … skel/ の画面が表に入っているか、管理画面、テーマの前のほう
#	t/screens_public.t … テーマの後ろのほう
#
use FindBin;
BEGIN { push(@INC, "$FindBin::Bin/lib", "$FindBin::Bin/../lib"); }
use Test::More;
use AppTest;
use ScreensTest;

binmode(Test::More->builder->$_, ':utf8') foreach (qw(output failure_output todo_output));

ScreensTest::check_listed();

my $app = ScreensTest::new_app();
ScreensTest::open_admin($app);
ScreensTest::open_public($app, ScreensTest::themes('first'));
ScreensTest::check_missing();

done_testing();
