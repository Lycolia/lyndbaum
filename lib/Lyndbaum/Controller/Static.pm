package Lyndbaum::Controller::Static;
# 静的なファイルの置き場所（/pub/）
#   ファイルはWebサーバーがそのまま返すので、ここに来るのは無いファイルへのリクエストだけ。
#   記事やコンテンツページとして探さずに 404 を返す（pub と pub/… は slug に使えない）
use strict;
use warnings;
use utf8;

sub not_found {
	my ($class, $app, $req) = @_;
	return $app->not_found;
}

1;
