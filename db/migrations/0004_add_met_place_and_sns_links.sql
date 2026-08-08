-- =====================================================================
-- migration 0004: 人物登録への「どこで会ったか」欄・SNSリンク欄（複数追加可）の追加
--
-- 背景: 人物登録時に出会った場所を記録したい、SNSリンクを何個でも追加できるようにしたい、
--       という要望に対応する。
--   ・persons.met_place を新設し、初回接点の場所（例：「〇〇異業種交流会」）を保持する。
--     first_met_at（初回接点日）と対になる項目。
--   ・person_profiles.sns_accounts は既存列だが、これまでアプリからは未使用だった。
--     形式を「サービス名をキーとするオブジェクト」から「{label, url}の配列」へ変更し、
--     同じサービスの複数リンクや、名刺のQRコードから読み取った未分類のリンクも
--     何個でも追加できるようにする（F-007のQRコード読み取り結果もここに格納する）。
--
-- 対象: 既存DBに対して1回だけ実行する。
-- 注意: h_persons はカレント/履歴の列順を一致させる必要がある（fn_track_history()が位置ベースでINSERTするため）。
--       本アプリはまだ本番データを持たないため、h_persons は再作成する（履歴データは失われる）。
--
-- 実行方法:
--   psql -U postgres -d GOEN -f db/migrations/0004_add_met_place_and_sns_links.sql
-- =====================================================================

-- 1. persons.met_place を追加する
ALTER TABLE persons ADD COLUMN IF NOT EXISTS met_place text;

-- 2. h_persons を新しい列構成で作り直す（位置ベースINSERTの整合性を保つため）
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

-- persons側の trg_persons_history トリガはDROP TABLE h_persons CASCADEの対象外（別テーブルへのトリガのため）
-- で存続しており、再作成は不要（fn_track_history()は対象テーブル名を動的に解決するため、
-- h_personsを作り直すだけで新しい列構成に追従する）。

-- h_persons のパーティションを作り直す（前月〜3か月先）
DO $$
DECLARE
  m date;
BEGIN
  FOR m IN
    SELECT generate_series(
      date_trunc('month', current_date) - interval '1 month',
      date_trunc('month', current_date) + interval '3 month',
      interval '1 month'
    )::date
  LOOP
    PERFORM fn_ensure_month_partition('h_persons', 'changed_at', m);
  END LOOP;
END $$;

-- 3. person_profiles.sns_accounts の意味変更（オブジェクト→配列）。既定値・既存データを揃える
ALTER TABLE person_profiles ALTER COLUMN sns_accounts SET DEFAULT '[]'::jsonb;
UPDATE person_profiles SET sns_accounts = '[]'::jsonb WHERE sns_accounts = '{}'::jsonb;
