use strict;
use warnings;
package Lyndbaum::Router;

sub route {
    return '<span>aaa</span>'
}

# sub route {
#     my ($request_method, $request_uri, $query_string) = @_;

#     # $request_uriがあれば記事・ページハンドラ
#     # なければクエリパラメーター系ハンドラに繋ぐようにする

#     if (has_request_uri($request_uri)) {
#         handle_article($request_uri, $query_string);
#     } elsif (has_query_string($has_query_string)) {
#         handle_controller($has_query_string);
#     } else {
#         # ファイル探し？
#     }

#     if (is_article($request_uri)) {
#         # 記事画面ハンドラ
#         # 非公開ページなどの認証はハンドラ側に置く
#     } elsif (is_page($request_uri)) {
#         # ページ画面ハンドラ
#         # 非公開ページなどの認証はハンドラ側に置く
#     } elsif (is_api($request_uri, $query_string)) {
#         # APIハンドラ
#     } elsif (is_admin($request_uri, $query_string)) {
#         # 管理画面ハンドラ
#         # 非公開ページなどの認証はハンドラ側に置く
#     } else {
#         # ファイル探し？
#     }

# }

# sub has_request_uri {
#     my $request_uri = shift;
# }

# sub has_query_string {
#     my $query_string = shift;
# }

# sub handle_article {
#     my ($request_uri, $query_string) = @_;

#     if (is_article($request_uri)) {
#         # 記事画面ハンドラ
#         # 非公開ページなどの認証はハンドラ側に置く
#     } elsif (is_page($request_uri)) {
#         # ページ画面ハンドラ
#         # 非公開ページなどの認証はハンドラ側に置く
#     } else {
#         # エラー？
#     }
# }

# sub handle_controller {
#     my $query_string = shift;

#     if (is_api($request_uri, $query_string)) {
#         # APIハンドラ
#     } elsif (is_admin($request_uri, $query_string)) {
#         # 管理画面ハンドラ
#         # 非公開ページなどの認証はハンドラ側に置く
#     } else {
#         # エラー？
#     }
# }

# sub is_article {
#      my $request_uri = shift;
# }

# sub is_page {
#      my $request_uri = shift;
# }

# sub is_api {
#     my ($request_uri, $query_string) = @_;
# }

# sub is_admin {
#     my ($request_uri, $query_string) = @_;
# }

1;
