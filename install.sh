#!/usr/bin/env bash

set -euo pipefail

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

if command -v pacman >/dev/null 2>&1; then
    echo "Arch Linux detected."

    sudo pacman -S --needed \
        curl tar python tk mpv \
        pipewire pipewire-pulse wireplumber libpulse

elif command -v apt-get >/dev/null 2>&1; then
    echo "Debian / Ubuntu detected."

    sudo apt-get update

    sudo apt-get install -y \
        curl tar python3 python3-tk mpv \
        pipewire pipewire-pulse wireplumber pulseaudio-utils

else
    echo "Unsupported Linux distribution."
    exit 1
fi

echo ""
echo "Downloading PYBOARD..."

curl -fL \
    "$REPO/archive/refs/heads/$BRANCH.tar.gz" \
    -o "$TEMP_DIR/pyboard.tar.gz"

mkdir -p "$TEMP_DIR/extracted"

tar -xzf "$TEMP_DIR/pyboard.tar.gz" \
    -C "$TEMP_DIR/extracted"

SOURCE_DIR="$TEMP_DIR/extracted/PYBOARD-$BRANCH"

if [[ ! -f "$SOURCE_DIR/soundboard.py" ||
      ! -f "$SOURCE_DIR/virtual-mic.sh" ||
      ! -f "$SOURCE_DIR/soundboard-virtual-mic.service" ]]; then
    echo "ERROR: Required PYBOARD files are missing from GitHub."
    echo "Check that all application files are committed to main."
    exit 1
fi

echo "Installing PYBOARD files..."

mkdir -p "$APP_DIR"
mkdir -p "$BIN_DIR"
mkdir -p "$SERVICE_DIR"
mkdir -p "$CONFIG_DIR"
mkdir -p "$DESKTOP_DIR"

install -m 644 \
    "$SOURCE_DIR/soundboard.py" \
    "$APP_DIR/soundboard.py"

install -m 755 \
    "$SOURCE_DIR/virtual-mic.sh" \
    "$BIN_DIR/pyboard-virtual-mic"

install -m 644 \
    "$SOURCE_DIR/soundboard-virtual-mic.service" \
    "$SERVICE_DIR/soundboard-virtual-mic.service"

mkdir -p "$APP_DIR/soundboards"

echo "Creating application launcher..."

cat > "$BIN_DIR/pyboard" <<EOF
#!/usr/bin/env bash
exec python3 "$APP_DIR/soundboard.py" "\$@"
EOF

chmod +x "$BIN_DIR/pyboard"

cat > "$DESKTOP_DIR/pyboard.desktop" <<EOF
[Desktop Entry]
Name=PYBOARD
Comment=Linux Soundboard - Made with Cozy
Exec=$BIN_DIR/pyboard
Terminal=false
Type=Application
Categories=AudioVideo;Audio;
EOF

systemctl --user daemon-reload

echo ""
echo "======================================"
echo "       PYBOARD INSTALLED!"
echo "======================================"
echo ""
echo "Launch with:"
echo "pyboard"
echo ""
echo "Or find PYBOARD in your applications menu."
echo ""
echo "Open Settings to enable your virtual microphone."
echo ""
echo "Made with ❤️ by Cozy"
