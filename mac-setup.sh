#!/bin/bash
# Финплан: собрать проект на Маке и открыть в Xcode.
# Запуск:  bash mac-setup.sh ВАШ_TEAM_ID
# Team ID: Xcode → Settings → Accounts → ваша команда, или developer.apple.com → Membership (10 символов).
set -e
cd "$(dirname "$0")"
TEAM="${1:-$TEAM_ID}"
if [ -z "$TEAM" ]; then
  TEAM=$(security find-certificate -c "Apple Development" -p 2>/dev/null | openssl x509 -noout -subject 2>/dev/null | grep -o "OU *= *[A-Z0-9]\{10\}" | grep -o "[A-Z0-9]\{10\}$" | head -1)
  [ -n "$TEAM" ] && echo "Нашёл команду в связке ключей: $TEAM (если не та, запустите: bash mac-setup.sh ВАШ_TEAM_ID)"
fi
if [ -z "$TEAM" ]; then echo "Укажите Team ID: bash mac-setup.sh ABCDE12345"; exit 1; fi
if ! command -v xcodegen >/dev/null; then
  if ! command -v brew >/dev/null; then echo "Нужен Homebrew: https://brew.sh, затем запустите скрипт ещё раз"; exit 1; fi
  echo "Ставлю XcodeGen…"; brew install xcodegen
fi
TEAM_ID="$TEAM" xcodegen generate
echo "Проект готов. Открываю Xcode: выберите свой iPhone сверху и нажмите ▶ (Cmd+R)."
open Finplan.xcodeproj
