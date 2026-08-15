-- 重要度（persons.importance / persons.importance_is_manual / persons_read.importance）を廃止する。
-- ダッシュボード（F-029）の重要度別内訳、人物一覧・カルテの★表示、人脈マップのソート順など、
-- importanceに依存していた表示・並び順はすべて撤去済み（アプリ側対応と対で適用すること）。
BEGIN;

DROP INDEX IF EXISTS ix_persons_read_owner_importance;
CREATE INDEX IF NOT EXISTS ix_persons_read_owner_last_contact ON persons_read (owner_user_id, last_contact_at DESC);

ALTER TABLE persons_read DROP COLUMN IF EXISTS importance;
ALTER TABLE persons DROP COLUMN IF EXISTS importance;
ALTER TABLE persons DROP COLUMN IF EXISTS importance_is_manual;

-- h_personsは`LIKE persons INCLUDING DEFAULTS`で作成時点のpersonsの列構成を複製しただけの静的な定義であり、
-- 元テーブルの列変更には自動追従しない。fn_track_history()トリガは「元テーブルと履歴テーブルの列が同一順序で
-- 一致していること」を前提に位置ベースでコピーする（($1).* ）ため、ここで揃えないと更新・削除のたびに
-- 型不一致エラー（列importanceはsmallintだが式はtextだった、等）でトリガが失敗するようになる。
ALTER TABLE h_persons DROP COLUMN IF EXISTS importance;
ALTER TABLE h_persons DROP COLUMN IF EXISTS importance_is_manual;

COMMIT;
