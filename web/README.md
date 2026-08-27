# GOEN Webサイト（会員登録・課金サイト）

Stripe審査・App Store/Google Play審査に向けて、アカウント作成とサブスク契約をアプリの外（Web）で
完結させるための最小限のサイトです。ビルドツールなしの素のHTML/CSS/JSで、静的ホスティングであれば
どこにでも配置できます（Vercel, Netlify, S3+CloudFront, GitHub Pages 等）。

## ページ構成

| ファイル | 内容 |
|---|---|
| `index.html` | トップページ（LP・料金） |
| `signup.html` | 会員登録 → 登録直後にStripe Checkoutへ自動遷移 |
| `login.html` | ログイン（契約状況確認・支払い管理用） |
| `account.html` | 契約状況の確認、支払い方法変更・解約（Stripeカスタマーポータルへ遷移）、退会案内 |
| `billing-success.html` | Stripe Checkout完了後のリダイレクト先 |
| `billing-cancel.html` | Stripe Checkoutキャンセル時のリダイレクト先 |
| `privacy.html` | プライバシーポリシー（下書き） |
| `terms.html` | 利用規約（下書き） |
| `tokushoho.html` | 特定商取引法に基づく表記（下書き） |

## ローカルでの動作確認

バックエンド（`backend/src/Goen.Api`）を起動した状態で、`web/`ディレクトリを適当な静的サーバーで配信してください。

```bash
cd web
python -m http.server 8080
# または: npx serve -l 8080
```

`http://localhost:8080` を開き、会員登録〜（モック環境なら）即座に契約完了、を確認できます。

## 公開前に必ずやること

1. **`assets/config.js`** の `API_BASE_URL` を、実際にデプロイしたバックエンドのURLに変更する。
2. **`tokushoho.html`**：事業者名・所在地・連絡先など、黄色くハイライトされた箇所をすべて実際の情報に置き換える。
3. **`privacy.html` / `terms.html`**：黄色くハイライトされた箇所（事業者名・連絡先・利用するAIプロバイダ名・準拠法の裁判所等）を実情報に置き換え、**弁護士等の専門家によるレビューを受ける**（特にGOENは名刺交換相手＝第三者の個人情報も扱うため要確認）。
4. **料金ページ（`index.html`内`#pricing`）**の価格を正式な金額に変更する。
5. バックエンド側の `Subscription` 設定を本番用に更新する：
   - `Provider` を `"stripe"` に変更
   - `ApiKey` / `WebhookSecret` は **`appsettings.json`に直接書かず**、`dotnet user-secrets` または環境変数で設定する
   - `PlanPriceIds.standard_monthly` に、Stripeダッシュボードで作成した実際のPrice IDを設定する
   - `SuccessUrl` / `CancelUrl` / `PortalReturnUrl` を、本番デプロイ後のこのサイトのURLに変更する
6. StripeダッシュボードのWebhook設定で、`{バックエンドの本番URL}/api/billing/webhook` を登録する。
