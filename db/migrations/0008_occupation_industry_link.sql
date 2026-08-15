-- 職種マスタ（m_occupation_type）に業種（m_industry）への紐付けを追加する。
-- 用途：職種追加画面で業種を選択/新規作成した際にリンクし、人脈図・ダッシュボードの
-- 業種別＞職種別グルーピングを「会社のindustry_code（実運用では入力経路がなく未設定のまま）」ではなく
-- 「人物が選んだ職種に紐づく業種」から導出できるようにする。
-- m_occupation_type / m_industry はどちらも静的マスタ（h_*履歴テーブルを持たない）ため、
-- h_persons等で必要だった列同期（fn_track_history()の位置ベースコピー対応）は不要。
BEGIN;

ALTER TABLE m_occupation_type ADD COLUMN IF NOT EXISTS industry_code varchar(10) REFERENCES m_industry(industry_code);
CREATE INDEX IF NOT EXISTS ix_occupation_type_industry ON m_occupation_type (industry_code);

COMMIT;
