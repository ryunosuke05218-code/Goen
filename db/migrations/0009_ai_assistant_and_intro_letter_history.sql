-- F-034: AI指示（人脈相談）・紹介文作成の質問（依頼）・回答（生成結果）履歴を追記保存し、
-- 人脈図画面のそれぞれの機能から過去のやり取りを読み返せるようにする。
-- どちらも追記のみのログテーブルであり、履歴テーブル（h_*）は持たない（briefsと同じ方針）。
BEGIN;

CREATE TABLE ai_assistant_queries (
  query_id      uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  org_id        uuid NOT NULL REFERENCES organizations(org_id),
  owner_user_id uuid NOT NULL REFERENCES users(user_id),
  instruction   text NOT NULL,
  answer        text NOT NULL,
  routes        jsonb NOT NULL DEFAULT '[]'::jsonb,
  hints         jsonb NOT NULL DEFAULT '[]'::jsonb,
  created_at    timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX ix_ai_assistant_queries_owner_created ON ai_assistant_queries (owner_user_id, created_at DESC);

CREATE TABLE intro_letter_requests (
  request_id         uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  org_id             uuid NOT NULL REFERENCES organizations(org_id),
  owner_user_id      uuid NOT NULL REFERENCES users(user_id),
  target_person_id   uuid NOT NULL REFERENCES persons(person_id) ON DELETE CASCADE,
  requirement        text NOT NULL,
  tone               text,
  length_hint        text,
  additional_notes   text,
  hp_url             text,
  attached_file_name text,
  generated_message  text NOT NULL,
  created_at         timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX ix_intro_letter_requests_owner_created ON intro_letter_requests (owner_user_id, created_at DESC);
CREATE INDEX ix_intro_letter_requests_target_person ON intro_letter_requests (target_person_id, created_at DESC);

COMMIT;
