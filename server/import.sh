#!/bin/bash
# Перенос данных со старого хостинга: /opt/finplan/import.sh "<адрес выгрузки>"
# Выгрузка зашифрована ключом этого сервера (кнопка «Перенести на свой сервер» в «Безопасности»).
set -euo pipefail
URL=$1; D=/var/lib/finplan/data; T=$(mktemp -d); trap 'rm -rf "$T"' EXIT
curl -fsSL --retry 3 "$URL" -o "$T/dump.bin"
php /opt/finplan/open-dump.php /etc/finplan/key.pem "$T/dump.bin" "$T/dump.tgz"
mkdir "$T/x"; tar -xzf "$T/dump.tgz" -C "$T/x"
ls "$T/x"/*.sqlite >/dev/null 2>&1 || { echo "в выгрузке нет базы"; exit 1; }
if ls "$D"/*.sqlite >/dev/null 2>&1; then mkdir -p /var/lib/finplan/backups/before-import-$(date +%s); mv "$D"/* /var/lib/finplan/backups/before-import-*/ 2>/dev/null || true; fi
cp -a "$T/x/." "$D/"
rm -f "$D"/migrate-*.bin
chmod -R u+rwX,g+rwX "$D"; setfacl -R -m u:finplan:rwX,m::rwX "$D" 2>/dev/null || true
echo "данные перенесены: $(ls "$D" | tr '\n' ' ')"
