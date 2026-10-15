# RSS

RSS 2.0だけを出す（旧システムもRSSだけだった。Atomは作らない）。

## 書き出し

- 静的なファイル`pub/rss.xml`（URLは`/pub/rss.xml`）として書き出し、Webサーバーがそのまま返す（`Lyndbaum::Feed`）。書き出す先は`config.json`の`feed_file`で変えられる（テスト用）
  - フィードリーダーは頻繁に取りに来るので、CGIを起動しないで済むようにする。ETagや304もWebサーバーに任せる
  - 一時ファイルに書いてから置き換える（書きかけのファイルを読ませない）
- 書き出すのは、記事を保存したとき、消したとき、再構築（`tools/rebuild-html.pl`）と取り込み（`tools/import-adiary.pl`）のとき。手で書き出すときは`perl tools/build-feed.pl`
- 絶対URLは`config.json`の`site_url`から作る（`tools/`から書き出すときはリクエストが無く、ホスト名がわからないため）。無ければ書き出さない
- 旧URL（`/pub/lycolia/rss.xml`）からの転送は、Webサーバーの設定で行う
- すべてのページの`<head>`に、自動検出のリンク（`<link rel="alternate" type="application/rss+xml">`）を入れる

## 中身

| 要素                   | 値                                           |
| ---------------------- | -------------------------------------------- |
| `title`、`description` | ブログの名前と説明                           |
| `link`                 | トップページ                                 |
| `language`             | `ja`                                         |
| `pubDate`              | いちばん新しい記事の公開日時                 |
| `lastBuildDate`        | 書き出した日時                               |
| `generator`            | `Lyndbaum`                                   |
| `docs`                 | `https://www.rssboard.org/rss-specification` |
| `atom:link rel="self"` | RSS自身のURL（validatorが推奨する）          |

`copyright`は出さない（旧システムは年だけを出していて、中身がなかった）。

記事（`item`）：

- 載せるのは、公開している普通の記事だけ。下書き、ゴミ箱、コンテンツページは載せない
- 新しい順に、設定の`feed_items`件（既定は10。旧データの`rss_items_int`を取り込む）

| 要素           | 値                                                                                                                                         |
| -------------- | ------------------------------------------------------------------------------------------------------------------------------------------ |
| `title`        | 題名                                                                                                                                       |
| `link`、`guid` | 記事のURL                                                                                                                                  |
| `category`     | タグごとに1つ。親を含めた名前（`料理::調味料`）。旧システムはカンマ区切りで1つにまとめていたが、RSS 2.0では要素を並べるのが正しい          |
| `dc:creator`   | 設定の`blog_author`（旧データでは記事の書いた人の名前を取り込む）。空なら出さない。RSS 2.0の`author`はメールアドレスを書く欄なので使わない |
| `pubDate`      | 公開日時                                                                                                                                   |
| `description`  | 本文のHTML全体（続きを読むの後ろも含める）                                                                                                 |

- 本文のHTMLは、CDATAで囲まずにXMLのエスケープをする（CDATAは中に`]]>`があると壊れるため。リーダーから見た中身は同じ）
- 本文の中の相対URL（`href`、`src`、`poster`）は、記事のURLをもとに絶対URLにする。`#見出し`は`記事のURL#見出し`になる
- XML 1.0で使えない文字（制御文字など）は取り除く
- 日時はRFC 822の形で、GMTで書く

## サイトマップ

Google Search Console などに登録するためのもの（sitemaps.org の形）。`Lyndbaum::Sitemap`。

- RSSと同じく、静的なファイル`pub/sitemap.xml`（URLは`/pub/sitemap.xml`）として書き出す。書き出す時機もRSSと同じ（`Lyndbaum::StaticFiles`が両方を書き出す）。書き出す先は`config.json`の`sitemap_file`で変えられる（テスト用）
- 中身：トップページと、公開している記事とコンテンツページ（下書きとゴミ箱の中は入れない）。記事はIDの順（旧システムと同じ）
  - `<loc>`：絶対URL（`site_url`から作る）
  - `<lastmod>`：更新日時（UTC。例：`2026-10-15T03:04:05+00:00`）。トップページは、いちばん新しい記事の更新日時
  - `<changefreq>`と`<priority>`は入れない（旧システムも入れていない。Googleは使わない）
- 旧システムとの違い：トップページを入れる
- 旧URL（`/pub/lycolia/sitemap.xml`）からの転送は、Webサーバーの設定（`.htaccess`）で行う
- 1つのサイトマップに入れられるのは5万件まで。それを超えるほど記事が増えたら、分ける
