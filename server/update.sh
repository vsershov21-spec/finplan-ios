#!/bin/bash
# Новый релиз → расшифровать → проверить → переключить. Без нового релиза ничего не делает.
set -euo pipefail
REL=${REL:-https://raw.githubusercontent.com/vsershov21-spec/finplan-ios/web-dist}
D=/opt/finplan; KEY=/etc/finplan/key.pem
T=$(mktemp -d -p "$D/releases" .tmp-XXXX); trap 'rm -rf "$T"' EXIT
curl -fsSL --retry 3 "$REL/VERSION" -o "$T/VERSION" || { echo "релиза нет"; exit 0; }
read -r VER SHA < "$T/VERSION"
[[ "$VER" =~ ^[A-Za-z0-9._-]+$ ]] || { echo "плохая версия"; exit 1; }
[ -d "$D/releases/$VER" ] && [ "$(readlink -f $D/current)" = "$D/releases/$VER" ] && exit 0
if [ ! -d "$D/releases/$VER" ]; then
  curl -fsSL --retry 3 "$REL/finplan-web.bin" -o "$T/web.bin"
  openssl cms -decrypt -binary -inform DER -in "$T/web.bin" -inkey "$KEY" -out "$T/web.tgz"
  echo "$SHA  $T/web.tgz" | sha256sum -c --quiet
  mkdir -p "$T/x"; tar -xzf "$T/web.tgz" -C "$T/x"
  for f in $(find "$T/x" -name '*.php'); do php -l "$f" >/dev/null || { echo "ошибка в $f"; exit 1; }; done
  rm -rf "$T/x/data"; ln -s /var/lib/finplan/data "$T/x/data"
  chmod -R a+rX "$T/x"; mv "$T/x" "$D/releases/$VER"
fi
ln -sfn "$D/releases/$VER" "$D/current.new" && mv -Tf "$D/current.new" "$D/current"
echo "$VER $(date -Is)" >> "$D/deploy.log"
ls -1dt "$D"/releases/*/ | grep -v "/.tmp-" | tail -n +7 | xargs -r rm -rf
echo "включён $VER"
