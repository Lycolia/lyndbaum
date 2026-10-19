# adiaryからの移行

一度だけ行う。`docs/deploy.md`の「設置」を済ませてから行う。

## 旧データの取り込み

**取り込み先のDBは空であること**（記事を書く前に行う。書いた後なら、`var/lyndbaum.db`を消して`migrate.pl`と`set-password.pl`からやり直す）。

同じサーバーにあるadiaryから取り込む。`<adiary>`はadiaryの置き場所、`lycolia`はadiaryのブログのID。adiaryの`data/`は読むだけで、書き換えない。adiaryが別のサーバーにあるときは、`data/`と`pub/lycolia/image/`をこのサーバーに送ってから、そのパスを使う。

添付ファイルを先に写す（ブログの画像を、添付ファイルの中から`pub/branding/`へ写すため）。

```sh
cd <置き場所>
cp -a <adiary>/pub/lycolia/image/. pub/attachments/     # . を付けて、ゴミ箱（.trashbox）も写す
mv pub/attachments/adiary pub/attachments/posts         # フォルダの名前を変える（docs/compat-diffs.md）
perl tools/import-adiary.pl <adiary>/data lycolia       # 取り込んで、全記事を変換し、RSSとサイトマップを書き出す
```

- コマンドは、CGIを動かすユーザー（実行ユーザー）で実行する。Webサーバーのユーザーで動くときは、頭に`sudo -u www-data`を付ける（`docs/deploy.md`の「設置」）。写した添付ファイルと、取り込みで書き出すファイルの持ち主が、実行ユーザーになるように
- 旧システムのゴミ箱（`.trashbox`）は、そのまま新しいメディアのゴミ箱になる
- ブログの画像を写せなかったときはそう出るので、ブログの設定の画面で入れ直す
- adiaryは、本番のドメインを切り替えるまで今のまま動かしておいてよい

## 本番のドメインに移る

1. 本番のドメインのドキュメントルートを`<置き場所>`にする
2. `config.json`の`site_url`を本番のURLにする
3. `perl tools/rebuild-html.pl`（RSSとサイトマップの絶対URLを書き直す）
4. Google Search Consoleなどに、`https://<本番のドメイン>/pub/sitemap.xml`を登録し直す
5. 旧URLが転送されることを確かめる。たとえば`/pub/lycolia/rss.xml`→`/pub/rss.xml`、記事の旧URL（`docs/legacy-urls.md`）。添付ファイルとRSSの旧URLは、Webサーバーが転送する（`.htaccess`、`docs/config samples/`のnginxの見本）
