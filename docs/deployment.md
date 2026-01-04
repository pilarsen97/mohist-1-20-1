# Развёртывание Minecraft сервера на Ubuntu VM

Полное руководство по установке и настройке Mohist 1.20.1 сервера на Ubuntu VM (Proxmox/VPS).

---

## Быстрый старт

```bash
# На Ubuntu VM (от вашего пользователя, не root):

# Автоматическая установка (Java 21, mcrcon, /opt/minecraft)
sudo ./deploy/setup-ubuntu.sh

# Клонировать репозиторий в /opt/minecraft
cd /opt/minecraft
git clone <repo-url> .
git lfs pull

# Настроить RCON пароль
cp deploy/config.env.example deploy/config.env
nano deploy/config.env  # Установить RCON_PASSWORD

# Установить systemd сервисы (использует $SUDO_USER)
sudo ./deploy/install-service.sh

# Запустить сервер
sudo systemctl start minecraft
```

**Важно:** Сервер работает от пользователя, который выполнил `sudo`. Путь установки: `/opt/minecraft`.

---

## Требования

| Компонент | Минимум | Рекомендуется |
|-----------|---------|---------------|
| **ОС** | Ubuntu 20.04+ | Ubuntu 22.04 LTS |
| **RAM** | 4 GB | 8+ GB |
| **CPU** | 2 ядра | 4+ ядра |
| **Диск** | 20 GB SSD | 50+ GB SSD |
| **Java** | OpenJDK 21 | OpenJDK 21 |

---

## 1. Первоначальная настройка

### Автоматическая установка

Скрипт `setup-ubuntu.sh` выполнит все необходимые шаги:

```bash
sudo ./deploy/setup-ubuntu.sh
```

**Что делает скрипт:**
1. Обновляет систему
2. Устанавливает зависимости (git, git-lfs, screen, htop, netcat, jq, bc)
3. Устанавливает OpenJDK 21
4. Компилирует и устанавливает mcrcon
5. Создаёт директорию `/opt/minecraft` с правами для `$SUDO_USER`
6. Настраивает Git LFS
7. Настраивает firewall (порты 25565, 9225)
8. Устанавливает systemd сервисы

### Ручная установка

Если нужно установить вручную:

```bash
# 1. Обновление системы
sudo apt update && sudo apt upgrade -y

# 2. Зависимости
sudo apt install -y openjdk-21-jdk-headless git git-lfs screen htop netcat-openbsd jq bc

# 3. mcrcon (RCON клиент)
cd /tmp
git clone https://github.com/Tiiffi/mcrcon.git
cd mcrcon && make
sudo cp mcrcon /usr/local/bin/

# 4. Директория для сервера
sudo mkdir -p /opt/minecraft
sudo chown $USER:$USER /opt/minecraft

# 5. Клонирование репозитория
cd /opt/minecraft
git clone <repo-url> .
git lfs pull
```

---

## 2. Конфигурация

### Вариант A: Интерактивный скрипт (рекомендуется)

Запустите мастер конфигурации:

```bash
./deploy/configure.sh
```

Скрипт автоматически:
1. Создаст `server.properties` из шаблона (если нужно)
2. Сгенерирует безопасный RCON пароль (или примет ваш)
3. Запросит IP сервера и MOTD
4. Синхронизирует пароль с `deploy/config.env`

**Пример вывода:**
```
╔════════════════════════════════════════════════════════════════╗
║  Minecraft Server Configuration - 2026-01-04 12:00:00          ║
╚════════════════════════════════════════════════════════════════╝

✓ Created server.properties from example

RCON Password Configuration
  Generated suggestion: Kj8mNp2xRt4wYz6Q

  Enter password (or press Enter to use generated):
  Server IP [localhost]: 82.202.140.197
  Message of the Day [KIBERmax server]:

✓ server.properties configured
✓ deploy/config.env synchronized
```

### Вариант B: Ручная настройка

#### Шаг 1: Копирование example-файлов

```bash
cp server.properties.example server.properties
cp deploy/config.env.example deploy/config.env
```

#### Шаг 2: Редактирование server.properties

```bash
nano server.properties
```

Измените строки в начале файла:
- `rcon.password=ВАШЕ_СИЛЬНОЕ_ПАРОЛЬ` (минимум 8 символов)
- `server-ip=ВАШ_IP` (или `localhost` для локального)
- `motd=Название сервера`

#### Шаг 3: Редактирование config.env

```bash
nano deploy/config.env
```

**Обязательные настройки:**

```bash
# RCON пароль (должен совпадать с server.properties!)
RCON_PASSWORD="ваш_пароль"

# Путь к серверу (по умолчанию /opt/minecraft)
SERVER_DIR="/opt/minecraft"

# Память (по вашим ресурсам)
MIN_RAM="2G"
MAX_RAM="8G"
```

#### Шаг 4: Защита файла конфигурации

```bash
chmod 600 deploy/config.env
```

### Проверка RCON пароля

RCON пароль должен совпадать в обоих файлах:

```bash
grep "rcon.password" server.properties
grep "RCON_PASSWORD" deploy/config.env
# Пароли должны быть одинаковые!
```

---

## 3. Установка сервисов

```bash
sudo ./deploy/install-service.sh
```

Скрипт:
- Определяет пользователя из `$SUDO_USER` (кто запустил sudo)
- Подставляет User/Group в systemd unit-файлы
- Копирует unit-файлы в `/etc/systemd/system/`
- Включает автозапуск при загрузке системы

**Важно:** Сервер будет работать от вашего пользователя, не от root и не от специального пользователя minecraft.

### Проверка установки

```bash
systemctl is-enabled minecraft.service
# Ожидаемый результат: enabled
```

---

## 4. Управление сервером

### Основные команды

```bash
# Статус
sudo systemctl status minecraft

# Запуск
sudo systemctl start minecraft

# Остановка (с сохранением мира)
sudo systemctl stop minecraft

# Перезапуск
sudo systemctl restart minecraft

# Отключить автозапуск
sudo systemctl disable minecraft

# Включить автозапуск
sudo systemctl enable minecraft
```

### Просмотр логов

```bash
# Логи в реальном времени
sudo journalctl -u minecraft -f

# Последние 200 строк
sudo journalctl -u minecraft -n 200

# Логи за сегодня
sudo journalctl -u minecraft --since today

# Логи с ошибками
sudo journalctl -u minecraft -p err
```

### Deploy скрипты

```bash
# Запуск с проверками
./deploy/start.sh

# Остановка с бэкапом
./deploy/stop.sh --backup

# Полное обновление (stop → backup → git pull → start)
./deploy/update.sh

# Только бэкап
./deploy/backup.sh
```

---

## 5. Обновление сервера

### Автоматическое обновление

```bash
./deploy/update.sh
```

**Что происходит:**
1. Уведомление игроков о техобслуживании
2. Сохранение мира и остановка сервера
3. Создание бэкапа
4. `git pull` с Git LFS файлами
5. Проверка целостности JAR-файла
6. Запуск сервера с health-check

**Опции:**
```bash
./deploy/update.sh --skip-backup   # Без бэкапа
./deploy/update.sh --no-start      # Не запускать после обновления
./deploy/update.sh --dry-run       # Показать что будет сделано
```

### Откат при ошибке

Если обновление провалилось, скрипт автоматически откатывается к предыдущему коммиту.

---

## 6. Резервное копирование

### Создание бэкапа

```bash
./deploy/backup.sh
```

Бэкапы сохраняются в `backups/` и включают:
- Все миры (world, world_nether, world_the_end)
- Конфигурационные файлы
- Метаданные (коммит Git)

### Управление бэкапами

```bash
# Список бэкапов
./deploy/backup.sh --list

# Проверка целостности последнего бэкапа
./deploy/backup.sh --verify

# Компактный режим (один архив)
./deploy/backup.sh --compact
```

### Настройки бэкапов

В `deploy/config.env`:

```bash
BACKUP_DIR="${SERVER_DIR}/backups"
BACKUP_RETENTION=7          # Хранить последние 7 бэкапов
BACKUP_COMPRESSION=6        # Уровень сжатия (1-9)
```

---

## 7. Мониторинг

### Health Check

```bash
# Человекочитаемый формат
./deploy/health-check.sh

# JSON формат (для API)
./deploy/health-check.sh --json

# Prometheus формат
./deploy/health-check.sh --prometheus

# Только код возврата (0=ok, 1=fail)
./deploy/health-check.sh --quiet
```

### Prometheus интеграция

Метрики доступны на порту 9225:

```bash
# Запустить exporter
sudo systemctl start minecraft-exporter

# Проверить метрики
curl http://localhost:9225/metrics
```

**Доступные метрики:**
- `minecraft_healthy` - сервер работает (0/1)
- `minecraft_players_online` - текущие игроки
- `minecraft_players_max` - максимум игроков
- `minecraft_tps` - тики в секунду (20 = норма)
- `minecraft_uptime_seconds` - время работы
- `minecraft_memory_used_bytes` - использование памяти
- `minecraft_disk_usage_percent` - использование диска
- `minecraft_world_size_bytes` - размер миров
- `minecraft_backup_last_timestamp` - время последнего бэкапа

### Prometheus конфигурация

Добавить в `prometheus.yml`:

```yaml
scrape_configs:
  - job_name: 'minecraft'
    static_configs:
      - targets: ['minecraft-vm:9225']
    scrape_interval: 15s
```

---

## 8. Устранение неполадок

### Сервер не запускается

```bash
# Проверить статус
sudo systemctl status minecraft

# Подробные логи
sudo journalctl -u minecraft -n 100

# Проверить JAR-файл
ls -la mohist-1.20.1-*.jar
# Должен быть ~135 MB
```

### RCON не работает

```bash
# Проверить пароль
grep "rcon.password" server.properties

# Сравнить с config.env
grep "RCON_PASSWORD" deploy/config.env

# Тест RCON вручную
mcrcon -H localhost -P 25575 -p <password> "list"
```

### Нехватка памяти

```bash
# Проверить использование
free -h
./deploy/health-check.sh

# Увеличить лимит в config.env
MAX_RAM="8G"

# Перезапустить
sudo systemctl restart minecraft
```

### Сервер не отвечает

```bash
# Проверить порт
nc -zv localhost 25565

# Проверить процесс
pgrep -f "mohist-1.20.1"

# Принудительный перезапуск
./deploy/stop.sh --force
./deploy/start.sh
```

---

## 9. Структура файлов

```
deploy/
├── config.env.example      # Шаблон конфигурации
├── config.env              # Ваша конфигурация (gitignored)
├── lib/
│   └── logging.sh          # Библиотека логирования
├── systemd/
│   ├── minecraft.service   # Unit-файл сервера
│   └── minecraft-exporter.service  # Unit-файл Prometheus
├── prometheus/
│   ├── minecraft-exporter.sh   # Prometheus exporter
│   └── prometheus-target.yml   # Конфиг для Prometheus
├── setup-ubuntu.sh         # Первоначальная настройка VM
├── install-service.sh      # Установка systemd сервисов
├── start.sh                # Запуск с проверками
├── stop.sh                 # Остановка с сохранением
├── update.sh               # Полный цикл обновления
├── backup.sh               # Резервное копирование
├── health-check.sh         # Проверка здоровья
├── graceful-shutdown.sh    # Сохранение мира через RCON
└── deploy.sh               # Git pull с LFS
```

---

## 10. Полезные команды

```bash
# Подключиться к консоли через RCON
mcrcon -H localhost -P 25575 -p <password>

# Выполнить команду
mcrcon -H localhost -P 25575 -p <password> "say Hello!"

# Список игроков
mcrcon -H localhost -P 25575 -p <password> "list"

# Сохранить мир
mcrcon -H localhost -P 25575 -p <password> "save-all"

# Статистика TPS
mcrcon -H localhost -P 25575 -p <password> "tps"
```

---

## Поддержка

- **Логи сервера:** `sudo journalctl -u minecraft -f`
- **Логи деплоя:** `logs/deploy/`
- **Crash reports:** `crash-reports/`
