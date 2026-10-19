# さくらのレンタルサーバーへのデプロイ

空のサーバーに置いて動かすまでの手順。SSHで入って作業する。

- 置き場所の例：`~/www/lyndbaum/`（以下では`$APP`と書く）。まずは試しのサブドメインの公開フォルダにする
- 本番のドメインに移るときは、コントロールパネルでドメインの公開フォルダを切り替える（下の「本番のドメインに移る」）

## 1. 置く

```sh
cd ~/www
git clone https://github.com/<リポジトリ>.git lyndbaum   # または手元から rsync で送る
cd lyndbaum
```

手元から送るときは、`config.json`、`var/`、`pub/attachments/`、`pub/branding/`、`pub/rss.xml`、`pub/sitemap.xml`を送らない（サーバーのものを上書きしないように）。`t/corpus/`（git管理外。記事のデータを含む）も送らない。

```sh
rsync -av --exclude .git --exclude config.json --exclude 'var/*' --exclude 'pub/attachments' --exclude 'pub/branding' --exclude 'pub/rss.xml' --exclude 'pub/sitemap.xml' --exclude t/corpus ./ <ユーザー>@<ホスト>:www/lyndbaum/
```

`.htaccess`がそろっていることを確かめる。`/pub/`の下だけをファイルとして返し（`/favicon.ico`は、サイトのアイコンか既定のロゴの`favicon.ico`を返す）、ほかのURLはすべて`index.cgi`に渡す。`config.json`やDBなど、実在するファイルへのアクセスは403にする。

## 2. 権限

さくらでは、CGIは自分のアカウントとして動く。`index.cgi`と、それを置いたフォルダは、グループやほかの人が書き込めると動かない（suEXEC）。

```sh
chmod 755 . index.cgi
mkdir -p var pub/attachments
chmod 700 var
chmod 755 pub pub/attachments
```

## 3. 設定

```sh
cp config.sample.json config.json
chmod 600 config.json
perl -Ilib -MLyndbaum::Random=random_token -e 'print random_token(32), "\n"'   # secret_key に入れる値
```

`config.json`を直す。

- `site_url`：サイトのURL（例：`https://test.example.jp`）。RSSとOGPの絶対URLに使う
- `secret_key`：上で作った値。コメントのフォームの署名に使う
- `cookie_secure`：httpsで動かすので、消すか`true`のまま
- そのほか（`db_path`、`attachment_path`など）は見本のままでよい

## 4. DBと管理者

```sh
perl tools/migrate.pl          # DB（var/lyndbaum.db）を作る
perl tools/set-password.pl     # 管理者のログイン名とパスワード（12文字以上、UTF-8で72バイトまで）
perl tools/build-feed.pl       # RSS（pub/rss.xml）とサイトマップ（pub/sitemap.xml）。記事を保存するたびにも書き出す
perl tools/check-env.pl        # 足りないものが無いか確かめる。NG が無ければよい
```

`tools/check-env.pl`は、Perlとモジュールの版、SQLiteで使っている機能、GDが読める画像の種類、https、設定、権限、DBを確かめる。

## 5. 確かめる

ブラウザで開く。

1. トップページが出る（記事が無ければ空）
2. `/admin`でログインできる
3. 「ブログの設定」で、ブログの名前と説明、書いた人の名前を入れる
4. 記事を書き、画像を上げ、下書きで見てから公開する。トップページ、記事のページ、`/pub/rss.xml`、`/pub/sitemap.xml`に出る
5. 記事にコメントを書ける（ログアウトして試す）
6. `/config.json`、`/var/lyndbaum.db`、`/lib/Lyndbaum/App.pm`が403になる
7. メディアの画面でtxtとmdを上げ、「元のファイルを開く」でテキストとして出る（ダウンロードにならない）。`curl -I`で、`Content-Type: text/plain`と`X-Content-Type-Options: nosniff`が付いている（`.htaccess`の`AddType`と`Header`。`nosniff`が無ければmod_headersが無い）

うまく動かないときは、さくらのコントロールパネルのエラーログを見る。

## 旧データの取り込み（任意）

adiaryのデータ（`data/`）と添付ファイル（`pub/lycolia/image/`）を手元からサーバーに送って取り込む。**取り込み先のDBは空であること**（記事を書く前に行う。書いた後なら、DBを消して`migrate.pl`からやり直す）。

```sh
# 手元で
rsync -av <adiaryのdata>/ <ユーザー>@<ホスト>:adiary-data/                        # 公開フォルダの外に置く
rsync -av <adiaryのpub>/lycolia/image/ <ユーザー>@<ホスト>:www/lyndbaum/pub/attachments/

# サーバーで
cd ~/www/lyndbaum
mv pub/attachments/adiary pub/attachments/posts    # フォルダの名前を変える（docs/compat-diffs.md）
perl tools/import-adiary.pl ~/adiary-data lycolia   # 取り込んで、全記事を変換し、RSSとサイトマップを書き出す
```

- 旧システムのゴミ箱（`.trashbox`）は、そのまま新しいメディアのゴミ箱になる
- ブログの画像は、添付ファイルの中から`pub/branding/`へ写す（写せなければそう出すので、ブログの設定の画面で入れ直す）
- 管理者はDBに入るので、DBを作り直したら`set-password.pl`をもう一度実行する
- 取り込みが済んだら、`~/adiary-data`は消してよい

## 本番のドメインに移る

1. 試しのサブドメインで確かめ終わったら、コントロールパネルで本番のドメインの公開フォルダを`$APP`にする
2. `config.json`の`site_url`を本番のURLにする
3. `perl tools/rebuild-html.pl`（RSSとサイトマップの絶対URLを書き直す。本文も変換し直す）
4. Google Search Consoleなどに、サイトマップのURL（`https://<本番のドメイン>/pub/sitemap.xml`）を登録する。旧システムの`/pub/lycolia/sitemap.xml`を登録してあった場合は、新しいURLを登録し直す（旧URLは転送するが、登録し直すほうが確実）
5. 旧URLの転送を確かめる（`.htaccess`）
   - `/pub/lycolia/image/adiary/…` → `/pub/attachments/posts/…`
   - `/pub/lycolia/image/…` → `/pub/attachments/…`
   - `/pub/lycolia/rss.xml` → `/pub/rss.xml`
   - `/pub/lycolia/sitemap.xml` → `/pub/sitemap.xml`
   - 記事、タグ、検索の旧URLは、アプリが転送する（`docs/legacy-urls.md`）

## 更新する

```sh
cd ~/www/lyndbaum
git pull                     # または手元から rsync（1. のとおり、設定とデータを除く）
perl tools/migrate.pl        # スキーマを最新にする（新しいマイグレーションが無ければ何もしない）
perl tools/check-env.pl
```

パーサーを直したとき（`docs/markdown-syntax.md`や`lib/Lyndbaum/Parser/`が変わったとき）は、管理画面のダッシュボードの「再構築」か、`perl tools/rebuild-html.pl`を実行する。

サイドバーのタグ一覧・右側メニューは、更新時に生成したHTMLをDBの`sidebar_cache`に保存する。新規DBの作成後は`perl tools/rebuild-sidebar.pl`で先に生成できる。キャッシュが無い場合やサイドバーのテンプレートが変わった場合は、次の閲覧時にも自動生成する。

## バックアップ

残すのは次の4つ。ほかはリポジトリから戻せる。

- `var/lyndbaum.db`（記事、コメント、設定、管理者）
- `pub/attachments/`（添付ファイル）
- `pub/branding/`（設定の画面で入れたサイトのアイコンとブログの画像。アイコンの元の画像は残さないので、無くしたら入れ直す）
- `config.json`

DBは、書き込みの途中で写さないよう、`sqlite3 var/lyndbaum.db ".backup backup.db"`で写すとよい。

## 気をつけること

- コンテンツページのslugが、実在するフォルダの名前（`lib`、`docs`、`tools`、`templates`、`db`、`t`、`var`、`pub`など）と同じだと、ページではなく403になる（`.htaccess`がフォルダを先に見るため）
- `index.cgi`の1行目は`#!/usr/bin/env perl`。さくらでPerlが見つからないときは、`which perl`の結果（例：`/usr/local/bin/perl`）に書き換える
