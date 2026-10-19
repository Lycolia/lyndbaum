-- 0002_index_public_articles.sql
-- 公開記事の抽出と並び順に合う索引
--
-- 0001 の部分索引 idx_articles_public は、統計（ANALYZE）が無いと選ばれず、
-- deleted_at で始まる idx_articles_admin が使われて、本文を含む結果の並べ替えが起きていた。
-- 等号で絞る列を先に並べた複合索引にすると、統計が無くても選ばれ、
--   - 時系列の一覧（kind = 'post'）は並べ替えが要らない
--   - 件数は索引だけで数えられる
--   - 検索とタグ（kind IN ('post', 'page')）も、索引だけで該当する記事を絞れる
-- 部分索引は不要になるので消す

DROP INDEX idx_articles_public;

CREATE INDEX idx_articles_public
    ON articles (status, deleted_at, kind, published_at DESC, id DESC);
