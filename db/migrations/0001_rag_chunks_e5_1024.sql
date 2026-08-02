-- =====================================================================
-- migration 0001: rag_chunks を multilingual-e5-large（1024次元）向けに再作成する
--
-- 対象: 既存DBに対して1回だけ実行する。
-- 前提: rag_chunks はこれまでアプリケーションから書き込まれたことがないテーブルのため
--       （RAG機能は本マイグレーションで初めて実装）、DROP しても実データの損失は発生しない。
--       もし既にrag_chunksへ何らかのデータを投入済みの場合は、実行前にバックアップすること。
--
-- 実行方法:
--   psql -U postgres -d GOEN -f db/migrations/0001_rag_chunks_e5_1024.sql
-- =====================================================================

DROP TABLE IF EXISTS rag_chunks;

-- 埋め込み次元数について: 開発環境は multilingual-e5-large（1024次元）を前提にする。
-- 本番でOpenAI text-embedding-3-small（1536次元）等の異なる次元のモデルへ切り替える場合、
-- ベクトル空間・次元数が異なり単純な値の変換はできないため、新しい次元のテーブルを作成して
-- 全チャンクを再埋め込みしたうえで切り替える（チャットモデルの切替とは異なりコード変更のみでは完結しない）。
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
  embedding       vector(1024) NOT NULL,
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
