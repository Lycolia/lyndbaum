package Lyndbaum::Controller;
# コントローラで共通に使う処理
use strict;
use warnings;
use utf8;

use Exporter 'import';
our @EXPORT_OK = qw(page_number);

# クエリの page。無いときは 1、数字でなければ 0（範囲外として404にする）
sub page_number {
	my ($req) = @_;
	my $page = $req->param('page');
	return 1 if !defined $page || $page eq '';
	return $page =~ /\A[1-9]\d{0,8}\z/ ? $page : 0;
}

1;
