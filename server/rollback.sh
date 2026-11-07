#!/bin/bash
# Вернуть предыдущий релиз: /opt/finplan/rollback.sh
set -euo pipefail
D=/opt/finplan; cur=$(readlink -f $D/current)
prev=$(ls -1dt "$D"/releases/*/ | sed 's#/$##' | grep -vx "$cur" | head -1)
[ -n "$prev" ] || { echo "нет предыдущего"; exit 1; }
ln -sfn "$prev" "$D/current.new" && mv -Tf "$D/current.new" "$D/current"
echo "откат на $(basename "$prev") $(date -Is)" >> "$D/deploy.log"; echo "откат на $(basename "$prev")"
