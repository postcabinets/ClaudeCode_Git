#!/bin/bash
# start-ttyd.sh — ttydをTailscaleインターフェースのみにバインドして起動
# セキュリティ: Tailscale VPN経由のみアクセス可能（LAN/インターネットからは不可）

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
PORT=7681

# .envから認証情報を読む
if [ -f "$PROJECT_DIR/.env" ]; then
    TTYD_USER=$(grep '^TTYD_USER=' "$PROJECT_DIR/.env" | cut -d= -f2)
    TTYD_PASS=$(grep '^TTYD_PASS=' "$PROJECT_DIR/.env" | cut -d= -f2)
fi
TTYD_USER="${TTYD_USER:-claude}"
TTYD_PASS="${TTYD_PASS:-changeme}"

TAILSCALE_IP=$(tailscale ip -4 2>/dev/null)
if [ -z "$TAILSCALE_IP" ]; then
    echo "ERROR: Tailscale is not connected. Start Tailscale first."
    exit 1
fi

# Tailscaleのネットワークインターフェース名を動的に取得
TS_IFACE=$(ifconfig | grep -B1 "$TAILSCALE_IP" | head -1 | grep -o '^[a-z0-9]*')
if [ -z "$TS_IFACE" ]; then
    echo "WARNING: Could not find Tailscale interface, binding to all interfaces"
    IFACE_OPT=""
else
    IFACE_OPT="--interface $TS_IFACE"
fi

echo "Starting ttyd on http://${TAILSCALE_IP}:${PORT} (iface: ${TS_IFACE:-all})"
echo "Access from your phone via Tailscale VPN"

exec ttyd \
    --port "$PORT" \
    $IFACE_OPT \
    --credential "${TTYD_USER}:${TTYD_PASS}" \
    --max-clients 3 \
    --ping-interval 30 \
    --writable \
    bash "${SCRIPT_DIR}/ttyd-claude.sh"
