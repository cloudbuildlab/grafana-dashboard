#!/bin/bash
set -e
exec > >(tee /var/log/user-data.log) 2>&1
echo "user-data started at $(date '+%Y-%m-%dT%H:%M:%S%z')"

# Allow network and IMDS to be ready
sleep 15

# Install Docker (Amazon Linux 2)
yum install -y docker
systemctl enable docker
systemctl start docker

# Wait for Docker to be ready
for i in $(seq 1 30); do
  if systemctl is-active --quiet docker && docker info >/dev/null 2>&1; then
    echo "Docker ready after $i attempt(s)"
    break
  fi
  if [ "$i" -eq 30 ]; then
    echo "ERROR: Docker did not become ready"
    exit 1
  fi
  sleep 2
done

# Local Grafana data dir (data is on instance disk)
mkdir -p /grafana-data/provisioning/dashboards /grafana-data/provisioning/datasources /grafana-data/provisioning/plugins /grafana-data/provisioning/alerting /grafana-data/provisioning/notifiers
chown -R 472:472 /grafana-data

# Fetch secrets from SSM (retry until instance profile/SSM is available)
CLIENT_SECRET=""
for i in $(seq 1 12); do
  RAW=$(aws ssm get-parameter --name "${ssm_cognito_secret}" --with-decryption --query Parameter.Value --output text --region "${aws_region}" 2>/dev/null || true)
  if [ -n "$RAW" ]; then
    CLIENT_SECRET=$(printf '%s' "$RAW" | tr -d '\n\r')
    echo "SSM cognito secret fetched after $i attempt(s)"
    break
  fi
  echo "SSM attempt $i/12 failed, retrying in 10s..."
  sleep 10
done
if [ -z "$CLIENT_SECRET" ]; then
  echo "ERROR: Failed to fetch Cognito client secret from SSM"
  exit 1
fi

%{if has_admin_password}
ADMIN_PW=""
for i in $(seq 1 12); do
  RAW_PW=$(aws ssm get-parameter --name "${ssm_admin_password}" --with-decryption --query Parameter.Value --output text --region "${aws_region}" 2>/dev/null || true)
  if [ -n "$RAW_PW" ]; then
    ADMIN_PW=$(printf '%s' "$RAW_PW" | tr -d '\n\r')
    echo "SSM admin password fetched after $i attempt(s)"
    break
  fi
  sleep 10
done
if [ -z "$ADMIN_PW" ]; then
  echo "ERROR: Failed to fetch admin password from SSM"
  exit 1
fi
%{endif}

# Write secrets to env file; Docker --env-file reads KEY=VALUE with no shell expansion
GRAFANA_ENV_FILE=/tmp/grafana-oauth-env
printf '%s\n' "GF_AUTH_GENERIC_OAUTH_CLIENT_SECRET=$CLIENT_SECRET" > "$GRAFANA_ENV_FILE"
%{if has_admin_password}
printf '%s\n' "GF_SECURITY_ADMIN_PASSWORD=$ADMIN_PW" >> "$GRAFANA_ENV_FILE"
%{endif}
chmod 600 "$GRAFANA_ENV_FILE"

# Run Grafana container (same env as grafana_cognito ECS task definition)
docker run -d --restart unless-stopped --name grafana \
  -p ${grafana_port}:3000 \
  -v /grafana-data:/grafana-data \
  -u 472:472 \
  --env-file "$GRAFANA_ENV_FILE" \
  -e GF_PATHS_DATA=/grafana-data \
  -e GF_PATHS_PLUGINS=/grafana-data/plugins \
  -e GF_PATHS_LOGS=/grafana-data/log \
  -e GF_PATHS_PROVISIONING=/grafana-data/provisioning \
  -e GF_SERVER_ROOT_URL=https://${grafana_fqdn} \
  -e GF_AUTH_GENERIC_OAUTH_ENABLED=true \
  -e GF_AUTH_GENERIC_OAUTH_NAME=Cognito \
  -e GF_AUTH_GENERIC_OAUTH_CLIENT_ID=${cognito_client_id} \
  -e "GF_AUTH_GENERIC_OAUTH_SCOPES=openid profile email" \
  -e GF_AUTH_GENERIC_OAUTH_AUTH_URL=${cognito_domain_url}/oauth2/authorize \
  -e GF_AUTH_GENERIC_OAUTH_TOKEN_URL=${cognito_domain_url}/oauth2/token \
  -e GF_AUTH_GENERIC_OAUTH_API_URL=${cognito_domain_url}/oauth2/userInfo \
  -e GF_AUTH_GENERIC_OAUTH_ALLOW_SIGN_UP=true \
  -e GF_AUTH_GENERIC_OAUTH_ROLE_ATTRIBUTE_PATH=grafana_role \
  -e GF_AUTH_GENERIC_OAUTH_ROLE_ATTRIBUTE_STRICT=true \
  -e GF_AUTH_GENERIC_OAUTH_ALLOW_ASSIGN_GRAFANA_ADMIN=true \
  -e GF_AUTH_DISABLE_LOGIN_FORM=false \
  ${grafana_image}

rm -f "$GRAFANA_ENV_FILE"

echo "user-data finished at $(date '+%Y-%m-%dT%H:%M:%S%z')"
