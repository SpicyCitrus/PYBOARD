#!/usr/bin/env python3

import json
import shutil
import secrets
import threading
import webbrowser
import argparse

from pathlib import Path
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

BASE = Path(__file__).resolve().parent
SOUNDS = BASE / "soundboards"
STATIC = BASE / "static"
TEMPLATES = BASE / "templates"

CONFIG = Path.home() / ".config" / "soundboard"
MIC_CONFIG = CONFIG / "virtual-mic.env"

HOST = "127.0.0.1"
PORT = 5000

TOKEN = secrets.token_urlsafe(32)

SOUNDS.mkdir(exist_ok=True)

process = None
process_lock = threading.RLock()


def get_player():
    for name in ("mpv", "ffplay", "cvlc"):
        if shutil.which(name):
            return name

    return None


def stop_sound():
    global process

    with process_lock:
        if process and process.poll() is None:
            process.terminate()

            try:
                process.wait(timeout=2)
            except Exception:
                process.kill()

        process = None


def play_sound(filename):
    global process

    if not isinstance(filename, str) or Path(filename).name != filename:
        raise ValueError("Invalid filename.")

    sound = SOUNDS / filename

    if sound.suffix.lower() != ".mp3" or not sound.is_file():
        raise ValueError("Sound not found.")

    selected = get_player()

    if not selected:
        raise RuntimeError("Install mpv, ffplay, or VLC.")

    with process_lock:
        stop_sound()

        if selected == "mpv":
            args = [
                "mpv",
                "--no-terminal",
                "--force-window=no"
            ]

            if MIC_CONFIG.exists():
                args.append("--audio-device=pulse/SoundboardSink")

            args.append(str(sound))

        elif selected == "ffplay":
            args = [
                "ffplay",
                "-nodisp",
                "-autoexit",
                "-loglevel",
                "error",
                str(sound)
            ]

        else:
            args = [
                "cvlc",
                "--play-and-exit",
                str(sound)
            ]

        process = __import__("subprocess").Popen(
            args,
            stdout=__import__("subprocess").DEVNULL,
            stderr=__import__("subprocess").DEVNULL
        )


def get_sounds():
    return [
        {
            "file": sound.name,
            "name": sound.stem.replace("_", " ")
        }
        for sound in sorted(
            SOUNDS.glob("*.mp3"),
            key=lambda item: item.name.lower()
        )
        if sound.is_file()
    ]


class Handler(BaseHTTPRequestHandler):

    def log_message(self, format, *args):
        pass

    def send_data(self, data, content_type, status=200):
        self.send_response(status)
        self.send_header("Content-Type", content_type)
        self.send_header("Cache-Control", "no-store")
        self.send_header("X-Content-Type-Options", "nosniff")
        self.send_header("Content-Length", str(len(data)))
        self.end_headers()
        self.wfile.write(data)

    def send_json(self, data, status=200):
        self.send_data(
            json.dumps(data).encode("utf-8"),
            "application/json",
            status
        )

    def do_GET(self):

        if self.path == "/":
            try:
                page = (TEMPLATES / "index.html").read_text(
                    encoding="utf-8"
                )

                page = page.replace("__TOKEN__", TOKEN)

                self.send_data(
                    page.encode("utf-8"),
                    "text/html; charset=utf-8"
                )

            except OSError:
                self.send_error(500, "Web UI files are missing")

        elif self.path == "/api/sounds":
            self.send_json(get_sounds())

        elif self.path in ("/style.css", "/app.js"):
            filename = self.path.lstrip("/")
            content_type = (
                "text/css; charset=utf-8"
                if filename == "style.css"
                else "application/javascript; charset=utf-8"
            )

            try:
                data = (STATIC / filename).read_bytes()
                self.send_data(data, content_type)

            except OSError:
                self.send_error(404)

        else:
            self.send_error(404)

    def do_POST(self):

        if self.client_address[0] not in ("127.0.0.1", "::1"):
            self.send_json({"error": "Local access only"}, 403)
            return

        if self.headers.get("X-PYBOARD-TOKEN") != TOKEN:
            self.send_json({"error": "Unauthorized"}, 403)
            return

        origin = self.headers.get("Origin")

        if origin and origin != f"http://{HOST}:{PORT}":
            self.send_json({"error": "Invalid origin"}, 403)
            return

        try:
            length = int(self.headers.get("Content-Length", "0"))

            if length <= 0 or length > 4096:
                raise ValueError("Invalid request size.")

            data = json.loads(self.rfile.read(length))

            if self.path == "/api/play":
                play_sound(data.get("file"))
                self.send_json({"success": True})

            elif self.path == "/api/stop":
                stop_sound()
                self.send_json({"success": True})

            elif self.path == "/api/delete":
                filename = data.get("file")

                if not isinstance(filename, str):
                    raise ValueError("Invalid filename.")

                if Path(filename).name != filename:
                    raise ValueError("Invalid filename.")

                sound = SOUNDS / filename

                if sound.suffix.lower() != ".mp3" or not sound.is_file():
                    raise ValueError("Sound not found.")

                stop_sound()
                sound.unlink()

                self.send_json({"success": True})

            else:
                self.send_json({"error": "Unknown endpoint"}, 404)

        except Exception as error:
            self.send_json({"error": str(error)}, 400)


def main():

    parser = argparse.ArgumentParser()
    parser.add_argument("--open", action="store_true")
    args = parser.parse_args()

    server = ThreadingHTTPServer(
        (HOST, PORT),
        Handler
    )

    server.daemon_threads = True

    print("======================================")
    print("          PYBOARD WEB UI")
    print("======================================")
    print()
    print(f"Running at http://{HOST}:{PORT}")
    print("Press Ctrl+C to stop.")

    if args.open:
        threading.Timer(
            1,
            lambda: webbrowser.open(
                f"http://{HOST}:{PORT}"
            )
        ).start()

    try:
        server.serve_forever()

    except KeyboardInterrupt:
        pass

    finally:
        stop_sound()
        server.server_close()


if __name__ == "__main__":
    main()
