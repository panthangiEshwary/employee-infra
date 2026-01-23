#!/bin/bash
set -ex
 
# ---------------------------
# System Update & Docker
# ---------------------------
yum update -y
yum install -y docker
systemctl start docker
systemctl enable docker
 
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
curl -L https://grafana.com/api/dashboards/1860/revisions/37/download \
  -o /opt/monitoring/grafana/dashboards/node-exporter.json
 
curl -L https://grafana.com/api/dashboards/4701/revisions/4/download \
  -o /opt/monitoring/grafana/dashboards/jvm.json
 
curl -L https://grafana.com/api/dashboards/6756/revisions/2/download \
  -o /opt/monitoring/grafana/dashboards/spring-boot.json
 
# ---------------------------
# Prometheus Config 
# ---------------------------
cat <<EOF > /opt/monitoring/prometheus/prometheus.yml
global:
  scrape_interval: 5s
 
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
# Prometheus Alert Rules (FIXED)
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
        annotations:
          description: "Spring Boot Application is DOWN"
 
      - alert: NodeDown
        expr: up{job="node"} == 0
        for: 10s
        labels:
          severity: critical
        annotations:
          description: "Node Exporter is DOWN"
 
      - alert: HighCPUUsage
        expr: (1 - avg(rate(node_cpu_seconds_total{mode="idle"}[2m]))) * 100 > 90
        for: 10s
        labels:
          severity: warning
        annotations:
          description: "High CPU Usage (>80%)"
 
      - alert: HighMemoryUsage
        expr: (1 - (node_memory_MemAvailable_bytes / node_memory_MemTotal_bytes)) * 100 > 90
        for: 10s
        labels:
          severity: warning
        annotations:
          description: "High Memory Usage (>75%)"
  - name: jvm-micrometer-compat
    rules:
      - record: jvm_classes_loaded
        expr: jvm_classes_loaded_classes

      - record: jvm_classes_unloaded_total
        expr: jvm_classes_unloaded_classes_total
      
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
  group_wait: 5s
  group_interval: 5s
  repeat_interval: 1m
 
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
    disableDeletion: false
    editable: true
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
    editable: true
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
