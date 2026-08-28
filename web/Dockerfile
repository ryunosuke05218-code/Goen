# web/ 配下の静的ファイル（HTML/CSS/JS）をNginxで配信するだけのシンプルなコンテナ。
FROM nginx:1.27-alpine

COPY . /usr/share/nginx/html
# scp等でファイルを転送すると、転送元（Windows等）のパーミッションがそのまま引き継がれ、
# Nginxの実行ユーザーから読めず403 Forbiddenになることがあるため、明示的に読み取り可能にする。
RUN chmod -R a+rX /usr/share/nginx/html

# JS/CSSにキャッシュ制御ヘッダを付与する（config.js等の更新がブラウザキャッシュで反映されない
# トラブルを防ぐため。nginx.conf参照）。
COPY nginx.conf /etc/nginx/conf.d/default.conf

EXPOSE 80
