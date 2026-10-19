-- 0001_init.sql
-- 初期スキーマ
--   初回のリリースの前に、それまでの 0001〜0007 を1つにまとめた（作者の了承を得て）
--   正式リリースまでは、このファイルを直接直す（作者の了承を得て）。正式リリースより後の変更は、0002 から新しいファイルとして足す
--
-- 前提：
--   - 接続ごとに PRAGMA foreign_keys = ON; を実行する（SQLiteは既定で無効）
--   - 日時はすべて UNIX 時刻（秒、INTEGER）で持ち、表示時にタイムゾーンを適用する
--   - STRICT テーブル（3.37以降）や RETURNING（3.35以降）は使わない
--     さくらの DBD::SQLite に同梱された SQLite のバージョンに依存しないため
--   - スキーマのバージョンは PRAGMA user_version で管理する

--------------------------------------------------------------------------------
-- 記事
--------------------------------------------------------------------------------
CREATE TABLE articles (
    id            INTEGER PRIMARY KEY,          -- 旧 pkey をそのまま引き継ぐ
    kind          TEXT    NOT NULL DEFAULT 'post'
                  CHECK (kind IN ('post', 'page')),
                  -- post: 通常の記事（時系列の一覧に出る）
                  -- page: コンテンツページ（木構造のメニューに並ぶ。時系列の一覧には出ない）
    slug          TEXT    NOT NULL UNIQUE,      -- URL に使うキー（旧 link_key）
    title         TEXT    NOT NULL DEFAULT '',
    syntax        TEXT    NOT NULL DEFAULT 'markdown',
                  -- 本文の記法。値はアプリ側のパーサー登録表のキー。
                  -- 今は markdown のみだが、記法を足すときにスキーマを変えずに済むよう CHECK は付けない
    body_src      TEXT    NOT NULL DEFAULT '',  -- 本文（原文）。これが正
    body_html     TEXT,                         -- 変換済みHTML。保存時と再構築時に作る。NULLなら未変換
    description   TEXT    NOT NULL DEFAULT '',  -- OGP や meta description 用
    eyecatch      TEXT    NOT NULL DEFAULT '',  -- アイキャッチ（添付ファイルの中のパス。編集の画面でメディアから選んだもの）
                                                -- 空なら本文の最初の画像、それも無ければブログの画像（docs/ogp.md）
    status        TEXT    NOT NULL DEFAULT 'draft'
                  CHECK (status IN ('draft', 'published')),
    published_at  INTEGER,                      -- 公開日時（記事の日付）。下書きは NULL でもよい
    created_at    INTEGER NOT NULL,
    updated_at    INTEGER NOT NULL,
    deleted_at    INTEGER,                      -- ゴミ箱に入れた日時。NULL なら通常の記事

    -- コンテンツの木（kind が page のときに使う）
    parent_id     INTEGER REFERENCES articles (id) ON DELETE SET NULL,  -- NULL なら最上位
    sort_order    INTEGER NOT NULL DEFAULT 0,   -- 同じ親の中での並び順

    -- コメント
    comments_open     INTEGER NOT NULL DEFAULT 1 CHECK (comments_open IN (0, 1)),
    last_comment_num  INTEGER NOT NULL DEFAULT 0,
                      -- 最後に使ったコメントの番号。消したコメントの番号を次の投稿に使い回さないため
                      -- （MAX(num) + 1 では、いちばん新しいコメントを消すと番号が戻る）

    -- 参照元（この記事へリンクしている記事の一覧）の生成済みHTML。Lyndbaum::Backlinks が作る
    --   NULL なら作り直しが要る（下の article_links のトリガーが NULL にする）。参照元が無ければ空文字
    backlinks_html    TEXT,

    CHECK (parent_id IS NULL OR parent_id <> id)
);

-- 公開記事の時系列の一覧（新しい順）用
CREATE INDEX idx_articles_public
    ON articles (published_at DESC)
    WHERE kind = 'post' AND status = 'published' AND deleted_at IS NULL;

-- コンテンツの木の表示用
CREATE INDEX idx_articles_tree
    ON articles (parent_id, sort_order)
    WHERE kind = 'page';

-- 管理画面の一覧（下書き、ゴミ箱を含む）用
CREATE INDEX idx_articles_admin
    ON articles (deleted_at, updated_at DESC);

--------------------------------------------------------------------------------
-- 検索用テキスト
--   記事本体と分けておくのは、将来 FTS5 に差し替えるときに
--   このテーブルだけを置き換えれば済むようにするため
--------------------------------------------------------------------------------
--   検索の範囲（タイトル、本文、原文）ごとに列を持つ。どれも正規化したもの
CREATE TABLE article_search (
    article_id  INTEGER PRIMARY KEY
                REFERENCES articles (id) ON DELETE CASCADE,
    text        TEXT    NOT NULL,              -- タイトル＋本文からマークアップを除いたもの
    title       TEXT    NOT NULL DEFAULT '',   -- タイトル
    source      TEXT    NOT NULL DEFAULT ''    -- タイトル＋原文（Markdown）。URL、動画のID、記法を含めて探すときに使う
);

--------------------------------------------------------------------------------
-- タグ
--------------------------------------------------------------------------------
CREATE TABLE tags (
    id          INTEGER PRIMARY KEY,
    parent_id   INTEGER REFERENCES tags (id) ON DELETE RESTRICT,  -- NULL なら最上位
    name        TEXT    NOT NULL,  -- 末端の名前（「料理::調味料」なら「調味料」）。親が違えば同じ名前を付けられる
    sort_order  INTEGER NOT NULL DEFAULT 0,
    CHECK (parent_id IS NULL OR parent_id <> id)
);

CREATE INDEX idx_tags_parent ON tags (parent_id, sort_order);

-- 同じ親の中でタグ名は一意
--   UNIQUE (parent_id, name) では、parent_id が NULL の最上位のタグ同士の重複を防げないため、式で索引を作る
CREATE UNIQUE INDEX idx_tags_name ON tags (COALESCE(parent_id, 0), name);

-- タグの祖先・子孫の組（閉包テーブル）
--   自分自身も depth = 0 で入れる
--   タグの追加・移動・削除のたびに、アプリ側で全件を作り直す
--   （タグは多くても数百件なので、全件作り直しで十分速く、一番壊れにくい）
CREATE TABLE tag_paths (
    ancestor    INTEGER NOT NULL REFERENCES tags (id) ON DELETE CASCADE,
    descendant  INTEGER NOT NULL REFERENCES tags (id) ON DELETE CASCADE,
    depth       INTEGER NOT NULL,
    PRIMARY KEY (ancestor, descendant)
) WITHOUT ROWID;

CREATE INDEX idx_tag_paths_descendant ON tag_paths (descendant, ancestor);

-- 記事とタグの対応（N:M）
CREATE TABLE article_tags (
    article_id  INTEGER NOT NULL REFERENCES articles (id) ON DELETE CASCADE,
    tag_id      INTEGER NOT NULL REFERENCES tags (id)     ON DELETE RESTRICT,
    PRIMARY KEY (article_id, tag_id)
) WITHOUT ROWID;

CREATE INDEX idx_article_tags_tag ON article_tags (tag_id, article_id);

--------------------------------------------------------------------------------
-- コメント
--   件数は記事側に持たず、毎回数える
--------------------------------------------------------------------------------
CREATE TABLE comments (
    id           INTEGER PRIMARY KEY,
    article_id   INTEGER NOT NULL REFERENCES articles (id) ON DELETE CASCADE,
    num          INTEGER NOT NULL,             -- 記事内での通し番号（#1, #2 ...）。削除しても詰めない
    status       TEXT    NOT NULL DEFAULT 'public'
                 CHECK (status IN ('public', 'held')),
                 -- public:  公開
                 -- held:    保留・非表示（承認待ち、または管理者が非表示にしたもの）
                 -- 非公開コメント（管理者だけが読めるコメント）は扱わない
    by_admin     INTEGER NOT NULL DEFAULT 0 CHECK (by_admin IN (0, 1)),  -- 管理者が書いたコメント
    author_name  TEXT    NOT NULL,
    body         TEXT    NOT NULL,             -- 原文（プレーンテキスト）。表示時にエスケープする
    ip           TEXT    NOT NULL DEFAULT '',  -- スパム対策用。公開しない
    host         TEXT    NOT NULL DEFAULT '',
    user_agent   TEXT    NOT NULL DEFAULT '',
    created_at   INTEGER NOT NULL,
    UNIQUE (article_id, num)
);

CREATE INDEX idx_comments_article ON comments (article_id, status, num);
CREATE INDEX idx_comments_recent  ON comments (created_at DESC);  -- 管理画面と「最近のコメント」用
CREATE INDEX idx_comments_ip      ON comments (ip, created_at);   -- 連投の制限用

--------------------------------------------------------------------------------
-- 更新履歴
--   題名か本文が変わる保存のときに、保存前の版を1件追加する（間隔と件数は設定。docs/admin.md の「更新履歴」）
--------------------------------------------------------------------------------
CREATE TABLE revisions (
    id          INTEGER PRIMARY KEY,
    article_id  INTEGER NOT NULL REFERENCES articles (id) ON DELETE CASCADE,
    title       TEXT    NOT NULL,
    body_src    TEXT    NOT NULL,
    saved_at    INTEGER NOT NULL,             -- その版が保存された日時（版の中身の日時）
    created_at  INTEGER NOT NULL DEFAULT 0    -- 履歴に加えた日時。前に履歴を残してから設定の間隔が過ぎたかを見る
);

CREATE INDEX idx_revisions_article ON revisions (article_id, created_at DESC);

--------------------------------------------------------------------------------
-- 記事間のリンク（参照元の表示用）
--   本文の [文字](slug) の形のリンク（# や ? の付いたもの、画像は除く）を、本文を変換するときに入れ直す
--   リンク先は slug で持つ。まだ無い記事やページへのリンクも持っておき、表示するときに記事と突き合わせる
--------------------------------------------------------------------------------
CREATE TABLE article_links (
    source_id    INTEGER NOT NULL REFERENCES articles (id) ON DELETE CASCADE,  -- リンクしている記事
    target_slug  TEXT    NOT NULL,                                             -- リンク先の slug
    PRIMARY KEY (source_id, target_slug)
) WITHOUT ROWID;

CREATE INDEX idx_article_links_target ON article_links (target_slug, source_id);

-- 参照元のHTMLを作り直す記事に印を付ける（backlinks_html を NULL にする）。作り直すのは Lyndbaum::Backlinks->rebuild
--   リンクが増えたり減ったりしたら、リンク先の記事
CREATE TRIGGER backlinks_links_insert
AFTER INSERT ON article_links
BEGIN
    UPDATE articles SET backlinks_html = NULL WHERE slug = NEW.target_slug;
END;

CREATE TRIGGER backlinks_links_delete
AFTER DELETE ON article_links
BEGIN
    UPDATE articles SET backlinks_html = NULL WHERE slug = OLD.target_slug;
END;

--   リンクしている記事の、参照元に出るかどうか（状態、ゴミ箱）、題名、並び順（公開日時）が変わったら、そのリンク先の記事
CREATE TRIGGER backlinks_source_update
AFTER UPDATE OF kind, title, status, published_at, deleted_at ON articles
BEGIN
    UPDATE articles SET backlinks_html = NULL
    WHERE slug IN (SELECT target_slug FROM article_links WHERE source_id = NEW.id);
END;

--   slug が変わったら（コンテンツページの名前や親を変えたとき）、その記事。リンクしてくる記事が変わる
CREATE TRIGGER backlinks_target_slug
AFTER UPDATE OF slug ON articles
BEGIN
    UPDATE articles SET backlinks_html = NULL WHERE id = NEW.id;
END;

--------------------------------------------------------------------------------
-- 外部URLの情報のキャッシュ（[&URL] の埋め込み用）
--   記事の保存時に取得し、表示時は読むだけにする
--------------------------------------------------------------------------------
CREATE TABLE url_cache (
    url         TEXT    PRIMARY KEY,
    title       TEXT,
    fetched_at  INTEGER NOT NULL,
    ok          INTEGER NOT NULL DEFAULT 1   -- 取得に失敗したら 0（再取得の判断に使う）
) WITHOUT ROWID;

--------------------------------------------------------------------------------
-- ブログの設定（管理画面から変えるもの）
--   値は文字列か JSON。設定ファイルに置くもの（DBの場所、秘密鍵など）はここに入れない
--------------------------------------------------------------------------------
CREATE TABLE settings (
    key    TEXT PRIMARY KEY,
    value  TEXT NOT NULL
) WITHOUT ROWID;

--------------------------------------------------------------------------------
-- 管理者のログイン
--   単一ユーザーなので管理者は1行だけ
--------------------------------------------------------------------------------
CREATE TABLE admin (
    id             INTEGER PRIMARY KEY CHECK (id = 1),
    login          TEXT    NOT NULL,
    password_hash  TEXT    NOT NULL,   -- アルゴリズム、反復回数、ソルト、ハッシュを含む文字列
    updated_at     INTEGER NOT NULL
);

CREATE TABLE sessions (
    token_hash  TEXT    PRIMARY KEY,   -- Cookie の値そのものではなく、そのハッシュを保存する
    csrf_token  TEXT    NOT NULL,
    created_at  INTEGER NOT NULL,
    expires_at  INTEGER NOT NULL
) WITHOUT ROWID;

CREATE INDEX idx_sessions_expires ON sessions (expires_at);

-- ログインの失敗の記録
--   同じ IP から短い間に何度も失敗したら、しばらくログインを受け付けない
--   古い行は、記録するときに消す
CREATE TABLE login_failures (
    ip         TEXT    NOT NULL,
    failed_at  INTEGER NOT NULL
);

CREATE INDEX idx_login_failures ON login_failures (ip, failed_at);

--------------------------------------------------------------------------------
-- 最後に使った番号
--   記事のIDを使い回さないため（旧システムと同じく、完全に削除した記事のIDも使わない）
--   MAX(id) + 1 では、いちばん新しい記事を完全に削除すると、そのIDと URL（/0 + ID）が次の記事に使われる
--------------------------------------------------------------------------------
CREATE TABLE sequences (
    name   TEXT    PRIMARY KEY,   -- articles：記事とコンテンツページのID
    value  INTEGER NOT NULL
) WITHOUT ROWID;

INSERT INTO sequences (name, value) VALUES ('articles', 0);

--------------------------------------------------------------------------------
-- サイドバーのHTMLキャッシュ
--------------------------------------------------------------------------------
-- サイドバーの生成済みHTML。データ更新時に無効化し、更新リクエストの終了時に再生成する
-- キャッシュの削除は元データと同じトランザクションなので、ロールバックも一緒に行われる
CREATE TABLE sidebar_cache (
    id           INTEGER PRIMARY KEY CHECK (id = 1),
    cache_key    TEXT NOT NULL,
    tags_html    TEXT NOT NULL,
    menu_html    TEXT NOT NULL
);

CREATE TRIGGER sidebar_cache_articles_insert
AFTER INSERT ON articles
BEGIN
    DELETE FROM sidebar_cache;
END;

CREATE TRIGGER sidebar_cache_articles_update
AFTER UPDATE OF kind, slug, title, status, published_at, deleted_at, parent_id, sort_order ON articles
BEGIN
    DELETE FROM sidebar_cache;
END;

CREATE TRIGGER sidebar_cache_articles_delete
AFTER DELETE ON articles
BEGIN
    DELETE FROM sidebar_cache;
END;

CREATE TRIGGER sidebar_cache_tags_insert
AFTER INSERT ON tags
BEGIN
    DELETE FROM sidebar_cache;
END;

CREATE TRIGGER sidebar_cache_tags_update
AFTER UPDATE ON tags
BEGIN
    DELETE FROM sidebar_cache;
END;

CREATE TRIGGER sidebar_cache_tags_delete
AFTER DELETE ON tags
BEGIN
    DELETE FROM sidebar_cache;
END;

CREATE TRIGGER sidebar_cache_tag_paths_insert
AFTER INSERT ON tag_paths
BEGIN
    DELETE FROM sidebar_cache;
END;

CREATE TRIGGER sidebar_cache_tag_paths_update
AFTER UPDATE ON tag_paths
BEGIN
    DELETE FROM sidebar_cache;
END;

CREATE TRIGGER sidebar_cache_tag_paths_delete
AFTER DELETE ON tag_paths
BEGIN
    DELETE FROM sidebar_cache;
END;

CREATE TRIGGER sidebar_cache_article_tags_insert
AFTER INSERT ON article_tags
BEGIN
    DELETE FROM sidebar_cache;
END;

CREATE TRIGGER sidebar_cache_article_tags_update
AFTER UPDATE ON article_tags
BEGIN
    DELETE FROM sidebar_cache;
END;

CREATE TRIGGER sidebar_cache_article_tags_delete
AFTER DELETE ON article_tags
BEGIN
    DELETE FROM sidebar_cache;
END;

CREATE TRIGGER sidebar_cache_comments_insert
AFTER INSERT ON comments
BEGIN
    DELETE FROM sidebar_cache;
END;

CREATE TRIGGER sidebar_cache_comments_update
AFTER UPDATE OF article_id, num, status, author_name, created_at ON comments
BEGIN
    DELETE FROM sidebar_cache;
END;

CREATE TRIGGER sidebar_cache_comments_delete
AFTER DELETE ON comments
BEGIN
    DELETE FROM sidebar_cache;
END;

CREATE TRIGGER sidebar_cache_settings_insert
AFTER INSERT ON settings
BEGIN
    DELETE FROM sidebar_cache;
END;

CREATE TRIGGER sidebar_cache_settings_update
AFTER UPDATE ON settings
BEGIN
    DELETE FROM sidebar_cache;
END;

CREATE TRIGGER sidebar_cache_settings_delete
AFTER DELETE ON settings
BEGIN
    DELETE FROM sidebar_cache;
END;

PRAGMA user_version = 1;
