#!/bin/bash
set -ex

# ---------------------------
# FIX 1: Correct package manager for AL2023
# ---------------------------
dnf update -y
dnf install -y docker jq curl

systemctl enable docker
systemctl start docker

# ---------------------------
# FIX 2: Define required IP variables (from Terraform)
# ---------------------------
app_private_ip="${APP_PRIVATE_IP}"
n8n_private_ip="${N8N_PRIVATE_IP}"

# ---------------------------
# Directory Structure
# ---------------------------
mkdir -p /opt/monitoring/prometheus/rules
mkdir -p /opt/monitoring/grafana/provisioning/dashboards
mkdir -p /opt/monitoring/grafana/provisioning/datasources
mkdir -p /opt/monitoring/grafana/dashboards
mkdir -p /opt/monitoring/alertmanager

# ---------------------------
# Download Grafana Dashboards
# ---------------------------
curl -fsSL https://grafana.com/api/dashboards/1860/revisions/37/download \
  -o /opt/monitoring/grafana/dashboards/node-exporter.json

curl -fsSL https://grafana.com/api/dashboards/4701/revisions/4/download \
  -o /opt/monitoring/grafana/dashboards/jvm.json

curl -fsSL https://grafana.com/api/dashboards/6756/revisions/2/download \
  -o /opt/monitoring/grafana/dashboards/spring-boot.json

# ---------------------------
# (UNCHANGED) Dashboard fixes
# ---------------------------
# ... your jq logic stays EXACTLY the same ...

# ---------------------------
# Prometheus Config
# ---------------------------
cat <<EOF > /opt/monitoring/prometheus/prometheus.yml
global:
  scrape_interval: 2s
  evaluation_interval: 2s

alerting:
  alertmanagers:
    - static_configs:
        - targets: ["alertmanager:9093"]

scrape_configs:
  - job_name: "spring-app"
    metrics_path: "/actuator/prometheus"
    static_configs:
      - targets: ["${app_private_ip}:8080"]

  - job_name: "node"
    static_configs:
      - targets: ["${app_private_ip}:9100"]

rule_files:
  - "rules/*.yml"
EOF

# ---------------------------
# Alertmanager Config
# ---------------------------
cat <<EOF > /opt/monitoring/alertmanager/alertmanager.yml
global:
  resolve_timeout: 10s

route:
  receiver: "n8n"
  group_by: ["alertname", "instance"]

receivers:
  - name: "n8n"
    webhook_configs:
      - url: "http://${n8n_private_ip}:5678/webhook/prometheus-alert"
        send_resolved: true
EOF

# ---------------------------
# Docker Network
# ---------------------------
docker network create employee-mon || true

# ---------------------------
# Run Prometheus
# ---------------------------
docker run -d \
  --name prometheus \
  --network employee-mon \
  -p 9090:9090 \
  -v /opt/monitoring/prometheus/prometheus.yml:/etc/prometheus/prometheus.yml \
  -v /opt/monitoring/prometheus/rules:/etc/prometheus/rules \
  --restart unless-stopped \
  prom/prometheus

# ---------------------------
# Run Grafana
# ---------------------------
docker run -d \
  --name grafana \
  --network employee-mon \
  -p 3000:3000 \
  -v /opt/monitoring/grafana/provisioning:/etc/grafana/provisioning \
  -v /opt/monitoring/grafana/dashboards:/var/lib/grafana/dashboards \
  --restart unless-stopped \
  grafana/grafana

# ---------------------------
# Run Alertmanager
# ---------------------------
docker run -d \
  --name alertmanager \
  --network employee-mon \
  -p 9093:9093 \
  -v /opt/monitoring/alertmanager/alertmanager.yml:/etc/alertmanager/alertmanager.yml \
  --restart unless-stopped \
  prom/alertmanager
