#!/usr/bin/env bash
set -Eeuo pipefail

MIC_NAME="SoundboardMic"
SINK_NAME="PYBOARD_Sink"
SOUNDBOARD_SINK="SoundboardSink"

CONFIG_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/pyboard"
CONFIG_FILE="$CONFIG_DIR/virtual-mic.conf"
OLD_CONFIG="${XDG_CONFIG_HOME:-$HOME/.config}/soundboard/virtual-mic.env"

STATE_DIR="${XDG_RUNTIME_DIR:-/tmp}/pyboard-$UID"
STATE_FILE="$STATE_DIR/virtual-mic.state"

MIC_SOURCE=""
OUTPUT_SINK=""

mkdir -p "$CONFIG_DIR" "$STATE_DIR"

if [[ -f "$OLD_CONFIG" ]]; then
    source "$OLD_CONFIG"
fi

if [[ -f "$CONFIG_FILE" ]]; then
    source "$CONFIG_FILE"
fi

require_pactl() {
    command -v pactl >/dev/null 2>&1 || {
        echo "ERROR: pactl is not installed."
        exit 1
    }

    pactl info >/dev/null 2>&1 || {
        echo "ERROR: No running PulseAudio-compatible audio server."
        exit 1
    }
}

source_exists() {
    pactl list short sources | awk '{print $2}' | grep -Fxq "$1"
}

sink_exists() {
    pactl list short sinks | awk '{print $2}' | grep -Fxq "$1"
}

cleanup_modules() {
    local module

    for ((i=${#MODULES[@]}-1; i>=0; i--)); do
        module="${MODULES[$i]}"
        pactl unload-module "$module" >/dev/null 2>&1 || true
    done

    rm -f "$STATE_FILE"
}

stop_mic() {
    require_pactl

    if [[ -f "$STATE_FILE" ]]; then
        mapfile -t MODULES < "$STATE_FILE"

        for ((i=${#MODULES[@]}-1; i>=0; i--)); do
            module="${MODULES[$i]}"
            if [[ "$module" =~ ^[0-9]+$ ]]; then
                pactl unload-module "$module" >/dev/null 2>&1 || true
            fi
        done

        rm -f "$STATE_FILE"
        echo "PYBOARD virtual microphone stopped."
    else
        echo "No PYBOARD-managed microphone instance found."
    fi
}

load_module() {
    local id
    id=$(pactl load-module "$@") || return 1

    if [[ ! "$id" =~ ^[0-9]+$ ]]; then
        return 1
    fi

    MODULES+=("$id")
}

start_mic() {
    require_pactl

    if [[ -f "$STATE_FILE" ]]; then
        echo "A PYBOARD state file already exists. Stopping the old instance first."
        stop_mic
    fi

    if source_exists "$MIC_NAME" ||
       sink_exists "$SINK_NAME" ||
       sink_exists "$SOUNDBOARD_SINK"; then
        echo "ERROR: A PYBOARD audio device already exists."
        echo "Run this script with 'stop' and try again."
        exit 1
    fi

    if [[ -z "$MIC_SOURCE" ]]; then
        MIC_SOURCE=$(pactl get-default-source)
    fi

    if [[ -z "$OUTPUT_SINK" ]]; then
        OUTPUT_SINK=$(pactl get-default-sink)
    fi

    if [[ "$MIC_SOURCE" == *.monitor ]]; then
        echo "ERROR: The selected microphone is a monitor source."
        echo "Choose your physical microphone in PYBOARD settings."
        exit 1
    fi

    if ! source_exists "$MIC_SOURCE"; then
        echo "ERROR: Microphone source not found: $MIC_SOURCE"
        exit 1
    fi

    if ! sink_exists "$OUTPUT_SINK"; then
        echo "ERROR: Speaker output not found: $OUTPUT_SINK"
        exit 1
    fi

    if [[ "$OUTPUT_SINK" == "$SINK_NAME" ||
          "$OUTPUT_SINK" == "$SOUNDBOARD_SINK" ]]; then
        echo "ERROR: The speaker output cannot be a PYBOARD virtual sink."
        exit 1
    fi

    MODULES=()

    echo "Creating PYBOARD audio devices..."

    if ! load_module module-null-sink \
        sink_name="$SINK_NAME" \
        sink_properties=device.description=PYBOARD_Microphone_Mix; then
        cleanup_modules
        echo "ERROR: Could not create microphone mixer."
        exit 1
    fi

    if ! load_module module-null-sink \
        sink_name="$SOUNDBOARD_SINK" \
        sink_properties=device.description=PYBOARD_Soundboard_Output; then
        cleanup_modules
        echo "ERROR: Could not create soundboard output."
        exit 1
    fi

    if ! load_module module-loopback \
        source="$MIC_SOURCE" \
        sink="$SINK_NAME" \
        latency_msec=20; then
        cleanup_modules
        echo "ERROR: Could not connect your physical microphone."
        exit 1
    fi

    if ! load_module module-loopback \
        source="$SOUNDBOARD_SINK.monitor" \
        sink="$SINK_NAME" \
        latency_msec=20; then
        cleanup_modules
        echo "ERROR: Could not mix soundboard audio into the microphone."
        exit 1
    fi

    if ! load_module module-loopback \
        source="$SOUNDBOARD_SINK.monitor" \
        sink="$OUTPUT_SINK" \
        latency_msec=20; then
        cleanup_modules
        echo "ERROR: Could not connect soundboard audio to your speakers."
        exit 1
    fi

    if ! load_module module-remap-source \
        master="$SINK_NAME.monitor" \
        source_name="$MIC_NAME" \
        source_properties=device.description=PYBOARD_Virtual_Microphone; then
        cleanup_modules
        echo "ERROR: Could not create the virtual microphone."
        exit 1
    fi

    printf '%s\n' "${MODULES[@]}" > "$STATE_FILE"

    echo
    echo "PYBOARD virtual microphone is running."
    echo "Physical microphone: $MIC_SOURCE"
    echo "Speaker output: $OUTPUT_SINK"
    echo "Soundboard output: $SOUNDBOARD_SINK"
    echo "Virtual microphone: $MIC_NAME"
    echo
    echo "Select $MIC_NAME in Discord, OBS, or your game."
    echo "Desktop audio is not routed into the virtual microphone."
}

status_mic() {
    require_pactl

    echo "=== PYBOARD Virtual Microphone ==="

    if source_exists "$MIC_NAME"; then
        echo "Status: RUNNING"
    else
        echo "Status: STOPPED"
    fi

    echo
    echo "Recording devices:"
    pactl list short sources

    echo
    echo "Output devices:"
    pactl list short sinks
}

configure_mic() {
    mkdir -p "$CONFIG_DIR"

    cat > "$CONFIG_FILE" <<EOF
MIC_SOURCE=$(printf '%q' "$MIC_SOURCE")
OUTPUT_SINK=$(printf '%q' "$OUTPUT_SINK")
EOF

    echo "Configuration saved to $CONFIG_FILE"
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
