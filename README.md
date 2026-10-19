# Милиончик

Трекер личных трат для Android: карточка месяца с календарём, категории, статистика, общие бюджеты с синхронизацией через собственный сервер. Приложение работает офлайн.

> Сейчас в репозитории каркас: заглушка приложения, сервер с `/api/v1/health`, общий пакет с логированием и проверка всего проекта одной командой.

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

Скрипт по очереди делает `pub get`, анализ (`--fatal-infos`) и тесты в `shared`, `server` и `app`. Для тестов сервера сам поднимает и убирает PostgreSQL из `deploy/docker-compose.test.yml` (порт 5433). В конце — сводка; код выхода не 0, если что-то упало.

## Сервер

1. База для разработки (порт 5434, данные в томе Docker):
   ```powershell
   docker compose -f deploy/docker-compose.dev.yml up -d --wait
   ```
2. Настройки: скопировать `server/.env.example` в `server/.env` и вписать `JWT_SECRET` (не короче 32 символов; команда генерации — в файле). Переменные окружения важнее значений из `.env`.
3. Запуск из папки `server`:
   ```powershell
   cd server
   dart run bin/server.dart
   ```
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

## Приложение

```powershell
cd app
flutter emulators --launch milionchik_api37
flutter run
```

- Уровень логов: `flutter run --dart-define=LOG_LEVEL=debug` (по умолчанию `info`).
- Проверка перехвата ошибок (только debug-сборка): `flutter run --dart-define=CRASH_TEST=1` — через 2 секунды после старта бросается тестовое исключение, его стек виден в логе.
- Логи: `adb logcat -s milionchik`. Ещё они пишутся в файл `files/logs/app.log` в каталоге приложения (два файла по 1 МБ):
  ```powershell
  adb exec-out run-as ru.milionchik.app cat files/logs/app.log
  ```

## Логи

Одна строка — одно событие, формат общий для приложения и сервера:

```
2026-10-19T18:40:12.345+03:00 INFO  [http] GET /api/v1/health 200 in 4ms size=43 ip=127.0.0.1 rid=7f3a0c1d9b2e4f60
```

Время с миллисекундами и поясом, уровень, модуль, сообщение, контекст `key=value`. Все строки одного запроса связаны `rid` (заголовок `X-Request-Id`). Ошибки — с типом, сообщением, кодом и полным стеком. Пароли, токены и коды в лог не попадают: токены видны как `***(43)`, логины как `an***`, коды приглашений как `MLN-****`.
