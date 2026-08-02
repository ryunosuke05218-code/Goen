-- =====================================================================
-- GOEN 開発用シードデータ
-- ローカル開発環境での動作確認用の最小データ。本番投入禁止。
-- パスワードはすべて "Password123!" を BCrypt でハッシュ化したもの。
-- =====================================================================

-- 都道府県マスタ（抜粋。全47件は本番投入時にCSV等で補完する）
INSERT INTO m_prefecture (pref_code, pref_name, region_name) VALUES
  ('13', '東京都',   '関東'),
  ('14', '神奈川県', '関東'),
  ('26', '京都府',   '関西'),
  ('27', '大阪府',   '関西'),
  ('23', '愛知県',   '中部'),
  ('40', '福岡県',   '九州')
ON CONFLICT DO NOTHING;

-- 業種マスタ（抜粋）
INSERT INTO m_industry (industry_code, industry_name, parent_code, sort_order, is_active) VALUES
  ('D', '製造業', NULL, 10, true),
  ('G', '情報通信業', NULL, 20, true),
  ('I', '卸売業・小売業', NULL, 30, true),
  ('L', '学術研究・専門技術サービス業', NULL, 40, true),
  ('M', '宿泊業・飲食サービス業', NULL, 50, true),
  ('N', '生活関連サービス業・娯楽業', NULL, 60, true)
ON CONFLICT DO NOTHING;

-- 開発用組織・ユーザー
INSERT INTO organizations (org_id, org_name, plan_type) VALUES
  ('00000000-0000-0000-0000-000000000001', 'GOEN開発用組織', 'personal')
ON CONFLICT DO NOTHING;

-- password_hash は PBKDF2-HMACSHA256(100,000回, salt16B+subkey32B, Base64)で "Password123!" をハッシュ化したもの。
-- 生成方式は backend/src/Goen.Infrastructure/Security/Pbkdf2PasswordHasher.cs と同一。開発ログイン確認用。
INSERT INTO users (user_id, org_id, email, password_hash, display_name, role, status) VALUES
  ('00000000-0000-0000-0000-000000000101', '00000000-0000-0000-0000-000000000001',
   'dev@example.com', 'kTYGPFaaOLZK6WkAE+iIDnScvInku8/zQdfiZMTLlDoL+qJotuADsCK3NUcotpYO',
   '開発太郎', 'org_admin', 'active')
ON CONFLICT DO NOTHING;
