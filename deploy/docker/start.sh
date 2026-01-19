#!/bin/bash
set -e

cleanup() {
    echo "Shutting down..."
    vncserver -kill :1 2>/dev/null || true
    pkill -f novnc_proxy 2>/dev/null || true
    exit 0
}

trap cleanup SIGTERM SIGINT SIGHUP

VNC_PASSWORD=${VNC_PASSWORD:-password}
RESOLUTION=${RESOLUTION:-1280x800}
NOVNC_PORT=${NOVNC_PORT:-6080}

rm -rf /tmp/.X1-lock /tmp/.X11-unix/X1 2>/dev/null || true

mkdir -p "$HOME/.vnc"
echo "$VNC_PASSWORD" | vncpasswd -f > "$HOME/.vnc/passwd"
chmod 600 "$HOME/.vnc/passwd"

cat > "$HOME/.vnc/xstartup" << 'EOF'
#!/bin/sh
unset SESSION_MANAGER
unset DBUS_SESSION_BUS_ADDRESS
openbox-session &
exec /usr/bin/antigravity_tools
EOF
chmod +x "$HOME/.vnc/xstartup"

echo "Checking for Antigravity Tools..."
CURRENT_VERSION=$(dpkg -s antigravity-tools 2>/dev/null | grep "Version:" | awk '{print "v"$2}' || echo "none")

ARCH=$(dpkg --print-architecture)
echo "Detected architecture: $ARCH"

RATE_LIMIT=$(wget -qO- --timeout=10 --header="Accept: application/vnd.github.v3+json" \
    "https://api.github.com/rate_limit" 2>/dev/null | grep -o '"remaining":[0-9]*' | head -1 | cut -d: -f2 || echo "0")

if [ "${RATE_LIMIT:-0}" -gt 5 ]; then
    LATEST_URL=$(wget -qO- --timeout=30 https://api.github.com/repos/lbjlaq/Antigravity-Manager/releases/latest \
        | grep "browser_download_url.*_${ARCH}.deb" \
        | cut -d '"' -f 4)

    if [ -n "$LATEST_URL" ]; then
        LATEST_VERSION=$(echo "$LATEST_URL" | grep -oP 'v[\d.]+' | head -1)

        if [ "$CURRENT_VERSION" = "none" ]; then
            echo "Installing $LATEST_VERSION..."
            wget -q --timeout=60 "$LATEST_URL" -O /tmp/ag.deb
            sudo apt-get update -qq && sudo apt-get install -y /tmp/ag.deb
            rm -f /tmp/ag.deb
            sudo rm -rf /var/lib/apt/lists/*
        elif [ "$CURRENT_VERSION" != "$LATEST_VERSION" ]; then
            echo "Updating $CURRENT_VERSION -> $LATEST_VERSION"
            wget -q --timeout=60 "$LATEST_URL" -O /tmp/ag.deb
            sudo apt-get update -qq && sudo apt-get install -y /tmp/ag.deb
            rm -f /tmp/ag.deb
            sudo rm -rf /var/lib/apt/lists/*
        else
            echo "Up to date: $CURRENT_VERSION"
        fi
    else
        echo "Cannot reach GitHub, using cached version"
    fi
else
    echo "GitHub API rate limit exceeded (remaining: ${RATE_LIMIT:-0}), using cached version"
fi

vncserver -localhost no -geometry ${RESOLUTION} -depth 24 :1
/usr/share/novnc/utils/novnc_proxy --vnc localhost:5901 --listen ${NOVNC_PORT} &

echo "Ready: http://localhost:${NOVNC_PORT}/vnc_lite.html"

while true; do
    sleep 1 &
    wait $!
done
