---
title: Monitoring Infrastructure
purpose: Prometheus, Grafana, Loki setup and metrics
prerequisites:
  - CLAUDE-deployment.md
related:
  - CLAUDE-deployment.md
  - monitoring.md
  - loki-setup.md
---
<!-- CLAUDE INSTRUCTION DOC -->
# Monitoring Infrastructure

> **Purpose**: Server monitoring with Prometheus, Grafana, and Loki.
> **Parent**: [CLAUDE.md](../CLAUDE.md)

---

## Architecture Overview

```
┌─────────────────┐     ┌────────────────┐     ┌─────────────┐
│ Minecraft Server│────▶│ minecraft-     │────▶│ Prometheus  │
│ (RCON: 25575)   │     │ exporter:9225  │     │             │
└─────────────────┘     └────────────────┘     └──────┬──────┘
                                                      │
┌─────────────────┐     ┌────────────────┐            ▼
│ Server Logs     │────▶│ Promtail       │────▶┌─────────────┐
│ /logs/*.log     │     │                │     │ Loki        │
└─────────────────┘     └────────────────┘     └──────┬──────┘
                                                      │
                                                      ▼
                                               ┌─────────────┐
                                               │ Grafana     │
                                               │ :3000       │
                                               └─────────────┘
```

---

## Prometheus Metrics Exporter

### Components

| File | Purpose |
|------|---------|
| `deploy/prometheus/minecraft-exporter.sh` | Exports metrics on port 9225 |
| `deploy/prometheus/prometheus-target.yml` | Prometheus scrape configuration |
| `deploy/systemd/minecraft-exporter.service` | Systemd service for exporter |

### Available Metrics

| Metric | Description |
|--------|-------------|
| `minecraft_up` | Server online status (1/0) |
| `minecraft_players_online` | Current player count |
| `minecraft_players_max` | Maximum player slots |
| `minecraft_tps` | Server TPS (ticks per second) |
| `minecraft_memory_used_bytes` | JVM heap memory used |
| `minecraft_memory_max_bytes` | JVM heap memory max |

### Exporter Management

```bash
# Start exporter
sudo systemctl start minecraft-exporter

# Check status
sudo systemctl status minecraft-exporter

# View logs
sudo journalctl -u minecraft-exporter -f
```

---

## Setup Guides

### Full Prometheus + Grafana Setup

See **[monitoring.md](monitoring.md)** for complete setup instructions:

- Prometheus installation and configuration
- Grafana datasource setup
- Alert rules configuration
- Dashboard import

### Loki Log Aggregation

See **[loki-setup.md](loki-setup.md)** for Loki setup and troubleshooting:

- Loki installation
- Promtail configuration
- Common issues (empty ring, 226/NAMESPACE, etc.)
- Log query examples

---

## Grafana Dashboard

### Pre-configured Dashboard

Import `docs/grafana-dashboard.json` into Grafana for ready-to-use visualization:

```bash
# In Grafana UI:
# 1. Go to Dashboards → Import
# 2. Upload grafana-dashboard.json
# 3. Select Prometheus datasource
```

### Dashboard Panels

| Panel | Description |
|-------|-------------|
| Server Status | Online/offline indicator |
| Player Count | Current vs max players |
| TPS Graph | Server performance over time |
| Memory Usage | Heap utilization percentage |
| Log Stream | Recent server logs (via Loki) |

---

## Prometheus Configuration

Add to `prometheus.yml`:

```yaml
scrape_configs:
  - job_name: 'minecraft'
    static_configs:
      - targets: ['localhost:9225']
    scrape_interval: 15s
```

Or use the provided config:

```bash
cp deploy/prometheus/prometheus-target.yml /etc/prometheus/conf.d/
```

---

## Alert Rules (Example)

```yaml
groups:
  - name: minecraft
    rules:
      - alert: MinecraftDown
        expr: minecraft_up == 0
        for: 2m
        labels:
          severity: critical
        annotations:
          summary: "Minecraft server is down"

      - alert: MinecraftLowTPS
        expr: minecraft_tps < 15
        for: 5m
        labels:
          severity: warning
        annotations:
          summary: "Server TPS below 15"

      - alert: MinecraftHighMemory
        expr: minecraft_memory_used_bytes / minecraft_memory_max_bytes > 0.9
        for: 10m
        labels:
          severity: warning
        annotations:
          summary: "Memory usage above 90%"
```

---

## Troubleshooting

### Exporter not collecting metrics

```bash
# Check if server is running
./deploy/health-check.sh

# Test RCON connectivity manually
mcrcon -H localhost -P 25575 -p YOUR_PASSWORD "list"

# Check exporter logs
sudo journalctl -u minecraft-exporter -n 50
```

### Prometheus not scraping

```bash
# Check target status in Prometheus UI
curl http://localhost:9090/api/v1/targets

# Test exporter endpoint directly
curl http://localhost:9225/metrics
```

### Loki issues

See **[loki-setup.md](loki-setup.md)** for common issues:
- Empty ring error
- 226/NAMESPACE errors
- Promtail not sending logs

---

## See Also

- [Deployment](CLAUDE-deployment.md) — update, backup, health-check scripts
- [monitoring.md](monitoring.md) — detailed Prometheus + Grafana setup
- [loki-setup.md](loki-setup.md) — Loki installation and troubleshooting
