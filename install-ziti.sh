#!/bin/sh
# install-ziti.sh — Install ziti-edge-tunnel as a persistent service on Teltonika RUT956
# Copy this file to /etc/ziti/ on the router and run it once as root.
# Requires: /etc/ziti/identity.json already present.

set -e

ZITI_DIR="/etc/ziti"
IDENTITY="${ZITI_DIR}/identity.json"
INITD="/etc/init.d/ziti"
BINARY_URL="https://github.com/affanzbasalamah/nicfragale-rut956/raw/main/OpenWRT-RUT956-1.16.1-stripped.gz"
BINARY="/tmp/ziti-edge-tunnel"
BINARY_GZ="/tmp/ziti-edge-tunnel.gz"

echo "[ziti-install] Checking identity file..."
[ -f "${IDENTITY}" ] || {
    echo "ERROR: Identity file not found at ${IDENTITY}"
    echo "Copy your .json identity file there first, then re-run."
    exit 1
}

echo "[ziti-install] Downloading ziti-edge-tunnel binary..."
wget -q -O "${BINARY_GZ}" "${BINARY_URL}" || {
    echo "ERROR: Download failed. Check internet connectivity."
    exit 1
}
echo "[ziti-install] Download complete."
gunzip -f "${BINARY_GZ}"
chmod +x "${BINARY}"
echo "[ziti-install] Binary ready: $(ls -lh ${BINARY} | awk '{print $5, $9}')"

echo "[ziti-install] Installing init.d service..."
cat > "${INITD}" << 'INITEOF'
#!/bin/sh /etc/rc.common

USE_PROCD=1
START=99
STOP=10

ZITI_DIR="/etc/ziti"
IDENTITY="${ZITI_DIR}/identity.json"
BINARY="/tmp/ziti-edge-tunnel"
BINARY_GZ="/tmp/ziti-edge-tunnel.gz"
BINARY_URL="https://github.com/affanzbasalamah/nicfragale-rut956/raw/main/OpenWRT-RUT956-1.16.1-stripped.gz"

download_binary() {
    [ -x "${BINARY}" ] && return 0
    logger -t ziti "Waiting for WAN connectivity..."
    local i=0
    while ! ping -c1 -W2 8.8.8.8 >/dev/null 2>&1; do
        i=$((i+1))
        [ $i -ge 30 ] && { logger -t ziti "ERROR: No WAN after 60s, giving up"; return 1; }
        sleep 2
    done
    logger -t ziti "Downloading ziti-edge-tunnel from GitHub..."
    wget -q -O "${BINARY_GZ}" "${BINARY_URL}" 2>/dev/null || {
        logger -t ziti "ERROR: Download failed"
        return 1
    }
    gunzip -f "${BINARY_GZ}" || {
        logger -t ziti "ERROR: Decompress failed"
        return 1
    }
    chmod +x "${BINARY}"
    logger -t ziti "Binary ready at ${BINARY}"
}

start_service() {
    [ -f "${IDENTITY}" ] || {
        logger -t ziti "ERROR: Identity file not found at ${IDENTITY} — not starting"
        return 1
    }
    download_binary || return 1

    logger -t ziti "Starting ziti-edge-tunnel..."
    procd_open_instance
    procd_set_param command "${BINARY}" run --identity "${IDENTITY}"
    procd_set_param respawn 300 5 0
    procd_set_param stdout 1
    procd_set_param stderr 1
    procd_close_instance
}

stop_service() {
    logger -t ziti "Stopped ziti-edge-tunnel"
}
INITEOF

chmod +x "${INITD}"

echo "[ziti-install] Enabling service to start on boot..."
/etc/init.d/ziti enable

echo "[ziti-install] Starting ziti-edge-tunnel now..."
/etc/init.d/ziti start

echo ""
echo "[ziti-install] Done. ziti-edge-tunnel is running and will auto-start on reboot."
echo "  Logs : logread | grep ziti"
echo "  Stop : /etc/init.d/ziti stop"
echo "  Start: /etc/init.d/ziti start"
