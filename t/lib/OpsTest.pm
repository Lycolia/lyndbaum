use strict;
use utf8;
#-------------------------------------------------------------------------------
# 主な操作の中身のテスト（t/operations_*.t）で共通に使うもの
#-------------------------------------------------------------------------------
package OpsTest;
use Exporter 'import';
our @EXPORT = qw(body read_file json_ok %ART);

# 記事を書くときのフォームの既定値
our %ART = (action => 'edit', parser => 'markdown', enable => 1, com_ok => 1, ymd => '2026-10-10');

# 応答の本文（文字列に戻したもの）
sub body {
	my $b = shift->{body} // '';
	utf8::decode($b);
	return $b;
}
# ファイルの中身。無ければ空
sub read_file {
	my $file = shift;
	open(my $fh, '<:utf8', $file) || return '';
	local $/;
	return <$fh>;
}
# JSONの応答が成功（ret=0）か
sub json_ok {
	my $r = shift;
	return $r->{json} && defined $r->{json}->{ret} && $r->{json}->{ret} eq '0';
}

1;
