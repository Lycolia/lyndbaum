package Lyndbaum::Parser;
# 記事の記法ごとのパーサーの登録表
#
# 記法を足すときは、parse を持つモジュールを作り、%PARSERS に登録する
# 記法をまたぐ処理（目次、続きを読む、検索用テキストの抽出）は Lyndbaum::Parser::Common にある
use strict;
use warnings;
use utf8;

use Lyndbaum::Parser::Markdown;

# 記法名 => パーサーのクラス。記法名は articles.syntax の値
my %PARSERS = (
	markdown => 'Lyndbaum::Parser::Markdown',
);

sub parser_for {
	my ($class, $syntax) = @_;
	return $PARSERS{$syntax} // die "対応していない記法です: $syntax\n";
}

# 本文を変換する
#   %context
#     article_id       記事ID（画像の data-lythumb などに使う）
#     article_url      記事のURL。見出しと目次のリンクを「記事のURL#ID」にする（省略すると「#ID」）
#     attachment_path  添付ファイルのURLの接頭辞（例：/pub/attachments/）
#     sectioning       見出しごとに <section> で囲むか
#     url_title        URLからページのタイトルを返す関数（[&URL] 用。省略可）
#     base_path        アプリのURLの接頭辞。記事内の相対リンク（[文字](0618) など）の先頭に付ける（省略すると空）
#   戻り値 { html => 変換したHTML, toc => [見出しの一覧], links => [記事へのリンクの slug の一覧] }
#     links は [文字](0756) の形のリンク先（# や ? の付いたもの、画像は除く）。出てきた順で、重複は除く
sub parse {
	my ($class, $syntax, $text, %context) = @_;
	return $class->parser_for($syntax)->parse($text, %context);
}

1;
