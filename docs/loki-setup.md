# Loki Setup & Troubleshooting Guide

Complete guide for setting up Loki log aggregation with Promtail for Minecraft server monitoring.

## Architecture Overview

```
MCserver-201 (192.168.1.201)          Prometheus VM (192.168.1.202)
┌─────────────────────────┐           ┌─────────────────────────┐
│  Minecraft Server       │           │  Loki                   │
│  └─ Promtail            │──push────▶│  └─ inmemory ring       │
│      ├─ journald        │   logs    │  └─ filesystem storage  │
│      ├─ server logs     │           │  └─ 30d retention       │
│      └─ crash reports   │           │                         │
└─────────────────────────┘           │  Grafana                │
                                      │  └─ Loki datasource     │
                                      └─────────────────────────┘
```

## Loki Installation (VM 101)

### 1. Download and Install Loki Binary

```bash
# Create directories
sudo mkdir -p /etc/loki /var/lib/loki

# Download Loki (check latest version at https://github.com/grafana/loki/releases)
cd /tmp
curl -LO https://github.com/grafana/loki/releases/download/v2.9.4/loki-linux-amd64.zip
unzip loki-linux-amd64.zip
sudo mv loki-linux-amd64 /usr/local/bin/loki
sudo chmod +x /usr/local/bin/loki

# Create loki user
sudo useradd --system --no-create-home --shell /bin/false loki

# Set ownership
sudo chown -R loki:loki /var/lib/loki
```

### 2. Loki Configuration

Create `/etc/loki/loki-config.yml`:

```yaml
auth_enabled: false

server:
  http_listen_address: 0.0.0.0
  http_listen_port: 3100
  grpc_listen_port: 9096
  log_level: info

common:
  path_prefix: /var/lib/loki
  replication_factor: 1

  ring:
    kvstore:
      store: inmemory    # CRITICAL for single-node deployment

storage_config:
  filesystem:
    directory: /var/lib/loki/chunks

schema_config:
  configs:
    - from: 2024-01-01
      store: tsdb
      object_store: filesystem
      schema: v13
      index:
        prefix: index_
        period: 24h

limits_config:
  retention_period: 720h              # 30 days
  allow_structured_metadata: false

table_manager:
  retention_deletes_enabled: true
  retention_period: 720h
```

**Key Configuration Notes:**
- `ring.kvstore.store: inmemory` - **Required** for single-node Loki (no cluster)
- `http_listen_address: 0.0.0.0` - Listen on all interfaces for remote Promtail connections
- `replication_factor: 1` - Single-node mode

### 3. Systemd Service

Create `/etc/systemd/system/loki.service`:

```ini
[Unit]
Description=Loki Log Aggregation System
Documentation=https://grafana.com/docs/loki/latest/
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
User=loki
Group=loki
ExecStart=/usr/local/bin/loki -config.file=/etc/loki/loki-config.yml
Restart=on-failure
RestartSec=5s
LimitNOFILE=65536

[Install]
WantedBy=multi-user.target
```

### 4. Start Loki

```bash
sudo systemctl daemon-reload
sudo systemctl enable loki
sudo systemctl start loki
sudo systemctl status loki
```

### 5. Verify Loki is Running

```bash
# Check if listening
ss -lntp | grep 3100

# Check readiness
curl http://127.0.0.1:3100/ready

# Expected: "ready"
```

## Promtail Installation (VM 100 - Minecraft Server)

### 1. Download and Install Promtail

```bash
cd /tmp
curl -LO https://github.com/grafana/loki/releases/download/v2.9.4/promtail-linux-amd64.zip
unzip promtail-linux-amd64.zip
sudo mv promtail-linux-amd64 /usr/local/bin/promtail
sudo chmod +x /usr/local/bin/promtail

# Create directories
sudo mkdir -p /etc/promtail /var/lib/promtail
sudo chmod 755 /var/lib/promtail
```

### 2. Promtail Configuration

See `deploy/prometheus/promtail-config.yml` for the complete configuration.

### 3. Systemd Service

See `deploy/systemd/promtail.service` for the service file.

### 4. Start Promtail

```bash
sudo systemctl daemon-reload
sudo systemctl enable promtail
sudo systemctl start promtail
sudo systemctl status promtail
```

## Grafana Configuration

### Add Loki Datasource

1. Go to Grafana → Configuration → Data Sources
2. Click "Add data source"
3. Select "Loki"
4. Configure:
   - **URL**: `http://localhost:3100` (if Grafana is on same VM as Loki)
   - **URL**: `http://192.168.1.202:3100` (if remote)
5. Click "Save & Test"

### Query Logs

In Grafana → Explore:
```
{job="minecraft"}
```

---

## Troubleshooting Guide

### Error: `status=226/NAMESPACE`

**Symptom:**
```
systemd[1]: promtail.service: Failed to set up mount namespacing
Main process exited, code=exited, status=226/NAMESPACE
```

**Cause:** Systemd sandbox options incompatible with VM/LXC environment.

**Solution:**
1. Comment out in service file:
```ini
# ReadOnlyPaths=
# ReadWritePaths=
```

2. Ensure directory exists:
```bash
sudo mkdir -p /var/lib/promtail
sudo chmod 755 /var/lib/promtail
```

3. Restart:
```bash
sudo systemctl daemon-reload
sudo systemctl restart promtail
```

---

### Error: `status=217/USER`

**Symptom:**
```
Main process exited, code=exited, status=217/USER
```

**Cause:** User specified in service file doesn't exist.

**Solution:**
Create the user or use root:
```bash
# Option 1: Create user
sudo useradd --system --no-create-home --shell /bin/false loki

# Option 2: Use root (in service file)
User=root
Group=root
```

---

### Error: `connection refused` to Loki

**Symptom:**
```
dial tcp 192.168.1.202:3100: connect: connection refused
```

**Cause:** Loki not running or listening only on localhost.

**Solution:**
1. Check Loki is running:
```bash
sudo systemctl status loki
```

2. Ensure Loki listens on all interfaces:
```yaml
server:
  http_listen_address: 0.0.0.0
  http_listen_port: 3100
```

3. Check firewall:
```bash
sudo ufw allow 3100/tcp
```

---

### Error: `HTTP 500 - empty ring`

**Symptom:**
```
HTTP 500 Internal Server Error: empty ring
```

**Cause:** Loki configured for cluster mode but running as single node.

**Solution:** Add inmemory ring configuration:
```yaml
common:
  ring:
    kvstore:
      store: inmemory
```

This is **mandatory** for single-node Loki deployments.

---

### Error: `error writing positions file`

**Symptom:**
```
error writing positions file
open /var/lib/promtail/.positions.yaml... no such file or directory
```

**Cause:** Promtail positions directory doesn't exist.

**Solution:**
```bash
sudo mkdir -p /var/lib/promtail
sudo chmod 755 /var/lib/promtail
sudo systemctl restart promtail
```

---

## Verification Commands

### Check Promtail Status
```bash
sudo systemctl status promtail
sudo journalctl -u promtail -n 50 --no-pager
```

### Check Loki Status
```bash
sudo systemctl status loki
curl http://127.0.0.1:3100/ready
curl http://127.0.0.1:3100/metrics | head -20
```

### Test Log Query
```bash
# Query last 1 hour of minecraft logs
curl -G -s "http://localhost:3100/loki/api/v1/query_range" \
  --data-urlencode 'query={job="minecraft"}' \
  --data-urlencode 'limit=10' | jq .
```

---

## Key Takeaways

| Error | Root Cause | Fix |
|-------|------------|-----|
| `226/NAMESPACE` | Systemd sandbox + mount namespace | Remove `ReadOnlyPaths`/`ReadWritePaths` |
| `217/USER` | Non-existent user | Create user or use `root` |
| `connection refused` | Service not listening on network | Set `http_listen_address: 0.0.0.0` |
| `empty ring` | Missing ring backend config | Add `ring.kvstore.store: inmemory` |
| `positions file error` | Missing directory | Create `/var/lib/promtail` |

**Single-node Loki always requires `inmemory` ring configuration.**
