#!/bin/bash
set -eux

exec > >(tee /var/log/userdata.log | logger -t userdata) 2>&1

echo "===== USER-DATA STARTED ====="

dnf update -y
dnf install -y docker aws-cli

systemctl enable docker
systemctl start docker

systemctl enable amazon-ssm-agent
systemctl start amazon-ssm-agent

mkdir -p /opt/app
chmod 755 /opt/app

cat << 'EOF' > /opt/app/deploy.sh
#!/bin/bash
set -eux

echo "===== DEPLOYMENT STARTED ====="

echo "$GHCR_TOKEN" | docker login ghcr.io -u "$GHCR_USER" --password-stdin

docker network create employee-net || true

########################################
# Backend
########################################
docker pull "$BACKEND_IMAGE"
docker rm -f employee-backend || true

docker run -d \
  --name employee-backend \
  --network employee-net \
  -p 8080:8080 \
  -e SPRING_DATASOURCE_URL="jdbc:mysql://${DB_HOST}:3306/employee_attendance_db" \
  -e SPRING_DATASOURCE_USERNAME="$DB_USER" \
  -e SPRING_DATASOURCE_PASSWORD="$DB_PASS" \
  --restart always \
  "$BACKEND_IMAGE"

########################################
# Frontend
########################################
docker pull "$FRONTEND_IMAGE"
docker rm -f employee-frontend || true

docker run -d \
  --name employee-frontend \
  --network employee-net \
  -p 80:80 \
  --restart always \
  "$FRONTEND_IMAGE"

########################################
# Node Exporter (HOST ACCESSIBLE)
########################################
docker rm -f node-exporter || true

docker run -d \
  --name node-exporter \
  --network employee-net \
  -p 9100:9100 \
  --restart unless-stopped \
  prom/node-exporter

echo "===== DEPLOYMENT COMPLETED ====="
EOF

chmod +x /opt/app/deploy.sh

########################################
# cAdvisor (HOST ACCESSIBLE)
########################################
docker rm -f cadvisor || true

docker run -d \
  --name cadvisor \
  -p 8085:8080 \
  --restart unless-stopped \
  -v /:/rootfs:ro \
  -v /var/run:/var/run:ro \
  -v /sys:/sys:ro \
  -v /var/lib/docker/:/var/lib/docker:ro \
  gcr.io/cadvisor/cadvisor:latest

########################################
# Day-0 deploy
########################################
/opt/app/deploy.sh

echo "===== USER-DATA COMPLETED ====="
