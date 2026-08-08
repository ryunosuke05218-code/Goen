-- =====================================================================
-- migration 0006: persons_read.created_at 追加（F-003 登録順ソート用）
--
-- 背景: 人物一覧のソート順に「登録順」を追加するにあたり、persons_readは
--       参照専用モデルのため元のpersons.created_atを非正規化して持たせる
--       （persons本体への結合を発生させないため）。
--
-- 実行方法:
--   psql -U postgres -d GOEN -f db/migrations/0006_persons_read_created_at.sql
-- =====================================================================

ALTER TABLE persons_read ADD COLUMN IF NOT EXISTS created_at timestamptz;

-- 既存行のバックフィル
UPDATE persons_read pr
SET created_at = p.created_at
FROM persons p
WHERE pr.person_id = p.person_id AND pr.created_at IS NULL;
