# web/ 配下の静的ファイル（HTML/CSS/JS）をNginxで配信するだけのシンプルなコンテナ。
FROM nginx:1.27-alpine

COPY . /usr/share/nginx/html
# scp等でファイルを転送すると、転送元（Windows等）のパーミッションがそのまま引き継がれ、
# Nginxの実行ユーザーから読めず403 Forbiddenになることがあるため、明示的に読み取り可能にする。
RUN chmod -R a+rX /usr/share/nginx/html

# SPAではなく複数のhtmlファイルなので、Nginxの既定設定（ファイルをそのまま返す）のままで問題ない。
EXPOSE 80
