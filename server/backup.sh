#!/bin/bash
# Ночной бэкап базы: 14 последних копий.
set -euo pipefail
B=/var/lib/finplan/backups; D=/var/lib/finplan/data; ts=$(date +%Y%m%d-%H%M)
for db in "$D"/*.sqlite; do [ -f "$db" ] || continue; php -r '$p=new PDO("sqlite:".$argv[1]); $p->exec("VACUUM INTO ".$p->quote($argv[2]));' "$db" "$B/$(basename "$db" .sqlite)-$ts.sqlite"; gzip -f "$B/$(basename "$db" .sqlite)-$ts.sqlite"; done
tar -czf "$B/files-$ts.tgz" --exclude='*.sqlite*' -C "$D" . 2>/dev/null || true
ls -1t "$B"/*.gz 2>/dev/null | tail -n +15 | xargs -r rm -f; ls -1t "$B"/files-*.tgz 2>/dev/null | tail -n +15 | xargs -r rm -f
