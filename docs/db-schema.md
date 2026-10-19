# DBスキーマ設計

定義そのものは`db/migrations/*.sql`にある。この文書は、その設計の理由と、主なクエリ、旧データからの移行の対応をまとめる。

## サイドバーのHTMLキャッシュ

`0001_init.sql`に`sidebar_cache`と無効化用トリガーを含める。開発版のためスキーマは`0001`にまとめ、初期スキーマを直接更新する。適用済みの`0001`の変更は`migrate.pl`では再実行されない。

- `sidebar_cache`は1行で、`cache_key`、`tags_html`、`menu_html`を持つ。検索フォームと管理者情報は保存しない。
- 記事・タグ・閉包テーブル・記事タグ対応・コメント・設定の変更でキャッシュを削除する。トリガーによる削除は元データと一緒にロールバックされる。記事とコメントは、サイドバーに出す列が変わったときだけ削除する（記事の本文やその変換結果、コメントの本文の更新では削除しない）。
- POST処理の終了時に、削除されたHTMLを再生成する。インポート・再構築ツールも終了時に生成する。直接SQLを使った場合は次の閲覧で生成する。
- 閲覧時は有効な行を読み出すだけ。初回・テンプレート変更・URL設定変更時は生成する。生成には即時トランザクションを使い、古い集計結果で新しい更新を上書きしない。ほかの接続が書き込み中などで保存できないときは、警告を出し、保存せずにその場で生成して表示する。POST処理の終了時の再生成に失敗しても、更新の結果はそのまま返す（次の閲覧で生成する）。
- キーにはルート、`base_path`、描画に使うファイルの更新情報を含める。依存ファイルを増やしたときは`SidebarCache.pm`の`@SOURCES`も更新する。
- 手動で作り直すときは`perl tools/rebuild-sidebar.pl [設定ファイル]`。元データを削除する必要はない。

## 参照元（バックリンク）

記事のページに、その記事へリンクしている記事の一覧（参照元）を出す。テンプレートと数えるリンクは`docs/templates.md`の「参照元」。

- `article_links`は、記事ごとに本文のリンク先のslugを持つ。本文を変換するとき（保存と再構築）に入れ直す。リンク先をIDではなくslugで持つのは、まだ無い記事やページへのリンクも持っておき、後でその記事ができたときに参照元に出すため
- 表示用のHTMLは`articles.backlinks_html`に持つ。NULLなら作り直しが要る印
- 印はトリガーが付ける。リンクの追加と削除ではリンク先の記事、リンク元の記事の題名、状態、公開日時、ゴミ箱、種類の変更ではそのリンク先の記事、slugの変更ではその記事自身。完全に削除した記事のリンクは`ON DELETE CASCADE`で消え、削除のトリガーが印を付ける
- POST処理の終了時に、印の付いた記事の分を作る。再構築・取り込みでは、テンプレートの変更も反映するよう全記事の分を作り直す。直接SQLを使った場合は次の閲覧で作る

## 全体の方針

- SQLite（さくらのレンタルサーバーにプリインストールされたDBD::SQLite）を使う
- 接続ごとに`PRAGMA foreign_keys = ON;`を実行する。SQLiteは既定で外部キーの制約を確認しない
- ジャーナルモードは既定（DELETE）のままにする。WALはネットワークファイルシステム上で問題が起きることがあり、レンタルサーバーでは避ける
- 書き込みが重なったときのために、`busy_timeout`（例：5秒）を設定する
- 日時はUNIX時刻（秒）の整数で持つ。表示時にAsia/Tokyoで整形する
- 新しめのSQLiteの機能（STRICTテーブル、RETURNINGなど）は使わない。挿入したIDは`last_insert_id`で取る
- スキーマのバージョンは`PRAGMA user_version`で管理する。マイグレーションは`db/migrations/NNNN_*.sql`を番号順に、未適用のものだけ流す

## テーブル一覧

| テーブル             | 内容                                                                 |
| -------------------- | -------------------------------------------------------------------- |
| `articles`           | 記事とコンテンツページ。下書きとゴミ箱も同じテーブルで状態として持つ |
| `article_search`     | 検索用のテキスト（記事ごとに1行）                                    |
| `tags`               | タグ。親子関係を持つ                                                 |
| `tag_paths`          | タグの祖先と子孫の組（閉包テーブル）                                 |
| `article_tags`       | 記事とタグの対応（N:M）                                              |
| `comments`           | コメント                                                             |
| `revisions`          | 記事の更新履歴                                                       |
| `url_cache`          | `[&URL]`用の、外部ページのタイトルのキャッシュ                      |
| `settings`           | 管理画面から変えるブログの設定                                       |
| `admin` / `sessions` | 管理者のログインとセッション（`docs/admin.md`）                      |
| `login_failures`     | ログインの失敗の記録（続けて失敗したIPを止めるため）               |
| `sequences`          | 最後に使った番号（記事のIDを使い回さないため）                       |

## 設計の判断

### 記事（`articles`）

- **IDは旧データのpkeyをそのまま引き継ぐ。**旧URLからの転送や、記事間リンクを壊さないため
- **`slug`は旧`link_key`。** 記事は旧`link_key`（「0+記事ID」）のまま。コンテンツページは「親のslug/題名」にする（下の「コンテンツページ」）
- **原文（`body_src`）が正で、HTML（`body_html`）はキャッシュ。** HTMLは記事の保存時と再構築（全記事の一括変換）のときだけ作り、表示時には作り直さない。パーサーを直しても、再構築するまでは表示が変わらない
- **ゴミ箱は`deleted_at`で表す。**旧システムは別テーブルにコピーしていたが、同じテーブルで状態として持つ方が、戻す処理も履歴との関係も単純になる。ゴミ箱の記事のslugも残るので、戻すときにslugがぶつかることはない（その代わり、ゴミ箱にある記事のslugは新しいページに使えない）
- **記事のIDは使い回さない。**完全に削除した記事のIDも使わない（旧システムと同じ）。最後に使ったIDは`sequences`に持つ。`MAX(id) + 1`では、いちばん新しい記事を完全に削除すると、そのIDとURLが次の記事に使われるため
- **下書きと公開は`status`で表す。**予約投稿は「`status = 'published'`かつ`published_at`が未来」で表現できるので、列を増やさない（必要になったときに一覧のクエリへ`published_at <= 現在時刻`を足す）
- 続きを読むは、HTMLの中の区切りで分けるので列を持たない

### 記法（`syntax`）

- 今は`markdown`だけだが、将来ほかの記法を足せるように、記事ごとに記法を持つ
- 値はアプリ側の「パーサー登録表」のキーにする。記法を足すときは、パーサーを登録するだけでスキーマは変えない（そのためCHECK制約を付けない）
- 記法をまたぐ処理（目次、続きを読む、検索用テキストの抽出、adiary独自タグ）は、パーサーの共通部品にしておくと、記法を足すときに作り直さずに済む

### コンテンツページ（`kind` / `parent_id` / `sort_order`）

- 旧システムの「コンテンツページ」を、記事の一種（`kind = 'page'`）として同じテーブルに持つ。本文、タグ、コメント、履歴、ゴミ箱の仕組みを記事と共有できる
- コンテンツは木構造のメニューとして並ぶ。親は`parent_id`、同じ親の中の順番は`sort_order`
- `slug`は「親のslug/題名」（親が無ければ題名）。題名と別には付けられない。題名に`/ \ ? # %`と制御文字は使えず、100文字まで。親の無いページは0で始められず、`search`・`pub`・`admin`にもできない（`Lyndbaum::Model::Article->page_name_errors`）
- コンテンツページは時系列の記事一覧には出さない。タグ検索と文字列検索には出す
- ブログのトップに固定表示するページは、`settings`に`front_page_id`（記事のID）として持つ。旧システムで、コンテンツkeyを`FrontPage` / `top` / `index`にしていたもの
- 親を消しても子は消えず、最上位に移る（`ON DELETE SET NULL`）。ゴミ箱に入れただけでは親子関係は変わらないので、木を表示するときは`deleted_at`を見て除く

### コメント（`comments`）

- 記事ごとに、コメントの受付（`comments_open`）を切り替えられる。ブログ全体の受付や承認制の設定は`settings`に置く
- 状態は2つ
  - `public`：公開
  - `held`：保留・非表示。承認制で承認待ちのもの、管理者が非表示にしたもの
- 非公開コメント（管理者だけが読めるコメント）は扱わない。旧データにある非公開コメントも取り込まない（公開できない内容を含むため）
- `num`は記事内の通し番号（#1, #2 …）。コメントを消しても番号は詰めず、使い回しもしない。最後に使った番号は`articles.last_comment_num`に持つ（`MAX(num) + 1`では、いちばん新しいコメントを消すと番号が戻るため）
- 本文はプレーンテキストの原文で持ち、表示時にエスケープする。表示と投稿の決まりは`docs/comments.md`
- 件数は記事側に持たず、毎回数える。記事が数千件程度なら、索引があれば十分速い
- IP、ホスト、ユーザーエージェントは、スパム対策と連投の制限のためだけに持ち、表示しない
- 記事を（ゴミ箱からも）完全に消すと、コメントも消える

### 検索（`article_search`）

- 検索の範囲ごとに列を持つ。どれも**正規化して**保存する
  - `title`：タイトル
  - `text`：タイトルと、本文からマークアップを除いたテキスト、画像の代替テキスト（範囲が「本文」のとき）
  - `source`：タイトルと原文（範囲が「原文」のとき。URL、動画のID、記法を含めて探せる）
- 本文を変換するときに作る（記事の保存時と再構築のとき）
  - 正規化はUnicode NFKC（標準ライブラリのUnicode::Normalize）と小文字化。全角英数と半角英数、大文字と小文字の違いを吸収できる
  - 検索語にも同じ正規化をかけてから`LIKE '%語%' ESCAPE '\'`で探す。`%` `_` `\`はエスケープする
- 記事本体と別テーブルにしたのは、将来FTS5（trigram）に移るとき、このテーブルだけを置き換えれば済むようにするため

### タグ（`tags` / `tag_paths` / `article_tags`）

- 親子関係は`parent_id`で持つ
- **タグ名は末端の名前で持ち、同じ親の中で一意にする。**「料理::調味料」と「料理::食材::調味料」のように、親が違えば同じ名前を付けられる
  - 旧システムは`料理::食材::調味料`のように親を含めた名前で持っていたが、末端の名前だけで見ると重複がある（「その他」「セキュリティ」「調味料」）
  - 親を含めた名前は、親をたどって組み立てる。親の名前を変えても子を書き換えずに済む
  - 最上位のタグ（`parent_id`がNULL）同士の重複も防ぐため、一意性は`COALESCE(parent_id, 0)`と`name`の式の索引で取る
- **子孫を含む検索と、ファセットの件数のために、閉包テーブル`tag_paths`を持つ**
  - 自分自身も`depth = 0`で入れておくと、「このタグか、その子孫」が`ancestor = ?`一つで書ける
  - タグを追加・移動・削除したら、**全件を作り直す**。タグは多くても数百件なので一瞬で終わり、差分更新より壊れにくい（下の「タグの閉包テーブルの作り直し」）
- 記事が付いているタグは削除できない（`ON DELETE RESTRICT`）。先に付け替えるか外す

## 主なクエリ

### 公開記事の一覧

```sql
SELECT id, slug, title, published_at
FROM articles
WHERE kind = 'post' AND status = 'published' AND deleted_at IS NULL
ORDER BY published_at DESC
LIMIT ? OFFSET ?;
```

### コンテンツの木

```sql
WITH RECURSIVE tree (id, title, slug, depth, path) AS (
    SELECT id, title, slug, 0, printf('%05d', sort_order)
    FROM articles
    WHERE kind = 'page' AND parent_id IS NULL
      AND status = 'published' AND deleted_at IS NULL
    UNION ALL
    SELECT a.id, a.title, a.slug, tree.depth + 1,
           tree.path || '/' || printf('%05d', a.sort_order)
    FROM articles a JOIN tree ON a.parent_id = tree.id
    WHERE a.status = 'published' AND a.deleted_at IS NULL
)
SELECT id, title, slug, depth FROM tree ORDER BY path;
```

`path`で並べると、木を深さ優先の順で、そのままメニューとして出力できる。

### タグの閉包テーブルの作り直し

```sql
DELETE FROM tag_paths;
WITH RECURSIVE p (ancestor, descendant, depth) AS (
    SELECT id, id, 0 FROM tags
    UNION ALL
    SELECT p.ancestor, t.id, p.depth + 1
    FROM p JOIN tags t ON t.parent_id = p.descendant
)
INSERT INTO tag_paths SELECT ancestor, descendant, depth FROM p;
```

タグの移動で親子が循環しないことは、アプリ側で移動前に確認する（移動先が自分の子孫でないこと）。

### ファセット検索

選んだタグすべてに（子孫タグを含めて）当てはまり、検索語も含む記事を絞り込み、その結果に対してタグごとの件数を数える。選んだタグがN個なら、プレースホルダもN個にして、最後の`?`にNを入れる。

```sql
WITH hit AS (
    SELECT a.id
    FROM articles a
    WHERE a.kind IN ('post', 'page')
      AND a.status = 'published' AND a.deleted_at IS NULL
      -- 選んだタグ（ここでは2個）すべてに当てはまる
      AND (SELECT COUNT(DISTINCT tp.ancestor)
           FROM article_tags at
           JOIN tag_paths tp ON tp.descendant = at.tag_id
           WHERE at.article_id = a.id
             AND tp.ancestor IN (?, ?)) = ?
      -- 検索語（ないときはこの条件ごと外す）
      AND a.id IN (SELECT article_id FROM article_search
                   WHERE text LIKE ? ESCAPE '\')
)
SELECT tp.ancestor AS tag_id, COUNT(DISTINCT at.article_id) AS cnt
FROM hit
JOIN article_tags at ON at.article_id = hit.id
JOIN tag_paths tp    ON tp.descendant = at.tag_id
GROUP BY tp.ancestor;
```

記事の一覧は`hit`から`published_at`の順に取る。件数は親タグに子孫の分も含まれる（「技術」に「Perl」の記事も数えられる）。

このクエリとコンテンツの木のクエリは、サンプルデータ（階層タグ、下書き、ゴミ箱、タグなしの記事、入れ子のコンテンツとリンク項目を含む）で結果が正しいことを確認済み。

## 旧データからの移行

旧システムのテキストDBから、次のように対応させる。

| 旧                                                    | 新                                                | 備考                                                                                                                                                           |
| ----------------------------------------------------- | ------------------------------------------------- | -------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| 記事`pkey`                                           | `articles.id`                                     | そのまま                                                                                                                                                       |
| `link_key`                                            | `articles.slug`                                   | 記事はそのまま。コンテンツページは使わず、「親のslug/題名」を作る。題名がURLに使えないときや、URLがぶつかるときは取り込みを止める                                   |
| `title`                                               | `articles.title`                                  |                                                                                                                                                                |
| `_text`（原文）                                       | `articles.body_src`                               |                                                                                                                                                                |
| `parser`                                              | `articles.syntax`                                 |                                                                                                                                                                |
| `text` / `text_s`（変換済みHTML）                     | 移さない                                          | 新しいパーサーで作り直す                                                                                                                                       |
| `enable`                                              | `articles.status`                                 | 1 → `published`、0 → `draft`                                                                                                                                   |
| `yyyymmdd`（記事の日付）と`tm`                       | `articles.published_at`                           | 日付は`yyyymmdd`、時刻は`tm`の時刻（日本時間）。旧システムは`yyyymmdd`を投稿日として表示する。`tm`はほかのシステムから移した記事では移した日になっている |
| `tm`                                                  | `articles.created_at`                             | 無ければ`update_tm`                                                                                                                                           |
| `update_tm`                                           | `articles.updated_at`                             |                                                                                                                                                                |
| `main_image`                                          | `articles.eyecatch`                               |                                                                                                                                                                |
| `description`                                         | `articles.description`                            |                                                                                                                                                                |
| `tags`（記事側の文字列）                              | `article_tags`                                    | 親を含めたタグ名のカンマ区切り。名前からタグの`pkey`を引く                                                                                                   |
| タグ`pkey` / `name` / `upnode` / `priority`          | `tags.id` / `name` / `parent_id` / `sort_order`   | `name`は最後の`::`より後ろだけを取る。`upnode`が空ならNULL                                                                                                |
| タグ`qt`（記事数）                                   | 移さない                                          | 毎回数える                                                                                                                                                     |
| `tagart`                                              | 移さない                                          | 付け直す前の古い行や重複、削除済みタグへの参照が残っているため、記事の`tags`を使う                                                                           |
| `ctype`が空でない記事                                | `kind = 'page'`                                   | コンテンツページ                                                                                                                                               |
| コンテンツkeyが`http://` `https://` `/`で始まるもの | 移さない                                          | 実データに無い。来たら取り込みを止める                                                                                                                         |
| コンテンツkeyが`FrontPage` / `top` / `index`のもの  | `kind = 'page'`と`settings.front_page_id`       |                                                                                                                                                                |
| 記事`upnode` / `priority`                            | `articles.parent_id` / `sort_order`               | `upnode`が0ならNULL                                                                                                                                        |
| 記事`tm`がない（下書き）                            | `articles.published_at`をNULL                   |                                                                                                                                                                |
| `com_ok`                                              | `comments_open`                                   |                                                                                                                                                                |
| `hcom_ok`                                             | 移さない                                          | 非公開コメントは扱わない                                                                                                                                       |
| `coms` / `coms_all`（コメント数）                     | 移さない                                          | 毎回数える                                                                                                                                                     |
| コメント`pkey` / `a_pkey` / `num`                    | `comments.id` / `article_id` / `num`              |                                                                                                                                                                |
| コメント`name` / `text`                              | `author_name` / `body`                            | 旧データはHTMLエスケープ済みで、改行は`<br>`。原文に戻して入れる                                                                                              |
| コメント`enable` / `hidden`                          | `comments.status`                                 | `hidden` = 1は取り込まない（非公開コメント）。`enable` = 1 → `public`、それ以外 → `held`                                                                      |
| コメント`id`（ログインユーザー）                     | `comments.by_admin`                               | 値があれば1                                                                                                                                                   |
| コメント`ip` / `host` / `agent` / `tm`               | `ip` / `host` / `user_agent` / `created_at`       |                                                                                                                                                                |
| 更新履歴`_rev`                                       | `revisions`                                       |                                                                                                                                                                |
| ゴミ箱`_trash` / `_trashcom`                         | `articles`（`deleted_at`に削除日時）/ `comments` |                                                                                                                                                                |

移行後に`article_search`と`tag_paths`を作り、全記事の`body_html`を生成する。

## 未決事項

- **画像**：今は画像をファイルとして置くだけで、DBに持たない。アップロード一覧などで不便が出たら、`media`テーブルを足す
- **URLの体系**：決まったら、旧URLとの対応に追加のテーブルが要るかを判断する
