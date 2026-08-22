-- =====================================================================
-- migration 0011: 自分自身を表す人物カルテ（persons.is_self）の追加
--
-- 背景: ダッシュボードから自分自身の人物カルテを登録・編集できるようにする。人物一覧では
--       通常の登録人物と混ざらないよう常に最上部に固定表示し、ダッシュボードの集計（総登録人数・
--       業種別/職種別の内訳）からは除外する（「自分」は人脈上の連絡先ではないため）。
--   ・persons.is_self を新設し、1ユーザーにつき最大1件（org_id, owner_user_id単位）に制限する
--     部分ユニークインデックスを張る。
--   ・persons_read.is_self を新設し、人物一覧・ダッシュボードの集計クエリで除外できるようにする。
--
-- 注意: h_persons はカレント/履歴の列順を一致させる必要がある（fn_track_history()が位置ベースでINSERTするため）。
--       本アプリはまだ本番データを持たないため、h_persons は再作成する（履歴データは失われる。migration 0004と同じ方針）。
--
-- 実行方法:
--   psql -U postgres -d GOEN -f db/migrations/0011_persons_is_self.sql
-- =====================================================================

-- 1. persons.is_self を追加する
ALTER TABLE persons ADD COLUMN IF NOT EXISTS is_self boolean NOT NULL DEFAULT false;
CREATE UNIQUE INDEX IF NOT EXISTS ux_persons_owner_self ON persons (org_id, owner_user_id) WHERE is_self;

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

-- 3. persons_read.is_self を追加する（人物一覧・ダッシュボードの除外フィルタ用）
ALTER TABLE persons_read ADD COLUMN IF NOT EXISTS is_self boolean NOT NULL DEFAULT false;
