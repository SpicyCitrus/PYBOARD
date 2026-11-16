#!/usr/bin/env bash

set -Eeuo pipefail

REPO="https://github.com/SpicyCitrus/PYBOARD"
BRANCH="main"

APP_DIR="$HOME/.local/share/pyboard"
BIN_DIR="$HOME/.local/bin"
SERVICE_DIR="$HOME/.config/systemd/user"
CONFIG_DIR="$HOME/.config/soundboard"
DESKTOP_DIR="$HOME/.local/share/applications"

TEMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TEMP_DIR"' EXIT

echo "======================================"
echo "          PYBOARD INSTALLER"
echo "          Made with ❤️ by Cozy"
echo "======================================"

echo ""
echo "Checking system dependencies..."

if command -v pacman >/dev/null 2>&1; then
    echo "Arch Linux detected."
    sudo pacman -S --needed --noconfirm curl tar python tk mpv libpulse
elif command -v apt-get >/dev/null 2>&1; then
    echo "Debian / Ubuntu detected."
    sudo apt-get update
    sudo apt-get install -y curl tar python3 python3-tk mpv pulseaudio-utils
else
    echo "ERROR: Unsupported Linux distribution."
    exit 1
fi

echo ""
echo "Downloading PYBOARD..."

curl -fL "$REPO/archive/refs/heads/$BRANCH.tar.gz" -o "$TEMP_DIR/pyboard.tar.gz"

mkdir -p "$TEMP_DIR/extracted"

tar -xzf "$TEMP_DIR/pyboard.tar.gz" -C "$TEMP_DIR/extracted"

SOURCE_DIR="$TEMP_DIR/extracted/PYBOARD-$BRANCH"

REQUIRED_FILES=(
    "soundboard.py"
    "web_ui.py"
    "templates/index.html"
    "static/style.css"
    "static/app.js"
    "virtual-mic.sh"
    "soundboard-virtual-mic.service"
)

for file in "${REQUIRED_FILES[@]}"; do
    if [[ ! -f "$SOURCE_DIR/$file" ]]; then
        echo "ERROR: Missing required file: $file"
        exit 1
    fi
done

echo ""
echo "Preparing installation..."

mkdir -p "$APP_DIR"
mkdir -p "$APP_DIR/templates"
mkdir -p "$APP_DIR/static"
mkdir -p "$APP_DIR/soundboards"

mkdir -p "$BIN_DIR"
mkdir -p "$SERVICE_DIR"
mkdir -p "$CONFIG_DIR"
mkdir -p "$DESKTOP_DIR"

echo "Installing soundboard..."

install -m 644 "$SOURCE_DIR/soundboard.py" "$APP_DIR/soundboard.py"

echo "Installing web interface..."

install -m 644 "$SOURCE_DIR/web_ui.py" "$APP_DIR/web_ui.py"
install -m 644 "$SOURCE_DIR/templates/index.html" "$APP_DIR/templates/index.html"
install -m 644 "$SOURCE_DIR/static/style.css" "$APP_DIR/static/style.css"
install -m 644 "$SOURCE_DIR/static/app.js" "$APP_DIR/static/app.js"

echo "Installing virtual microphone..."

install -m 755 "$SOURCE_DIR/virtual-mic.sh" "$BIN_DIR/pyboard-virtual-mic"
install -m 644 "$SOURCE_DIR/soundboard-virtual-mic.service" "$SERVICE_DIR/soundboard-virtual-mic.service"

cat > "$BIN_DIR/pyboard" <<EOF
#!/usr/bin/env bash
exec python3 "$APP_DIR/soundboard.py" "\$@"
EOF

chmod +x "$BIN_DIR/pyboard"

cat > "$BIN_DIR/pyboard-web" <<EOF
#!/usr/bin/env bash
exec python3 "$APP_DIR/web_ui.py" "\$@"
EOF

chmod +x "$BIN_DIR/pyboard-web"

cat > "$DESKTOP_DIR/pyboard.desktop" <<EOF
[Desktop Entry]
Name=PYBOARD
Comment=Linux Soundboard - Made with Cozy
Exec=$BIN_DIR/pyboard
Terminal=false
Type=Application
Categories=AudioVideo;Audio;
EOF

if command -v systemctl >/dev/null 2>&1 &&
   systemctl --user daemon-reload >/dev/null 2>&1; then
    echo "Systemd user services reloaded."
else
    echo "Systemd user services unavailable; skipping reload."
fi

echo ""
echo "Starting PYBOARD Web UI..."

WEB_URL="http://127.0.0.1:5000"

if curl -fsS --max-time 2 "$WEB_URL/" >/dev/null 2>&1; then
    echo "PYBOARD is already running."
else
    nohup "$BIN_DIR/pyboard-web" > "$CONFIG_DIR/web-ui.log" 2>&1 </dev/null &

    STARTED=false

    for attempt in {1..10}; do
        if curl -fsS --max-time 2 "$WEB_URL/" >/dev/null 2>&1; then
            STARTED=true
            break
        fi
        sleep 1
    done

    if [[ "$STARTED" != "true" ]]; then
        echo ""
        echo "WARNING: PYBOARD Web UI did not start."
        echo "Check the log:"
        echo "$CONFIG_DIR/web-ui.log"
    fi
fi

echo ""
echo "======================================"
echo "          PYBOARD INSTALLED!"
echo "======================================"

echo ""
echo "OPEN PYBOARD IN YOUR BROWSER:"
echo ""
echo "  $WEB_URL"
echo ""

echo "DESKTOP VERSION:"
echo ""
echo "  pyboard"
echo ""

echo "WEB VERSION:"
echo ""
echo "  pyboard-web"
echo ""

echo "VIRTUAL MICROPHONE:"
echo ""
echo "  pyboard-virtual-mic start"
echo "  pyboard-virtual-mic stop"
echo "  pyboard-virtual-mic status"
echo ""

echo "MICROPHONE CONFIGURATION:"
echo ""
echo "  ~/.config/pyboard/virtual-mic.conf"
echo ""

echo "INSTALLATION LOG:"
echo ""
echo "  $CONFIG_DIR/web-ui.log"

echo ""
echo "======================================"
echo "       Made with ❤️ by Cozy"
echo "======================================"
