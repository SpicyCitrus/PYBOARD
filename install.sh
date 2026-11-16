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

# Dependencies

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

# Verify files

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

echo "Installing PYBOARD..."

mkdir -p "$APP_DIR"
mkdir -p "$APP_DIR/templates"
mkdir -p "$APP_DIR/static"
mkdir -p "$BIN_DIR"
mkdir -p "$SERVICE_DIR"
mkdir -p "$CONFIG_DIR"
mkdir -p "$DESKTOP_DIR"
mkdir -p "$APP_DIR/soundboards"

# Desktop application

install -m 644 \
    "$SOURCE_DIR/soundboard.py" \
    "$APP_DIR/soundboard.py"

# Web UI

install -m 644 \
    "$SOURCE_DIR/web_ui.py" \
    "$APP_DIR/web_ui.py"

install -m 644 \
    "$SOURCE_DIR/templates/index.html" \
    "$APP_DIR/templates/index.html"

install -m 644 \
    "$SOURCE_DIR/static/style.css" \
    "$APP_DIR/static/style.css"

install -m 644 \
    "$SOURCE_DIR/static/app.js" \
    "$APP_DIR/static/app.js"

# Virtual microphone

install -m 755 \
    "$SOURCE_DIR/virtual-mic.sh" \
    "$BIN_DIR/pyboard-virtual-mic"

install -m 644 \
    "$SOURCE_DIR/soundboard-virtual-mic.service" \
    "$SERVICE_DIR/soundboard-virtual-mic.service"

# Desktop launcher

cat > "$BIN_DIR/pyboard" <<EOF
#!/usr/bin/env bash
exec python3 "$APP_DIR/soundboard.py" "\$@"
EOF

chmod +x "$BIN_DIR/pyboard"

# Web launcher

cat > "$BIN_DIR/pyboard-web" <<EOF
#!/usr/bin/env bash
exec python3 "$APP_DIR/web_ui.py" "\$@"
EOF

chmod +x "$BIN_DIR/pyboard-web"

# Application menu entry

cat > "$DESKTOP_DIR/pyboard.desktop" <<EOF
[Desktop Entry]
Name=PYBOARD
Comment=Linux Soundboard - Made with Cozy
Exec=$BIN_DIR/pyboard
Terminal=false
Type=Application
Categories=AudioVideo;Audio;
EOF

# Make local binaries accessible in this shell

case ":$PATH:" in
    *":$BIN_DIR:"*) ;;
    *)
        echo ""
        echo "NOTE: Add $BIN_DIR to your PATH if commands are not found."
        ;;
esac

# Reload systemd

systemctl --user daemon-reload

echo ""
echo "======================================"
echo "       PYBOARD INSTALLED!"
echo "======================================"
echo ""

read -r -p "Would you like to use the PYBOARD Web UI? (y/n): " WEB_CHOICE

if [[ "$WEB_CHOICE" =~ ^[Yy]$ ]]; then

    echo ""
    echo "Starting PYBOARD Web UI..."

    # Start only if the configured local endpoint is not responding.
    if curl -fsS --max-time 2 \
        http://127.0.0.1:5000/ >/dev/null 2>&1; then

        echo "A service is already responding on port 5000."
        echo "Open http://127.0.0.1:5000 in your browser."

    else

        nohup "$BIN_DIR/pyboard-web" --open \
            > "$CONFIG_DIR/web-ui.log" 2>&1 \
            </dev/null &

        echo "Web UI launched in the background."
        echo "Address: http://127.0.0.1:5000"

    fi

else

    echo ""
    echo "Web UI installation skipped at launch."
    echo "You can start it anytime with:"
    echo "pyboard-web --open"

fi

echo ""
echo "======================================"
echo "Launch desktop version:"
echo "pyboard"
echo ""
echo "Launch browser version:"
echo "pyboard-web --open"
echo ""
echo "Web UI address:"
echo "http://127.0.0.1:5000"
echo "======================================"
echo ""
echo "Made with ❤️ by Cozy"
