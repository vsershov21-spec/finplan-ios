#!/bin/bash
# Финплан на VPS Vershov Studio. Один раз, от root:
#   sudo bash -c "$(curl -fsSL https://raw.githubusercontent.com/vsershov21-spec/finplan-ios/main/server/install.sh)"
# Ставит PHP-FPM, пользователя finplan, сайт в Caddy, таймеры обновления (каждые 5 минут), cron приложения и ночной бэкап.
# Код приложения приходит зашифрованным релизом: расшифровать его может только этот сервер (ключ /etc/finplan/key.pem).
set -euo pipefail
[ "$(id -u)" = 0 ] || { echo "Запустите от root: sudo bash $0"; exit 1; }
DOMAIN=${DOMAIN:-fin.vershov.com}
RAW=https://raw.githubusercontent.com/vsershov21-spec/finplan-ios/main/server
OPS=${OPS:-vershov-commander}   # пользователь, через которого Claude выкатывает обновления и переносит данные

echo "→ PHP"
export DEBIAN_FRONTEND=noninteractive
apt-get update -qq
apt-get install -y -qq php-fpm php-cli php-sqlite3 php-curl php-mbstring php-xml php-gd php-bcmath php-intl acl openssl curl >/dev/null
PHPV=$(php -r 'echo PHP_MAJOR_VERSION.".".PHP_MINOR_VERSION;')

echo "→ пользователь и папки"
id finplan >/dev/null 2>&1 || useradd --system --home /var/lib/finplan --shell /usr/sbin/nologin finplan
install -d -o finplan -g finplan -m 2770 /var/lib/finplan /var/lib/finplan/data /var/lib/finplan/backups /var/lib/finplan/inbox
install -d -o finplan -g finplan -m 2775 /opt/finplan /opt/finplan/releases
install -d -o root -g finplan -m 0750 /etc/finplan
if [ ! -f /etc/finplan/key.pem ]; then
  openssl req -x509 -newkey rsa:3072 -nodes -keyout /etc/finplan/key.pem -out /etc/finplan/cert.pem -days 36500 -subj "/CN=finplan-deploy" 2>/dev/null
fi
chgrp finplan /etc/finplan/key.pem /etc/finplan/cert.pem; chmod 0640 /etc/finplan/key.pem; chmod 0644 /etc/finplan/cert.pem
cp /etc/finplan/cert.pem /opt/finplan/cert.pem
if id "$OPS" >/dev/null 2>&1; then
  setfacl -m u:"$OPS":rx /etc/finplan; setfacl -m u:"$OPS":r /etc/finplan/key.pem
  for d in /opt/finplan /var/lib/finplan; do setfacl -R -m u:"$OPS":rwX,u:finplan:rwX "$d"; setfacl -R -d -m u:"$OPS":rwX,u:finplan:rwX,g:finplan:rwX "$d"; done
fi

echo "→ скрипты"
for f in update.sh import.sh cron.sh backup.sh rollback.sh open-dump.php; do curl -fsSL "$RAW/$f" -o "/opt/finplan/$f"; done
chmod 755 /opt/finplan/*.sh; chown finplan:finplan /opt/finplan/*.sh /opt/finplan/open-dump.php

echo "→ PHP-FPM"
cat > /etc/php/$PHPV/fpm/pool.d/finplan.conf <<POOL
[finplan]
user = finplan
group = finplan
listen = /run/php/finplan.sock
listen.owner = caddy
listen.group = caddy
pm = ondemand
pm.max_children = 10
pm.process_idle_timeout = 60s
request_terminate_timeout = 120s
php_admin_value[upload_max_filesize] = 32M
php_admin_value[post_max_size] = 34M
php_admin_value[memory_limit] = 256M
php_admin_value[realpath_cache_ttl] = 5
php_admin_value[date.timezone] = Europe/Moscow
php_admin_value[expose_php] = Off
POOL
systemctl enable --now php$PHPV-fpm >/dev/null; systemctl restart php$PHPV-fpm

echo "→ таймеры"
mk() { # имя, описание, команда, расписание
cat > /etc/systemd/system/finplan-$1.service <<U
[Unit]
Description=Финплан — $2
After=network-online.target
[Service]
Type=oneshot
User=finplan
Group=finplan
ExecStart=$3
U
cat > /etc/systemd/system/finplan-$1.timer <<U
[Unit]
Description=Финплан — $2
[Timer]
$4
Persistent=true
[Install]
WantedBy=timers.target
U
}
mk update "проверить новый релиз" /opt/finplan/update.sh "OnBootSec=1min
OnUnitActiveSec=5min"
mk cron "напоминания, дайджест, курсы" /opt/finplan/cron.sh "OnCalendar=*-*-* *:07:00"
mk backup "ночной бэкап" /opt/finplan/backup.sh "OnCalendar=*-*-* 04:35"
systemctl daemon-reload
systemctl enable --now finplan-update.timer finplan-cron.timer finplan-backup.timer >/dev/null

echo "→ Caddy"
if ! grep -q "^$DOMAIN" /etc/caddy/Caddyfile; then
  cp /etc/caddy/Caddyfile "/etc/caddy/Caddyfile.bak.$(date +%s)"
  cat >> /etc/caddy/Caddyfile <<CADDY

$DOMAIN {
	tls {
		issuer acme {
			disable_tlsalpn_challenge
		}
	}
	root * /opt/finplan/current
	encode zstd gzip
	@closed path /data /data/* /lib /lib/* *.sqlite *.sqlite-wal *.sqlite-shm *.md
	respond @closed 403
	header {
		X-Content-Type-Options nosniff
		Referrer-Policy no-referrer
		X-Frame-Options DENY
		-Server
	}
	@nocache path / *.html *.js *.css *.webmanifest
	header @nocache Cache-Control no-cache
	@php path *.php
	php_fastcgi @php unix//run/php/finplan.sock {
		try_files {path}
	}
	file_server
}
CADDY
  caddy validate --config /etc/caddy/Caddyfile --adapter caddyfile >/dev/null
  systemctl reload caddy
fi

sudo -u finplan /opt/finplan/update.sh || true
echo
echo "Готово. Сервер: $(curl -s -4 ifconfig.me 2>/dev/null)"
echo "Дальше — перенос данных (Claude сделает сам) и смена A-записи $DOMAIN на этот IP."
