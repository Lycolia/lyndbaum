use strict;
use utf8;
#-------------------------------------------------------------------------------
# 画面がエラーにならずに出るかのテスト（公開画面、テーマの後ろのほう）
#-------------------------------------------------------------------------------
# 実行: prove t/screens_public.t
#
# 何を確かめるかは t/screens_admin.t の頭に書いた。
#
use FindBin;
BEGIN { push(@INC, "$FindBin::Bin/lib", "$FindBin::Bin/../lib"); }
use Test::More;
use AppTest;
use ScreensTest;

binmode(Test::More->builder->$_, ':utf8') foreach (qw(output failure_output todo_output));

my $app = ScreensTest::new_app();
ScreensTest::open_public($app, ScreensTest::themes('rest'));
ScreensTest::check_missing();

done_testing();
