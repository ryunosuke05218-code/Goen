-- =====================================================================
-- migration 0015: 設定画面の拡充（メールアドレス変更・パスワード変更・通知設定）に伴うusers拡張
--
-- 背景:
--   設定画面に「通知のオン/オフ」を追加するため、users.allow_notifications を新設する。
--   メールアドレス変更・パスワード変更自体は既存カラム（email, password_hash）をUPDATEするだけで
--   スキーマ変更は不要だが、それらのUPDATEより前に必ずh_usersを新しい列構成に合わせておく必要がある
--   （fn_track_history()が位置ベースでINSERTするため。migration 0004/0007/0011/0012/0013/0014と同じ方針）。
--
-- 実行方法:
--   psql -U postgres -d GOEN -f db/migrations/0015_user_account_settings.sql
-- =====================================================================

-- 1. users.allow_notifications を新設する
ALTER TABLE users ADD COLUMN IF NOT EXISTS allow_notifications boolean NOT NULL DEFAULT true;

-- 2. h_users を新しい列構成（allow_notifications追加後）で作り直す。
--    usersへの次のUPDATE（メール変更・パスワード変更・通知設定変更等）より必ず先に行う。
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
    PERFORM fn_ensure_month_partition('h_users', 'changed_at', m);
  END LOOP;
END $$;
