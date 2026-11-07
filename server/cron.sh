#!/bin/bash
# Планировщик приложения (раньше — cron хостинга): напоминания, дайджест, курсы.
set -euo pipefail
cd /opt/finplan/current
KEY=$(php -r 'require "lib/bootstrap.php"; echo (string)setting("cron_key");' 2>/dev/null || true)
[ -n "$KEY" ] || exit 0
php cron.php "$KEY" >/dev/null
