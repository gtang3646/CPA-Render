# ============ Stage 0: 拉取上游源码 ============
FROM debian:bookworm-slim AS fetch
ARG CLI_REF=main
ARG CPA_REF=main
RUN apt-get update && apt-get install -y --no-install-recommends git ca-certificates \
    && rm -rf /var/lib/apt/lists/*
RUN git clone --depth 1 --branch ${CLI_REF} https://github.com/router-for-me/CLIProxyAPI /src/CLIProxyAPI \
 && git clone --depth 1 --branch ${CPA_REF} https://github.com/seakee/CPA-Manager-Plus /src/CPA-Manager-Plus

# ============ Stage 1: 构建 CLIProxyAPI ============
FROM golang:1.26-bookworm AS cli
ARG VERSION=render
WORKDIR /src
COPY --from=fetch /src/CLIProxyAPI/go.mod /src/CLIProxyAPI/go.sum ./
RUN go mod download
COPY --from=fetch /src/CLIProxyAPI/ ./
RUN CGO_ENABLED=1 GOOS=linux go build -buildvcs=false \
    -ldflags="-s -w -X 'main.Version=${VERSION}' -X 'main.Commit=render' -X 'main.BuildDate=render'" \
    -o /out/CLIProxyAPI ./cmd/server

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

# ============ Stage 3: 构建 CPA Manager (Go, 内嵌前端) ============
FROM golang:1.24-alpine AS manager
ARG TARGETOS
ARG TARGETARCH
WORKDIR /src
COPY --from=fetch /src/CPA-Manager-Plus/apps/manager-server ./apps/manager-server
COPY --from=web /app/apps/web/dist/index.html ./apps/manager-server/internal/httpapi/web/management.html
WORKDIR /src/apps/manager-server
RUN go mod download
RUN CGO_ENABLED=0 GOOS=${TARGETOS} GOARCH=${TARGETARCH} go build -o /out/cpa-manager-plus ./cmd/cpa-manager-plus

# ============ 最终镜像 ============
FROM caddy:2
ENV TZ=Asia/Shanghai \
    HTTP_ADDR=0.0.0.0:18317 \
    USAGE_DATA_DIR=/data \
    USAGE_DB_PATH=/data/usage.sqlite

RUN apt-get update && apt-get install -y --no-install-recommends tzdata && rm -rf /var/lib/apt/lists/*

COPY --from=cli /out/CLIProxyAPI /CLIProxyAPI/CLIProxyAPI
COPY --from=manager /out/cpa-manager-plus /usr/local/bin/cpa-manager-plus
COPY Caddyfile /etc/caddy/Caddyfile
COPY start.sh /app/start.sh
RUN chmod +x /app/start.sh

EXPOSE 10000
ENTRYPOINT ["/app/start.sh"]