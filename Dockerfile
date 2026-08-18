# ============ Stage 0: 拉取上游 CPA 源码 ============
FROM debian:bookworm-slim AS fetch
ARG CPA_REF=main
RUN apt-get update && apt-get install -y --no-install-recommends git ca-certificates \
    && rm -rf /var/lib/apt/lists/*
RUN git clone --depth 1 --branch ${CPA_REF} https://github.com/seakee/CPA-Manager-Plus /src/CPA-Manager-Plus

# ============ Stage 1: 复用 CLIProxyAPI 官方预构建镜像 ============
FROM eceasy/cli-proxy-api:latest AS cli

# ============ Stage 2: 构建 CPA 前端 (React/Vite 单文件) ============
FROM node:22-alpine AS web
ARG VERSION=render
WORKDIR /app
COPY --from=fetch /src/CPA-Manager-Plus/package*.json ./
COPY --from=fetch /src/CPA-Manager-Plus/apps/web/package.json ./apps/web/package.json
RUN npm ci
COPY --from=fetch /src/CPA-Manager-Plus/apps/web ./apps/web
WORKDIR /app/apps/web
RUN VERSION=$VERSION npm run build

# ============ Stage 3: 构建 CPA Manager (静态 Go 二进制) ============
FROM golang:1.24-alpine AS manager
ARG TARGETOS
ARG TARGETARCH
WORKDIR /src
COPY --from=fetch /src/CPA-Manager-Plus/apps/manager-server ./apps/manager-server
COPY --from=web /app/apps/web/dist/index.html ./apps/manager-server/internal/httpapi/web/management.html
WORKDIR /src/apps/manager-server
RUN go mod download
RUN CGO_ENABLED=0 GOOS=${TARGETOS} GOARCH=${TARGETARCH} go build -o /out/cpa-manager-plus ./cmd/cpa-manager-plus

# ============ Stage 4: 从官方镜像取 Caddy 静态二进制 (改为非 Alpine 版本，确保 glibc 兼容) ============
FROM caddy:2 AS caddybin
RUN cp "$(command -v caddy)" /caddy

# ============ 最终镜像（Debian，glibc 环境） ============
FROM debian:bookworm-slim
ENV TZ=Asia/Shanghai \
    HTTP_ADDR=0.0.0.0:18317 \
    USAGE_DATA_DIR=/data \
    USAGE_DB_PATH=/data/usage.sqlite

RUN apt-get update && apt-get install -y --no-install-recommends ca-certificates tzdata netcat-openbsd \
    && rm -rf /var/lib/apt/lists/* \
    && echo "* soft nofile 65535" >> /etc/security/limits.conf \
    && echo "* hard nofile 65535" >> /etc/security/limits.conf

COPY --from=caddybin /caddy /usr/local/bin/caddy
COPY --from=cli /CLIProxyAPI/CLIProxyAPI /CLIProxyAPI/CLIProxyAPI
COPY --from=manager /out/cpa-manager-plus /usr/local/bin/cpa-manager-plus
COPY Caddyfile /etc/caddy/Caddyfile
COPY start.sh /app/start.sh

RUN chmod +x /usr/local/bin/caddy /usr/local/bin/cpa-manager-plus /app/start.sh

EXPOSE 10000
ENTRYPOINT ["/app/start.sh"]