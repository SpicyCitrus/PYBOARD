#!/usr/bin/env bash
set -Eeuo pipefail

CONFIG_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/pyboard"
CONFIG_FILE="$CONFIG_DIR/virtual-mic.conf"
STATE_DIR="${XDG_RUNTIME_DIR:-/tmp}/pyboard-$UID"
STATE_FILE="$STATE_DIR/virtual-mic.state"

MIC_NAME="PYBOARD_Mic"
SINK_NAME="PYBOARD_Sink"
SOUNDBOARD_SINK="PYBOARD_Soundboard"

mkdir -p "$CONFIG_DIR" "$STATE_DIR"

PHYSICAL_SOURCE=""
OUTPUT_SINK=""

if [[ -f "$CONFIG_FILE" ]]; then
    source "$CONFIG_FILE"
fi

require_audio() {
    if ! command -v pactl >/dev/null 2>&1; then
        echo "ERROR: pactl is not installed."
        exit 1
    fi

    if ! pactl info >/dev/null 2>&1; then
        echo "ERROR: No PulseAudio-compatible audio server running."
        exit 1
    fi
}

module_exists() {
    pactl list short sources |
        awk '{print $2}' |
        grep -Fxq "$MIC_NAME"
}

load_module() {
    local name="$1"
    shift

    local id
    id=$(pactl load-module "$@") || {
        echo "ERROR: Could not load $name."
        stop_mic
        exit 1
    }

    printf '%s|%s\n' "$id" "$name" >> "$STATE_FILE"
}

start_mic() {
    require_audio

    if module_exists; then
        echo "PYBOARD virtual microphone is already running."
        return
    fi

    if [[ -f "$STATE_FILE" ]]; then
        stop_mic
    fi

    PHYSICAL_SOURCE="${PHYSICAL_SOURCE:-$(pactl get-default-source)}"
    OUTPUT_SINK="${OUTPUT_SINK:-$(pactl get-default-sink)}"

    if [[ -z "$PHYSICAL_SOURCE" || -z "$OUTPUT_SINK" ]]; then
        echo "ERROR: Could not detect your microphone or speakers."
        exit 1
    fi

    echo "Creating PYBOARD audio mixer..."
    echo "Microphone: $PHYSICAL_SOURCE"
    echo "Speakers: $OUTPUT_SINK"

    : > "$STATE_FILE"

    load_module "combined-sink" \
        module-null-sink \
        sink_name="$SINK_NAME" \
        sink_properties=device.description=PYBOARD_Mixed_Audio

    load_module "soundboard-sink" \
        module-null-sink \
        sink_name="$SOUNDBOARD_SINK" \
        sink_properties=device.description=PYBOARD_Soundboard

    load_module "physical-microphone-loopback" \
        module-loopback \
        source="$PHYSICAL_SOURCE" \
        sink="$SINK_NAME" \
        latency_msec=20

    load_module "soundboard-microphone-loopback" \
        module-loopback \
        source="$SOUNDBOARD_SINK.monitor" \
        sink="$SINK_NAME" \
        latency_msec=20

    load_module "soundboard-speaker-loopback" \
        module-loopback \
        source="$SOUNDBOARD_SINK.monitor" \
        sink="$OUTPUT_SINK" \
        latency_msec=20

    load_module "combined-microphone" \
        module-remap-source \
        master="$SINK_NAME.monitor" \
        source_name="$MIC_NAME" \
        source_properties=device.description=PYBOARD_Microphone

    echo ""
    echo "PYBOARD virtual microphone is ready!"
    echo ""
    echo "Select this microphone in your applications:"
    echo "  $MIC_NAME"
    echo ""
    echo "Play soundboard audio through:"
    echo "  $SOUNDBOARD_SINK"
    echo ""
    echo "Your physical microphone remains available."
    echo "Soundboard audio is also sent to your speakers."
}

stop_mic() {
    require_audio

    if [[ ! -f "$STATE_FILE" ]]; then
        echo "No PYBOARD audio mixer state found."
        return
    fi

    echo "Stopping PYBOARD audio mixer..."

    local temp
    temp=$(mktemp)

    tac "$STATE_FILE" > "$temp"

    while IFS='|' read -r id expected; do
        [[ "$id" =~ ^[0-9]+$ ]] || continue

        local current
        current=$(pactl list short modules |
            awk -v id="$id" '$1 == id {print $0}')

        if [[ -n "$current" && "$current" == *"$expected"* ]]; then
            pactl unload-module "$id" || true
        fi
    done < "$temp"

    rm -f "$temp" "$STATE_FILE"

    echo "PYBOARD audio mixer stopped."
    echo "Existing audio devices were not removed."
}

status_mic() {
    require_audio

    echo "PYBOARD Audio Mixer"
    echo "==================="

    if module_exists; then
        echo "Status: RUNNING"
    else
        echo "Status: STOPPED"
    fi

    echo ""
    echo "Virtual microphone:"
    pactl list short sources | grep -F "$MIC_NAME" || true

    echo ""
    echo "Soundboard output:"
    pactl list short sinks | grep -F "$SOUNDBOARD_SINK" || true
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
    *)
        echo "Usage: $0 {start|stop|restart|status}"
        exit 1
        ;;
esac
