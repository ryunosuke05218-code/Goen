-- =====================================================================
-- migration 0016: rag_chunks を OpenAI text-embedding-3-small（1536次元）向けに再作成する
--
-- 背景: 埋め込みプロバイダをOllama(multilingual-e5-large, 1024次元)からOpenAI
--       (text-embedding-3-small, 1536次元)へ切り替えた際、migration 0001のコメントで
--       予告されていた「次元数変更に伴うrag_chunks再作成」が未実施のまま本番稼働しており、
--       全てのRAGインデックス投入がpgvectorの次元不一致エラー（expected 1024, not 1536）で
--       失敗し続けていた（rag_index_queueが全件failed、rag_chunksは常に0件）。
--       本マイグレーションで是正し、失敗滞留していたキュー項目を再実行対象に戻す。
--
-- 前提: rag_chunksは次元不一致で1件も書き込みに成功していないため、DROPしても実データの
--       損失は発生しない（本番で確認済み: 2026-08-30時点で0件）。
--
-- 実行方法:
--   psql -U postgres -d GOEN -f db/migrations/0016_rag_chunks_openai_1536.sql
-- =====================================================================

DROP TABLE IF EXISTS rag_chunks;

CREATE TABLE rag_chunks (
  chunk_id        uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  org_id          uuid NOT NULL,
  owner_user_id   uuid NOT NULL,
  person_id       uuid NOT NULL REFERENCES persons(person_id) ON DELETE CASCADE,
  visibility      text NOT NULL,
  source_type     text NOT NULL CHECK (source_type IN ('profile','card','transcript','note','need')),
  source_id       uuid NOT NULL,
  source_version  integer NOT NULL,
  chunk_no        integer NOT NULL,
  content         text NOT NULL,
  embedding       vector(1536) NOT NULL,
  embedding_model text NOT NULL,
  embedding_dim   integer NOT NULL,
  occurred_at     timestamptz,
  industry_code   varchar(10),
  pref_code       char(2),
  token_count     integer,
  created_at      timestamptz NOT NULL DEFAULT now()
);
CREATE UNIQUE INDEX ux_rag_chunks_source ON rag_chunks (source_type, source_id, chunk_no);
CREATE INDEX ix_rag_chunks_owner_person ON rag_chunks (owner_user_id, person_id);
CREATE INDEX ix_rag_chunks_owner_occurred ON rag_chunks (owner_user_id, occurred_at DESC);
CREATE INDEX ix_rag_chunks_embedding_hnsw ON rag_chunks
  USING hnsw (embedding vector_cosine_ops) WITH (m = 16, ef_construction = 64);
CREATE INDEX ix_rag_chunks_content_trgm ON rag_chunks USING gin (content gin_trgm_ops);

-- 次元不一致で失敗し続けていたキュー項目を再実行対象に戻す（RagIndexingWorkerが自動で拾い直す）。
UPDATE rag_index_queue SET status = 'pending', retry_count = 0, error_message = NULL WHERE status = 'failed';
