-- =====================================================================
-- migration 0003: 通知機能（F-012）の廃止に伴うスキーマ整理
--
-- 背景: 通知機能は未実装のプレースホルダー画面のみで、バックエンドは一切実装されていなかった
--       （notify_type/送信バッチ等は存在しない）。F-012を廃止し、代わりに紹介文作成機能（F-026）を
--       新設したため、通知専用のテーブル・カラムを削除する。
--
-- 対象: 既存DBに対して1回だけ実行する。
-- 注意: notifications テーブルの既存データは削除される（未実装機能のため実データは存在しない想定）。
--
-- 実行方法:
--   psql -U postgres -d GOEN -f db/migrations/0003_drop_notifications.sql
-- =====================================================================

DROP TABLE IF EXISTS notifications CASCADE;

ALTER TABLE users DROP COLUMN IF EXISTS notify_hour;
ALTER TABLE users DROP COLUMN IF EXISTS notify_settings;
