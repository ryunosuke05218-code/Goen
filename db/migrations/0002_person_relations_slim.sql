-- =====================================================================
-- migration 0002: person_relations を「人脈（community）／紹介元（referrer）」の
--                  2種類のみに絞り込む
--
-- 背景:
--   同僚(colleague)・取引先(client)・提携先(partner)のような組織上・取引上の関係は、
--   紹介経路探索（BFS）にとって「実際に紹介できる人脈」を意味しない場合が多く、
--   グラフのエッジとして持つと画面や経路探索が混乱する。これらの文脈情報は
--   人物カルテ側（person_profiles.note 等）にテキストとして持たせ、RAG検索の
--   補足情報として提示する方式に変更する。
--
-- 対象: 既存DBに対して1回だけ実行する。
-- 注意: colleague/client/partner/other の既存行は削除される（実データ喪失に注意）。
--       本アプリはまだ本番データを持たないため、削除のみを行い、
--       ノートへの自動変換は行わない（変換が必要な場合は事前に個別対応すること）。
--
-- 実行方法:
--   psql -U postgres -d GOEN -f db/migrations/0002_person_relations_slim.sql
-- =====================================================================

DELETE FROM person_relations WHERE relation_type NOT IN ('referrer', 'community');

ALTER TABLE person_relations DROP CONSTRAINT person_relations_relation_type_check;
ALTER TABLE person_relations ADD CONSTRAINT person_relations_relation_type_check
  CHECK (relation_type IN ('referrer', 'community'));
