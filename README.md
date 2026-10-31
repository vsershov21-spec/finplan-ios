# Финплан для iPhone

Нативное приложение на Swift. Внутри — сайт fin.vershov.com во весь экран. Поверх сайта приложение добавляет то, чего нет в браузере:

- **Face ID** при открытии и вход без пароля. Пароль хранится в связке ключей iPhone.
- **Виджет**: на домашнем экране малый и средний, на экране блокировки — строка, круг и прямоугольник.
- **Taptic Engine**: вибрация на сохранении, удалении, свайпе и быстрой трате.
- **Пуши через Apple (APNs)** и цифра на значке.
- **Ссылки и файлы**: Telegram, календарь и внешние ссылки открываются снаружи. Выгрузка данных открывается через «Поделиться».

Код сайта обновляется установщиком install.php, как раньше. Приложение пересобирать не нужно: оно всегда открывает свежую версию сайта.

## Сборка

Мак не нужен, всё собирает GitHub Actions на macOS.

- **«Проверка сборки»** запускается на каждый push. Она собирает приложение для симулятора, запускает его и делает снимки экрана. Результат лежит в Artifacts.
- **«TestFlight»** запускается вручную. Она подписывает приложение и загружает его в App Store Connect.

## Первый выпуск: один раз

### 1. Apple Developer

На developer.apple.com → Certificates, IDs & Profiles:

1. **Identifiers → App Groups → +.** Создайте `group.com.vershov.finplan`.
2. **Identifiers → App IDs → +**, тип App. Bundle ID `com.vershov.finplan`. Включите:
   - Push Notifications;
   - App Groups (выберите группу из шага 1).
3. Ещё один App ID: `com.vershov.finplan.widget`, тоже с App Groups и той же группой.
4. **Keys → +.** Назовите ключ «Finplan Push» и включите Apple Push Notifications service (APNs).
   - Скачайте файл `AuthKey_XXXXXXXXXX.p8`. Скачать его можно только один раз.
   - Запишите Key ID.
5. **Membership** (вверху справа): запишите Team ID.

### 2. App Store Connect

1. **Apps → + → New App.** Платформа iOS, название «Финплан», язык русский, Bundle ID `com.vershov.finplan`, SKU `finplan`.
2. **Users and Access → Integrations → App Store Connect API → +.**
   - Роль: **Admin**. Она нужна, чтобы GitHub сам создал сертификат подписи.
   - Скачайте `AuthKey_YYYYYYYYYY.p8`.
   - Запишите Key ID и Issuer ID (он показан над таблицей).

### 3. Секреты в GitHub

Откройте репозиторий → Settings → Secrets and variables → Actions → New repository secret. Добавьте четыре секрета:

| Секрет | Что вписать |
|---|---|
| `APPLE_TEAM_ID` | Team ID из шага 1.5 |
| `ASC_KEY_ID` | Key ID ключа App Store Connect из шага 2.2 |
| `ASC_ISSUER_ID` | Issuer ID из шага 2.2 |
| `ASC_KEY_P8` | всё содержимое файла `AuthKey_YYYYYYYYYY.p8` из шага 2.2, вместе со строками BEGIN и END |

### 4. Выпуск

1. Откройте Actions → TestFlight → Run workflow.
2. Через 10–15 минут сборка появится в App Store Connect → TestFlight.
3. В TestFlight → Internal Testing добавьте себя и Настю. Внутренним тестировщикам проверка Apple не нужна.
4. На iPhone поставьте TestFlight из App Store и установите Финплан.

### 5. Пуши

В Финплане откройте Профиль → Уведомления на телефон → «Пуши в приложение для iPhone». Это может сделать только владелец.

1. Впишите Key ID и Team ID из шага 1.
2. Вставьте всё содержимое файла APNs-ключа (`AuthKey_XXXXXXXXXX.p8`).
3. Нажмите «Сохранить».

Потом в приложении включите «Пуши на этом телефоне» и нажмите «Прислать тестовый». Если что-то не так, под кнопкой появится ответ Apple.

Сборки TestFlight работают с боевыми серверами APNs (production). Отладочные сборки из Xcode — с тестовыми (sandbox). Сервер различает их сам.
