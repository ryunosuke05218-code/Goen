-- F-038: 氏名・会社名をもとにAIがWeb検索し、公開情報から人物の参考情報（要約＋出典）を生成する。
-- ai_person_cardsとは異なり公開Web情報を根拠にするため、出典（sources）を必須で保持する。
-- 世代管理は行わず、人物1件につき最新1件のみ（再実行のたびに上書き）。
BEGIN;

CREATE TABLE person_research_results (
  person_id    uuid PRIMARY KEY REFERENCES persons(person_id) ON DELETE CASCADE,
  org_id       uuid NOT NULL REFERENCES organizations(org_id),
  summary      text NOT NULL,
  sources      jsonb NOT NULL DEFAULT '[]'::jsonb,
  llm_model    text NOT NULL,
  generated_at timestamptz NOT NULL DEFAULT now(),
  created_at   timestamptz NOT NULL DEFAULT now(),
  created_by   uuid,
  updated_at   timestamptz NOT NULL DEFAULT now(),
  updated_by   uuid,
  version      integer NOT NULL DEFAULT 1
);

CREATE TRIGGER trg_person_research_results_touch BEFORE UPDATE ON person_research_results
  FOR EACH ROW EXECUTE FUNCTION fn_touch();

COMMIT;
