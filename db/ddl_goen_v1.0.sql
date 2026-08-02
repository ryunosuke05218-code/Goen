-- =====================================================================
-- GOEN（HUMAN NETWORK OS） DDL v1.0
-- 対象: テーブル設計書_GOEN_v1.0.md
-- DBMS: PostgreSQL 17 以上
-- 備考:
--   ・PGroonga は開発用 Docker イメージ（pgvector/pgvector）に同梱されていないため、
--     開発環境では pg_trgm による代替全文検索とする（D-002 未決事項に対応する暫定措置）。
--     本番導入時は PGroonga または pg_bigm への切替を検討する。
--   ・UUIDはアプリケーション側でUUIDv7を採番して送信する運用を基本とし、
--     DBのDEFAULTはアドホックな手動INSERT用のフォールバックとして gen_random_uuid()（v4）を設定する。
--   ・パーティションは開発初期化時に「前月〜3か月先」のみ作成する。運用時は pg_partman 等で自動化する（第10章）。
-- =====================================================================

-- ---------------------------------------------------------------------
-- 0.-1 既存オブジェクトの削除（本DDLは再実行可能にするため、実行のたびに全テーブルを作り直す。
--       開発用DBのリセット専用。本番では絶対に流さないこと）
-- ---------------------------------------------------------------------
DROP TABLE IF EXISTS
  import_jobs, ai_api_logs, audit_logs, auth_tokens,
  rag_index_queue, rag_chunks, persons_read, briefs, ai_person_cards,
  h_transcripts, transcripts, h_contact_media, contact_media, h_contacts, contacts,
  h_referrals, referrals, h_referral_needs, referral_needs, h_next_actions, next_actions,
  h_person_relations, person_relations, h_person_tags, person_tags,
  h_person_profiles, person_profiles, h_persons, persons,
  h_tags, tags, h_companies, companies, h_users, users, h_organizations, organizations,
  m_prefecture, m_industry
  CASCADE;

-- ---------------------------------------------------------------------
-- 0. 拡張機能
-- ---------------------------------------------------------------------
CREATE EXTENSION IF NOT EXISTS pgcrypto;   -- UUID生成
CREATE EXTENSION IF NOT EXISTS vector;     -- pgvector（ベクトル検索）
CREATE EXTENSION IF NOT EXISTS pg_trgm;    -- 日本語全文検索の暫定代替（本番はPGroonga/pg_bigmを検討）

-- ---------------------------------------------------------------------
-- 0.1 共通トリガ関数
-- ---------------------------------------------------------------------

-- BEFORE UPDATE: updated_at / version を自動更新する
CREATE OR REPLACE FUNCTION fn_touch() RETURNS trigger AS $$
BEGIN
  NEW.updated_at := now();
  NEW.version := COALESCE(OLD.version, 0) + 1;
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- AFTER UPDATE OR DELETE: 変更前イメージを h_ テーブルへ退避する（3.1 カレント／ヒストリ分離方式）
-- 前提: 履歴テーブルは「元テーブルの全カラムを同一順序で保持」＋末尾に
--       (history_id, operation, changed_at, changed_by) を追加した構造であること。
CREATE OR REPLACE FUNCTION fn_track_history() RETURNS trigger AS $$
DECLARE
  history_table text := 'h_' || TG_TABLE_NAME;
  op char(1);
  actor uuid;
BEGIN
  IF TG_OP = 'UPDATE' THEN
    op := 'U';
    actor := NEW.updated_by;
  ELSIF TG_OP = 'DELETE' THEN
    op := 'D';
    actor := OLD.updated_by;
  END IF;

  EXECUTE format(
    'INSERT INTO %I SELECT ($1).*, gen_random_uuid(), $2, clock_timestamp(), $3',
    history_table
  ) USING OLD, op, actor;

  IF TG_OP = 'DELETE' THEN
    RETURN OLD;
  END IF;
  RETURN NULL;
END;
$$ LANGUAGE plpgsql;

-- 月次RANGEパーティションを不足分だけ作成するヘルパー（h_* / audit_logs / ai_api_logs 用）
CREATE OR REPLACE FUNCTION fn_ensure_month_partition(
  parent_table text,
  partition_key text,
  for_month date
) RETURNS void AS $$
DECLARE
  month_start date := date_trunc('month', for_month);
  month_end date := month_start + interval '1 month';
  partition_name text := parent_table || '_' || to_char(month_start, 'YYYYMM');
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_class WHERE relname = partition_name
  ) THEN
    EXECUTE format(
      'CREATE TABLE %I PARTITION OF %I FOR VALUES FROM (%L) TO (%L)',
      partition_name, parent_table, month_start, month_end
    );
  END IF;
END;
$$ LANGUAGE plpgsql;

-- =====================================================================
-- 1. 静的マスタ（m_） ※共通カラムなし・履歴なし
-- =====================================================================

CREATE TABLE m_industry (
  industry_code varchar(10) PRIMARY KEY,
  industry_name text NOT NULL,
  parent_code   varchar(10) REFERENCES m_industry(industry_code),
  sort_order    integer NOT NULL DEFAULT 0,
  is_active     boolean NOT NULL DEFAULT true
);

CREATE TABLE m_prefecture (
  pref_code   char(2) PRIMARY KEY,
  pref_name   text NOT NULL,
  region_name text NOT NULL
);

-- =====================================================================
-- 2. 準マスタ ※共通カラムあり・履歴あり
-- =====================================================================

-- 2.1 organizations（組織）
CREATE TABLE organizations (
  org_id         uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  org_name       text NOT NULL,
  parent_org_id  uuid REFERENCES organizations(org_id),
  plan_type      text NOT NULL CHECK (plan_type IN ('personal','team','enterprise')),
  created_at     timestamptz NOT NULL DEFAULT now(),
  created_by     uuid,
  updated_at     timestamptz NOT NULL DEFAULT now(),
  updated_by     uuid,
  version        integer NOT NULL DEFAULT 1
);

CREATE TABLE h_organizations (
  LIKE organizations INCLUDING DEFAULTS,
  history_id uuid NOT NULL DEFAULT gen_random_uuid(),
  operation  char(1) NOT NULL CHECK (operation IN ('U','D')),
  changed_at timestamptz NOT NULL DEFAULT now(),
  changed_by uuid
) PARTITION BY RANGE (changed_at);
ALTER TABLE h_organizations ADD PRIMARY KEY (history_id, changed_at);
CREATE INDEX ix_h_organizations_org_id ON h_organizations (org_id, changed_at DESC);

CREATE TRIGGER trg_organizations_touch BEFORE UPDATE ON organizations
  FOR EACH ROW EXECUTE FUNCTION fn_touch();
CREATE TRIGGER trg_organizations_history AFTER UPDATE OR DELETE ON organizations
  FOR EACH ROW EXECUTE FUNCTION fn_track_history();

-- 2.2 users（ユーザー）
CREATE TABLE users (
  user_id         uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  org_id          uuid NOT NULL REFERENCES organizations(org_id),
  email           text NOT NULL,
  password_hash   text NOT NULL,
  display_name    text NOT NULL,
  role            text NOT NULL CHECK (role IN ('member','manager','org_admin','sys_admin')),
  status          text NOT NULL CHECK (status IN ('active','suspended','retired')) DEFAULT 'active',
  last_login_at   timestamptz,
  created_at      timestamptz NOT NULL DEFAULT now(),
  created_by      uuid,
  updated_at      timestamptz NOT NULL DEFAULT now(),
  updated_by      uuid,
  version         integer NOT NULL DEFAULT 1
);
-- メールアドレスは大文字小文字を区別しないログインIDとして扱う（citext拡張は使わずlower()一意索引で代替）
CREATE UNIQUE INDEX ux_users_email ON users (lower(email));
CREATE INDEX ix_users_org_id ON users (org_id);

CREATE TABLE h_users (
  LIKE users INCLUDING DEFAULTS,
  history_id uuid NOT NULL DEFAULT gen_random_uuid(),
  operation  char(1) NOT NULL CHECK (operation IN ('U','D')),
  changed_at timestamptz NOT NULL DEFAULT now(),
  changed_by uuid
) PARTITION BY RANGE (changed_at);
ALTER TABLE h_users ADD PRIMARY KEY (history_id, changed_at);
CREATE INDEX ix_h_users_user_id ON h_users (user_id, changed_at DESC);

CREATE TRIGGER trg_users_touch BEFORE UPDATE ON users
  FOR EACH ROW EXECUTE FUNCTION fn_touch();
CREATE TRIGGER trg_users_history AFTER UPDATE OR DELETE ON users
  FOR EACH ROW EXECUTE FUNCTION fn_track_history();

-- 2.3 companies（企業）
CREATE TABLE companies (
  company_id         uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  company_name       text NOT NULL,
  company_name_kana  text,
  company_name_normalized text NOT NULL, -- 「株式会社」表記ゆれ吸収用の正規化済み検索キー（7.5）
  industry_code      varchar(10) REFERENCES m_industry(industry_code),
  pref_code          char(2) REFERENCES m_prefecture(pref_code),
  address            text,
  url                text,
  employee_scale     text CHECK (employee_scale IN ('1-10','11-50','51-200','201-1000','1000+')),
  created_at         timestamptz NOT NULL DEFAULT now(),
  created_by         uuid,
  updated_at         timestamptz NOT NULL DEFAULT now(),
  updated_by         uuid,
  version            integer NOT NULL DEFAULT 1
);
CREATE INDEX ix_companies_name_normalized ON companies USING gin (company_name_normalized gin_trgm_ops);
CREATE INDEX ix_companies_industry ON companies (industry_code);

CREATE TABLE h_companies (
  LIKE companies INCLUDING DEFAULTS,
  history_id uuid NOT NULL DEFAULT gen_random_uuid(),
  operation  char(1) NOT NULL CHECK (operation IN ('U','D')),
  changed_at timestamptz NOT NULL DEFAULT now(),
  changed_by uuid
) PARTITION BY RANGE (changed_at);
ALTER TABLE h_companies ADD PRIMARY KEY (history_id, changed_at);
CREATE INDEX ix_h_companies_company_id ON h_companies (company_id, changed_at DESC);

CREATE TRIGGER trg_companies_touch BEFORE UPDATE ON companies
  FOR EACH ROW EXECUTE FUNCTION fn_touch();
CREATE TRIGGER trg_companies_history AFTER UPDATE OR DELETE ON companies
  FOR EACH ROW EXECUTE FUNCTION fn_track_history();

-- 2.4 tags（タグ）
CREATE TABLE tags (
  tag_id     uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  org_id     uuid NOT NULL REFERENCES organizations(org_id),
  tag_name   text NOT NULL,
  created_at timestamptz NOT NULL DEFAULT now(),
  created_by uuid,
  updated_at timestamptz NOT NULL DEFAULT now(),
  updated_by uuid,
  version    integer NOT NULL DEFAULT 1
);
CREATE UNIQUE INDEX ux_tags_org_name ON tags (org_id, tag_name);

CREATE TABLE h_tags (
  LIKE tags INCLUDING DEFAULTS,
  history_id uuid NOT NULL DEFAULT gen_random_uuid(),
  operation  char(1) NOT NULL CHECK (operation IN ('U','D')),
  changed_at timestamptz NOT NULL DEFAULT now(),
  changed_by uuid
) PARTITION BY RANGE (changed_at);
ALTER TABLE h_tags ADD PRIMARY KEY (history_id, changed_at);
CREATE INDEX ix_h_tags_tag_id ON h_tags (tag_id, changed_at DESC);

CREATE TRIGGER trg_tags_touch BEFORE UPDATE ON tags
  FOR EACH ROW EXECUTE FUNCTION fn_touch();
CREATE TRIGGER trg_tags_history AFTER UPDATE OR DELETE ON tags
  FOR EACH ROW EXECUTE FUNCTION fn_track_history();

-- =====================================================================
-- 3. コア業務テーブル ※共通カラムあり・履歴あり
-- =====================================================================

-- 3.1 persons（人物） -- 参照頻度が最も高いテーブル。行幅を小さく保つ（7.6）
CREATE TABLE persons (
  person_id            uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  org_id               uuid NOT NULL REFERENCES organizations(org_id),
  owner_user_id        uuid NOT NULL REFERENCES users(user_id),
  company_id           uuid REFERENCES companies(company_id),
  full_name            text NOT NULL,
  full_name_kana       text,
  department           text,
  job_title            text,
  importance           smallint NOT NULL CHECK (importance BETWEEN 1 AND 5) DEFAULT 3,
  importance_is_manual boolean NOT NULL DEFAULT false,
  visibility           text NOT NULL CHECK (visibility IN ('private','team','org')) DEFAULT 'private',
  first_met_at         date,
  last_contact_at      timestamptz,
  introducer_person_id uuid REFERENCES persons(person_id),
  source_type          text NOT NULL CHECK (source_type IN ('card_ocr','manual','import')),
  created_at           timestamptz NOT NULL DEFAULT now(),
  created_by           uuid,
  updated_at           timestamptz NOT NULL DEFAULT now(),
  updated_by           uuid,
  version              integer NOT NULL DEFAULT 1
);
CREATE INDEX ix_persons_owner_last_contact ON persons (owner_user_id, last_contact_at DESC);
CREATE INDEX ix_persons_org_company ON persons (org_id, company_id);
CREATE INDEX ix_persons_full_name_kana ON persons (full_name_kana);
CREATE INDEX ix_persons_introducer ON persons (introducer_person_id);

CREATE TABLE h_persons (
  LIKE persons INCLUDING DEFAULTS,
  history_id uuid NOT NULL DEFAULT gen_random_uuid(),
  operation  char(1) NOT NULL CHECK (operation IN ('U','D')),
  changed_at timestamptz NOT NULL DEFAULT now(),
  changed_by uuid
) PARTITION BY RANGE (changed_at);
ALTER TABLE h_persons ADD PRIMARY KEY (history_id, changed_at);
CREATE INDEX ix_h_persons_person_id ON h_persons (person_id, changed_at DESC);

CREATE TRIGGER trg_persons_touch BEFORE UPDATE ON persons
  FOR EACH ROW EXECUTE FUNCTION fn_touch();
CREATE TRIGGER trg_persons_history AFTER UPDATE OR DELETE ON persons
  FOR EACH ROW EXECUTE FUNCTION fn_track_history();

-- 3.2 person_profiles（人物詳細）
CREATE TABLE person_profiles (
  person_id     uuid PRIMARY KEY REFERENCES persons(person_id) ON DELETE CASCADE,
  tel           text,
  mobile        text,
  email         text,
  pref_code     char(2) REFERENCES m_prefecture(pref_code),
  address       text,
  url           text,
  sns_accounts  jsonb NOT NULL DEFAULT '{}'::jsonb,
  birthday      date,
  note          text,
  created_at    timestamptz NOT NULL DEFAULT now(),
  created_by    uuid,
  updated_at    timestamptz NOT NULL DEFAULT now(),
  updated_by    uuid,
  version       integer NOT NULL DEFAULT 1
);

CREATE TABLE h_person_profiles (
  LIKE person_profiles INCLUDING DEFAULTS,
  history_id uuid NOT NULL DEFAULT gen_random_uuid(),
  operation  char(1) NOT NULL CHECK (operation IN ('U','D')),
  changed_at timestamptz NOT NULL DEFAULT now(),
  changed_by uuid
) PARTITION BY RANGE (changed_at);
ALTER TABLE h_person_profiles ADD PRIMARY KEY (history_id, changed_at);
CREATE INDEX ix_h_person_profiles_person_id ON h_person_profiles (person_id, changed_at DESC);

CREATE TRIGGER trg_person_profiles_touch BEFORE UPDATE ON person_profiles
  FOR EACH ROW EXECUTE FUNCTION fn_touch();
CREATE TRIGGER trg_person_profiles_history AFTER UPDATE OR DELETE ON person_profiles
  FOR EACH ROW EXECUTE FUNCTION fn_track_history();

-- 3.3 person_tags（人物タグ／多対多）
CREATE TABLE person_tags (
  person_id  uuid NOT NULL REFERENCES persons(person_id) ON DELETE CASCADE,
  tag_id     uuid NOT NULL REFERENCES tags(tag_id) ON DELETE CASCADE,
  created_at timestamptz NOT NULL DEFAULT now(),
  created_by uuid,
  updated_at timestamptz NOT NULL DEFAULT now(),
  updated_by uuid,
  version    integer NOT NULL DEFAULT 1,
  PRIMARY KEY (person_id, tag_id)
);

CREATE TABLE h_person_tags (
  LIKE person_tags INCLUDING DEFAULTS,
  history_id uuid NOT NULL DEFAULT gen_random_uuid(),
  operation  char(1) NOT NULL CHECK (operation IN ('U','D')),
  changed_at timestamptz NOT NULL DEFAULT now(),
  changed_by uuid
) PARTITION BY RANGE (changed_at);
ALTER TABLE h_person_tags ADD PRIMARY KEY (history_id, changed_at);
CREATE INDEX ix_h_person_tags_person_id ON h_person_tags (person_id, changed_at DESC);

CREATE TRIGGER trg_person_tags_touch BEFORE UPDATE ON person_tags
  FOR EACH ROW EXECUTE FUNCTION fn_touch();
CREATE TRIGGER trg_person_tags_history AFTER UPDATE OR DELETE ON person_tags
  FOR EACH ROW EXECUTE FUNCTION fn_track_history();

-- 3.4 person_relations（人脈関係／エッジ）
CREATE TABLE person_relations (
  relation_id         uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  org_id              uuid NOT NULL REFERENCES organizations(org_id),
  from_person_id      uuid NOT NULL REFERENCES persons(person_id) ON DELETE CASCADE,
  to_person_id        uuid NOT NULL REFERENCES persons(person_id) ON DELETE CASCADE,
  relation_type       text NOT NULL CHECK (relation_type IN ('referrer','community')), -- 同僚/取引先等の文脈情報はperson_profiles.note側で保持しRAG検索に委ねる
  strength            smallint NOT NULL CHECK (strength BETWEEN 1 AND 5) DEFAULT 3,
  strength_is_manual  boolean NOT NULL DEFAULT false,
  is_bidirectional    boolean NOT NULL DEFAULT false,
  note                text,
  created_at          timestamptz NOT NULL DEFAULT now(),
  created_by          uuid,
  updated_at          timestamptz NOT NULL DEFAULT now(),
  updated_by          uuid,
  version             integer NOT NULL DEFAULT 1
);
CREATE UNIQUE INDEX ux_person_relations_edge ON person_relations (from_person_id, to_person_id, relation_type);
CREATE INDEX ix_person_relations_from ON person_relations (from_person_id, strength DESC);
CREATE INDEX ix_person_relations_to ON person_relations (to_person_id, strength DESC);

CREATE TABLE h_person_relations (
  LIKE person_relations INCLUDING DEFAULTS,
  history_id uuid NOT NULL DEFAULT gen_random_uuid(),
  operation  char(1) NOT NULL CHECK (operation IN ('U','D')),
  changed_at timestamptz NOT NULL DEFAULT now(),
  changed_by uuid
) PARTITION BY RANGE (changed_at);
ALTER TABLE h_person_relations ADD PRIMARY KEY (history_id, changed_at);
CREATE INDEX ix_h_person_relations_relation_id ON h_person_relations (relation_id, changed_at DESC);

CREATE TRIGGER trg_person_relations_touch BEFORE UPDATE ON person_relations
  FOR EACH ROW EXECUTE FUNCTION fn_touch();
CREATE TRIGGER trg_person_relations_history AFTER UPDATE OR DELETE ON person_relations
  FOR EACH ROW EXECUTE FUNCTION fn_track_history();

-- 3.5 next_actions（次回アクション）
CREATE TABLE next_actions (
  action_id           uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  person_id           uuid NOT NULL REFERENCES persons(person_id) ON DELETE CASCADE,
  user_id             uuid NOT NULL REFERENCES users(user_id),
  content             text NOT NULL,
  due_date            date,
  status              text NOT NULL CHECK (status IN ('open','done','canceled')) DEFAULT 'open',
  completed_at        timestamptz,
  source_contact_id   uuid,
  created_at          timestamptz NOT NULL DEFAULT now(),
  created_by          uuid,
  updated_at          timestamptz NOT NULL DEFAULT now(),
  updated_by          uuid,
  version             integer NOT NULL DEFAULT 1
);
CREATE INDEX ix_next_actions_user_due_open ON next_actions (user_id, due_date) WHERE status = 'open';

CREATE TABLE h_next_actions (
  LIKE next_actions INCLUDING DEFAULTS,
  history_id uuid NOT NULL DEFAULT gen_random_uuid(),
  operation  char(1) NOT NULL CHECK (operation IN ('U','D')),
  changed_at timestamptz NOT NULL DEFAULT now(),
  changed_by uuid
) PARTITION BY RANGE (changed_at);
ALTER TABLE h_next_actions ADD PRIMARY KEY (history_id, changed_at);
CREATE INDEX ix_h_next_actions_action_id ON h_next_actions (action_id, changed_at DESC);

CREATE TRIGGER trg_next_actions_touch BEFORE UPDATE ON next_actions
  FOR EACH ROW EXECUTE FUNCTION fn_touch();
CREATE TRIGGER trg_next_actions_history AFTER UPDATE OR DELETE ON next_actions
  FOR EACH ROW EXECUTE FUNCTION fn_track_history();

-- 3.6 referral_needs（紹介ニーズ：WANTED／CAN CONNECT）
CREATE TABLE referral_needs (
  need_id               uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id               uuid NOT NULL REFERENCES users(user_id),
  person_id             uuid REFERENCES persons(person_id),
  kind                  text NOT NULL CHECK (kind IN ('wanted','can_connect')),
  title                 text NOT NULL,
  description           text,
  target_industry_codes varchar(10)[] NOT NULL DEFAULT '{}',
  target_pref_codes     char(2)[] NOT NULL DEFAULT '{}',
  target_job_titles     text[] NOT NULL DEFAULT '{}',
  visibility            text NOT NULL CHECK (visibility IN ('private','team','org','community')) DEFAULT 'private',
  valid_from            date NOT NULL DEFAULT current_date,
  valid_to              date,
  status                text NOT NULL CHECK (status IN ('active','fulfilled','expired')) DEFAULT 'active',
  created_at            timestamptz NOT NULL DEFAULT now(),
  created_by            uuid,
  updated_at            timestamptz NOT NULL DEFAULT now(),
  updated_by            uuid,
  version               integer NOT NULL DEFAULT 1
);
CREATE INDEX ix_referral_needs_kind_status_valid ON referral_needs (kind, status, valid_to);
CREATE INDEX ix_referral_needs_industry_gin ON referral_needs USING gin (target_industry_codes);

CREATE TABLE h_referral_needs (
  LIKE referral_needs INCLUDING DEFAULTS,
  history_id uuid NOT NULL DEFAULT gen_random_uuid(),
  operation  char(1) NOT NULL CHECK (operation IN ('U','D')),
  changed_at timestamptz NOT NULL DEFAULT now(),
  changed_by uuid
) PARTITION BY RANGE (changed_at);
ALTER TABLE h_referral_needs ADD PRIMARY KEY (history_id, changed_at);
CREATE INDEX ix_h_referral_needs_need_id ON h_referral_needs (need_id, changed_at DESC);

CREATE TRIGGER trg_referral_needs_touch BEFORE UPDATE ON referral_needs
  FOR EACH ROW EXECUTE FUNCTION fn_touch();
CREATE TRIGGER trg_referral_needs_history AFTER UPDATE OR DELETE ON referral_needs
  FOR EACH ROW EXECUTE FUNCTION fn_track_history();

-- 3.7 referrals（紹介実績）
CREATE TABLE referrals (
  referral_id       uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  need_id           uuid REFERENCES referral_needs(need_id),
  from_user_id      uuid NOT NULL REFERENCES users(user_id),
  to_person_id      uuid NOT NULL REFERENCES persons(person_id),
  target_person_id  uuid NOT NULL REFERENCES persons(person_id),
  match_score       numeric(5,4),
  match_reason      jsonb,
  referral_text     text,
  consent_from_at   timestamptz,
  consent_to_at     timestamptz,
  status            text NOT NULL CHECK (status IN ('proposed','consented','introduced','met','deal','declined')) DEFAULT 'proposed',
  introduced_at     timestamptz,
  result_note       text,
  is_deal           boolean NOT NULL DEFAULT false,
  created_at        timestamptz NOT NULL DEFAULT now(),
  created_by        uuid,
  updated_at        timestamptz NOT NULL DEFAULT now(),
  updated_by        uuid,
  version           integer NOT NULL DEFAULT 1,
  -- 「AIが同意なく連絡先を共有しない」（F-008業務ルール／受入基準A-009）をDB層で担保する
  CONSTRAINT ck_referrals_consent_before_introduced CHECK (
    status NOT IN ('introduced','met','deal') OR (consent_from_at IS NOT NULL AND consent_to_at IS NOT NULL)
  )
);
CREATE INDEX ix_referrals_need_id ON referrals (need_id);
CREATE INDEX ix_referrals_target_person ON referrals (target_person_id);

CREATE TABLE h_referrals (
  LIKE referrals INCLUDING DEFAULTS,
  history_id uuid NOT NULL DEFAULT gen_random_uuid(),
  operation  char(1) NOT NULL CHECK (operation IN ('U','D')),
  changed_at timestamptz NOT NULL DEFAULT now(),
  changed_by uuid
) PARTITION BY RANGE (changed_at);
ALTER TABLE h_referrals ADD PRIMARY KEY (history_id, changed_at);
CREATE INDEX ix_h_referrals_referral_id ON h_referrals (referral_id, changed_at DESC);

CREATE TRIGGER trg_referrals_touch BEFORE UPDATE ON referrals
  FOR EACH ROW EXECUTE FUNCTION fn_touch();
CREATE TRIGGER trg_referrals_history AFTER UPDATE OR DELETE ON referrals
  FOR EACH ROW EXECUTE FUNCTION fn_track_history();

-- =====================================================================
-- 4. 追記型テーブル ※共通カラムあり
-- =====================================================================

-- 4.1 contacts（接点ログ）※履歴あり
CREATE TABLE contacts (
  contact_id   uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  org_id       uuid NOT NULL REFERENCES organizations(org_id),
  person_id    uuid NOT NULL REFERENCES persons(person_id) ON DELETE CASCADE,
  user_id      uuid NOT NULL REFERENCES users(user_id),
  contact_type text NOT NULL CHECK (contact_type IN ('card_exchange','one_on_one','meeting','referral','event','other')),
  occurred_at  timestamptz NOT NULL,
  place        text,
  note         text,
  has_media    boolean NOT NULL DEFAULT false,
  created_at   timestamptz NOT NULL DEFAULT now(),
  created_by   uuid,
  updated_at   timestamptz NOT NULL DEFAULT now(),
  updated_by   uuid,
  version      integer NOT NULL DEFAULT 1
);
CREATE INDEX ix_contacts_person_occurred ON contacts (person_id, occurred_at DESC);
CREATE INDEX ix_contacts_user_occurred ON contacts (user_id, occurred_at DESC);

CREATE TABLE h_contacts (
  LIKE contacts INCLUDING DEFAULTS,
  history_id uuid NOT NULL DEFAULT gen_random_uuid(),
  operation  char(1) NOT NULL CHECK (operation IN ('U','D')),
  changed_at timestamptz NOT NULL DEFAULT now(),
  changed_by uuid
) PARTITION BY RANGE (changed_at);
ALTER TABLE h_contacts ADD PRIMARY KEY (history_id, changed_at);
CREATE INDEX ix_h_contacts_contact_id ON h_contacts (contact_id, changed_at DESC);

-- next_actions.source_contact_id / transcripts.contact_id は contacts 作成後に定義する外部キー
ALTER TABLE next_actions ADD CONSTRAINT fk_next_actions_source_contact
  FOREIGN KEY (source_contact_id) REFERENCES contacts(contact_id);

CREATE TRIGGER trg_contacts_touch BEFORE UPDATE ON contacts
  FOR EACH ROW EXECUTE FUNCTION fn_touch();
CREATE TRIGGER trg_contacts_history AFTER UPDATE OR DELETE ON contacts
  FOR EACH ROW EXECUTE FUNCTION fn_track_history();

-- 4.2 contact_media（接点メディア：音声・名刺画像）※履歴あり
CREATE TABLE contact_media (
  media_id       uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  contact_id     uuid NOT NULL REFERENCES contacts(contact_id) ON DELETE CASCADE,
  media_type     text NOT NULL CHECK (media_type IN ('business_card','audio','image','document')),
  storage_path   text NOT NULL,
  file_size      bigint NOT NULL,
  duration_sec   integer,
  ocr_confidence numeric(4,3),
  ocr_raw        jsonb,
  upload_status  text NOT NULL CHECK (upload_status IN ('pending','uploaded','failed')) DEFAULT 'pending',
  created_at     timestamptz NOT NULL DEFAULT now(),
  created_by     uuid,
  updated_at     timestamptz NOT NULL DEFAULT now(),
  updated_by     uuid,
  version        integer NOT NULL DEFAULT 1
);
CREATE INDEX ix_contact_media_contact_id ON contact_media (contact_id);

CREATE TABLE h_contact_media (
  LIKE contact_media INCLUDING DEFAULTS,
  history_id uuid NOT NULL DEFAULT gen_random_uuid(),
  operation  char(1) NOT NULL CHECK (operation IN ('U','D')),
  changed_at timestamptz NOT NULL DEFAULT now(),
  changed_by uuid
) PARTITION BY RANGE (changed_at);
ALTER TABLE h_contact_media ADD PRIMARY KEY (history_id, changed_at);
CREATE INDEX ix_h_contact_media_media_id ON h_contact_media (media_id, changed_at DESC);

CREATE TRIGGER trg_contact_media_touch BEFORE UPDATE ON contact_media
  FOR EACH ROW EXECUTE FUNCTION fn_touch();
CREATE TRIGGER trg_contact_media_history AFTER UPDATE OR DELETE ON contact_media
  FOR EACH ROW EXECUTE FUNCTION fn_track_history();

-- 4.3 transcripts（文字起こし）※履歴あり
CREATE TABLE transcripts (
  transcript_id   uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  contact_id      uuid NOT NULL REFERENCES contacts(contact_id) ON DELETE CASCADE,
  media_id        uuid REFERENCES contact_media(media_id),
  content         text NOT NULL,
  content_edited  boolean NOT NULL DEFAULT false,
  confidence      numeric(4,3),
  asr_model       text NOT NULL,
  language        text NOT NULL DEFAULT 'ja',
  status          text NOT NULL CHECK (status IN ('processing','done','failed')) DEFAULT 'processing',
  created_at      timestamptz NOT NULL DEFAULT now(),
  created_by      uuid,
  updated_at      timestamptz NOT NULL DEFAULT now(),
  updated_by      uuid,
  version         integer NOT NULL DEFAULT 1
);
CREATE INDEX ix_transcripts_contact_id ON transcripts (contact_id);

CREATE TABLE h_transcripts (
  LIKE transcripts INCLUDING DEFAULTS,
  history_id uuid NOT NULL DEFAULT gen_random_uuid(),
  operation  char(1) NOT NULL CHECK (operation IN ('U','D')),
  changed_at timestamptz NOT NULL DEFAULT now(),
  changed_by uuid
) PARTITION BY RANGE (changed_at);
ALTER TABLE h_transcripts ADD PRIMARY KEY (history_id, changed_at);
CREATE INDEX ix_h_transcripts_transcript_id ON h_transcripts (transcript_id, changed_at DESC);

CREATE TRIGGER trg_transcripts_touch BEFORE UPDATE ON transcripts
  FOR EACH ROW EXECUTE FUNCTION fn_touch();
CREATE TRIGGER trg_transcripts_history AFTER UPDATE OR DELETE ON transcripts
  FOR EACH ROW EXECUTE FUNCTION fn_track_history();

-- 4.4 ai_person_cards（AI人物カルテ：世代管理・履歴テーブルなし）
CREATE TABLE ai_person_cards (
  card_id           uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  person_id         uuid NOT NULL REFERENCES persons(person_id) ON DELETE CASCADE,
  generation        integer NOT NULL,
  is_latest         boolean NOT NULL DEFAULT true,
  summary           text,
  business          text,
  issues            text,
  introducer_name   text,
  hobby             text,
  strengths         text,
  wanted_summary    text,
  field_sources     jsonb NOT NULL DEFAULT '{}'::jsonb, -- 項目ごとの生成元 "ai"/"user"（F-010）
  llm_model         text NOT NULL,
  generated_at      timestamptz NOT NULL DEFAULT now(),
  input_contact_ids uuid[] NOT NULL DEFAULT '{}',
  created_at        timestamptz NOT NULL DEFAULT now(),
  created_by        uuid,
  updated_at        timestamptz NOT NULL DEFAULT now(),
  updated_by        uuid,
  version           integer NOT NULL DEFAULT 1
);
CREATE UNIQUE INDEX ux_ai_person_cards_latest ON ai_person_cards (person_id) WHERE is_latest;
CREATE INDEX ix_ai_person_cards_person_generation ON ai_person_cards (person_id, generation DESC);

CREATE TRIGGER trg_ai_person_cards_touch BEFORE UPDATE ON ai_person_cards
  FOR EACH ROW EXECUTE FUNCTION fn_touch();

-- 4.5 briefs（商談前ブリーフ：履歴テーブルなし）
CREATE TABLE briefs (
  brief_id      uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  person_id     uuid NOT NULL REFERENCES persons(person_id) ON DELETE CASCADE,
  meeting_at    timestamptz,
  key_points    text,
  questions     jsonb NOT NULL DEFAULT '[]'::jsonb,
  proposals     jsonb NOT NULL DEFAULT '[]'::jsonb,
  open_promises text,
  source_urls   text[] NOT NULL DEFAULT '{}',
  generated_at  timestamptz NOT NULL DEFAULT now(),
  created_at    timestamptz NOT NULL DEFAULT now(),
  created_by    uuid,
  updated_at    timestamptz NOT NULL DEFAULT now(),
  updated_by    uuid,
  version       integer NOT NULL DEFAULT 1
);
CREATE INDEX ix_briefs_person_id ON briefs (person_id, generated_at DESC);

CREATE TRIGGER trg_briefs_touch BEFORE UPDATE ON briefs
  FOR EACH ROW EXECUTE FUNCTION fn_touch();

-- =====================================================================
-- 5. 参照最適化テーブル（_read）※更新日時のみ・履歴なし
-- =====================================================================

CREATE TABLE persons_read (
  person_id       uuid PRIMARY KEY REFERENCES persons(person_id) ON DELETE CASCADE,
  org_id          uuid NOT NULL,
  owner_user_id   uuid NOT NULL,
  visibility      text NOT NULL,
  full_name       text NOT NULL,
  full_name_kana  text,
  company_name    text,
  industry_name   text,
  pref_name       text,
  job_title       text,
  importance      smallint NOT NULL,
  summary         text,
  issues          text,
  tags            jsonb NOT NULL DEFAULT '[]'::jsonb,
  last_contact_at timestamptz,
  contact_count   integer NOT NULL DEFAULT 0,
  open_action     jsonb,
  search_text     text NOT NULL DEFAULT '',
  refreshed_at    timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX ix_persons_read_owner_importance ON persons_read (owner_user_id, importance DESC, last_contact_at DESC);
CREATE INDEX ix_persons_read_org_visibility ON persons_read (org_id, visibility);
CREATE INDEX ix_persons_read_search_text ON persons_read USING gin (search_text gin_trgm_ops);

-- =====================================================================
-- 6. 検索テーブル（rag_）※非同期で再構築・履歴なし
-- =====================================================================

-- 埋め込み次元数について: 開発環境は multilingual-e5-large（1024次元）を前提にする。
-- 本番でOpenAI text-embedding-3-small（1536次元）等の異なる次元のモデルへ切り替える場合、
-- ベクトル空間・次元数が異なり単純な値の変換はできないため、新しい次元のテーブル（例: rag_chunks_v2）を
-- 作成して全チャンクを再埋め込みしたうえで切り替える（4.4節参照。チャットモデルの切替とは異なりコード変更のみでは完結しない）。
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

CREATE TABLE rag_index_queue (
  queue_id      uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  source_type   text NOT NULL,
  source_id     uuid NOT NULL,
  person_id     uuid NOT NULL,
  operation     char(1) NOT NULL CHECK (operation IN ('U','D')),
  status        text NOT NULL CHECK (status IN ('pending','processing','done','failed')) DEFAULT 'pending',
  retry_count   integer NOT NULL DEFAULT 0,
  error_message text,
  enqueued_at   timestamptz NOT NULL DEFAULT now(),
  processed_at  timestamptz
);
CREATE UNIQUE INDEX ux_rag_index_queue_pending ON rag_index_queue (source_type, source_id) WHERE status = 'pending';

-- =====================================================================
-- 7. システムテーブル
-- =====================================================================

-- 7.1 auth_tokens（認証トークン：リフレッシュトークン）
CREATE TABLE auth_tokens (
  token_id    uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id     uuid NOT NULL REFERENCES users(user_id) ON DELETE CASCADE,
  token_hash  text NOT NULL,
  device_info jsonb,
  issued_at   timestamptz NOT NULL DEFAULT now(),
  expires_at  timestamptz NOT NULL,
  revoked_at  timestamptz,
  created_at  timestamptz NOT NULL DEFAULT now()
);
CREATE UNIQUE INDEX ux_auth_tokens_hash ON auth_tokens (token_hash);
CREATE INDEX ix_auth_tokens_user_id ON auth_tokens (user_id) WHERE revoked_at IS NULL;

-- 7.2 audit_logs（監査ログ）※月次パーティション
CREATE TABLE audit_logs (
  log_id        uuid NOT NULL DEFAULT gen_random_uuid(),
  occurred_at   timestamptz NOT NULL DEFAULT now(),
  user_id       uuid,
  org_id        uuid,
  operation     text NOT NULL CHECK (operation IN ('view','create','update','delete','export','login','permission_change')),
  target_table  text,
  target_id     uuid,
  target_count  integer,
  ip_address    inet,
  user_agent    text,
  detail        jsonb,
  PRIMARY KEY (log_id, occurred_at)
) PARTITION BY RANGE (occurred_at);
CREATE INDEX ix_audit_logs_user_occurred ON audit_logs (user_id, occurred_at DESC);

-- 7.3 ai_api_logs（外部AI API呼出ログ）※月次パーティション（リスクR-003のコスト監視に使用）
CREATE TABLE ai_api_logs (
  log_id        uuid NOT NULL DEFAULT gen_random_uuid(),
  occurred_at   timestamptz NOT NULL DEFAULT now(),
  org_id        uuid,
  user_id       uuid,
  api_type      text NOT NULL CHECK (api_type IN ('ocr','asr','llm')),
  provider      text NOT NULL,
  model         text,
  token_count   integer,
  cost_amount   numeric(10,4),
  latency_ms    integer,
  success       boolean NOT NULL,
  error_message text,
  PRIMARY KEY (log_id, occurred_at)
) PARTITION BY RANGE (occurred_at);
CREATE INDEX ix_ai_api_logs_org_occurred ON ai_api_logs (org_id, occurred_at DESC);

-- 7.4 import_jobs（データ移行ジョブ）
CREATE TABLE import_jobs (
  job_id         uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  org_id         uuid NOT NULL REFERENCES organizations(org_id),
  user_id        uuid NOT NULL REFERENCES users(user_id),
  source         text NOT NULL CHECK (source IN ('legacy_graph','business_card_app','other')),
  file_name      text,
  total_count    integer,
  success_count  integer NOT NULL DEFAULT 0,
  failure_count  integer NOT NULL DEFAULT 0,
  error_detail   jsonb,
  status         text NOT NULL CHECK (status IN ('pending','processing','done','failed')) DEFAULT 'pending',
  started_at     timestamptz,
  finished_at    timestamptz,
  created_at     timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX ix_import_jobs_org_id ON import_jobs (org_id, created_at DESC);

-- =====================================================================
-- 8. パーティション初期化（前月〜3か月先。以降は運用時に pg_partman 等で自動化する）
-- =====================================================================

DO $$
DECLARE
  m date;
  tbl text;
BEGIN
  FOR tbl IN SELECT unnest(ARRAY[
    'h_organizations','h_users','h_companies','h_tags',
    'h_persons','h_person_profiles','h_person_tags','h_person_relations',
    'h_next_actions','h_referral_needs','h_referrals',
    'h_contacts','h_contact_media','h_transcripts',
    'audit_logs','ai_api_logs'
  ])
  LOOP
    FOR m IN
      SELECT generate_series(
        date_trunc('month', current_date) - interval '1 month',
        date_trunc('month', current_date) + interval '3 month',
        interval '1 month'
      )::date
    LOOP
      IF tbl LIKE 'h_%' THEN
        PERFORM fn_ensure_month_partition(tbl, 'changed_at', m);
      ELSE
        PERFORM fn_ensure_month_partition(tbl, 'occurred_at', m);
      END IF;
    END LOOP;
  END LOOP;
END $$;

-- =====================================================================
-- END OF DDL
-- =====================================================================
