#!/usr/bin/env bash

set -euo pipefail

CONFIG="$HOME/.config/soundboard/virtual-mic.env"
RUNTIME="$XDG_RUNTIME_DIR/pyboard-virtual-mic"
ACTION="${1:-start}"

if [[ ! -f "$CONFIG" ]]; then
    echo "Microphone configuration not found."
    exit 1
fi

source "$CONFIG"

if [[ -z "${MIC_SOURCE:-}" ]]; then
    echo "No microphone selected."
    exit 1
fi

stop_modules() {
    if [[ -f "$RUNTIME" ]]; then
        while read -r MODULE_ID; do
            if [[ "$MODULE_ID" =~ ^[0-9]+$ ]]; then
                pactl unload-module "$MODULE_ID" || true
            fi
        done < "$RUNTIME"

        rm -f "$RUNTIME"
    fi
}

case "$ACTION" in
    start)
        for attempt in {1..20}; do
            if pactl info >/dev/null 2>&1; then
                break
            fi
            sleep 0.5
        done

        pactl info >/dev/null

        if ! pactl list short sources | awk '{print $2}' | grep -Fxq "$MIC_SOURCE"; then
            echo "Selected microphone is unavailable: $MIC_SOURCE"
            exit 1
        fi

        if pactl list short sources | awk '{print $2}' | grep -Fxq "SoundboardMic"; then
            echo "Virtual microphone already exists."
            exit 0
        fi

        stop_modules
        : > "$RUNTIME"

        if pactl list short sinks | awk '{print $2}' | grep -Fxq "SoundboardSink"; then
            echo "SoundboardSink already exists."
            exit 1
        fi

        SINK_ID=$(pactl load-module module-null-sink \
            sink_name=SoundboardSink \
            sink_properties=device.description=SoundboardSink)

        echo "$SINK_ID" >> "$RUNTIME"

        SOURCE_ID=$(pactl load-module module-combine-source \
            source_name=SoundboardMic \
            source_properties=device.description=SoundboardMic \
            "slaves=${MIC_SOURCE},SoundboardSink.monitor")

        echo "$SOURCE_ID" >> "$RUNTIME"

        echo "PYBOARD virtual microphone started."
        ;;

    stop)
        stop_modules
        echo "PYBOARD virtual microphone stopped."
        ;;

    *)
        echo "Usage: virtual-mic.sh start|stop"
        exit 1
        ;;
esac
