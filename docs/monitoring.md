# Настройка мониторинга Prometheus + Grafana

Руководство по настройке стека мониторинга в отдельном LXC контейнере для Minecraft сервера.

---

## Архитектура

```
┌─────────────────────────────────────────────────────────────────────┐
│                         Proxmox VE (pve)                            │
│                                                                     │
│  ┌─────────────────────┐         ┌─────────────────────────────┐   │
│  │ 100 (MCserver-201)  │         │ 101 (prometheus)            │   │
│  │                     │         │                             │   │
│  │ minecraft-exporter  │◀────────│ Prometheus    :9090         │   │
│  │ :9225               │ scrape  │ Grafana       :3000         │   │
│  │                     │ 15s     │ Alertmanager  :9093 (опц.)  │   │
│  │ minecraft.service   │         │                             │   │
│  └─────────────────────┘         └─────────────────────────────┘   │
│                                           │                         │
│                                           ▼                         │
│                                    Telegram/Discord                 │
│                                    (уведомления)                    │
└─────────────────────────────────────────────────────────────────────┘
```

**Компоненты:**

| Компонент | Роль | Порт |
|-----------|------|------|
| **minecraft-exporter** | Сбор метрик с сервера | 9225 |
| **Prometheus** | Хранение и агрегация метрик | 9090 |
| **Grafana** | Визуализация и дашборды | 3000 |
| **Alertmanager** | Уведомления (опционально) | 9093 |

---

## Требования

### LXC контейнер (prometheus)

| Ресурс | Минимум | Рекомендуется |
|--------|---------|---------------|
| **RAM** | 512 MB | 1 GB |
| **CPU** | 1 ядро | 2 ядра |
| **Диск** | 8 GB | 20 GB |
| **ОС** | Ubuntu 22.04 | Ubuntu 22.04 |

### Сетевые требования

| Направление | Порт | Протокол | Назначение |
|-------------|------|----------|------------|
| prometheus → minecraft | 9225 | TCP | Сбор метрик |
| браузер → prometheus | 9090 | TCP | Web UI Prometheus |
| браузер → grafana | 3000 | TCP | Web UI Grafana |

---

## 1. Подготовка Minecraft сервера

На **MCserver-201** убедитесь, что exporter работает:

```bash
# Проверить статус exporter
sudo systemctl status minecraft-exporter

# Если не запущен
sudo systemctl start minecraft-exporter
sudo systemctl enable minecraft-exporter

# Проверить метрики
curl http://localhost:9225/metrics
```

**Ожидаемый вывод:**
```
# HELP minecraft_healthy Minecraft server health status
# TYPE minecraft_healthy gauge
minecraft_healthy 1
# HELP minecraft_players_online Current online players
# TYPE minecraft_players_online gauge
minecraft_players_online 5
...
```

### Открыть порт для Prometheus

```bash
# На MCserver-201
sudo ufw allow from <IP-prometheus-LXC> to any port 9225
```

---

## 2. Установка Prometheus

На **LXC 101 (prometheus)**:

### Установка пакета

```bash
# Обновление системы
sudo apt update && sudo apt upgrade -y

# Установка Prometheus
sudo apt install -y prometheus

# Проверить версию
prometheus --version
```

### Конфигурация Prometheus

```bash
sudo nano /etc/prometheus/prometheus.yml
```

```yaml
global:
  scrape_interval: 15s
  evaluation_interval: 15s

alerting:
  alertmanagers:
    - static_configs:
        - targets: []
        # - targets: ['localhost:9093']  # Раскомментировать для Alertmanager

rule_files:
  # - "alerts.yml"  # Раскомментировать для правил алертов

scrape_configs:
  # Prometheus собирает метрики сам о себе
  - job_name: 'prometheus'
    static_configs:
      - targets: ['localhost:9090']

  # Minecraft сервер
  - job_name: 'minecraft'
    static_configs:
      - targets: ['<IP-MCserver-201>:9225']
        labels:
          instance: 'mcserver-201'
          server: 'mohist-1.20.1'
    scrape_interval: 15s
    scrape_timeout: 10s
```

**Замените `<IP-MCserver-201>`** на реальный IP адрес Minecraft сервера.

### Запуск Prometheus

```bash
# Проверить конфигурацию
promtool check config /etc/prometheus/prometheus.yml

# Перезапустить сервис
sudo systemctl restart prometheus
sudo systemctl enable prometheus

# Проверить статус
sudo systemctl status prometheus
```

### Проверка работы

Откройте в браузере: `http://<IP-prometheus>:9090`

1. Перейдите в **Status → Targets**
2. Убедитесь, что `minecraft` target в состоянии **UP**

---

## 3. Установка Grafana

На том же **LXC 101 (prometheus)**:

### Добавление репозитория

```bash
# Зависимости
sudo apt install -y apt-transport-https software-properties-common wget

# GPG ключ
sudo mkdir -p /etc/apt/keyrings/
wget -q -O - https://apt.grafana.com/gpg.key | gpg --dearmor | sudo tee /etc/apt/keyrings/grafana.gpg > /dev/null

# Репозиторий
echo "deb [signed-by=/etc/apt/keyrings/grafana.gpg] https://apt.grafana.com stable main" | sudo tee /etc/apt/sources.list.d/grafana.list

# Установка
sudo apt update
sudo apt install -y grafana
```

### Запуск Grafana

```bash
sudo systemctl daemon-reload
sudo systemctl start grafana-server
sudo systemctl enable grafana-server

# Проверить статус
sudo systemctl status grafana-server
```

### Первый вход

1. Откройте: `http://<IP-prometheus>:3000`
2. Логин: `admin`
3. Пароль: `admin`
4. **Смените пароль** при первом входе!

---

## 4. Подключение Prometheus к Grafana

### Добавление Data Source

1. В Grafana: **Connections → Data sources → Add data source**
2. Выберите **Prometheus**
3. Настройки:

| Параметр | Значение |
|----------|----------|
| Name | Prometheus |
| URL | `http://localhost:9090` |
| Access | Server (default) |

4. Нажмите **Save & test**
5. Должно появиться: "Data source is working"

---

## 5. Создание дашборда Minecraft

### Импорт готового дашборда

Готовый дашборд находится в файле [`grafana-dashboard.json`](./grafana-dashboard.json).

**Импорт в Grafana:**

1. Откройте Grafana: `http://<IP-prometheus>:3000`
2. **Dashboards → New → Import**
3. Нажмите **Upload dashboard JSON file**
4. Выберите файл `grafana-dashboard.json`
5. Выберите **Prometheus** как Data source
6. Нажмите **Import**

**Что включено в дашборд:**

| Секция | Панели |
|--------|--------|
| **Server Status** | Статус, Игроки, TPS, Uptime, Время с бэкапа, Размер бэкапа |
| **Players** | График игроков, График TPS |
| **Resources** | Память, Диск (%), Свободное место |
| **World Data** | Размер мира, История бэкапов |

**Цветовая индикация:**
- TPS: 🟢 19-20 (норма), 🟡 15-19 (нагрузка), 🔴 <15 (проблемы)
- Диск: 🟢 <70%, 🟡 70-85%, 🟠 85-95%, 🔴 >95%
- Бэкап: 🟢 <6ч, 🟡 6-12ч, 🟠 12-24ч, 🔴 >24ч

---

### Ручное создание панелей (альтернатива)

**Создайте новый дашборд** и добавьте панели:

#### Панель: Статус сервера

```
Type: Stat
Query: minecraft_healthy
Title: Server Status
Value mappings:
  1 → "Online" (green)
  0 → "Offline" (red)
```

#### Панель: Игроки онлайн

```
Type: Gauge
Query: minecraft_players_online
Title: Players Online
Max: minecraft_players_max
```

#### Панель: TPS (Ticks Per Second)

```
Type: Gauge
Query: minecraft_tps
Title: Server TPS
Thresholds:
  0-15: red
  15-19: yellow
  19-20: green
```

#### Панель: Использование памяти

```
Type: Time series
Query: minecraft_memory_used_bytes / 1024 / 1024 / 1024
Title: Memory Usage (GB)
Unit: GB
```

#### Панель: Размер мира

```
Type: Stat
Query: minecraft_world_size_bytes / 1024 / 1024 / 1024
Title: World Size
Unit: GB
```

#### Панель: Время работы

```
Type: Stat
Query: minecraft_uptime_seconds / 3600
Title: Uptime
Unit: hours
```

### Примеры PromQL запросов

```promql
# Текущие игроки
minecraft_players_online

# Процент заполненности сервера
minecraft_players_online / minecraft_players_max * 100

# Средний TPS за 5 минут
avg_over_time(minecraft_tps[5m])

# Память в процентах (если есть max)
minecraft_memory_used_bytes / minecraft_memory_max_bytes * 100

# Время с последнего бэкапа (часы)
(time() - minecraft_backup_last_timestamp) / 3600

# Rate изменения размера мира
rate(minecraft_world_size_bytes[1h])
```

---

## 6. Alertmanager (опционально)

### Установка

```bash
sudo apt install -y prometheus-alertmanager
```

### Конфигурация алертов

Создайте файл правил:

```bash
sudo nano /etc/prometheus/alerts.yml
```

```yaml
groups:
  - name: minecraft
    rules:
      # Сервер недоступен
      - alert: MinecraftServerDown
        expr: minecraft_healthy == 0
        for: 1m
        labels:
          severity: critical
        annotations:
          summary: "Minecraft server is down"
          description: "Server has been unhealthy for more than 1 minute"

      # Низкий TPS
      - alert: MinecraftLowTPS
        expr: minecraft_tps < 15
        for: 5m
        labels:
          severity: warning
        annotations:
          summary: "Minecraft TPS is low"
          description: "TPS has been below 15 for 5 minutes (current: {{ $value }})"

      # Много игроков
      - alert: MinecraftHighPlayerCount
        expr: minecraft_players_online > 50
        for: 1m
        labels:
          severity: info
        annotations:
          summary: "High player count"
          description: "{{ $value }} players online"

      # Давно не было бэкапа (>24h)
      - alert: MinecraftBackupOld
        expr: (time() - minecraft_backup_last_timestamp) > 86400
        for: 1h
        labels:
          severity: warning
        annotations:
          summary: "Backup is old"
          description: "Last backup was more than 24 hours ago"
```

### Включение правил в Prometheus

```bash
sudo nano /etc/prometheus/prometheus.yml
```

```yaml
rule_files:
  - "alerts.yml"

alerting:
  alertmanagers:
    - static_configs:
        - targets: ['localhost:9093']
```

### Настройка Telegram уведомлений

```bash
sudo nano /etc/prometheus/alertmanager.yml
```

```yaml
global:
  resolve_timeout: 5m

route:
  group_by: ['alertname']
  group_wait: 10s
  group_interval: 10s
  repeat_interval: 1h
  receiver: 'telegram'

receivers:
  - name: 'telegram'
    telegram_configs:
      - bot_token: '<YOUR_BOT_TOKEN>'
        chat_id: <YOUR_CHAT_ID>
        message: |
          {{ range .Alerts }}
          🚨 {{ .Labels.alertname }}
          {{ .Annotations.summary }}
          {{ .Annotations.description }}
          {{ end }}
```

**Получение Telegram токена:**
1. Напишите @BotFather в Telegram
2. Создайте бота: `/newbot`
3. Скопируйте токен
4. Получите chat_id: напишите боту, затем откройте `https://api.telegram.org/bot<TOKEN>/getUpdates`

### Запуск Alertmanager

```bash
sudo systemctl restart prometheus-alertmanager
sudo systemctl enable prometheus-alertmanager
sudo systemctl restart prometheus
```

---

## 7. Проверка и устранение неполадок

### Тестирование связи

```bash
# С prometheus LXC проверить доступность exporter
curl http://<IP-MCserver-201>:9225/metrics

# Проверить targets в Prometheus
curl http://localhost:9090/api/v1/targets | jq '.data.activeTargets'

# Проверить метрики в Prometheus
curl 'http://localhost:9090/api/v1/query?query=minecraft_healthy'
```

### Типичные проблемы

#### Target в состоянии DOWN

```bash
# Проверить firewall на MCserver
sudo ufw status

# Проверить что exporter слушает
ss -tlnp | grep 9225

# Проверить сетевую связность
ping <IP-MCserver-201>
nc -zv <IP-MCserver-201> 9225
```

#### Grafana не показывает данные

1. Проверьте Data source: **Connections → Data sources → Prometheus → Test**
2. Проверьте время: убедитесь что временной диапазон дашборда корректен
3. Проверьте запрос: в панели нажмите **Query inspector**

#### Prometheus не запускается

```bash
# Проверить конфигурацию
promtool check config /etc/prometheus/prometheus.yml

# Посмотреть логи
sudo journalctl -u prometheus -f
```

#### Alertmanager не отправляет уведомления

```bash
# Проверить конфигурацию
amtool check-config /etc/prometheus/alertmanager.yml

# Посмотреть логи
sudo journalctl -u prometheus-alertmanager -f

# Проверить активные алерты
curl http://localhost:9093/api/v2/alerts
```

---

## 8. Полезные команды

```bash
# Prometheus
sudo systemctl status prometheus
sudo journalctl -u prometheus -f
promtool check config /etc/prometheus/prometheus.yml

# Grafana
sudo systemctl status grafana-server
sudo journalctl -u grafana-server -f

# Alertmanager
sudo systemctl status prometheus-alertmanager
sudo journalctl -u prometheus-alertmanager -f
amtool alert

# Проверка метрик
curl -s http://localhost:9090/api/v1/query?query=up | jq
curl -s http://localhost:9090/api/v1/targets | jq '.data.activeTargets[] | {job: .labels.job, health: .health}'
```

---

## Структура файлов

```
/etc/prometheus/
├── prometheus.yml          # Основная конфигурация
├── alerts.yml              # Правила алертов
└── alertmanager.yml        # Конфигурация Alertmanager

/var/lib/prometheus/        # Данные Prometheus (TSDB)
/var/lib/grafana/           # Данные Grafana (дашборды, users)
```

---

## Порты и сервисы

| Сервис | Порт | Systemd unit |
|--------|------|--------------|
| Prometheus | 9090 | prometheus.service |
| Grafana | 3000 | grafana-server.service |
| Alertmanager | 9093 | prometheus-alertmanager.service |
| Minecraft exporter | 9225 | minecraft-exporter.service |
