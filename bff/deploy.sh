#!/usr/bin/env bash
# 部署 Tomeet BFF 到生产服务器：交叉编译 → workbench 上传 → 换二进制 → 重启 → 验证。
# 前置：本机已装 Go 和 workbench CLI；服务器已装 systemd 单元并配好 /opt/tomeet-bff/.env（见 Task 4）。
# 用法:  bff/deploy.sh
set -euo pipefail

INSTANCE_ID="${INSTANCE_ID:-i-bp1bal3zezgaul8tc0m6}"
REMOTE_DIR="/opt/tomeet-bff"
SERVICE="tomeet-bff"

cd "$(dirname "$0")"

VERSION="$(git rev-parse --short HEAD 2>/dev/null || echo nogit)"
if ! git diff --quiet -- . 2>/dev/null; then
    VERSION="${VERSION}-dirty"
fi

OUT="$(mktemp -t tomeet-bff)"
trap 'rm -f "$OUT"' EXIT

echo "==> Building linux/amd64 (version=$VERSION)"
GOOS=linux GOARCH=amd64 CGO_ENABLED=0 go build \
    -ldflags "-X main.version=$VERSION" \
    -o "$OUT" .

echo "==> Uploading to $INSTANCE_ID:/tmp/tomeet-bff.new"
workbench upload "$OUT" /tmp/tomeet-bff.new --instance-id "$INSTANCE_ID" -f

echo "==> Swapping binary and restarting $SERVICE"
workbench exec --instance-id "$INSTANCE_ID" --timeout 60 --command "
  set -e
  cp $REMOTE_DIR/tomeet-bff $REMOTE_DIR/tomeet-bff.bak 2>/dev/null || true
  mv /tmp/tomeet-bff.new $REMOTE_DIR/tomeet-bff
  chmod +x $REMOTE_DIR/tomeet-bff
  systemctl restart $SERVICE
  sleep 1
  systemctl is-active $SERVICE
"

echo "==> Verifying startup log (expect version=$VERSION)"
workbench exec --instance-id "$INSTANCE_ID" --command \
    "journalctl -u $SERVICE -n 1 --no-pager | grep 'listening'"

echo "==> Checking local health endpoint"
workbench exec --instance-id "$INSTANCE_ID" --command \
    "curl -fsS --max-time 5 http://127.0.0.1:8088/health"
echo
echo "==> Deploy OK (version=$VERSION)"
