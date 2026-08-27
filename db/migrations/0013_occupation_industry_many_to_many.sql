-- =====================================================================
-- migration 0013: 職種×業種を多対多にし、人物の業種を職種経由の導出から独立した直接選択に変更
--
-- 背景:
--   ・業種は固定8種で運用することになり（設定画面からの追加・編集・削除は不可）、人物登録・編集画面の
--     業種欄も自由入力コンボボックスからプルダウン選択に変更した。
--   ・職種は複数の業種にまたがりうる（例: 「営業」は複数の業種で使われる）ため、
--     m_occupation_type.industry_code（単一の任意FK）では表現できず、多対多の中間テーブルに変更する。
--   ・職種が複数業種を持ちうる以上、これまでのように「人物の業種 = 選んだ職種の業種」という導出は
--     成立しなくなる。そのため persons.industry_code を新設し、業種は人物ごとに独立して直接持たせる
--     方式に変更する（画面側は業種プルダウン→条件に合う職種一覧、または職種選択→紐づく業種の絞り込み/
--     自動設定、の双方向UIになる）。
--
-- 注意: h_persons はカレント/履歴の列順を一致させる必要がある（fn_track_history()が位置ベースでINSERTする
--       ため）。本アプリはまだ本番データを持たないため、h_persons は再作成する（履歴データ＝監査ログのみが
--       失われる。persons本体の現在データは変更しない。migration 0004/0007/0011/0012と同じ方針）。
--       m_occupation_type は静的マスタで履歴テーブルを持たないため対象外。
--       h_persons の再作成は persons への最初のUPDATEより前に行うこと（fn_track_history()は位置ベースで
--       INSERTするため、persons側に列を追加した直後にUPDATEすると、まだ列数が合っていない旧h_personsへの
--       INSERTでエラーになる）。
--
-- 実行方法:
--   psql -U postgres -d GOEN -f db/migrations/0013_occupation_industry_many_to_many.sql
-- =====================================================================

-- 1. persons.industry_code を新設する（この時点ではUPDATEしない。h_personsが未対応のため）
ALTER TABLE persons ADD COLUMN IF NOT EXISTS industry_code varchar(10) REFERENCES m_industry(industry_code);
CREATE INDEX IF NOT EXISTS ix_persons_industry_code ON persons (industry_code);

-- 2. 職種×業種の中間テーブルを新設し、既存の単一紐付け（m_occupation_type.industry_code）を引き継ぐ
CREATE TABLE IF NOT EXISTS m_occupation_type_industry (
  occupation_code varchar(10) NOT NULL REFERENCES m_occupation_type(occupation_code) ON DELETE CASCADE,
  industry_code   varchar(10) NOT NULL REFERENCES m_industry(industry_code) ON DELETE CASCADE,
  PRIMARY KEY (occupation_code, industry_code)
);
INSERT INTO m_occupation_type_industry (occupation_code, industry_code)
  SELECT occupation_code, industry_code FROM m_occupation_type WHERE industry_code IS NOT NULL
  ON CONFLICT DO NOTHING;

-- 3. m_occupation_type.industry_code（単一紐付け）を廃止する
DROP INDEX IF EXISTS ix_occupation_type_industry;
ALTER TABLE m_occupation_type DROP COLUMN IF EXISTS industry_code;

-- 4. h_persons を新しい列構成（industry_code追加後）で作り直す。
--    personsへのUPDATE（次のステップ）より必ず先に行う。
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

-- 5. persons.industry_code を、既存の「職種に紐づいていた業種」からベストエフォートで引き継ぐ
--    （h_personsが新しい列構成に対応済みのため、ここでのUPDATEは履歴トリガでエラーにならない）
UPDATE persons p
  SET industry_code = oi.industry_code
  FROM m_occupation_type_industry oi
  WHERE p.occupation_code = oi.occupation_code
    AND p.industry_code IS NULL;

-- 6. persons_read.industry_name は非正規化列のため、業種の導出元が変わった今回の変更だけでは
--    自動的に反映されない（アプリ側のPersonReadSyncServiceは人物の書き込み時にしか動かないため）。
--    導出ロジック（persons.industry_code優先、なければcompanies.industry_codeにフォールバック）で
--    既存の全件を再計算する。ダッシュボードの業種別内訳・人脈図の業種グルーピングが
--    このタイミングで一時的に古いまま（=最新にならない）表示されるのを防ぐため必須の手順。
UPDATE persons_read pr
  SET industry_name = i.industry_name
  FROM persons p
  LEFT JOIN companies c ON c.company_id = p.company_id
  LEFT JOIN m_industry i ON i.industry_code = COALESCE(p.industry_code, c.industry_code)
  WHERE pr.person_id = p.person_id;
