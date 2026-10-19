# テンプレート

HTMLは`templates/*.html`のテンプレートから作る。エンジンは自作の小さなもの（`lib/Lyndbaum/Template.pm`）。
ここでは、書き方と、各テンプレートで使える変数をまとめる。変数を足したり変えたりしたら、この資料も直す。

## 書き方

| 書き方                                     | 意味                                                         |
| ------------------------------------------ | ------------------------------------------------------------ |
| `{{ a.b.c }}`                              | 値を出す。HTMLエスケープする（`& < > " '`）                  |
| `{{ raw a.b }}`                            | 値をエスケープせずに出す。使う箇所には理由をコメントで残す   |
| `{{# if a.b }}` … `{{/ if }}`              | 値が真なら中を出す                                           |
| `{{# if a.b }}` … `{{# else }}` … `{{/ if }}` | 真なら前を、偽なら後ろを出す                              |
| `{{# if not a.b }}` … `{{/ if }}`          | 値が偽なら中を出す                                           |
| `{{# for item in a.list }}` … `{{/ for }}` | 配列の要素ごとに中を出す。中では`item`で要素を参照する     |
| `{{> name }}`                              | 部品`templates/name.html`を読み込む                        |
| `{{! コメント }}`                           | 何も出さない。複数行にまたがってよい                         |

### 値の参照

- `a.b.c`は、ハッシュならキーで、配列なら数字の添え字で（`list.0`）たどる。
- 途中で値が無くなったら、空（`undef`）になる。エラーにはならず、出力は空文字列になる。
- 名前の先頭は、内側のスコープから順に探す。`for`の中では、ループの変数と`loop`が外側の同じ名前より優先される。
- 使える文字は英数字と`_`だけ。比較（`==`）、演算、関数の呼び出し、フィルタは無い。必要な値は、コントローラか`Lyndbaum::View`で作って渡す（例：`article.show_updated`）。

### 真と偽

- Perlの真偽と同じ。`undef`、空文字列、`0`、`"0"`は偽。
- それに加えて、空の配列も偽とする。`{{# if articles }}`で「1件以上あるか」を確かめられる。
- `else if`は無い。`{{# else }}`の中に`{{# if }}`を入れ子にする。

### for

- 中では`loop`が使える。

  | 変数          | 意味                     |
  | ------------- | ------------------------ |
  | `loop.index`  | 0から数えた番号         |
  | `loop.number` | 1から数えた番号         |
  | `loop.first`  | 最初の要素なら真         |
  | `loop.last`   | 最後の要素なら真         |

- ループの変数の名前に`loop`は使えない。
- 値が無い（`undef`）ときは何も出さない。配列でない値を渡すとエラーになる。
- 入れ子にした`for`の`loop`は、内側のものを指す。

### 部品（`{{> name }}`）

- 読み込んだ側の変数を、そのまま使える。引数は渡せないので、`for`の変数の名前で受け渡す（例：`{{# for article in articles }}{{> article_summary }}{{/ for }}`）。
- 名前に使えるのは英数字、`_`、`-`、`/`。`/`で`templates/`の下のフォルダを指せる。
- 自分自身を読み込んで木を出せる（`tag_tree_item.html`を参照）。深さは20段まで。

### 空白と改行

ブロックの印（`#`、`/`、`>`、`!`）だけの行は、行の前の字下げと後ろの改行ごと出力から除く。
値を出すタグ（`{{ a }}`、`{{ raw a }}`）のある行や、ほかの文字と同じ行に書いたブロックの印は、そのまま残る。

```
<ul>
  {{# for tag in tags }}
  <li>{{ tag.name }}</li>
  {{/ for }}
</ul>
```

は、次のように出る（`for`の行は残らない）。

```
<ul>
  <li>料理</li>
  <li>言語</li>
</ul>
```

### 誤り

閉じていない`{{# if }}`、対応しない`{{/ for }}`、知らないブロック（`{{# unless }}`など）、使えない式は、読み込んだときにエラーになる。メッセージにはファイル名と行が入る。

### エスケープしない値（`raw`）

`raw`で出してよいのは、作った側でエスケープや許可リストの確認を済ませた値だけ。今`raw`で出しているのは次のもの。

| 値                          | 作る場所                                   |
| --------------------------- | ------------------------------------------ |
| `content`                   | 各ページのテンプレートの出力               |
| `sidebar_tags`、`sidebar_menu` | `Lyndbaum::SidebarCache`（サイドバーのテンプレートの生成済みHTML） |
| `article.backlinks_html`    | `Lyndbaum::Backlinks`（`backlinks.html`の生成済みHTML） |
| `article.body`              | パーサー（許可リストに通したHTML）。一覧では`Lyndbaum::Parser::Common->excerpt`が印の前で切り、開いているタグを閉じたもの |
| `box.html`                  | `Lyndbaum::SidebarBoxes->for_display`      |
| `comment.html`              | `Lyndbaum::CommentText`                    |
| `article.title_html`、`s`（`snippets`）、`line.html` | `Lyndbaum::Highlight`（`<mark>`だけを含む） |

`article.body_src`や`article.body_html`を`raw`で出してはいけない。本文は`article.body`を使う。

## 公開側のページ

`Lyndbaum::App->render`が、ページのテンプレートを出力し、それを`layout.html`で包む。

### すべてのページで使える変数

ページのテンプレートと`layout.html`の両方で使える。同じ名前の変数をページが渡したときは、ページのものが優先される。

| 変数              | 中身                                                                      |
| ----------------- | ------------------------------------------------------------------------- |
| `blog`            | ブログの設定（下の「blog」）                                              |
| `urls.top`        | トップページのURL                                                         |
| `urls.search`     | 検索のURL                                                                 |
| `urls.feed`       | RSSのURL                                                                  |
| `urls.style`      | `common.css`（公開側と管理画面の両方で使う見た目）のURL                  |
| `urls.site_style` | `site.css`（公開側だけの見た目）のURL。`urls.style`の後に読む            |
| `urls.lythumb_css`、`urls.prism_css`、`urls.prism_core`  | 画像の拡大表示とコードの色付けのファイルのURL      |
| `urls.scripts`    | 読み込むJavaScriptのURLの配列（この順に`defer`で読む）                  |
| `form`            | 検索フォームの値（下の「form」）。検索のページでは、入力した検索語が入る |
| `sidebar_tags`    | `sidebar_tags.html`の生成済みHTML（エスケープ済み）                     |
| `sidebar_menu`    | `sidebar_menu.html`の生成済みHTML（自由欄も許可リストに通してある）     |
| `app_version`     | Lyndbaumの版（`0.2.0-beta`など）                                        |
| `admin_bar`       | 管理者のメニュー（下の「admin_bar」）。ログインしていなければ空           |

### layout.htmlだけで使える変数

サイドバーは`SidebarCache`で生成してDBに保存する。`layout.html`は`sidebar_tags`と`sidebar_menu`を`raw`で埋め込む。検索フォームの`form`はページごとに変わるのでキャッシュしない。

`sidebar_tags.html`では`tag_tree`（公開記事の付いたタグの木）、`sidebar_menu.html`では次の変数を使える。これらは通常のページには渡さない。

| 変数 | 中身 |
| --- | --- |
| `content_tree` | サイドバーのコンテンツの木（下の「コンテンツの木」） |
| `recent_posts` | 最近の記事5件。要素は`url`、`title` |
| `recent_comments` | 最近のコメント5件。要素は`url`（`#cN`付き）、`title`、`author_name`、`created` |
| `archive` | 過去ログ（下の「archive」） |
| `sidebar_boxes` | 自由欄。要素は`title`、`html`（許可リストに通したHTML） |

| 変数      | 中身                                                  |
| --------- | ----------------------------------------------------- |
| `content` | ページのテンプレートの出力（エスケープ済み）          |

ページが渡した`title`、`head`、`noindex`も、`layout.html`で`<title>`や`<meta>`に使う。

| 変数               | 中身                                                                       |
| ------------------ | -------------------------------------------------------------------------- |
| `title`            | ページの題名。あれば`<title>`を「題名-ブログ名」にする                 |
| `head.canonical`   | このページの絶対URL                                                        |
| `head.description` | ページの説明                                                               |
| `head.ogp`         | OGPとTwitter Cardのメタタグの配列。要素は`attr`（`property`か`name`）、`key`、`content` |
| `noindex`          | 真なら検索エンジンに載せない（下書き）                                     |

`head`を渡すのは、トップページと記事のページ。

### ページごとの変数

| テンプレート     | 使う場面             | 変数                                                    |
| ---------------- | -------------------- | ------------------------------------------------------- |
| `top.html`       | トップページ         | `articles`（記事の配列）、`pager`、`head`               |
| `article.html`   | 記事、コンテンツページ | `article`（記事。個別ページの項目を含む）、`title`、`head`、`noindex` |
| `search.html`    | 検索                 | `title`、`form`、`selected`、`tag_facet`、`date_facet`、`articles`、`pager`。検索の条件が無いときは`title`と`form`だけ |
| `not_found.html` | 404                  | `title`                                                 |

部品は、読み込んだ側の変数を使う。

| 部品                     | 読み込む場所                      | 前提とする変数                     |
| ------------------------ | --------------------------------- | ---------------------------------- |
| `article_summary.html`   | `top.html`                        | `article`（一覧の記事）            |
| `search_result.html`     | `search.html`                     | `article`（検索結果の記事）        |
| `pager.html`             | `top.html`、`search.html`         | `pager`                            |
| `search_form.html`       | `layout.html`、`search.html`      | `form`、`urls.search`              |
| `tag_tree_item.html`     | `layout.html`、自分自身           | `node`（タグの木の要素）           |
| `content_tree_item.html` | `layout.html`、自分自身           | `node`（コンテンツの木の要素）     |
| `comments_section.html`  | `article.html`                    | `article`                          |
| `comment_form.html`      | `comments_section.html`           | `article.comment_form`             |
| `admin_bar.html`         | `layout.html`                     | `admin_bar`                        |

### 参照元（`backlinks.html`）

記事のページの、本文とコメントの間に出す「参照元」（その記事へリンクしている記事の一覧）。

- `Lyndbaum::Backlinks`が記事の保存、ゴミ箱の操作、再構築、取り込みのときに描画し、DB（`articles.backlinks_html`）に保存する。表示のときは描画しない。`article.html`は`article.backlinks_html`を`raw`で埋め込む
- **テンプレートを変えたら再構築する**（`perl tools/rebuild-html.pl`か、管理画面の再構築）。再構築するまでは、前のテンプレートで作ったHTMLが出る
- 参照元が無い記事では描画せず、空にする
- 数えるリンクは、本文の`[文字](0756)`や`[文字](管理人について)`の形だけ。`#`や`?`の付いたもの、`/`で始まるもの、画像は数えない。同じ記事から何度リンクしていても1件。公開中でゴミ箱に無い記事とページからのリンクだけを出し、自分自身へのリンクは出さない

使える変数は次のものだけ（通常のページの変数は渡さない）。

| 変数        | 中身                                                         |
| ----------- | ------------------------------------------------------------ |
| `backlinks` | 参照元の記事の配列（公開日時の新しい順）。要素は`title`、`url` |

### 値の形

#### blog

設定の値（`Lyndbaum::Model::Setting`）。テンプレートで使うのは主に次のもの。

| 変数                    | 中身                                     |
| ----------------------- | ---------------------------------------- |
| `blog.blog_title`       | ブログ名                                 |
| `blog.blog_description` | ブログの説明。空のこともある             |
| `blog.blog_author`      | 書いた人の名前。空のこともある           |
| `blog.per_page`         | 1ページの記事の数                        |

ほかに、コメントの設定（`comments_*`）や編集の設定（`revision_*`）なども入っている。

#### 日時

日時は次の形のハッシュ。日本時間。値が無いとき（下書きの公開日時など）は、ハッシュではなく空になる。

| 変数       | 例                          | 使いどころ                       |
| ---------- | --------------------------- | -------------------------------- |
| `date`     | `2026-10-16`                | 表示                             |
| `datetime` | `2026-10-16 12:34`          | 表示                             |
| `iso`      | `2026-10-16T12:34:56+09:00` | `<time datetime="…">`            |
| `input`    | `2026-10-16T12:34`          | `<input type="datetime-local">`  |

#### 記事

一覧（`articles`の要素）、検索結果、個別ページのどれでも使える項目。

| 変数                   | 中身                                                                 |
| ---------------------- | -------------------------------------------------------------------- |
| `article.id`           | 記事のID                                                             |
| `article.title`        | 題名                                                                 |
| `article.url`          | 記事のURL                                                            |
| `article.slug`         | URLのパス（`0575`、`親/子`）                                         |
| `article.kind`         | `post`（記事）か`page`（コンテンツページ）                          |
| `article.is_page`      | コンテンツページなら真                                               |
| `article.description`  | 説明。空のこともある                                                 |
| `article.published`    | 投稿日時（日時の形）                                                 |
| `article.updated`      | 更新日時（日時の形）                                                 |
| `article.show_updated` | 更新日を出すなら真（投稿日と日付が違うとき。投稿日が無いときも真）   |
| `article.tags`         | 付いているタグの配列（下の「タグ」。親を含めた名前の順）             |
| `article.comments_open`| コメントを受け付ける記事なら1                                       |
| `article.eyecatch`     | 選んだアイキャッチ（添付ファイルの中のパス）。選んでいなければ空（`docs/ogp.md`） |

個別ページ（`article.html`）だけで使える項目。

| 変数                     | 中身                                                             |
| ------------------------ | ---------------------------------------------------------------- |
| `article.body`           | 本文のHTML（続きを読むの印を除いたもの）。`raw`で出す            |
| `article.backlinks_html` | 参照元（下の「参照元」）の生成済みHTML。参照元が無ければ空。`raw`で出す |
| `article.comments`       | 公開中のコメントの配列（下の「コメント」）                       |
| `article.comments_count` | 公開中のコメントの数                                             |
| `article.comment_form`   | コメントのフォーム（下の「コメントのフォーム」）。出さないときは空 |
| `article.is_draft`       | 下書きなら真（管理者にだけ見せている）                           |
| `article.edit_url`       | 編集の画面のURL（下書きのときだけ）                              |

一覧（`articles`の要素。トップと検索結果）だけで使える項目。

| 変数                 | 中身                                                                                         |
| -------------------- | -------------------------------------------------------------------------------------------- |
| `article.list_image` | 一覧に出すアイキャッチの画像のURL。アイキャッチが添付ファイルのときだけ入る（外部の画像は入れない）。サムネイルがあればサムネイル、無ければ元の画像 |
| `article.body`       | 本文のHTML。続きを読むの印があればその前まで（印の前で開いているタグは閉じてある）、無ければ全文。`raw`で出す。見出し、目次、脚注のリンクは「記事のURL#ID」なので、一覧に並べても、その記事の見出しや脚注へ行く |
| `article.has_more`   | 続きを読むの印で切ったなら真（「続きを読む」のリンクを出すのに使う）                          |

一覧に本文を出すかどうか、本文を出すときにアイキャッチを出すかどうかは、テンプレートの書き方で決める。今はトップの一覧（`article_summary.html`）では本文と「続きを読む」のリンクを出し、説明とアイキャッチは出さない（旧システムと同じ）。検索結果（`search_result.html`）では説明かその抜粋と、アイキャッチを出す。

検索結果（`search_result.html`）で、検索語があるときだけ入る項目。

| 変数                    | 中身                                                                |
| ----------------------- | ------------------------------------------------------------------- |
| `article.title_html`    | 検索語を`<mark>`で囲んだ題名。`raw`で出す                         |
| `article.snippets`      | 範囲が本文のとき、当たった箇所の前後の抜粋の配列。要素は`raw`で出す |
| `article.source_lines`  | 範囲が原文のとき、当たった行の配列。要素は`number`（行番号）、`html`（`raw`で出す） |
| `article.omitted_lines` | 範囲が原文のとき、上限を超えて省いた行の数                          |

#### タグ

`article.tags`の要素と、`tag_tree`の要素（`node`）。

| 変数        | 中身                                                       |
| ----------- | ---------------------------------------------------------- |
| `name`      | タグの名前（`調味料`）                                     |
| `full_name` | 親を含めた名前（`料理::食材::調味料`）                     |
| `url`       | そのタグで絞り込んだ検索のURL                              |
| `id`、`parent_id` | タグのIDと、親のID                                  |

`tag_tree`の要素には、さらに次のものがある。

| 変数       | 中身                                              |
| ---------- | ------------------------------------------------- |
| `count`    | 子孫のタグを含めた、公開記事の数                  |
| `children` | 子のタグの配列（同じ形）                          |

#### コンテンツの木

`content_tree`の要素（`node`）。`id`、`parent_id`、`title`、`slug`、`url`、`children`（子のページの配列）。

#### archive

年の配列（新しい順）。

| 変数                  | 中身                                    |
| --------------------- | --------------------------------------- |
| `year.year`           | 年（`2026`）                            |
| `year.count`          | その年の記事の数                        |
| `year.url`            | その年で絞り込んだ検索のURL             |
| `year.open`           | いちばん新しい年なら真                  |
| `year.months`         | 月の配列。要素は`label`（`2026年10月`）、`count`、`url` |

#### pager

| 変数             | 中身                                     |
| ---------------- | ---------------------------------------- |
| `pager.page`     | 今のページ                               |
| `pager.last`     | 最後のページ                             |
| `pager.total`    | 全部の件数                               |
| `pager.has_more` | 2ページ以上あるなら真                    |
| `pager.prev_url` | 前（新しい側）のページのURL。無ければ空  |
| `pager.next_url` | 次（古い側）のページのURL。無ければ空    |

#### form

| 変数          | 中身                                                                  |
| ------------- | --------------------------------------------------------------------- |
| `form.q`      | 検索語                                                                |
| `form.scopes` | 検索の範囲の選択肢の配列。要素は`value`（`text`、`title`、`source`）、`label`、`selected` |

#### 検索の絞り込み

| 変数         | 中身                                                                       |
| ------------ | -------------------------------------------------------------------------- |
| `selected`   | 選んでいる条件の配列。要素は`label`、`remove_url`（その条件を外したURL）  |
| `tag_facet`  | タグの候補の配列。要素は`label`、`count`、`url`（そのタグを足したURL）    |
| `date_facet` | 年か月の候補の配列。要素は`label`、`count`、`url`                         |

#### admin_bar

ログイン中に、公開側のページと管理画面の上に出す管理者のメニュー（`docs/admin.md`）。公開側では、コントローラが`render`に`req`（リクエスト）を渡したページで入る（404のページでは入らない）。管理画面では、ログイン中のすべてのページで入る。

| 変数                   | 中身                                                                  |
| ---------------------- | --------------------------------------------------------------------- |
| `admin_bar.home_url`   | 左端の行き先（公開側ではダッシュボード、管理画面ではトップページ）    |
| `admin_bar.home_label` | 左端の名前（「ダッシュボード」か「ブログを表示」）                    |
| `admin_bar.new_article`| 新しい記事のURL                                                       |
| `admin_bar.new_page`   | 新しいコンテンツページのURL                                           |
| `admin_bar.comments`   | コメントの一覧のURL（新着があればすべての一覧、無くて承認待ちがあれば承認待ちの一覧） |
| `admin_bar.held_count` | 承認待ちのコメントの数                                                |
| `admin_bar.new_count`  | 新着のコメントの数（`docs/admin.md`の「新着のコメント」）             |
| `admin_bar.edit`       | 今のページの編集の画面のURL（記事とコンテンツページだけ）             |
| `admin_bar.logout`     | ログアウトのURL（POSTで送る）                                        |
| `admin_bar.csrf_token` | ログアウトのフォームに入れるCSRFのトークン                          |

#### コメント

`article.comments`の要素。

| 変数          | 中身                                         |
| ------------- | -------------------------------------------- |
| `num`         | コメントの番号（`id="cN"`に使う）           |
| `author_name` | 名前                                         |
| `by_admin`    | 管理者が書いたものなら真                     |
| `created`     | 投稿日時（日時の形）                         |
| `html`        | 本文のHTML。`raw`で出す                     |

#### コメントのフォーム

`article.comment_form`。

| 変数       | 中身                                                                     |
| ---------- | ------------------------------------------------------------------------ |
| `open`     | フォームを出すなら真。偽のときは`notice`だけを出す                     |
| `notice`   | 投稿した後の知らせ（承認待ちなど）                                       |
| `action`   | 送り先のURL                                                              |
| `token`    | フォームのトークン                                                       |
| `js_token` | 真なら、トークンをJavaScript（`script`）で入れる                        |
| `script`   | `comment.js`のURL                                                       |
| `admin`    | 管理者として書くなら真                                                   |
| `name`、`body` | 入力欄に戻す値                                                       |
| `errors`   | 誤りの理由（文字列）の配列                                               |

## 管理画面

`Lyndbaum::App->render_admin`が、ページのテンプレート（`admin_*.html`）を出力し、それを`admin_layout.html`で包む。

すべてのページで使える変数は次のもの。

| 変数         | 中身                                                           |
| ------------ | -------------------------------------------------------------- |
| `blog`       | ブログの設定（公開側と同じ）                                   |
| `urls`       | 管理画面の各ページのURL（`admin`、`articles`、`new_article`、`new_page`、`trash`、`tags`、`media`、`comments`、`blog_settings`、`comment_settings`、`editor_settings`、`sidebar`、`rebuild`、`logout`など）と、`top`、`style`（`common.css`）、`admin_style`（`admin.css`。`style`の後に読む）、`admin_script`、`media_script`、`unsaved_script` |
| `logged_in`  | ログインしていれば1                                           |
| `csrf_token` | フォームに入れるCSRFのトークン。ログインしていなければ空      |
| `content`    | ページのテンプレートの出力（`admin_layout.html`だけ）         |
| `admin_bar`  | 上の管理者のメニュー（公開側の「admin_bar」と同じ形。`home_url`はトップページ、`home_label`は「ブログを表示」）。ログインしていなければ空 |
| `admin_menu` | 左のナビ（下の表）。ログインしていなければ空                   |

`admin_menu`の要素。

| 変数       | 中身                                                                 |
| ---------- | -------------------------------------------------------------------- |
| `key`      | 項目の名前（`dashboard`、`articles`、`settings`など）               |
| `label`    | 表示する名前                                                         |
| `url`      | 行き先                                                               |
| `count`    | 件数（コメントの承認待ち）。無ければ空                               |
| `new_count` | 新着のコメントの数（コメントの項目だけ）。無ければ空                |
| `current`  | 今のページがこの項目か、その子なら真                                 |
| `children` | 子の配列（今のページがこの項目の子のときだけ。ほかは空）。要素は`key`、`label`、`url`、`current` |

今のページは、テンプレートの名前から決める（`Lyndbaum::App`の`%NAV_OF`）。同じテンプレートで複数の項目にあたるページ（設定、記事の編集）は、コントローラが`render_admin`に`nav`を渡す。

ページごとの変数は、そのページを出すコントローラ（`lib/Lyndbaum/Controller/Admin*.pm`）の`render_admin`の呼び出しを見る。

### 選択肢と「直接入力」の欄（`preset_field.html`）

数を選択肢から選び、「直接入力」を選んだときだけ数を入れる欄を出す部品（サムネイルの大きさ）。「直接入力」の欄を出し入れするのは`admin.js`。
値は`Lyndbaum::SettingsForm->preset_field`で作り、`for`の変数`preset`で渡す（例：`{{# for preset in field.preset }}{{> preset_field }}{{/ for }}`）。

| 変数             | 中身                                                                   |
| ---------------- | ---------------------------------------------------------------------- |
| `preset.name`    | フォームの項目名。選択肢は`name`、入力欄は`name_other`で送る。空ならフォームで送らない（記事の編集の画面のアップロードの欄。`admin-article.js`が読む） |
| `preset.label`   | 欄の名前（`aria-label`に使う）                                        |
| `preset.options` | 選択肢の配列。要素は`value`（数か`other`）、`label`、`selected`        |
| `preset.other`   | 「直接入力」を選んでいれば真（入力欄を出す）                           |
| `preset.value`、`preset.min`、`preset.max`、`preset.unit` | 入力欄の値、範囲、後ろに付ける単位          |

使う場所は、編集の設定（`admin_settings.html`の`field.preset`）と、記事の編集の画面のアップロードの欄（`admin_article_form.html`の`thumbnail_preset`）。
管理画面のフォームには、必ず`<input type="hidden" name="csrf_token" value="{{ csrf_token }}">`を入れる（`docs/admin.md`）。
