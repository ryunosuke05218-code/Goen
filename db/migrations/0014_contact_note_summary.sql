-- =====================================================================
-- migration 0014: 接点メモ（contacts.note）のAI要約をDBに保持する
--
-- 背景:
--   接点詳細画面に「メモを要約する」ボタンを追加し、押下するたびにAIが接点メモを要約する。
--   毎回AIを呼び出すコスト・待ち時間を避けるため、生成結果はDBに保持し、次に画面を開いたときは
--   前回生成した要約をそのまま表示する（再要約したい場合のみボタンを再度押す）。
--
-- 注意: h_contacts はカレント/履歴の列順を一致させる必要がある（fn_track_history()が位置ベースで
--       INSERTするため）。本アプリはまだ本番データを持たないため、h_contacts は再作成する
--       （履歴データ＝監査ログのみが失われる。contacts本体の現在データは変更しない。
--       migration 0004/0007/0011/0012/0013と同じ方針）。
--       h_contacts の再作成は contacts への次のUPDATEより前に行うこと。
--
-- 実行方法:
--   psql -U postgres -d GOEN -f db/migrations/0014_contact_note_summary.sql
-- =====================================================================

-- 1. contacts.note_summary を新設する
ALTER TABLE contacts ADD COLUMN IF NOT EXISTS note_summary text;

-- 2. h_contacts を新しい列構成（note_summary追加後）で作り直す。
--    contactsへの次のUPDATEより必ず先に行う。
DROP TABLE IF EXISTS h_contacts CASCADE;

CREATE TABLE h_contacts (
  LIKE contacts INCLUDING DEFAULTS,
  history_id uuid NOT NULL DEFAULT gen_random_uuid(),
  operation  char(1) NOT NULL CHECK (operation IN ('U','D')),
  changed_at timestamptz NOT NULL DEFAULT now(),
  changed_by uuid
) PARTITION BY RANGE (changed_at);
ALTER TABLE h_contacts ADD PRIMARY KEY (history_id, changed_at);
CREATE INDEX ix_h_contacts_contact_id ON h_contacts (contact_id, changed_at DESC);

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
    PERFORM fn_ensure_month_partition('h_contacts', 'changed_at', m);
  END LOOP;
END $$;
