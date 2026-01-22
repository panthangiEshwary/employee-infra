#!/bin/bash
set -ex

yum update -y
yum install -y docker
systemctl enable docker
systemctl start docker

mkdir -p /opt/monitoring/prometheus/rules
mkdir -p /opt/monitoring/grafana/provisioning/{dashboards,datasources}
mkdir -p /opt/monitoring/grafana/dashboards
mkdir -p /opt/monitoring/alertmanager

########################################
# Prometheus config
########################################
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

  - job_name: "cadvisor"
    static_configs:
      - targets: ["${app_private_ip}:8085"]

rule_files:
  - "rules/*.yml"
EOF

########################################
# Alert rules
########################################
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
    expr: (1 - avg(rate(node_cpu_seconds_total{mode="idle"}[2m]))) * 100 > 80
    for: 30s
    labels:
      severity: warning
    annotations:
      description: "High CPU usage"

  - alert: HighMemoryUsage
    expr: (1 - (node_memory_MemAvailable_bytes / node_memory_MemTotal_bytes)) * 100 > 75
    for: 30s
    labels:
      severity: warning
    annotations:
      description: "High memory usage"
EOF

########################################
# Alertmanager
########################################
cat <<EOF > /opt/monitoring/alertmanager/alertmanager.yml
global:
  resolve_timeout: 30s

route:
  receiver: "n8n"

receivers:
- name: "n8n"
  webhook_configs:
  - url: "http://${n8n_private_ip}:5678/webhook/prometheus-alert"
    send_resolved: true
EOF

########################################
# Network
########################################
docker network create employee-mon || true

########################################
# Containers
########################################
docker run -d \
  --name prometheus \
  --network employee-mon \
  -p 9090:9090 \
  -v /opt/monitoring/prometheus/prometheus.yml:/etc/prometheus/prometheus.yml \
  -v /opt/monitoring/prometheus/rules:/etc/prometheus/rules \
  prom/prometheus

docker run -d \
  --name grafana \
  --network employee-mon \
  -p 3000:3000 \
  grafana/grafana

docker run -d \
  --name alertmanager \
  --network employee-mon \
  -p 9093:9093 \
  -v /opt/monitoring/alertmanager/alertmanager.yml:/etc/alertmanager/alertmanager.yml \
  prom/alertmanager
