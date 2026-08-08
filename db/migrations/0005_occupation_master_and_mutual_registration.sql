-- =====================================================================
-- migration 0005: 職種マスタ新設、相互人脈登録、AI人物カルテの追加ソース対応
--
-- 背景（要件定義書v1.8、テーブル設計書v1.7）:
--   ・F-006（人脈図）の階層グルーピングに使う「職種」を、業種と同様の静的マスタ化する（Q-011解消）
--   ・F-028（相互人脈登録）のON/OFF設定を保持する列をusersに追加する
--   ・F-010（AI人物カルテ）でHPリンク・資料ファイル等の追加ソースを記録する列をai_person_cardsに追加する
--
-- 対象: 既存DBに対して1回だけ実行する。
-- 注意: h_persons・h_users はカレント/履歴の列順を一致させる必要があるため再作成する
--       （fn_track_history()が位置ベースでINSERTするため。0004と同じ理由）。
--       本アプリはまだ本番データを持たないため、履歴データの喪失を許容する。
--
-- 実行方法:
--   psql -U postgres -d GOEN -f db/migrations/0005_occupation_master_and_mutual_registration.sql
-- =====================================================================

-- 1. 職種マスタを新設する
CREATE TABLE IF NOT EXISTS m_occupation_type (
  occupation_code varchar(10) PRIMARY KEY,
  occupation_name text NOT NULL,
  sort_order      integer NOT NULL DEFAULT 0,
  is_active       boolean NOT NULL DEFAULT true
);

-- 2. users.allow_mutual_registration を追加する
ALTER TABLE users ADD COLUMN IF NOT EXISTS allow_mutual_registration boolean NOT NULL DEFAULT true;

DROP TABLE IF EXISTS h_users CASCADE;
CREATE TABLE h_users (
  LIKE users INCLUDING DEFAULTS,
  history_id uuid NOT NULL DEFAULT gen_random_uuid(),
  operation  char(1) NOT NULL CHECK (operation IN ('U','D')),
  changed_at timestamptz NOT NULL DEFAULT now(),
  changed_by uuid
) PARTITION BY RANGE (changed_at);
ALTER TABLE h_users ADD PRIMARY KEY (history_id, changed_at);
CREATE INDEX ix_h_users_user_id ON h_users (user_id, changed_at DESC);

-- 3. persons.occupation_code を追加し、source_type の許容値に mutual_registration を追加する
ALTER TABLE persons ADD COLUMN IF NOT EXISTS occupation_code varchar(10) REFERENCES m_occupation_type(occupation_code);
CREATE INDEX IF NOT EXISTS ix_persons_occupation_code ON persons (occupation_code);

ALTER TABLE persons DROP CONSTRAINT IF EXISTS persons_source_type_check;
ALTER TABLE persons ADD CONSTRAINT persons_source_type_check
  CHECK (source_type IN ('card_ocr','manual','import','mutual_registration'));

DROP TABLE IF EXISTS h_persons CASCADE;
CREATE TABLE h_persons (
  LIKE persons INCLUDING DEFAULTS,
  history_id uuid NOT NULL DEFAULT gen_random_uuid(),
  operation  char(1) NOT NULL CHECK (operation IN ('U','D')),
  changed_at timestamptz NOT NULL DEFAULT now(),
  changed_by uuid
) PARTITION BY RANGE (changed_at);
ALTER TABLE h_persons ADD PRIMARY KEY (history_id, changed_at);
CREATE INDEX ix_h_persons_person_id ON h_persons (person_id, changed_at DESC);

-- h_users・h_persons のパーティションを作り直す（前月〜3か月先）
DO $$
DECLARE
  m date;
  tbl text;
BEGIN
  FOR tbl IN SELECT unnest(ARRAY['h_users', 'h_persons'])
  LOOP
    FOR m IN
      SELECT generate_series(
        date_trunc('month', current_date) - interval '1 month',
        date_trunc('month', current_date) + interval '3 month',
        interval '1 month'
      )::date
    LOOP
      PERFORM fn_ensure_month_partition(tbl, 'changed_at', m);
    END LOOP;
  END LOOP;
END $$;

-- 4. ai_person_cards.input_sources を追加する（履歴テーブルなしのため単純ALTERで足りる）
ALTER TABLE ai_person_cards ADD COLUMN IF NOT EXISTS input_sources jsonb NOT NULL DEFAULT '[]'::jsonb;

-- 5. persons_read.occupation_name を追加する（履歴テーブルなしのため単純ALTERで足りる）
ALTER TABLE persons_read ADD COLUMN IF NOT EXISTS occupation_name text;
