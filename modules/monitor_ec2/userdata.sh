#!/bin/bash
set -ex

# ---------------------------
# FIX 1: Correct package manager for AL2023
# ---------------------------
dnf update -y
dnf install -y docker jq curl --allowerasing

systemctl enable docker
systemctl start docker

# ---------------------------
# FIX 3: Wait for Docker daemon (CRITICAL)
# ---------------------------
until docker info >/dev/null 2>&1; do
  echo "Waiting for Docker to be ready..."
  sleep 2
done

# ---------------------------
# FIX 2: Terraform variables (DO NOT REMOVE)
# ---------------------------
app_private_ip="${app_private_ip}"
n8n_private_ip="${n8n_private_ip}"

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
# FIX Grafana Dashboards for Provisioning
# ---------------------------
for f in /opt/monitoring/grafana/dashboards/*.json; do
  jq '
    del(.__inputs, .__requires)
    | walk(
        if type == "object" and has("datasource") then
          .datasource = "Prometheus"
        else .
        end
      )
  ' "$f" > /tmp/dashboard.json && mv /tmp/dashboard.json "$f"
done

# ---------------------------
# FIX Node Exporter variables
# ---------------------------
jq '
  if .title == "Node Exporter Full" then
    .templating.list |= map(
      if .name == "job" then
        .query = "label_values(up, job)"
      elif .name == "instance" then
        .query = "label_values(up{job=\"$job\"}, instance)"
      else .
      end
    )
  else .
  end
' /opt/monitoring/grafana/dashboards/node-exporter.json \
> /tmp/node-exporter-fixed.json && \
mv /tmp/node-exporter-fixed.json /opt/monitoring/grafana/dashboards/node-exporter.json

# ---------------------------
# FIX Spring Boot Statistics variables
# ---------------------------
jq '
  if .title == "Spring Boot Statistics" then
    .templating.list |= map(
      if .name == "instance" then
        .query = "label_values(up{job=\"spring-app\"}, instance)"
      elif .name == "application" then
        .query = "label_values(application)"
      elif .name == "hikaricp" then
        .query = "label_values(jdbc_connections_active, pool)"
      elif .name == "memory_pool_heap" then
        .query = "label_values(jvm_memory_used_bytes{area=\"heap\"}, id)"
      elif .name == "memory_pool_nonheap" then
        .query = "label_values(jvm_memory_used_bytes{area=\"nonheap\"}, id)"
      else .
      end
    )
  else .
  end
' /opt/monitoring/grafana/dashboards/spring-boot.json \
> /tmp/spring-boot-fixed.json && \
mv /tmp/spring-boot-fixed.json /opt/monitoring/grafana/dashboards/spring-boot.json

# ---------------------------
# FIX JVM (Micrometer) uptime panels
# ---------------------------
jq '
  if .title == "JVM (Micrometer)" then
    .panels |= map(
      if .title == "Uptime" then
        .targets[0].expr = "jvm_uptime_seconds{job=\"spring-app\"}"
      elif .title == "Start time" then
        .targets[0].expr = "time() - jvm_uptime_seconds{job=\"spring-app\"}"
      else .
      end
    )
  else .
  end
' /opt/monitoring/grafana/dashboards/jvm.json \
> /tmp/jvm-fixed.json && \
mv /tmp/jvm-fixed.json /opt/monitoring/grafana/dashboards/jvm.json

# ---------------------------
# Prometheus Config (FAST)
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
    scrape_interval: 2s
    scrape_timeout: 1s
    static_configs:
      - targets: ["${app_private_ip}:8080"]

  - job_name: "node"
    scrape_interval: 2s
    static_configs:
      - targets: ["${app_private_ip}:9100"]

rule_files:
  - "rules/*.yml"
EOF

# ---------------------------
# Prometheus Alert Rules
# ---------------------------
cat <<EOF > /opt/monitoring/prometheus/rules/alerts.yml
groups:
  - name: basic-alerts
    rules:
      - alert: AppDown
        expr: up{job="spring-app"} == 0
        for: 10s
        labels:
          severity: critical

      - alert: NodeDown
        expr: up{job="node"} == 0
        for: 10s
        labels:
          severity: critical
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
# Grafana Provisioning
# ---------------------------
cat <<EOF > /opt/monitoring/grafana/provisioning/dashboards/dashboards.yml
apiVersion: 1
providers:
  - name: "Prebuilt Dashboards"
    folder: "Auto Dashboards"
    type: file
    options:
      path: /var/lib/grafana/dashboards
EOF

cat <<EOF > /opt/monitoring/grafana/provisioning/datasources/prometheus.yml
apiVersion: 1
datasources:
  - name: Prometheus
    type: prometheus
    access: proxy
    url: http://prometheus:9090
    isDefault: true
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
