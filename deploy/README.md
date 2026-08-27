# VPSへのデプロイ手順（Webサイト + 既存apiコンテナへのドメイン割り当て）

VPS上の `myapp/` フォルダ（既存の `publish/`・`Dockerfile`・`docker-compose.yml` があるところ）に、
`web/` フォルダと `deploy/Caddyfile` を**そのまま追加**し、既存の `docker-compose.yml` に
`web`・`caddy` サービスを追記する構成にする。

```
myapp/
├── publish/              (既存: API発行物)
├── Dockerfile             (既存: API用)
├── docker-compose.yml     (既存に web / caddy を追記する)
├── web/                   (新規: このリポジトリの web/ フォルダをそのまま配置)
│   ├── Dockerfile
│   ├── index.html ...
└── deploy/
    └── Caddyfile          (新規: このリポジトリの deploy/Caddyfile を配置)
```

## 1. ファイルをscpで配置する

ローカルから、リポジトリの `web/` フォルダと `deploy/Caddyfile` をVPSの `myapp/` 直下へ転送する。

```bash
scp -r web/ user@<VPSのIP>:~/myapp/
scp -r deploy/ user@<VPSのIP>:~/myapp/
```

## 2. `docker-compose.yml` に `web`・`caddy` を追記する

既存の `db`・`api` サービスはそのまま。以下を追記する（全体像）。

```yaml
services:
  db:
    image: postgres:18
    ports:
      - "127.0.0.1:5432:5432"
    restart: unless-stopped
    environment:
      POSTGRES_USER: ${POSTGRES_USER}
      POSTGRES_PASSWORD: ${POSTGRES_PASSWORD}
      POSTGRES_DB: ${POSTGRES_DB}
    volumes:
      - pgdata:/var/lib/postgresql
    healthcheck:
      test: ["CMD-SHELL", "pg_isready -U ${POSTGRES_USER} -d ${POSTGRES_DB}"]
      interval: 10s
      timeout: 5s
      retries: 5

  api:
    build: .
    restart: unless-stopped
    depends_on:
      db:
        condition: service_healthy
    environment:
      ASPNETCORE_URLS: http://+:8080
      ConnectionStrings__DefaultConnection: "Host=db;Port=5432;Database=${POSTGRES_DB};Username=${POSTGRES_USER};Password=${POSTGRES_PASSWORD}"
      # Stripe連携用（実際の値は.envまたはサーバー環境変数で渡す。ここに直書きしないこと）
      Subscription__Provider: "stripe"
      Subscription__ApiKey: ${STRIPE_API_KEY}
      Subscription__WebhookSecret: ${STRIPE_WEBHOOK_SECRET}
      Subscription__SuccessUrl: "https://goen-app.com/billing-success.html"
      Subscription__CancelUrl: "https://goen-app.com/billing-cancel.html"
      Subscription__PortalReturnUrl: "https://goen-app.com/account.html"
      Subscription__PlanPriceIds__standard_monthly: ${STRIPE_PRICE_ID_STANDARD}
    ports:
      - "127.0.0.1:8080:8080"   # 変更不要。Caddyはcompose内からサービス名 api:8080 で直接届く

  # ここから追加
  web:
    build:
      context: ./web
    restart: unless-stopped
    # ホストへの公開は不要（caddyが同じcomposeネットワーク内からサービス名 web:80 で直接アクセスするため）

  caddy:
    image: caddy:2-alpine
    restart: unless-stopped
    ports:
      - "80:80"
      - "443:443"
    volumes:
      - ./deploy/Caddyfile:/etc/caddy/Caddyfile:ro
      - caddy_data:/data
      - caddy_config:/config
    depends_on:
      - web
      - api

volumes:
  pgdata:
  caddy_data:
  caddy_config:
```

`api`サービスの`environment`に`Subscription__*`を足したのは、以前案内した`dotnet user-secrets`は
ローカル開発専用のため、本番はこのように環境変数で渡す必要があるからです。
`${STRIPE_API_KEY}`等は`myapp/.env`ファイルに書いておけばdocker composeが自動で読み込みます。

```bash
# myapp/.env（既存の POSTGRES_* に追記する）
STRIPE_API_KEY=sk_live_xxxxxxxxxxxx
STRIPE_WEBHOOK_SECRET=whsec_xxxxxxxxxxxx
STRIPE_PRICE_ID_STANDARD=price_xxxxxxxxxxxx
```

`.env`ファイルはgit管理・scp転送の対象から外し、VPS上で直接編集すること。

## 3. ドメインを用意し、DNSをVPSに向ける

ドメインレジストラ（お名前.com, Cloudflare等）の管理画面で、**Aレコード**を追加する。

| ホスト名 | 種別 | 値 |
|---|---|---|
| `@`（またはドメイン本体） | A | VPSのグローバルIPアドレス |
| `www` | A | VPSのグローバルIPアドレス |
| `api` | A | VPSのグローバルIPアドレス |

反映には数分〜数時間かかることがある（`dig goen-app.com`等で確認できる）。

## 4. VPSのファイアウォールで80/443番ポートを開放する

クラウド側のセキュリティグループ・VPSのOS側ファイアウォール（`ufw`等）の両方で、
TCP 80番・443番を外部からのアクセスに開放する。Let's Encryptの証明書発行は80番ポート経由で
行われるため、ここが塞がっていると証明書が取得できない。

```bash
sudo ufw allow 80/tcp
sudo ufw allow 443/tcp
```

## 5. 起動する

`Caddyfile`内のドメインを実際のものに書き換えてから、`myapp/`で以下を実行する。

```bash
cd ~/myapp
docker compose up -d --build
```

`web`・`caddy`（および既存の`db`・`api`）が起動する。

## 6. 動作確認

```bash
curl -I https://goen-app.com
curl -I https://api.goen-app.com/health
```

両方とも `200 OK`（または想定通りのレスポンス）が返ればHTTPS化は完了。
初回アクセス時にCaddyが自動でLet's Encrypt証明書を取得するため、数秒〜数十秒かかることがある
（うまくいかない場合は`docker compose logs caddy`でエラーを確認）。

## 7. Webサイト側の設定を本番URLに差し替える

`web/assets/config.js`の`API_BASE_URL`を`https://api.goen-app.com`に変更してからscpし直し、
`docker compose up -d --build web`で反映する。

## 8. StripeのWebhook設定

Stripeダッシュボードで、Webhookエンドポイントに`https://api.goen-app.com/api/billing/webhook`を登録する。

## 更新時の再デプロイ

```bash
cd ~/myapp
docker compose up -d --build web   # webだけ更新する場合
docker compose up -d --build api   # apiだけ更新する場合
```
