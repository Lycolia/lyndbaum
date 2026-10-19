# デプロイ

CGIの動くWebサーバーに置いて動かす手順。adiaryから移るときは、設置の後に`docs/migrate-from-adiary.md`を行う。

## 必要なもの

- Perl 5.32.1以上と、DBI、DBD::SQLite。GDがあれば画像のサムネイルを作る（無ければ作らないだけ）
- Webサーバーは次のどちらか
  - Apache：mod_rewriteと、`.htaccess`を使えること（`AllowOverride FileInfo`。`Options`も書いているので`Options`も）。設定は同梱の`.htaccess`。mod_headersがあれば`X-Content-Type-Options: nosniff`を付ける
  - nginx：fcgiwrapなどでCGIを動かす。設定は`docs/nginx.conf.sample`を元に書く
- `/pub/`の下だけをファイルとして返し、ほかのURLはすべて`index.cgi`に渡す。`config.json`やDBなど、ほかのファイルは返さない

## 設置

リポジトリを、Webサーバーの公開フォルダ（ドキュメントルート）として置く。以下の`<置き場所>`はそのパス。

```sh
git clone https://github.com/<リポジトリ>.git <置き場所>   # または、下の「手元から送る」
cd <置き場所>
mkdir -p var pub/attachments pub/branding

cp config.json.sample config.json
perl -Ilib -MLyndbaum::Random=random_token -e 'print random_token(32), "\n"'   # secret_key に入れる値
```

`config.json`の`site_url`（例：`https://blog.example.jp`）と`secret_key`（上で作った値）を書く。ほかは見本のままでよい。httpで動かすときだけ、`"cookie_secure": false`を足す（ログインのCookieにSecureを付けないように）。

CGIを動かすユーザーが、`var/`、`pub/`（RSSとサイトマップを書き出す）、`pub/attachments/`、`pub/branding/`に書き込めるようにする。`config.json`と`var/`は、ほかのユーザーから読めないようにする。

- CGIが自分のアカウントとして動くサーバー（suEXEC。さくらのレンタルサーバーなど）では、`chmod 755 . index.cgi`、`chmod 700 var`、`chmod 600 config.json`。グループやほかの人が書き込めると、CGIが動かない
- Webサーバーのユーザー（`www-data`など）で動くときは、上のフォルダをそのユーザーが書き込めるようにする

```sh
perl tools/migrate.pl          # DB（var/lyndbaum.db）を作る
perl tools/set-password.pl     # 管理者のログイン名とパスワード（12文字以上）
perl tools/check-env.pl        # NG が無ければよい
```

ブラウザで確かめる。

1. トップページが出て、`/admin`でログインできる
2. 「ブログの設定」で、ブログの名前と説明、書いた人の名前を入れる
3. 画像を入れた記事を公開すると、トップページと`/pub/rss.xml`に出る。ログアウトしてコメントを書ける
4. `/config.json`と`/var/lyndbaum.db`が読めない（403か404）

## 更新

```sh
cd <置き場所>
git pull                     # または、下の「手元から送る」
perl tools/migrate.pl        # 新しいマイグレーションが無ければ何もしない
```

パーサーが変わったとき（`lib/Lyndbaum/Parser/`など）は、ダッシュボードの「再構築」か`perl tools/rebuild-html.pl`を実行する。

## 手元から送る

サーバーにしか無いもの（設定、DB、添付ファイルなど）を上書きしないように除いて送る。

```sh
rsync -av --exclude .git --exclude config.json --exclude 'var/*' --exclude 'pub/attachments' --exclude 'pub/branding' --exclude 'pub/rss.xml' --exclude 'pub/sitemap.xml' --exclude t/corpus ./ <ユーザー>@<ホスト>:<置き場所>/
```

## バックアップ

次の4つを残す。ほかはリポジトリから戻せる。

- `var/lyndbaum.db`（記事、コメント、設定、管理者）。書き込みの途中で写さないよう、`sqlite3 var/lyndbaum.db ".backup backup.db"`で写す
- `pub/attachments/`（添付ファイル）
- `pub/branding/`（設定の画面で入れたサイトのアイコンとブログの画像）
- `config.json`

## うまく動かないとき

- Webサーバーのエラーログを見る
- 500になる：`index.cgi`の1行目は`#!/usr/bin/env perl`。Perlが見つからないときは、`which perl`の結果（例：`/usr/local/bin/perl`）に書き換える
- ファイルを上げると413になる：Webサーバーの上限が`config.json`の`upload_max_mb`より小さい（nginxなら`client_max_body_size`）
- （Apache）コンテンツページが403になる：slugが実在するフォルダの名前（`lib`、`docs`、`tools`、`var`など）と同じだと、`.htaccess`がフォルダを先に見る。slugを変える
