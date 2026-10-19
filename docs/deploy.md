# デプロイ

CGIの動くWebサーバーに置いて動かす手順。adiaryから移るときは、設置の後に`docs/migrate-from-adiary.md`を行う。

## 必要なもの

- Perl 5.32.1以上と、DBI、DBD::SQLite。GDがあれば画像のサムネイルを作る（無ければ作らないだけ）
- Webサーバーは次のどちらか
  - Apache：mod_rewriteと、`.htaccess`を使えること（`AllowOverride FileInfo`。`Options`も書いているので`Options`も）。設定は同梱の`.htaccess`。mod_headersがあれば`X-Content-Type-Options: nosniff`を付ける
  - nginx：fcgiwrapなどでCGIを動かす。設定は`docs/config samples/nginx-fcgiwrap.conf`を元に書く
  - プロセスを動かし続けられるサーバーでは、FastCGIで常駐させてもよい（下の「FastCGIで動かす」）
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

CGIを動かすユーザー（以下、実行ユーザー）を、書き込むもの（`var/`、`pub/`、`pub/attachments/`、`pub/branding/`）と`config.json`の持ち主にする。`pub/`にはRSSとサイトマップを書き出す。`config.json`と`var/`は、実行ユーザーのほかからは読めないようにする。`tools/`のコマンドも実行ユーザーで実行する（作ったDBなどを、実行ユーザーが書き換えられるように）。

- CGIが自分のアカウントとして動くサーバー（suEXEC。さくらのレンタルサーバーなど）では、実行ユーザーは自分。`chmod 755 . index.cgi`、`chmod 700 var`、`chmod 600 config.json`。グループやほかの人が書き込めると、CGIが動かない
- Webサーバーのユーザー（`www-data`など）で動くときは、そのユーザーを持ち主にする。`pub/`はフォルダだけ（`pub/assets/`はリポジトリのものなので、`git pull`するユーザーのままにする）

```sh
sudo chown -R www-data:www-data var pub/attachments pub/branding config.json
sudo chown www-data:www-data pub
sudo chmod 700 var
sudo chmod 600 config.json
```

`tools/`のコマンドを実行する。Webサーバーのユーザーで動くときは、頭に`sudo -u www-data`を付ける（例：`sudo -u www-data perl tools/migrate.pl`）。

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

## FastCGIで動かす（任意）

CGIでは、リクエストのたびにPerlを起動し、モジュールを読み込む（手元で1回あたり約45ms）。プロセスを動かし続けられるサーバー（自分で管理していて、systemdなどを使えるもの）では、`index.fcgi`で常駐させると、この時間がかからなくなる。レンタルサーバーなど、常駐させられないところでは`index.cgi`のままでよい。

- PerlのFCGIモジュールが要る。OSのパッケージで入れる（DebianとUbuntuは`apt install libfcgi-perl`）。`perl tools/check-env.pl`の「FCGI」がOKならよい
- `perl index.fcgi [--socket-mode 権限] ソケット [プロセスの数] [1つのプロセスが受けるリクエストの数]`。既定は4と1000。ソケットは、UNIXソケットのパスか、`127.0.0.1:9000`の形
- 1つのプロセスは、決まった数のリクエストを受けたら終わり、作り直す。止める合図（TERM）を受けたら、処理中の応答を返し終えてから終わる
- 設定（`config.json`）とテンプレートは、CGIと同じくリクエストごとに読む。プログラム（`lib/`など）を変えたときだけ、起動し直す
- UNIXソケットに繋ぐには、ソケットへの書き込みの権限が要る。ソケットの権限は既定で0660（実行ユーザーとそのグループが読み書きできる）
  - Webサーバーが実行ユーザーと同じユーザーで動くときは、そのままでよい
  - 別のユーザーで動くとき（nginxが`nginx`ユーザーで動き、実行ユーザーが`www-data`のときなど）は、Webサーバーのユーザーを実行ユーザーのグループに入れる（`sudo usermod -aG www-data nginx`。入れた後にWebサーバーを起動し直す）
  - 権限を変えるときは`--socket-mode`で8進数で渡す（例：`perl index.fcgi --socket-mode 0600 /run/lyndbaum/lyndbaum.sock`）。誰でも繋げる0666などにすると、同じサーバーのほかのユーザーも、アプリにリクエストを直接送れる（`HTTPS`や`REMOTE_ADDR`も偽れる）

systemdの設定は、`docs/config samples/lyndbaum.service`を`/etc/systemd/system/lyndbaum.service`に写し、`<置き場所>`を書き換えてから有効にする。`var/`などの持ち主と権限、`tools/`のコマンドの実行のしかたは、CGIをWebサーバーのユーザーで動かすときと同じ（上の「設置」）。

```sh
sudo systemctl daemon-reload
sudo systemctl enable --now lyndbaum
```

nginxの設定は、`docs/config samples/nginx-fastcgi.conf`を元に書く。CGIの見本（`nginx-fcgiwrap.conf`）との違いは、`fastcgi_pass`の行き先が上のソケット（`unix:/run/lyndbaum/lyndbaum.sock`）であることだけ。

## 更新

```sh
cd <置き場所>
git pull                     # または、下の「手元から送る」
perl tools/migrate.pl        # 新しいマイグレーションが無ければ何もしない（実行ユーザーで。上の「設置」）
```

FastCGIで動かしているときは、`sudo systemctl restart lyndbaum`で起動し直す（上の「FastCGIで動かす」）。

パーサーが変わったとき（`lib/Lyndbaum/Parser/`など）は、ダッシュボードの「再構築」か`perl tools/rebuild-html.pl`（実行ユーザーで）を実行する。

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
- （FastCGI）起動しない：`journalctl -u lyndbaum`で理由を見る。すぐに落ちることが続くと、systemdが起動し直すのをやめる（`Start request repeated too quickly`）。直したら`sudo systemctl reset-failed lyndbaum`の後に`sudo systemctl restart lyndbaum`
