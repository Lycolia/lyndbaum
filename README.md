<div align="center">
  <img src="docs/assets/logo-vector.svg" height="64" width="64">
</div>

# Lyndbaum 4 - Neo-Modern High-performance CMS software

このプログラムは[nabe-abk/adiary](https://github.com/nabe-abk/adiary)のフォークです。
原典となる著作権表記はオリジナルのREADMEである、[README.original.md](README.original.md)に記しています。

フォーク後の改変箇所についてはGitのコミットログに記すものとします。

このプロジェクトは本家の3.52devで追従を打ち切り、独自路線に転換しています。

主な変更点については[変更履歴](docs/変更履歴.md)に記載しています。

# 動作環境

- Linux（WSLを含む）またはFreeBSD
- Perl 5.14.0以降（pure Perl可）
  - `crypt()`がbcrypt（`$2b$`）に対応していること（libxcryptを使うLinuxや、さくらのレンタルサーバーのFreeBSDなら対応している）

次のどれかの構成で動かします。

| 置く場所                  | 構成                               | 必要なApacheのモジュール           | 設定の見本                                                                                             |
| ------------------------- | ---------------------------------- | ---------------------------------- | ------------------------------------------------------------------------------------------------------ |
| レンタルサーバー          | Apache2 + CGI（`lyndbaum.cgi`）    | mod_rewrite                        | [.htaccess](docs/config-example/.htaccess.sample)                                                      |
| VPS、小規模な自宅サーバー | Apache2 + CGI（`lyndbaum.cgi`）    | mod_cgiまたはmod_cgid、mod_rewrite | [apache.conf](docs/config-example/apache.conf)、[.htaccess](docs/config-example/.htaccess.sample)      |
| VPS、小規模な自宅サーバー | nginx + FastCGI（`lyndbaum.fcgi`） | （不要）                           | [nginx.conf](docs/config-example/nginx.conf)、[lyndbaum.service](docs/config-example/lyndbaum.service) |

さくらのレンタルサーバーのように常駐するプログラムを禁止しているサーバーでは、`lyndbaum.fcgi`は使えないのでCGIで動かします。

Perl標準モジュールのほかに、使い方によって次のモジュールが必要です。

| モジュール    | 要るとき                                                                                                       |
| ------------- | -------------------------------------------------------------------------------------------------------------- |
| FCGI          | FastCGIで動かすとき（`lyndbaum.fcgi`）。ソケットで待ち受けるときはスレッド（ithreads）に対応したPerlも必要     |
| Image::Magick | 画像のサムネイルを作るとき。無いと、画像のサムネイルの代わりにアイコンを出す                                   |
| Net::SSLeay   | 外部のサイトとhttpsで通信するとき（更新通知、`[&URL]`のタイトルの取得、記事の画像の取り込みなど）。Ver1.92以降 |

httpsの通信では接続先の証明書を検証するので、サーバーにCA証明書（Debian系なら`ca-certificates`）が必要です。

# インストール方法

1. 解凍してでてきたファイルをサーバ上の任意の位置に置く
2. lyndbaum.cgiに実行属性を付ける（`lyndbaum.cgi`とそのフォルダは755か705。777ではCGIが動かないサーバーがある）
3. `__cache/`, `data/`, `pub/`を`www`権限で書き込めるようにする。（suEXECの場合は不要）
4. 設定ファイルは無くても動く。普段の設定は、ログインしてから管理画面の「システム設定」で行う。画面に無い項目（`lyndbaum.user.cgi.sample`を参照）を変えるときだけ、`lyndbaum.user.cgi`を作る
5. Apacheでは、`docs/config-example/.htaccess.sample`を根元に`.htaccess`としてコピーする。これが無いと`data/`などの非公開のフォルダをWebから読める。VPSなどでは、`docs/config-example/apache.conf`も手元に合わせて設定する。nginxでは、[動作環境](#動作環境)の表の設定を使う
6. `lyndbaum.cgi`にアクセスし、ID、パスワードを適当に入力してログイン。
7. その後、自分自身をユーザーとして追加する。

詳細は[オンラインマニュアル](http://adiary.org/v3man/)を参照してください。

# 著作権表示(Copyright)

- Copyright (C)2013-2025 nabe@abk.
- Copyright (C)2024-2026 Lycolia.

本プログラム（システム）はフリーソフトウェアです。

AGPL(AFFERO GENERAL PUBLIC LICENSE) Version 3またはそれ以降のバージョンの下で本プログラム（システム）を再配布することが可能です。

# 利用著作物

以下のものをライセンスに基づき使用しています。

## JavaScript

- jQuery (MIT)
  - jQuery UI (MIT / GPLv2)
  - dynatree (MIT)
  - Color Picker (MIT / GPL)
- [Lythumb-viewer](https://github.com/Lycolia/lythumb-viewer) (AGPLv3)
- [Prism.js](https://prismjs.com/) (MIT)

## Perl

`lib/Digest/`に同梱しています。

- Digest::SHA::PurePerl (Perl)
- Digest::HMAC (Perl)
- Digest::HMAC_MD5 (Perl)

## プラグインとテーマ

- `plugin/`以下に存在するプラグインはそれぞれ個別の著作物です。
- `pub/assets/theme/`以下に存在するテーマファイルはそれぞれ個別の著作物です。

ライセンスについては、各ディレクトリ内のREADME等を参照してください。

## フォント

VLゴシックフォント（`pub/assets/dist/VL-PGothic-Regular.ttf`）を
ライセンスに基づき同梱しています。
フォントのライセンスは`pub/assets/dist/VLGothic/`以下を参照してください。

## 画像アイコン

- `pub/assets/dist/album-icon`以下のアイコンの多くはせりか氏の著作物です。
- `pub/assets/dist/album-icon/pdf.png`は http://iconhoihoi.oops.jp/ の著作物です。
- `pub/assets/dist/album-icon`以下の`g-\*.png`と`trashbox.png`はGNOME Desktopアイコンです。
- `pub/assets/dist/mahjong/`以下のファイルは「[麻雀豆腐](http://majandofu.com/mahjong-images)」の画像を利用しています。
- `pub/assets/theme/base.css`のソーシャルボタンのXとFacebookのロゴは、各社の商標です。はてなブックマークのマーク（「B!ブックマーク」）は、はてなの公式のブックマークボタンのものです。

せりか氏著作物のライセンスは、adiaryのライセンスに準じます。
