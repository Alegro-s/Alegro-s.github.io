#!/usr/bin/env bash
# Запускается на сервере скриптом deploy.ps1. Можно запустить и вручную:
#   bash setup-server.sh mydomain.ru /tmp/portfolio.tar.gz
set -euo pipefail
DOMAIN="$1"; ARCHIVE="$2"
ROOT=/var/www/portfolio
CONF=/etc/nginx/sites-available/portfolio

command -v nginx >/dev/null || { apt-get update && apt-get install -y nginx; }

# 1. Файлы сайта: новая версия рядом, затем быстрая подмена
rm -rf "$ROOT.new" && mkdir -p "$ROOT.new"
tar -xzf "$ARCHIVE" -C "$ROOT.new"
[ -d "$ROOT" ] && rm -rf "$ROOT.old" && mv "$ROOT" "$ROOT.old"
mv "$ROOT.new" "$ROOT"
chown -R www-data:www-data "$ROOT" 2>/dev/null || true
rm -f "$ARCHIVE"

# 2. Конфиг nginx ставится только при первом запуске, чтобы не затереть HTTPS от certbot
if [ ! -f "$CONF" ]; then
  sed "s/__DOMAIN__/$DOMAIN/g" "$(dirname "$0")/nginx-portfolio.conf" > "$CONF"
  ln -sf "$CONF" /etc/nginx/sites-enabled/portfolio
fi
nginx -t
systemctl reload nginx

# 3. HTTPS. Сработает, когда домен уже смотрит на этот сервер
if [ ! -d "/etc/letsencrypt/live/$DOMAIN" ]; then
  command -v certbot >/dev/null || apt-get install -y certbot python3-certbot-nginx
  certbot --nginx -d "$DOMAIN" -d "www.$DOMAIN" --non-interactive --agree-tos --register-unsafely-without-email --redirect \
    || echo "HTTPS пока не выпущен: проверьте, что A-записи $DOMAIN и www.$DOMAIN указывают на этот сервер, и запустите deploy ещё раз."
fi
echo "Готово: https://$DOMAIN"
