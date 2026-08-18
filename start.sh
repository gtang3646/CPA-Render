#!/bin/sh
set -e

# 两个 Key 必须都在 Render 环境变量（Secrets）中配置
if [ -z "$CPA_MANAGER_ADMIN_KEY" ] || [ -z "$CPA_MANAGEMENT_KEY" ]; then
  echo "ERROR: 缺少 CPA_MANAGER_ADMIN_KEY 或 CPA_MANAGEMENT_KEY，请在 Render 环境变量的 Secrets 中配置。" >&2
  exit 1
fi

mkdir -p /data /root/.cli-proxy-api /CLIProxyAPI

# 自动生成 CLIProxyAPI config.yaml
cat > /CLIProxyAPI/config.yaml <<EOF
host: ""
port: 8317
auth-dir: "/root/.cli-proxy-api"
api-keys:
  - "${CPA_MANAGER_ADMIN_KEY}"
remote-management:
  allow-remote: false
  secret-key: "${CPA_MANAGEMENT_KEY}"
usage-statistics-enabled: true
debug: false
EOF

# CPA-Manager-Plus (18317)
cpa-manager-plus &

# CLIProxyAPI (8317)
(cd /CLIProxyAPI && ./CLIProxyAPI) &

# Caddy 反向代理主进程，监听 Render 分配的 $PORT (10000)
exec caddy run --config /etc/caddy/Caddyfile --adapter caddyfile