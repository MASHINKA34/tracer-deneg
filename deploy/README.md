# Деплой сервера Милиончика на VPS с нуля

Инструкция ведёт от покупки VPS до работающего `https://<домен>/api/v1/health`, ежедневных бэкапов и обновлений. На сервере работают три контейнера из `deploy/docker-compose.yml`: `db` (PostgreSQL 18.6), `server` (сервер Милиончика, собирается из `server/Dockerfile`) и `caddy` (HTTPS-сертификат Let's Encrypt и проксирование `/api/*`, `/privacy`, `/delete-account`). Наружу открыты только порты 80 и 443 Caddy, база и сервер доступны только внутри сети Docker.

Обозначения:

- `<домен>` - имя сервера, например `api.example.ru` (домен ещё не выбран).
- `<IP-сервера>` - публичный IPv4-адрес VPS из панели провайдера.
- Блоки `bash` выполняются на сервере (Ubuntu), блоки `powershell` - на своём компьютере с Windows.
- Пользователь на сервере - `deploy`, код - в `/opt/milionchik`. Если выбираешь другие, замени их во всех командах (и в строке crontab).

Как проверялась инструкция (25.10.2026): шаги 9-15 (`.env`, запуск, health, бэкап, проверка и оба варианта восстановления, пересборка при обновлении, логи, отчёты об ошибках) и часть таблицы шага 16 (пустой `.env`, сменённый пароль базы, короткий `JWT_SECRET`, остановленные `server` и `db`) прогнаны на Windows 11 + Docker Desktop 29.8 с `DOMAIN=localhost` - Caddy выдаёт сертификат своего локального центра, поэтому там `curl -k`. Не проверялись: шаги 1-8 (VPS, SSH, swap, sysctl, ufw, установка Docker, DNS, клонирование) - VPS ещё нет; строка crontab, `journalctl`, `scp`, `git pull` и `docker image prune` - нужен настоящий сервер.

## 1. Выбор VPS

| Что | Рекомендация | Откуда цифры |
|---|---|---|
| Система | Ubuntu Server 26.04 LTS (64-бит) | Актуальная LTS: вышла в апреле 2026, стандартная поддержка до мая 2031 ([ubuntu.com/about/release-cycle](https://ubuntu.com/about/release-cycle), проверено 25.10.2026). Docker официально поддерживает 26.04, 24.04 и 22.04 LTS - если у провайдера ещё нет 26.04, подойдёт 24.04 |
| Архитектура и виртуализация | x86_64 (amd64), KVM | Образы и сборка проверялись только на amd64. В контейнерных VPS (OpenVZ, LXC) Docker и `sysctl` часто недоступны |
| Память | 2 ГБ; минимум 1 ГБ + swap 2 ГБ (шаг 3) | Лимиты контейнеров в compose: db 512 МБ + server 768 МБ + caddy 128 МБ = 1408 МБ (это потолки, а не резерв). Замер 25.10.2026 на тестовых данных: в покое db 26 МБ, server 15 МБ, caddy 13 МБ; сборка сервера (`dart compile exe` на 1 CPU) - пик около 350 МБ. Ubuntu Server: минимум 1 ГБ для облачных образов, советуют от 3 ГБ ([системные требования](https://ubuntu.com/server/docs/reference/installation/system-requirements/), страница написана для 24.04) |
| Процессор | 1 vCPU | Сборка сервера на 1 CPU локально - 9 с, на VPS дольше (не замерялось) |
| Диск | SSD от 20 ГБ | Ubuntu - до 5 ГБ (советуют от 25 ГБ на всё). Образы: postgres:18.6 650 МБ + caddy:2.11.7 93 МБ + сервер 24 МБ (около 770 МБ), для сборки сервера ещё dart:3.13.6 1,2 ГБ и кэш сборки. Логи контейнеров - до 50 МБ на контейнер (ротация в compose). База и 14 ежедневных бэкапов - по объёму данных |
| Сеть | Публичный IPv4 | DNS - только A-запись (шаг 7) |

На Windows понадобится клиент OpenSSH - в Windows 11 он встроен:

```powershell
ssh -V
```

Ответ вида `OpenSSH_for_Windows_9.5p2, LibreSSL 3.8.2`.

## 2. Первичная настройка Ubuntu

### 2.1. SSH-ключ на Windows

```powershell
ssh-keygen -t ed25519 -C "milionchik-vps"
Get-Content $env:USERPROFILE\.ssh\id_ed25519.pub
```

`ssh-keygen` спросит путь (Enter - `C:\Users\<имя>\.ssh\id_ed25519`) и пароль ключа (лучше задать). Если ключ уже есть и спрашивает `Overwrite (y/n)?` - ответить `n` и взять существующий. Закрытый ключ `id_ed25519` никому не передавать.

Строку `ssh-ed25519 AAAA… milionchik-vps` (открытый ключ) вставить в поле «SSH-ключ» при заказе VPS. Если провайдер выдал только пароль root, положить ключ на сервер так (спросит пароль root один раз):

```powershell
Get-Content $env:USERPROFILE\.ssh\id_ed25519.pub | ssh root@<IP-сервера> "umask 077; mkdir -p ~/.ssh && tr -d '\r' >> ~/.ssh/authorized_keys"
```

`tr -d '\r'` убирает символ конца строки Windows, который PowerShell добавляет при передаче текста в `ssh`.

### 2.2. Вход и обновления

```powershell
ssh root@<IP-сервера>
```

При первом входе `ssh` покажет отпечаток ключа сервера - если провайдер показывает его в панели, сверить и ответить `yes`. Если провайдер создал пользователя `ubuntu` вместо root - войти им и выполнить `sudo -i`.

```bash
apt update && apt full-upgrade -y
[ -f /var/run/reboot-required ] && reboot
```

Если сервер ушёл в перезагрузку - подождать минуту и войти снова.

Часовой пояс по умолчанию - UTC, его можно не менять: сервер Милиончика пишет логи в UTC, а время запуска бэкапа в crontab (шаг 12) задаётся по поясу сервера. Посмотреть: `timedatectl`.

### 2.3. Пользователь без root

```bash
adduser deploy
usermod -aG sudo deploy
install -d -m 700 -o deploy -g deploy /home/deploy/.ssh
install -m 600 -o deploy -g deploy /root/.ssh/authorized_keys /home/deploy/.ssh/authorized_keys
```

`adduser` спросит пароль (он нужен для `sudo`, сохранить в менеджер паролей), а потом имя и другие данные - их можно пропустить через Enter. Если входили пользователем `ubuntu`, во второй команде `install` вместо `/root/.ssh/authorized_keys` - `/home/ubuntu/.ssh/authorized_keys`.

Не закрывая текущее окно, в новом окне PowerShell:

```powershell
ssh deploy@<IP-сервера>
```

и на сервере:

```bash
sudo -v && echo sudo ok
```

Дальше всё делается от `deploy`.

### 2.4. SSH только по ключу, без root

```bash
sudo tee /etc/ssh/sshd_config.d/10-milionchik.conf >/dev/null <<'EOF'
PermitRootLogin no
PasswordAuthentication no
KbdInteractiveAuthentication no
EOF
sudo sshd -t
sudo systemctl restart ssh.service
sudo sshd -T | grep -E '^(permitrootlogin|passwordauthentication|kbdinteractiveauthentication|pubkeyauthentication) '
```

Должно вывести `permitrootlogin no`, `passwordauthentication no`, `kbdinteractiveauthentication no`, `pubkeyauthentication yes`. Имя файла начинается с `10-`: OpenSSH берёт первое встреченное значение, а файлы из `sshd_config.d` читаются по алфавиту, поэтому настройки должны идти раньше файла облачного образа `50-cloud-init.conf`, который может включать вход по паролю ([Ubuntu: OpenSSH server](https://ubuntu.com/server/docs/how-to/security/openssh-server/)).

Проверить в новом окне PowerShell, пока старое открыто: `ssh deploy@<IP-сервера>` входит, `ssh root@<IP-сервера>` отвечает `Permission denied (publickey)`.

### 2.5. Автоматические обновления

В Ubuntu Server пакет `unattended-upgrades` стоит и включён сразу: раз в день он ставит обновления безопасности Ubuntu ([Ubuntu: automatic updates](https://ubuntu.com/server/docs/how-to/software/automatic-updates/)). Проверить:

```bash
cat /etc/apt/apt.conf.d/20auto-upgrades
ls /var/log/unattended-upgrades/
```

В первом файле должна быть строка `APT::Periodic::Unattended-Upgrade "1";`. Сам он не перезагружает сервер и не обновляет пакеты Docker (они из репозитория Docker, а не Ubuntu) - это делается вручную раз в месяц (шаг 13.3).

## 3. Swap (если памяти меньше 2 ГБ)

```bash
free -h
swapon --show
```

Если `swapon --show` ничего не вывел и памяти 1 ГБ:

```bash
sudo fallocate -l 2G /swapfile
sudo chmod 600 /swapfile
sudo mkswap /swapfile
sudo swapon /swapfile
echo '/swapfile none swap sw 0 0' | sudo tee -a /etc/fstab
free -h
```

В строке `Swap:` должно стать `2.0Gi`.

## 4. Буфер UDP для HTTP/3

Caddy отвечает и по HTTP/3 (UDP 443) и просит у ядра буфер UDP 7 МБ. Без настройки в логе Caddy появляется строка `failed to sufficiently increase receive buffer size (was: 208 kiB, wanted: 7168 kiB, got: 416 kiB)` - HTTP/3 работает, но медленнее. Значения - из [quic-go: UDP Buffer Sizes](https://github.com/quic-go/quic-go/wiki/UDP-Buffer-Sizes):

```bash
sudo tee /etc/sysctl.d/60-milionchik-udp.conf >/dev/null <<'EOF'
net.core.rmem_max=7500000
net.core.wmem_max=7500000
EOF
sudo sysctl --system
sysctl net.core.rmem_max net.core.wmem_max
```

Должно вывести `net.core.rmem_max = 7500000` и `net.core.wmem_max = 7500000`; после перезагрузки значения сохраняются. Если провайдер запрещает менять эти параметры (`sysctl --system` пишет ошибку про `net.core.rmem_max`), шаг можно пропустить. Если Caddy уже запущен - `docker compose restart caddy` (из `/opt/milionchik/deploy`).

## 5. Файрвол ufw

```bash
sudo apt install -y ufw
sudo ufw default deny incoming
sudo ufw default allow outgoing
sudo ufw allow 22/tcp
sudo ufw allow 80/tcp
sudo ufw allow 443/tcp
sudo ufw allow 443/udp
sudo ufw enable
sudo ufw status verbose
```

На вопрос `Command may disrupt existing ssh connections. Proceed with operation (y|n)?` ответить `y` - порт 22 уже открыт. В выводе `Status: active`, `Default: deny (incoming)` и правила для 22/tcp, 80/tcp, 443/tcp, 443/udp (IPv4 и `(v6)`). 80 нужен Let's Encrypt для проверки домена и для перенаправления на HTTPS, 443/udp - HTTP/3.

Важно: порты, которые публикует Docker (`ports:` в compose), обходят правила ufw ([Docker: Docker and ufw](https://docs.docker.com/engine/network/packet-filtering-firewalls/)). В `docker-compose.yml` опубликованы только 80 и 443 Caddy; не добавляй `ports:` сервисам `db` и `server` - они окажутся открыты в интернет независимо от ufw.

Если у провайдера есть свой файрвол в панели - открыть там те же порты.

## 6. Docker

Официальный способ - apt-репозиторий Docker: [docs.docker.com/engine/install/ubuntu](https://docs.docker.com/engine/install/ubuntu/) (проверено 25.10.2026, страница обновлена 12.10.2026; в репозитории для 26.04 на эту дату docker-ce 29.9.2 и docker-compose-plugin 5.6.1). Команды ниже - из этой страницы; если она изменилась, делать по ней.

Убрать пакеты, которые конфликтуют с Docker (на чистой системе apt скажет, что их нет):

```bash
sudo apt remove $(dpkg --get-selections docker.io docker-compose docker-compose-v2 docker-doc docker-buildx podman-docker containerd runc | cut -f1)
```

Подключить репозиторий:

```bash
sudo apt update
sudo apt install ca-certificates curl
sudo install -m 0755 -d /etc/apt/keyrings
sudo curl -fsSL https://download.docker.com/linux/ubuntu/gpg -o /etc/apt/keyrings/docker.asc
sudo chmod a+r /etc/apt/keyrings/docker.asc
sudo tee /etc/apt/sources.list.d/docker.sources <<EOF
Types: deb
URIs: https://download.docker.com/linux/ubuntu
Suites: $(. /etc/os-release && echo "${UBUNTU_CODENAME:-$VERSION_CODENAME}")
Components: stable
Architectures: $(dpkg --print-architecture)
Signed-By: /etc/apt/keyrings/docker.asc
EOF
sudo apt update
```

Установить и проверить:

```bash
sudo apt install docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
sudo docker run --rm hello-world
systemctl is-enabled docker
```

`hello-world` печатает `Hello from Docker!`, `is-enabled` - `enabled` (Docker сам стартует после перезагрузки).

Запуск `docker` без `sudo` ([post-installation steps](https://docs.docker.com/engine/install/linux-postinstall/)):

```bash
sudo usermod -aG docker $USER
exit
```

Войти снова (`ssh deploy@<IP-сервера>`) и проверить:

```bash
docker version --format '{{.Server.Version}}'
docker compose version
```

Группа `docker` даёт права, равные root, - в неё добавляется только `deploy`.

Логи контейнеров отдельно настраивать не нужно: ротация (`json-file`, 10 МБ × 5 файлов на контейнер) задана в `docker-compose.yml`.

## 7. DNS

У регистратора домена создать A-запись: имя `<домен>` → значение `<IP-сервера>`, TTL 300-3600. `DOMAIN` в `.env` (шаг 9) должен совпадать с этим именем буква в букву.

AAAA-запись (IPv6) не создавать, а если регистратор поставил свою (например, на страницу-заглушку) - удалить. Сети Docker в `docker-compose.yml` только IPv4: подключения по IPv6 Docker передаёт в контейнер через свой прокси ([Docker: port publishing](https://docs.docker.com/engine/network/port-publishing/)), и Caddy видит не адрес телефона, а адрес внутри Docker (предполагаю по устройству прокси Docker, не проверялось). Тогда лимиты сервера по IP (30 запросов в минуту на `/auth/*`) делили бы все клиенты IPv6 на одних. Включение IPv6 - отдельная правка compose.

Проверить с Windows (может занять до TTL после изменения записи):

```powershell
Resolve-DnsName <домен> -Type A -DnsOnly
Resolve-DnsName <домен> -Type AAAA -DnsOnly
```

Первая команда должна вернуть `<IP-сервера>`, вторая - не вернуть ни одной строки с типом `AAAA`. На сервере: `getent hosts <домен>`.

Запускать Caddy (шаг 10) только после того, как A-запись отвечает правильным адресом: сертификат он запрашивает сразу при старте.

## 8. Код на сервер

На сервер попадает то, что лежит в ветке `main` на GitHub, - перед деплоем изменения должны быть запушены.

```bash
sudo apt install -y git
sudo install -d -o deploy -g deploy /opt/milionchik
git clone https://github.com/MASHINKA34/tracer-deneg.git /opt/milionchik
cd /opt/milionchik
git log -1 --oneline
ls -l deploy/backup.sh deploy/restore.sh
```

Последняя команда должна показать `-rwxr-xr-x` (скрипты исполняемые).

## 9. Настройки `.env`

`deploy/.env` в git не попадает. Пароли генерируются прямо в файл и на экран не выводятся:

```bash
cd /opt/milionchik/deploy
cp .env.example .env
chmod 600 .env
sed -i "s|^POSTGRES_PASSWORD=.*|POSTGRES_PASSWORD=$(openssl rand -hex 32)|" .env
sed -i "s|^JWT_SECRET=.*|JWT_SECRET=$(openssl rand -base64 48)|" .env
sed -i "s|^LOG_LEVEL=.*|LOG_LEVEL=info|" .env
sed -i "s|^DOMAIN=.*|DOMAIN=<домен>|" .env
nano .env
```

В `nano` заполнить `PRIVACY_CONTACT` (почта или Telegram для вопросов о данных) и `PRIVACY_OPERATOR` (имя или ник оператора данных) - они видны всем на странице `https://<домен>/privacy`. Кавычки не нужны, пробелы и кириллица допустимы, символ `$` - нет. Сохранить: Ctrl+O, Enter, выход - Ctrl+X.

| Переменная | Что это |
|---|---|
| `DOMAIN` | Имя из шага 7 |
| `POSTGRES_PASSWORD` | Пароль базы, 64 символа `0-9a-f` (входит в адрес подключения сервера, поэтому только латиница и цифры) |
| `JWT_SECRET` | Секрет подписи токенов, 64 символа |
| `LOG_LEVEL` | `info`; `debug` - только на время разбора (шаг 14) |
| `PRIVACY_CONTACT`, `PRIVACY_OPERATOR` | Для `/privacy`; пустые - на странице «не указан» и `WARN` в логе сервера |

Проверить, что всё заполнено, не показывая значения:

```bash
awk -F= '/^[A-Z_]+=/ { print $1 " " length(substr($0, index($0, "=") + 1)) }' .env
docker compose config --quiet && echo config ok
```

Первая команда печатает длины: `POSTGRES_PASSWORD 64`, `JWT_SECRET 64`, у остальных - больше 0. Вторая - `config ok`; если переменной нет, например `required variable DOMAIN is missing a value: DOMAIN is required, set it in deploy/.env`. `docker compose config` без `--quiet` печатает пароли - не запускать при посторонних и не вставлять его вывод в чаты.

- Команды с `openssl` выполнять один раз, до первого запуска. PostgreSQL запоминает пароль при создании тома с данными; если потом поменять `POSTGRES_PASSWORD`, сервер не стартует (шаг 16).
- Сразу сохранить копию `.env` в менеджер паролей: с ней сервер переносится на новый VPS (шаг 12.5). Показать файл, чтобы скопировать: `cat .env`.

## 10. Запуск

```bash
cd /opt/milionchik/deploy
docker compose up -d --build --wait
docker compose ps
```

Первый запуск скачивает образы (около 770 МБ и 1,2 ГБ образ сборки) и собирает сервер - несколько минут. Локально при скачанных образах сборка заняла 17 с, запуск до healthy - 10 с. `--wait` ждёт, пока все три контейнера станут healthy; при ошибке пишет `dependency failed to start: container milionchik-server-1 is unhealthy` - смотреть шаг 16.

В `docker compose ps` у `milionchik-db-1`, `milionchik-server-1`, `milionchik-caddy-1` статус `Up … (healthy)`, порты есть только у caddy: `0.0.0.0:80->80/tcp`, `0.0.0.0:443->443/tcp`, `0.0.0.0:443->443/udp` (и то же для `[::]`).

При старте сервер сам применяет миграции базы под блокировкой - отдельной команды нет.

## 11. Проверка

На сервере:

```bash
curl -fsS https://<домен>/api/v1/health
curl -sSI http://<домен>/api/v1/health | head -2
docker compose logs caddy | grep -E 'certificate obtained|could not get certificate'
```

С Windows:

```powershell
curl.exe -sS https://<домен>/api/v1/health
curl.exe -sSI https://<домен>/api/v1/health
```

Ожидается:

- health - `{"status":"ok","version":"0.1.0","db":"ok"}` (версия - текущая версия сервера);
- `http://` - `HTTP/1.1 308 Permanent Redirect` и `Location: https://<домен>/api/v1/health`;
- в заголовках HTTPS-ответа `Strict-Transport-Security: max-age=31536000`, `X-Content-Type-Options: nosniff`, `X-Request-Id: …`, заголовка `Server` нет;
- в логе Caddy `certificate obtained successfully {"identifier": "<домен>", …}` (на VPS издатель - Let's Encrypt; локально проверялось только с `"issuer": "local"`);
- в браузере открываются `https://<домен>/privacy` и `https://<домен>/delete-account`, любой другой путь - 404.

## 12. Бэкапы и восстановление

Скрипты `deploy/backup.sh` и `deploy/restore.sh` работают с контейнером `db` через `docker compose`, настройки берут из `deploy/.env`. Справка: `./backup.sh --help`, `./restore.sh --help`.

### 12.1. Бэкап вручную

```bash
/opt/milionchik/deploy/backup.sh
ls -lh /opt/milionchik/deploy/backups/
```

Файл `deploy/backups/milionchik-ГГГГ-ММ-ДД_ЧЧММСС.dump` (формат `pg_dump` custom, проверяется `pg_restore --list` до переименования из `.partial`). Хранятся 14 дней: старше удаляются после удачного нового бэкапа. Последняя строка вывода:

```
2026-10-25T20:58:25.165+03:00 INFO  [backup] backup finished file=…/deploy/backups/milionchik-2026-10-25_205823.dump size_bytes=35583 dump_ms=620 deleted_old=0 in 3416ms run=20261025205821-22637
```

Ошибка - строка `ERROR [backup] … step=<шаг>` с причиной и код выхода 1, например `database container is not running service=db (start it: docker compose up -d db)`.

### 12.2. Каждый день по расписанию

```bash
crontab -e
```

(при первом запуске выбрать редактор, проще всего `nano`) и добавить строку:

```
30 3 * * * /opt/milionchik/deploy/backup.sh 2>&1 | logger -t milionchik-backup
```

Бэкап каждый день в 03:30 по времени сервера (UTC по умолчанию - это 06:30 по Москве). Проверить: `crontab -l`. На следующий день:

```bash
sudo journalctl -t milionchik-backup --since yesterday
ls -lh /opt/milionchik/deploy/backups/
```

### 12.3. Копия бэкапов вне сервера

Бэкапы на том же VPS пропадут вместе с ним - раз в неделю копировать их к себе (PowerShell):

```powershell
New-Item -ItemType Directory -Force D:\Backups\milionchik
scp "deploy@<IP-сервера>:/opt/milionchik/deploy/backups/milionchik-*.dump" D:\Backups\milionchik\
```

В бэкапе все данные пользователей (логины, траты, комментарии, хэши паролей) - хранить в закрытой папке, не в общих облачных папках.

### 12.4. Проверка бэкапа

Раз в месяц и после настройки - восстановить последний бэкап во временную базу и сравнить число строк с рабочей:

```bash
cd /opt/milionchik/deploy
./restore.sh --check "$(ls -t backups/milionchik-*.dump | head -1)"
```

Рабочая база не меняется, временная удаляется. Итог (время в начале строк опущено):

```
INFO  [backup] restored rows db=restore_check_… users=2 budgets=2 budget_members=2 categories=22 expenses=6 recurring_rules=0 schema_migrations=3 in 626ms
INFO  [backup] restore check matches live database tables=7 differ=0
```

`restore check differs from live database … differ=N` - нормально, если после бэкапа данные менялись.

### 12.5. Восстановление

На том же сервере (откат данных к бэкапу):

```bash
cd /opt/milionchik/deploy
./backup.sh
docker compose stop server
./restore.sh --replace backups/milionchik-<дата>.dump milionchik
docker compose start server
curl -fsS https://<домен>/api/v1/health
```

Первая команда - бэкап текущего состояния на случай, если откат понадобится отменить. Бэкап восстанавливается во временную базу и только потом заменяет `milionchik`; при ошибке рабочая база остаётся как была. Если не остановить сервер, скрипт откажется: `database has active connections, stop the server first (docker compose stop server)`.

На новом сервере (старый VPS потерян): шаги 1-9, но в шаге 9 вместо генерации паролей вставить сохранённый `.env`; затем без шага 10:

```powershell
ssh deploy@<IP-сервера> "mkdir -p /opt/milionchik/deploy/backups"
scp D:\Backups\milionchik\milionchik-<дата>.dump deploy@<IP-сервера>:/opt/milionchik/deploy/backups/
```

```bash
cd /opt/milionchik/deploy
docker compose up -d --wait db
./restore.sh --replace backups/milionchik-<дата>.dump milionchik
docker compose up -d --build --wait
curl -fsS https://<домен>/api/v1/health
```

Сервер видит, что миграции уже применены: `migrations: nothing to apply, 3 already applied`. Затем - шаг 11 и расписание бэкапов (12.2).

**Телефоны после восстановления.** Всё, что попало на сервер после момента бэкапа, на сервере пропадает. Телефоны, которые синхронизировались позже бэкапа, помнят позицию синхронизации впереди сервера и не получат часть новых изменений (так устроен pull по курсору; на телефоне не проверялось). После восстановления каждому пользователю - «Профиль» → «Выйти» и войти снова: выход стирает данные и позицию синхронизации на телефоне, вход скачивает всё с сервера заново. Траты, которые остались только на телефоне, при этом пропадут.

## 13. Обновление

### 13.1. Новая версия кода

```bash
cd /opt/milionchik/deploy
./backup.sh
docker compose logs --no-color server > ~/server-$(date +%F-%H%M).log
git pull --ff-only
docker compose up -d --build --wait
docker compose ps
curl -fsS https://<домен>/api/v1/health
docker image prune -f
```

- Перед обновлением - бэкап (откат данных - шаг 12.5) и копия логов сервера: при пересоздании контейнера его старые логи удаляются.
- `up -d --build` пересобирает сервер и пересоздаёт только изменившиеся контейнеры (локально - 16 с: `milionchik-server-1 Recreated`, у `db` и `caddy` - `Running`). Перерыв в работе API - несколько секунд. Новые миграции сервер применит сам; в health - новая версия.
- `docker image prune -f` удаляет старые образы сервера без имени.
- `git pull --ff-only` отказывается, если на сервере правили файлы репозитория: `git status` покажет какие. `.env` и `backups/` git не трогает.

Откат кода: `git log --oneline -5`, `git checkout <хэш>`, `docker compose up -d --build --wait`. Если новая версия успела применить миграцию, старый сервер стартует с предупреждением `migrations: … is applied but missing … (database is newer than this server?)` - если он работает неправильно, восстановить бэкап, сделанный перед обновлением. Вернуться на ветку: `git checkout main`.

### 13.2. Версии образов

Версии закреплены: `postgres:18.6`, `caddy:2.11.7` в `deploy/docker-compose.yml`, `dart:3.13.6` и `busybox:1.38.0-musl` в `server/Dockerfile`. Само на сервере ничего не обновляется: новую версию образа ставит разработчик правкой этих файлов в репозитории, на сервер она приходит обычным обновлением (13.1), нужные образы `up` скачивает сам.

- PostgreSQL внутри 18 (18.6 → 18.7) - просто новый тег: минорные версии не требуют выгрузки и загрузки данных ([postgresql.org/support/versioning](https://www.postgresql.org/support/versioning/)).
- Мажорная версия (19 и дальше) заменой тега не делается: данные 18 лежат в томе в `/var/lib/postgresql/18/docker`, и новая версия, скорее всего, создала бы рядом пустую базу. Это отдельная задача с переносом данных через бэкап и `restore.sh`.

### 13.3. Ubuntu и Docker

Раз в месяц:

```bash
sudo apt update && sudo apt full-upgrade -y
[ -f /var/run/reboot-required ] && sudo reboot
```

Обновление пакетов Docker перезапускает Docker, а с ним и контейнеры. После перезагрузки контейнеры поднимаются сами (`restart: unless-stopped`), проверить: `cd /opt/milionchik/deploy && docker compose ps` и health.

## 14. Логи

Все команды - из `/opt/milionchik/deploy`.

```bash
docker compose logs -f --tail 100 server
docker compose logs --since 1h server | grep -E ' (ERROR|WARN) '
docker compose logs server | grep rid=<rid>
docker compose logs --since 1h caddy
docker compose logs --since 1h db
sudo journalctl -t milionchik-backup --since today
sudo journalctl -u docker --since today
```

`-f` - следить в реальном времени (выход - Ctrl+C). Строка сервера:

```
2026-10-25T17:58:16.245+00:00 INFO  [http] POST /api/v1/sync/push 200 in 13ms size=156 ip=172.30.80.4 rid=f5c29ffc124e8adb
```

Время UTC с миллисекундами, уровень, модуль, сообщение, `key=value`. Все строки одного запроса связаны `rid` (заголовок ответа `X-Request-Id`). В `ip=` access-лога - адрес Caddy внутри сети Docker (`172.30.80.x`), а не телефона. Паролей, токенов и кодов в логах нет: секреты видны как `***`, логины как `an***`.

Ротация: у каждого контейнера до 5 файлов по 10 МБ, старые строки удаляются. Логи контейнера пропадают при его пересоздании (обновление, правка `.env`) - нужное сохранить заранее: `docker compose logs --no-color server > ~/server-$(date +%F-%H%M).log`.

Подробные логи на время разбора:

```bash
sed -i "s|^LOG_LEVEL=.*|LOG_LEVEL=debug|" .env
docker compose up -d --wait server
```

В логе - `INFO  [server] log level debug` и строки `DEBUG`. После разбора вернуть `LOG_LEVEL=info` той же парой команд.

## 15. Отчёты об ошибках из приложения

Приложение отправляет падения, ошибки и «Отправить логи разработчику» на `POST /api/v1/client-errors`. Сервер хранит их 30 дней (уборка раз в сутки) и пишет в свой лог строку без текста ошибки:

```bash
cd /opt/milionchik/deploy
docker compose logs --since 24h server | grep 'client error received'
```

```
2026-10-25T17:58:16.733+00:00 WARN  [client-errors] client error received id=511df2dd-0714-4f74-8ad3-39de5bd02923 kind=error appVersion=1.0.0+4001 androidSdk=36 userId=none auth=none size=204 messageBytes=37 messageHash=e0ab5c42324b stackBytes=35 logsBytes=0 in 4ms rid=9a783620d81b784a
```

Список отчётов - `server/bin/admin.dart errors`. В образе сервера Dart нет, поэтому команда запускается во временном контейнере Dart: первый раз скачать зависимости (нужен интернет), потом запуск в сети `milionchik_backend`, где доступна база. Из `/opt/milionchik`:

```bash
cd /opt/milionchik
docker run --rm -u "$(id -u):$(id -g)" -e HOME=/tmp -e PUB_CACHE=/src/server/.dart_tool/pub-cache -v "$PWD":/src -w /src/server dart:3.13.6 dart pub get --enforce-lockfile
docker run --rm -u "$(id -u):$(id -g)" -e HOME=/tmp -e PUB_CACHE=/src/server/.dart_tool/pub-cache --network milionchik_backend --env-file deploy/.env -v "$PWD":/src -w /src/server dart:3.13.6 sh -c 'DATABASE_URL="postgres://milionchik:${POSTGRES_PASSWORD}@db:5432/milionchik?sslmode=disable" exec dart run bin/admin.dart errors --since 1d'
```

Первую команду повторять только после обновления кода (13.1). Пароль базы берётся из `deploy/.env` внутри контейнера и в командной строке не виден. Вместо `--since 1d` - `30m`, `12h`, `7d`; `--limit N` - сколько показать (1-1000, по умолчанию 50). Вывод:

```
client errors since 2026-10-24 17:59:34 +00:00 (1d): 1 found, showing 1, newest first
received             id                                    kind   app         sdk  device    user  stack  logs  message
-------------------  ------------------------------------  -----  ----------  ---  --------  ----  -----  ----  -------------------------------------
2026-10-25 17:58:16  511df2dd-0714-4f74-8ad3-39de5bd02923  error  1.0.0+4001  36   r82-test  -     35 B   -     r82 test report: StateError bad state
```

Один отчёт целиком (стек и приложенные логи) - по `id`:

```bash
cd /opt/milionchik/deploy
docker compose exec db psql -U milionchik -d milionchik -x -c "SELECT received_at, kind, app_version, android_sdk, device_model, message, stack, logs FROM client_errors WHERE id = '<id>'"
```

## 16. Если что-то сломалось

Сначала - из `/opt/milionchik/deploy`:

```bash
docker compose ps
docker compose logs --since 15m server | grep -E ' (ERROR|WARN) '
df -h /
free -h
```

| Что видно | Причина и что делать |
|---|---|
| `required variable POSTGRES_PASSWORD is missing a value: POSTGRES_PASSWORD is required, set it in deploy/.env` | Не заполнен `deploy/.env` или команда запущена не из `/opt/milionchik/deploy` - шаг 9 |
| `dependency failed to start: container milionchik-server-1 is unhealthy` | Сервер не стартует - причина в `docker compose logs server`, строки ниже |
| `ERROR [db] Postgres connect failed db:5432 (attempt 5/5) … 28P01: password authentication failed for user "milionchik"` | `POSTGRES_PASSWORD` в `.env` поменяли после первого запуска. Вернуть прежнее значение из менеджера паролей и `docker compose up -d --wait`. Если прежнего нет - задать базе новый: `docker compose exec db psql -U milionchik -d milionchik`, в нём `\password milionchik` (ввести значение из `.env`), `\q`, затем `docker compose up -d --wait` (этот путь не проверялся) |
| `ERROR [server] config invalid: JWT_SECRET is too short (8 chars), need ≥ 32` | Исправить значение в `.env` (шаг 9) и `docker compose up -d --wait` |
| `migration failed … rolled back` в логе сервера | Ошибка новой миграции: в строке файл и SQLSTATE. Каждая миграция идёт в своей транзакции, упавшая откатилась целиком. Не перезапускать по кругу: откатить код (13.1) и сообщить разработчику |
| health отвечает `502`, в логе Caddy, например, `dial tcp: lookup server: i/o timeout` | Контейнер `server` остановлен или перезапускается: `docker compose ps`, логи сервера, `docker compose up -d --wait` |
| health отвечает `503` и `{"status":"degraded",…,"db":"error"}`, в логе `WARN  [health] database check failed` | База недоступна: `docker compose ps db`, `docker compose logs --since 15m db`, место на диске `df -h /`; запуск - `docker compose up -d --wait db` |
| Браузер или `curl` ругается на сертификат, в логе Caddy `could not get certificate` | A-запись не указывает на сервер (шаг 7), закрыты 80/443 (ufw и файрвол провайдера, шаг 5) или `DOMAIN` не совпадает с именем. Caddy сам повторяет попытки с паузами, а при неудаче с Let's Encrypt пробует ZeroSSL ([Caddy: automatic HTTPS](https://caddyserver.com/docs/automatic-https)); не перезапускать его по кругу - у Let's Encrypt лимит 5 неудачных проверок домена в час ([rate limits](https://letsencrypt.org/docs/rate-limits/)). После исправления - `docker compose restart caddy` |
| Контейнер перезапускается по кругу, `docker inspect --format '{{.State.OOMKilled}} {{.RestartCount}}' milionchik-server-1` показывает `true` | Не хватает памяти: `sudo journalctl -k \| grep -i oom`; добавить swap (шаг 3) или память VPS |
| Кончилось место (`No space left on device`) | `docker system df` и `du -sh backups/`. Освободить: `docker image prune -f` (старые образы), `docker builder prune -f` (кэш сборки, следующая сборка будет дольше) |
| При скачивании образов `toomanyrequests` | Лимит Docker Hub на анонимные загрузки: подождать час или войти `docker login` |
| В логе Caddy `failed to sufficiently increase receive buffer size` | Не сделан шаг 4 |
| Бэкап не появился | `sudo journalctl -t milionchik-backup --since yesterday`: строка `ERROR [backup] … step=<шаг>` с причиной; `crontab -l` - есть ли строка |
| Приложение показывает «Не задан адрес сервера» | APK собран без `API_URL` - раздел ниже |

После перезагрузки VPS контейнеры поднимаются сами; если нет - `sudo systemctl status docker` и `docker compose up -d --wait`.

## Приложение для этого сервера

Release-сборка на Windows - корневой [README.md](../README.md), разделы «Подпись release-сборки» и «Release-сборка». Адрес сервера задаётся при сборке:

```powershell
cd app
flutter build apk --release --split-per-abi --dart-define=API_URL=https://<домен>/api/v1
```

Перед раздачей APK проверить с Windows, что `curl.exe -sS https://<домен>/api/v1/health` отвечает `"status":"ok"`.
