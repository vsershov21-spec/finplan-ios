# Финплан на своём сервере

Сервер приложения — на VPS Vershov Studio (рядом с «Вдвоём»). Код приходит **зашифрованным** релизом `web-latest`
из этого репозитория: расшифровать его может только сервер (ключ `/etc/finplan/key.pem` не покидает VPS).
В репозитории лежат только скрипты и открытый сертификат `cert.pem` — ни кода сайта, ни данных, ни токенов.

- Установка, один раз от root: `sudo bash -c "$(curl -fsSL https://raw.githubusercontent.com/vsershov21-spec/finplan-ios/main/server/install.sh)"`
- Обновления: сервер сам проверяет релиз каждые 5 минут (`finplan-update.timer`). Журнал — `/opt/finplan/deploy.log`.
- Откат: `/opt/finplan/rollback.sh`.
- Данные: `/var/lib/finplan/data`, бэкапы каждую ночь — `/var/lib/finplan/backups` (14 копий).
- Планировщик приложения (раньше cron хостинга): `finplan-cron.timer`, раз в час.
