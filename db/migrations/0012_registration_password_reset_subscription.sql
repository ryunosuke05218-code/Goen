-- =====================================================================
-- migration 0012: 自己登録・パスワードリセット・サブスク課金の土台を追加
--
-- 背景:
--   ・これまで自己登録画面がなく、事前登録済みユーザーでのログインのみだった。メール＋パスワードの
--     自己登録に対応する（新規登録者ごとに新しい組織（organizations.plan_type='personal'）を作成する）。
--   ・パスワードを忘れた場合のリセット機能がなかった。password_reset_tokens を新設し、
--     メールで送る6桁コード（ハッシュのみ保存）で本人確認する方式とする（モバイルアプリのため
--     ディープリンクより実装・運用が簡単なコード入力方式を採用）。
--   ・サブスク課金の土台として organizations に契約状態を保持する列を追加する。決済手段は
--     開発初期はStripeを使うが、Google Play/App StoreのIAPへ切り替えられるよう、
--     プロバイダ非依存の内部プランコード（subscription_plan_code）とプロバイダ種別
--     （subscription_provider）を分けて持たせる設計とする。
--
-- 注意: h_organizations はカレント/履歴の列順を一致させる必要がある（fn_track_history()が
--       位置ベースでINSERTするため）。本アプリはまだ本番データを持たないため、h_organizations は
--       再作成する（履歴データは失われる。migration 0004/0011と同じ方針）。
--
-- 実行方法:
--   psql -U postgres -d GOEN -f db/migrations/0012_registration_password_reset_subscription.sql
-- =====================================================================

-- 1. パスワードリセット用トークン（6桁コードのハッシュのみ保存）
CREATE TABLE password_reset_tokens (
  token_id   uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id    uuid NOT NULL REFERENCES users(user_id) ON DELETE CASCADE,
  code_hash  text NOT NULL,
  expires_at timestamptz NOT NULL,
  used_at    timestamptz,
  created_at timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX ix_password_reset_tokens_user_id ON password_reset_tokens (user_id, created_at DESC);

-- 2. サブスク課金の状態を organizations に追加する
ALTER TABLE organizations ADD COLUMN IF NOT EXISTS subscription_status text NOT NULL DEFAULT 'trialing'
  CHECK (subscription_status IN ('trialing','active','past_due','canceled','incomplete'));
ALTER TABLE organizations ADD COLUMN IF NOT EXISTS subscription_provider text; -- 'stripe' / 'google_play' / 'app_store'（未契約はNULL）
ALTER TABLE organizations ADD COLUMN IF NOT EXISTS subscription_plan_code text; -- プロバイダ非依存の内部プランコード（例: 'standard_monthly'）
ALTER TABLE organizations ADD COLUMN IF NOT EXISTS subscription_provider_customer_id text; -- Stripe Customer ID等
ALTER TABLE organizations ADD COLUMN IF NOT EXISTS subscription_provider_subscription_id text; -- Stripe Subscription ID等
ALTER TABLE organizations ADD COLUMN IF NOT EXISTS subscription_current_period_end timestamptz;
ALTER TABLE organizations ADD COLUMN IF NOT EXISTS trial_ends_at timestamptz;

-- 3. h_organizations を新しい列構成で作り直す（位置ベースINSERTの整合性を保つため）
DROP TABLE IF EXISTS h_organizations CASCADE;

CREATE TABLE h_organizations (
  LIKE organizations INCLUDING DEFAULTS,
  history_id uuid NOT NULL DEFAULT gen_random_uuid(),
  operation  char(1) NOT NULL CHECK (operation IN ('U','D')),
  changed_at timestamptz NOT NULL DEFAULT now(),
  changed_by uuid
) PARTITION BY RANGE (changed_at);
ALTER TABLE h_organizations ADD PRIMARY KEY (history_id, changed_at);
CREATE INDEX ix_h_organizations_org_id ON h_organizations (org_id, changed_at DESC);

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
    PERFORM fn_ensure_month_partition('h_organizations', 'changed_at', m);
  END LOOP;
END $$;
