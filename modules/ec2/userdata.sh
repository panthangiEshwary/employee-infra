#!/bin/bash
set -eux
 
# Log everything
exec > >(tee /var/log/userdata.log | logger -t userdata) 2>&1
 
echo "===== USER-DATA STARTED ====="
 
########################################
# Update system & install Docker
########################################
dnf update -y
dnf install -y docker
dnf install -y aws-cli
 
 
systemctl enable docker
systemctl start docker
 
 
########################################
# Enable SSM Agent (AL2023 already has it)
########################################
systemctl enable amazon-ssm-agent
systemctl start amazon-ssm-agent
 
########################################
# Create application directory
########################################
mkdir -p /opt/app
chmod 755 /opt/app
 
########################################
# Create deploy.sh (NO secrets here)
########################################
cat << 'EOF' > /opt/app/deploy.sh
#!/bin/bash
set -eux
 
echo "===== DEPLOYMENT STARTED ====="
echo "Timestamp: $(date)"
 
# Required env vars (injected by SSM):
# GHCR_USER
# GHCR_TOKEN
# BACKEND_IMAGE
# FRONTEND_IMAGE
# DB_HOST
# DB_USER
# DB_PASS
 
########################################
# Login to GHCR
########################################
echo "$GHCR_TOKEN" | docker login ghcr.io -u "$GHCR_USER" --password-stdin
 
########################################
# Backend container
########################################
docker pull "$BACKEND_IMAGE"
 
docker stop employee-backend || true
docker rm employee-backend || true
docker rmi employee-backend || true
docker network create employee-net || true
 
docker run -d \
  --name employee-backend \
  --network employee-net \
  -p 8080:8080 \
  -e SPRING_DATASOURCE_URL="jdbc:mysql://${DB_HOST}:3306/employee_attendance_db" \
  -e SPRING_DATASOURCE_USERNAME="$DB_USER" \
  -e SPRING_DATASOURCE_PASSWORD="$DB_PASS" \
  -e SPRING_JPA_HIBERNATE_DDL_AUTO=update \
  -e SPRING_JPA_SHOW_SQL=true \
  --restart=always \
  "$BACKEND_IMAGE"
 
########################################
# Frontend container
########################################
docker pull "$FRONTEND_IMAGE"
 
docker stop employee-frontend || true
docker rm employee-frontend || true
 
docker run -d \
  --name employee-frontend \
  --network employee-net \
  -p 80:80 \
  --restart=always \
  "$FRONTEND_IMAGE"
 
########################################
# node exporter
########################################
docker run -d \
  --name node-exporter \
  --network employee-net \
  -p 9100:9100 \
  --restart unless-stopped \
  prom/node-exporter
 
echo "===== DEPLOYMENT COMPLETED ====="
EOF
 
########################################
# Make deploy script executable
########################################
chmod +x /opt/app/deploy.sh
 
 
 
########################################
# Initial Deployment (Day 0)
########################################
 
echo "===== TRIGGERING INITIAL DEPLOYMENT ====="
export GHCR_USER="${GHCR_USER}"   # Ensure these are in your template variables
export GHCR_TOKEN="${GHCR_TOKEN}" 
export DB_HOST="${DB_HOST}"
export DB_USER="${DB_USER}"
export DB_PASS="${DB_PASS}"
export BACKEND_IMAGE="${BACKEND_IMAGE}"
export FRONTEND_IMAGE="${FRONTEND_IMAGE}"
 
# Execute the script immediately
/opt/app/deploy.sh
 
echo "===== USER-DATA COMPLETED SUCCESSFULLY ====="
