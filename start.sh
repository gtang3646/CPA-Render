#!/bin/sh
set -e

if [ -z "$CPA_MANAGER_ADMIN_KEY" ] || [ -z "$CPA_MANAGEMENT_KEY" ]; then
  echo "ERROR: 缺少 CPA_MANAGER_ADMIN_KEY 或 CPA_MANAGEMENT_KEY" >&2
  exit 1
fi

mkdir -p /data /root/.cli-proxy-api /CLIProxyAPI

cat > /CLIProxyAPI/config.yaml <<EOF
host: "0.0.0.0"
port: 8317
auth-dir: "/root/.cli-proxy-api"
api-keys:
  - "${CPA_MANAGER_ADMIN_KEY}"
remote-management:
  allow-remote: false
  secret-key: "${CPA_MANAGEMENT_KEY}"
usage-statistics-enabled: true
debug: true
EOF

# 启动 CLIProxyAPI
echo "Starting CLIProxyAPI..."
(cd /CLIProxyAPI && ./CLIProxyAPI) &
CLIPID=$!

# 等待就绪
for i in $(seq 1 15); do
  if nc -z 127.0.0.1 8317 2>/dev/null; then
    echo "CLIProxyAPI ready on :8317"
    break
  fi
  if [ $i -eq 15 ]; then
    echo "WARNING: CLIProxyAPI not ready after 15s, continuing anyway"
  fi
  sleep 1
done

# 启动 CPA Manager
echo "Starting CPA Manager..."
cpa-manager-plus &
MANPID=$!

for i in $(seq 1 15); do
  if nc -z 127.0.0.1 18317 2>/dev/null; then
    echo "CPA Manager ready on :18317"
    break
  fi
  if [ $i -eq 15 ]; then
    echo "WARNING: CPA Manager not ready after 15s, continuing anyway"
  fi
  sleep 1
done

echo "Starting Caddy..."
exec caddy run --config /etc/caddy/Caddyfile --adapter caddyfile