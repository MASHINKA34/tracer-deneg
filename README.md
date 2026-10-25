# Милиончик

Трекер личных трат для Android: карточка месяца с календарём, категории, статистика, общие бюджеты с синхронизацией через собственный сервер. Приложение работает офлайн.

> Сейчас в репозитории каркас: заглушка приложения с дизайн-системой и каталогом компонентов, сервер с `/api/v1/health`, общий пакет с доменной логикой и логированием и проверка всего проекта одной командой.

## Структура

| Папка | Что внутри |
|---|---|
| `app/` | Flutter-приложение (Android 11+, `ru.milionchik.app`) |
| `server/` | Сервер на Dart (shelf + PostgreSQL) |
| `shared/` | Общий пакет на чистом Dart для приложения и сервера (сейчас — формат логов и маскировка секретов) |
| `deploy/` | Docker Compose: PostgreSQL для разработки и для тестов |
| `tool/` | `check.ps1` — анализ и тесты всего проекта |

## Что нужно

- Flutter stable 3.47 (Dart 3.13 в комплекте), `flutter` в `PATH`.
- Android SDK: платформа 36, эмулятор, образы Android 11 (API 30) и новее.
- Docker Desktop.
- Windows 11, PowerShell (команды ниже — для него).

## Проверка всего проекта

```powershell
powershell -ExecutionPolicy Bypass -File tool/check.ps1
```

Скрипт по очереди делает `pub get`, анализ (`--fatal-infos`) и тесты в `shared`, `server` и `app` (в `app` ещё проверка, что `tokens.g.dart` совпадает с токенами, и сверка с эталонными скриншотами). Для тестов сервера сам поднимает и убирает PostgreSQL из `deploy/docker-compose.test.yml` (порт 5433). В конце — сводка; код выхода не 0, если что-то упало.

## Сервер

1. База для разработки (порт 5434, данные в томе Docker):
   ```powershell
   docker compose -f deploy/docker-compose.dev.yml up -d --wait db
   ```
   Имя сервиса `db` обязательно: без него поднимется и сервер в Docker (см. ниже) и займёт порт 8080.
2. Настройки: скопировать `server/.env.example` в `server/.env` и вписать `JWT_SECRET` (не короче 32 символов; команда генерации — в файле). Переменные окружения важнее значений из `.env`.
3. Запуск из папки `server`:
   ```powershell
   cd server
   dart run bin/server.dart
   ```
   При старте сервер применяет новые миграции из `server/migrations` (`NNNN_имя.sql`, каждая в своей транзакции, под `pg_advisory_lock` — два сервера на одной базе не мешают друг другу) и пишет в лог каждую. Ошибка миграции — сервер не стартует, в логе файл, строка и SQLSTATE.
4. Проверка:
   ```powershell
   curl.exe http://127.0.0.1:8080/api/v1/health
   ```
   Ответ `{"status":"ok","version":"0.1.0","db":"ok"}`. Если база недоступна — `503` и `"db":"error"`, причина — в логе сервера.
5. Остановка — `Ctrl+C`: сервер закрывает HTTP и пул соединений и пишет это в лог.

| Переменная | Обязательная | По умолчанию | Что это |
|---|---|---|---|
| `DATABASE_URL` | да | — | `postgres://user:password@host:port/db?sslmode=disable` |
| `JWT_SECRET` | да | — | Секрет подписи токенов, ≥ 32 символов |
| `HOST` | нет | `0.0.0.0` | Адрес HTTP |
| `PORT` | нет | `8080` | Порт HTTP |
| `LOG_LEVEL` | нет | `info` | `debug`, `info`, `warn`, `error` |
| `MIGRATIONS_DIR` | нет | `migrations` | Папка SQL-миграций (относительный путь — от папки запуска) |

### Сервер в Docker

Образ — `server/Dockerfile`, контекст сборки — корень репозитория (нужен `shared/`). Сборка `dart compile exe` в `dart:3.13.6`, запуск в `busybox:1.38.0-musl` с библиотеками из `/runtime` образа Dart, пользователь `milionchik` (uid 10001, не root), миграции в `/app/migrations`. В контекст сборки попадает только белый список из `.dockerignore`, `server/.env` в образ не копируется.

1. Сборка и запуск вместе с базой:
   ```powershell
   docker compose -f deploy/docker-compose.dev.yml up -d --build
   ```
2. Проверка:
   ```powershell
   curl.exe http://127.0.0.1:8080/api/v1/health
   docker compose -f deploy/docker-compose.dev.yml ps
   docker compose -f deploy/docker-compose.dev.yml exec server id
   ```
   Ответ `{"status":"ok","version":"0.1.0","db":"ok"}`, у `server` статус `(healthy)`, `id` — `uid=10001(milionchik)`. `HEALTHCHECK` образа запрашивает `/api/v1/health` раз в 30 с (на старте — раз в 2 с); если база не отвечает, сервер отдаёт 503 и после трёх неудач подряд контейнер становится `unhealthy`.
3. Логи — `docker compose -f deploy/docker-compose.dev.yml logs -f server`: тот же формат, что без Docker, время в UTC.
4. Остановка сервера — `docker compose -f deploy/docker-compose.dev.yml stop server`, всего — `docker compose -f deploy/docker-compose.dev.yml down` (том с данными базы остаётся).

Настройки контейнер берёт из переменных окружения при `up`, `server/.env` он не читает. `DATABASE_URL` указывает на сервис `db`. `JWT_SECRET` по умолчанию — несекретная строка для разработки из compose-файла; `LOG_LEVEL` (по умолчанию `info`), `PRIVACY_CONTACT`, `PRIVACY_OPERATOR` — как в таблице выше. Пример:
```powershell
$env:LOG_LEVEL = "debug"; docker compose -f deploy/docker-compose.dev.yml up -d --wait
```

Сервер в Docker и `dart run bin/server.dart` слушают один порт 8080, поэтому работает только один из них: перед `dart run` останови контейнер командой из п. 4.

## Приложение

```powershell
cd app
flutter emulators --launch milionchik_api36
flutter run
```

Эмуляторы: `milionchik_api30` (Android 11) и `milionchik_api36` (Android 16, образ API 36.1), оба 360×800 dp.

- Уровень логов: `flutter run --dart-define=LOG_LEVEL=debug` (по умолчанию `info`).
- Проверка перехвата ошибок (только debug-сборка): `flutter run --dart-define=CRASH_TEST=1` — через 2 секунды после старта бросается тестовое исключение, его стек виден в логе.
- Логи: `adb logcat -s milionchik`. Ещё они пишутся в файл `files/logs/app.log` в каталоге приложения (два файла по 1 МБ):
  ```powershell
  adb exec-out run-as ru.milionchik.app cat files/logs/app.log
  ```

### Integration-тест на эмуляторе

Сценарий `app/integration_test/month_picker_day_sheet_flow_test.dart`: главная за октябрь 2026 → выбор месяца → сентябрь → назад к октябрю стрелкой › → шторка дня 17 октября → жест «назад». Данные у теста свои: база в памяти с демо-тратами (как у dev seed) и часы 19.10.2026 18:40, поэтому дата эмулятора и данные приложения на нём не важны. Тестовая сборка ставится поверх приложения на эмуляторе.

```powershell
cd app
flutter emulators --launch milionchik_api30
adb devices
flutter test integration_test -d emulator-5554
```

`emulator-5554` - имя из вывода `adb devices`. Так же на `milionchik_api36`, только перед запуском закрыть приложение: `adb shell am force-stop ru.milionchik.app` (см. «Если эмулятор с образом API 36.1+ падает»).

- Успех - `All tests passed!` в конце вывода. Шаги с длительностью видны в выводе и в `adb logcat -s milionchik` (модуль `[it]`), например `step 3/6 September chosen in picker and shown on main screen in 590ms`. Упавший шаг - строка `ERROR [it] step N/6 "<шаг>" failed after …ms` с причиной и стеком.
- Подробные логи приложения во время теста: добавить `--dart-define=LOG_LEVEL=debug`.
- Первый запуск собирает APK через Gradle и скачивает зависимости `integration_test` (около 3 минут), повторный - около 1-1,5 минуты; сам сценарий идёт 5-16 секунд.
- В `tool/check.ps1` integration-тест не входит: ему нужен запущенный эмулятор, сборка и установка APK занимают минуты, а полная проверка проекта должна проходить без устройства.

### Замер кадров анимации декора

Сценарий `app/integration_test/decor_animation_perf_test.dart`: главная 29 декабря 2026 (Новый год, база в памяти с тратами декабря), 10 секунд анимации декора, потом 5 секунд с выключенными системными анимациями. Время кадров честное только в profile-сборке:

```powershell
cd app
adb shell am force-stop ru.milionchik.app
flutter drive --profile --driver=test_driver/integration_test.dart --target=integration_test/decor_animation_perf_test.dart -d emulator-5554
```

- Итог - `All tests passed!`; цифры - в `app/build/integration_response_data.json` (`newyear_animated` и `animations_disabled`: число кадров, среднее/90-й/99-й/худшее время сборки (UI) и растеризации кадра в мс, пропуски `missed_frame_*_budget_count`, `tickers_max` - сколько тикеров анимаций было активно) и строками `decor perf animated: …` / `decor perf animations disabled: …` в `adb logcat -s milionchik`.
- Эмулятор рисует медленнее телефона, поэтому сравнивать цифры имеет смысл только между прогонами на одном образе.
- `flutter drive` после прогона удаляет приложение с эмулятора вместе с данными; чтобы оставить его (и данные), добавь `--keep-app-running` и потом поставь обычную сборку через `flutter run`.
- Без анимаций кадры всё равно идут: тестовая обвязка `integration_test` сама просит кадр после каждого кадра. Поэтому «тишину» сценарий проверяет по числу активных тикеров (`tickers max=0` в логе), а не по числу кадров.

### Локальная база (`app/lib/data/db/`)

База на телефоне — SQLite через drift: таблицы в `tables.dart`, класс `AppDatabase` и версия схемы (`schemaVersion`) в `app_database.dart`, запуск шагов миграции и ошибка неизвестной версии — в `migrations.dart`. Снимки схемы каждой версии лежат в `app/drift_schemas/app_database/drift_schema_v<N>.json`, их тестовые копии — в `app/test/data/db/app_database/generated/` (настройка — `app/build.yaml`). Тест `test/data/db/schema_snapshot_test.dart` сверяет текущую схему со снимком последней версии: если поменять таблицу и не выпустить новую версию, он краснеет и пишет, какая колонка или индекс разошлись.

Порядок изменения схемы (всё из папки `app`):

1. Поменять таблицы в `tables.dart` и поднять `schemaVersion` в `app_database.dart` на 1. Версию никогда не уменьшать и не переиспользовать.
2. Пересоздать код базы и снять снимок новой версии:
   ```powershell
   dart run build_runner build
   dart run drift_dev make-migrations
   ```
   Появятся `drift_schemas/app_database/drift_schema_v<N>.json`, `lib/data/db/app_database.steps.dart` (функции `migrationSteps` и классы `Schema<N>`), тестовые копии схем в `test/data/db/app_database/generated/` и заготовка `test/data/db/app_database/migration_test.dart`. Старые снимки не трогать и не пересоздавать.
3. Написать шаг миграции: в `app_database.dart` импортировать `app_database.steps.dart` и в `_upgradeSchema` передать шаги в `migrateSchema`, например для новой колонки `note` в `local_prefs`:
   ```dart
   migrateSchema(
     m,
     from: from,
     to: to,
     steps: migrationSteps(
       from1To2: (m, schema) async {
         await m.addColumn(schema.localPrefs, schema.localPrefs.note);
       },
     ),
   );
   ```
   `schema` — схема той версии, в которую переводит шаг (`Schema2` …). Каждый шаг переводит базу ровно на одну версию, версия в файле сохраняется после каждого шага. Пока шага нет, тест из шага 4 падает с `UnknownSchemaVersionException: no migration from database schema version 1 to app schema version 2`.
4. Проверить. В заготовке `migration_test.dart` убрать `// ignore_for_file` и комментарии `TODO` (в репозитории их нет), для изменённых колонок заполнить тест с данными. Поправить тесты, где схема записана явно (`schema_test.dart`, `open_database_test.dart`). Затем:
   ```powershell
   flutter test test/data/db
   ```
   и полная проверка `tool/check.ps1`. Все файлы из шага 2 коммитятся вместе с изменением схемы.

Если файл базы на телефоне новее приложения (поставили старую сборку поверх новой) или для его версии нет шага, база не открывается: в логе `[db]` строка `schema migration failed from=<было> to=<стало>` с причиной и стеком, файл остаётся как был.

### Дизайн-система (`app/lib/ui/`)

Цвета, шрифты, отступы, компоненты и декор карточки месяца — из макетов Figma; экраны собираются только из этих деталей.

- **Токены.** `app/tool/design-tokens.json` (выгрузка переменных Figma) → `app/lib/ui/tokens/tokens.g.dart`. Сгенерированный файл руками не правится; после изменения JSON:
  ```powershell
  cd app
  dart run tool/gen_tokens.dart
  ```
  `dart run tool/gen_tokens.dart --check` только проверяет, что файл актуален (это шаг `check.ps1`).
- **Тема:** `AppTheme.build(brightness, mood)` — светлая/тёмная × 15 «настроений» (4 сезона + 11 праздников). Цвета — `context.colors` (нейтральные, категории) и `context.mood` (акцент, подсветка дней, декор).
- **Шрифты** Unbounded и Manrope лежат в `app/assets/fonts/` вместе с лицензиями `OFL.txt`; иконки — SVG из Figma в `app/assets/icons/`.
- **Каталог компонентов** (только debug-сборка): долгий тап по логотипу на главной. Переключатели темы, настроения, масштаба шрифта и ширины экрана.
- **Эталонные скриншоты** (`app/test/ui/golden/goldens/`) проверяются обычным `flutter test`. Если внешний вид изменён намеренно — пересоздать и просмотреть изменения:
  ```powershell
  cd app
  flutter test --update-goldens test/ui/golden
  ```
  Эталоны рисуются на Windows: настоящие шрифты приложения и эмодзи Segoe UI Emoji из `C:\Windows\Fonts`.

### Если эмулятор с образом API 36.1+ падает

На некоторых компьютерах (эмулятор 37.2.12) системный графический драйвер образов API 36.1 и 37 падает при чтении кадра (`mapper.ranchu: Assertion failed: !rcEnc->featureInfo()->hasReadColorBufferDma`), и вместе с ним перезапускается `system_server`. Помогает:

- навигация тремя кнопками вместо жестов (настройка сохраняется в эмуляторе):
  ```powershell
  adb shell cmd overlay enable-exclusive --category com.android.internal.systemui.navbar.threebutton
  ```
- снимок экрана — средствами эмулятора, а не `adb shell screencap`:
  ```powershell
  adb emu screenrecord screenshot .
  ```
- если повторный `flutter run` при уже открытом приложении завершается ошибкой `Activity class {ru.milionchik.app/…MainActivity} does not exist` — это система эмулятора перезапустилась (падает снимок задачи старого экземпляра); запустить `flutter run` ещё раз.

## Логи

Одна строка — одно событие, формат общий для приложения и сервера:

```
2026-10-19T18:40:12.345+03:00 INFO  [http] GET /api/v1/health 200 in 4ms size=43 ip=127.0.0.1 rid=7f3a0c1d9b2e4f60
```

Время с миллисекундами и поясом, уровень, модуль, сообщение, контекст `key=value`. Все строки одного запроса связаны `rid` (заголовок `X-Request-Id`). Ошибки — с типом, сообщением, кодом и полным стеком. Пароли, токены и коды в лог не попадают: токены видны как `***(43)`, логины как `an***`, коды приглашений как `MLN-****`.
