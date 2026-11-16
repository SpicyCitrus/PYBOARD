#!/usr/bin/env bash
set -Eeuo pipefail

APP_NAME="PYBOARD"
CONFIG_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/pyboard"
CONFIG_FILE="$CONFIG_DIR/virtual-mic.conf"
STATE_DIR="${XDG_RUNTIME_DIR:-/tmp}/pyboard-$UID"
STATE_FILE="$STATE_DIR/virtual-mic.state"

mkdir -p "$CONFIG_DIR" "$STATE_DIR"

# Default configuration
MIC_NAME="PYBOARD_Mic"
SINK_NAME="PYBOARD_Sink"
SET_DEFAULT="false"

# Load optional user configuration
if [[ -f "$CONFIG_FILE" ]]; then
    # shellcheck disable=SC1090
    source "$CONFIG_FILE"
fi

require_pactl() {
    if ! command -v pactl >/dev/null 2>&1; then
        echo "ERROR: pactl is not installed."
        echo "Install pulseaudio-utils or the equivalent for your distribution."
        exit 1
    fi

    if ! pactl info >/dev/null 2>&1; then
        echo "ERROR: No running PulseAudio-compatible audio server."
        exit 1
    fi
}

module_exists() {
    pactl list short sources | awk '{print $2}' |
        grep -Fxq "${MIC_NAME}"
}

start_mic() {
    require_pactl

    if module_exists; then
        echo "PYBOARD virtual microphone is already running."
        return
    fi

    echo "Creating PYBOARD virtual microphone..."

    local sink_module source_module

    sink_module=$(pactl load-module module-null-sink \
        sink_name="$SINK_NAME" \
        sink_properties="device.description=PYBOARD_Virtual_Mic") || {
        echo "ERROR: Could not create virtual sink."
        exit 1
    }

    if ! source_module=$(pactl load-module module-remap-source \
        master="$SINK_NAME.monitor" \
        source_name="$MIC_NAME" \
        source_properties="device.description=PYBOARD_Microphone"); then
        pactl unload-module "$sink_module" || true
        echo "ERROR: Could not create virtual microphone."
        exit 1
    fi

    printf '%s\n%s\n' "$sink_module" "$source_module" > "$STATE_FILE"

    if [[ "$SET_DEFAULT" == "true" ]]; then
        pactl set-default-source "$MIC_NAME"
    fi

    echo
    echo "PYBOARD virtual microphone created successfully!"
    echo "Microphone: $MIC_NAME"
    echo "Audio output: $SINK_NAME"
    echo
    echo "Select $MIC_NAME in Discord, OBS, or your other applications."
}

stop_mic() {
    require_pactl

    if [[ ! -f "$STATE_FILE" ]]; then
        echo "No PYBOARD-managed microphone instance found."
        return
    fi

    mapfile -t MODULES < "$STATE_FILE"

    # Unload ONLY the modules created by this script.
    for module in "${MODULES[@]}"; do
        if [[ "$module" =~ ^[0-9]+$ ]]; then
            pactl unload-module "$module" 2>/dev/null || true
        fi
    done

    rm -f "$STATE_FILE"

    echo "PYBOARD virtual microphone stopped."
    echo "Your existing audio drivers and devices were not removed."
}

status_mic() {
    require_pactl

    echo "=== PYBOARD Virtual Microphone ==="

    if module_exists; then
        echo "Status: RUNNING"
        echo "Device: $MIC_NAME"
    else
        echo "Status: STOPPED"
    fi

    echo
    echo "Available recording devices:"
    pactl list short sources
}

configure_mic() {
    mkdir -p "$CONFIG_DIR"

    cat > "$CONFIG_FILE" <<EOF
# PYBOARD virtual microphone configuration

MIC_NAME="$MIC_NAME"
SINK_NAME="$SINK_NAME"

# Set to true to make PYBOARD the default microphone.
# This changes the default source, not your installed drivers.
SET_DEFAULT="$SET_DEFAULT"
EOF

    echo "Configuration saved to:"
    echo "$CONFIG_FILE"
}

case "${1:-status}" in
    start)
        start_mic
        ;;
    stop)
        stop_mic
        ;;
    restart)
        stop_mic
        start_mic
        ;;
    status)
        status_mic
        ;;
    configure)
        configure_mic
        ;;
    *)
        echo "Usage: $0 {start|stop|restart|status|configure}"
        exit 1
        ;;
esac
