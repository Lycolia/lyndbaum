# OGP

記事のページ（コンテンツページと下書きを含む）とトップページの`<head>`に、OGPとTwitter Card のメタタグ、`canonical`、`meta description`を出す（`Lyndbaum::OGP`、`Lyndbaum::App->page_head`）。検索の結果などのほかのページには出さない。

## 出すもの

| タグ | 記事 | トップページ |
| ---- | ---- | ------------ |
| `link rel="canonical"`、`og:url` | 記事のURL | トップページのURL（2ページ目からは`?page=N`） |
| `og:type` | `article` | `website` |
| `og:title`、`twitter:title` | 記事の題名 | ブログの名前 |
| `meta description`、`og:description`、`twitter:description` | 記事の説明（本文の先頭64文字） | ブログの説明 |
| `og:image`、`twitter:image` | 記事の画像（下）。無ければブログの画像 | ブログの画像 |
| `og:site_name` | ブログの名前 | ブログの名前 |
| `og:locale` | `ja_JP` | `ja_JP` |
| `twitter:card` | 記事の画像があれば`summary_large_image`、無ければ`summary` | `summary` |

- URLは絶対URLにする。元は`config.json`の`site_url`。無ければリクエストのホスト名から作る
- 値の無いもの（説明が空、ブログの画像が無いなど）は出さない
- 旧システムとの違い：`og:locale`は空だったので`ja_JP`を入れる。`twitter:url`はXの仕様に無いので出さない

## 記事の画像

記事ごとに決め方（`og_image_mode`）を持つ。編集の画面の「OGPの画像」の枠で選ぶ。

| 決め方 | 画像 |
| ------ | ---- |
| `auto`（既定） | 本文の最初の画像。サムネイルを元の画像へのリンクで囲んでいれば（`[image:S:…]`）、元の画像（旧システムと同じ） |
| `chosen` | 「メディアから選ぶ」で選んだ画像（`og_image`。添付ファイルの中のパス「フォルダ/名前」） |
| `none` | 使わない（ブログの画像を出す） |

- 「メディアから選ぶ」の窓（`docs/admin.md`の「メディア」）で画像を選んで「OGPの画像にする」を押すと、`chosen`にする。本文の下の「メディアから選ぶ」の窓からも選べる
- 旧データで画像（`main_image`）が決まっている記事は`chosen`で取り込む。決まっていなければ`auto`
- 旧システムは、OGPの欄が空なら本文の最初の画像、書けばその画像だった。「使わない」は、旧システムに作者が後で足したかったもの（adiary-extends 44f8d6e1）

## ブログの画像

「ブログの設定」の`blog_image`（添付ファイルの中のパス。例：`@system/sys-blog_image.png`）。「メディアから選ぶ」で選べる。旧データの`blog_image`を取り込む。
