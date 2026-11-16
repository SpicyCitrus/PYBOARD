import sys
import re
import html
import shutil
import subprocess
import tkinter as tk
import urllib.request
import urllib.parse
from tkinter import ttk, messagebox
from pathlib import Path

BASE = Path(__file__).resolve().parent
SOUNDS = BASE / "soundboards"

CONFIG = Path.home() / ".config" / "pyboard"
MIC_CONFIG = CONFIG / "virtual-mic.conf"

SERVICE = "soundboard-virtual-mic.service"

MIC_NAME = "PYBOARD_Mic"
SINK_NAME = "PYBOARD_Sink"

SOUNDS.mkdir(parents=True, exist_ok=True)

BG = "#151722"
PANEL = "#202437"
CARD = "#292e43"
ACCENT = "#7567ef"
GREEN = "#279d75"
RED = "#c34c5d"
WHITE = "#ffffff"
MUTED = "#aab0c5"


def command(args, timeout=15):
    try:
        return subprocess.run(
            args,
            capture_output=True,
            text=True,
            timeout=timeout
        )
    except (OSError, subprocess.TimeoutExpired):
        return None


def player():
    for name in ("mpv", "ffplay", "cvlc"):
        if shutil.which(name):
            return name
    return None


def clean_name(name):
    name = re.sub(r"[^\w -]", "", name)
    name = re.sub(r"\s+", "_", name.strip())
    return name[:90] or "sound"


def virtual_mic_running():
    if not shutil.which("pactl"):
        return False

    result = command(["pactl", "list", "short", "sources"])

    if not result or result.returncode != 0:
        return False

    return any(
        line.split()[1] == MIC_NAME
        for line in result.stdout.splitlines()
        if len(line.split()) >= 2
    )


def download_sound(url):
    parsed = urllib.parse.urlparse(url)

    if parsed.scheme not in ("http", "https"):
        raise ValueError("Invalid URL.")

    if parsed.hostname not in (
        "myinstants.com",
        "www.myinstants.com"
    ):
        raise ValueError("Please use a Myinstants sound page URL.")

    request = urllib.request.Request(
        url,
        headers={"User-Agent": "Mozilla/5.0"}
    )

    with urllib.request.urlopen(request, timeout=30) as response:
        page = response.read().decode("utf-8", errors="replace")

    page = html.unescape(page)

    matches = re.findall(
        r"""(?:src|href)\s*=\s*["']([^"']+\.mp3(?:\?[^"']*)?)["']""",
        page,
        re.IGNORECASE
    )

    if not matches:
        matches = re.findall(
            r"""["']([^"']*?/media/sounds/[^"']+\.mp3(?:\?[^"']*)?)["']""",
            page,
            re.IGNORECASE
        )

    if not matches:
        raise ValueError("Could not find an MP3 on this page.")

    audio_url = urllib.parse.urljoin(url, matches[0])
    audio = urllib.parse.urlparse(audio_url)

    if audio.hostname not in (
        "myinstants.com",
        "www.myinstants.com"
    ):
        raise ValueError("Unexpected audio download host.")

    filename = clean_name(Path(audio.path).stem)
    destination = SOUNDS / f"{filename}.mp3"

    index = 1

    while destination.exists():
        destination = SOUNDS / f"{filename}_{index}.mp3"
        index += 1

    request = urllib.request.Request(
        audio_url,
        headers={"User-Agent": "Mozilla/5.0"}
    )

    with urllib.request.urlopen(request, timeout=60) as response:
        data = response.read(30 * 1024 * 1024 + 1)

    if not data or len(data) > 30 * 1024 * 1024:
        raise ValueError("Invalid or oversized audio file.")

    if not (
        data.startswith(b"ID3")
        or data.startswith(b"\xff\xfb")
        or data.startswith(b"\xff\xf3")
        or data.startswith(b"\xff\xf2")
    ):
        raise ValueError("The downloaded file does not appear to be an MP3.")

    destination.write_bytes(data)

    return destination


def downloader():
    print("=" * 45)
    print("             PYBOARD")
    print("       Made with ❤️ by Cozy")
    print("=" * 45)
    print()
    print("Paste a Myinstants sound link:")

    url = input("> ").strip()

    try:
        print("\nDownloading...")
        result = download_sound(url)
        print(f"\nDownloaded successfully: {result.name}")

    except Exception as error:
        print(f"\nDownload failed: {error}")

    input("\nPress Enter to close...")


class Pyboard:

    def __init__(self, root):
        self.root = root

        self.root.title("PYBOARD")
        self.root.geometry("820x590")
        self.root.minsize(600, 440)
        self.root.configure(bg=BG)

        self.process = None

        self.style = ttk.Style()
        self.style.theme_use("clam")

        self.style.configure(
            "TCombobox",
            fieldbackground=CARD,
            background=CARD,
            foreground=WHITE,
            arrowcolor=WHITE
        )

        self.build()
        self.refresh()

        self.root.protocol("WM_DELETE_WINDOW", self.close)

    def button(self, parent, text, callback, color=ACCENT):
        return tk.Button(
            parent,
            text=text,
            command=callback,
            bg=color,
            fg=WHITE,
            activebackground=color,
            activeforeground=WHITE,
            relief="flat",
            borderwidth=0,
            cursor="hand2",
            padx=15,
            pady=9,
            font=("Arial", 10, "bold")
        )

    def build(self):
        header = tk.Frame(self.root, bg=PANEL, height=105)
        header.pack(fill="x")
        header.pack_propagate(False)

        branding = tk.Frame(header, bg=PANEL)
        branding.pack(side="left", padx=24, pady=18)

        tk.Label(
            branding,
            text="PYBOARD",
            font=("Arial", 27, "bold"),
            fg=WHITE,
            bg=PANEL
        ).pack(anchor="w")

        tk.Label(
            branding,
            text="Made with ❤️ by Cozy",
            font=("Arial", 9),
            fg=MUTED,
            bg=PANEL
        ).pack(anchor="w")

        self.button(
            header,
            "⚙ Settings",
            self.settings,
            CARD
        ).pack(side="right", padx=20)

        navigation = tk.Frame(self.root, bg=BG)
        navigation.pack(fill="x", padx=22, pady=18)

        self.button(
            navigation,
            "♫ Soundboards",
            self.refresh
        ).pack(side="left")

        self.button(
            navigation,
            "+ Download More",
            self.open_downloader,
            GREEN
        ).pack(side="right")

        self.container = tk.Frame(self.root, bg=BG)
        self.container.pack(
            fill="both",
            expand=True,
            padx=22
        )

        self.status = tk.Label(
            self.root,
            text="Ready",
            bg=PANEL,
            fg=MUTED,
            anchor="w",
            padx=15,
            pady=11
        )

        self.status.pack(side="bottom", fill="x")

    def refresh(self):
        for widget in self.container.winfo_children():
            widget.destroy()

        files = sorted(
            SOUNDS.glob("*.mp3"),
            key=lambda item: item.name.lower()
        )

        if not files:
            tk.Label(
                self.container,
                text="♫\n\nNo sounds yet!\n\nUse Download More to get started.",
                font=("Arial", 15),
                fg=MUTED,
                bg=BG,
                justify="center"
            ).pack(expand=True)

            self.status.config(text="0 sounds available")
            return

        canvas = tk.Canvas(
            self.container,
            bg=BG,
            highlightthickness=0
        )

        scrollbar = ttk.Scrollbar(
            self.container,
            orient="vertical",
            command=canvas.yview
        )

        inner = tk.Frame(canvas, bg=BG)

        canvas_window = canvas.create_window(
            (0, 0),
            window=inner,
            anchor="nw"
        )

        inner.bind(
            "<Configure>",
            lambda event: canvas.configure(
                scrollregion=canvas.bbox("all")
            )
        )

        canvas.bind(
            "<Configure>",
            lambda event: canvas.itemconfigure(
                canvas_window,
                width=event.width
            )
        )

        canvas.configure(yscrollcommand=scrollbar.set)

        canvas.pack(side="left", fill="both", expand=True)
        scrollbar.pack(side="right", fill="y")

        for sound in files:
            self.sound_row(inner, sound)

        self.status.config(text=f"{len(files)} sounds available")

    def sound_row(self, parent, sound):
        row = tk.Frame(parent, bg=CARD, padx=12, pady=10)
        row.pack(fill="x", pady=5)

        tk.Label(
            row,
            text="♫",
            font=("Arial", 17),
            fg=ACCENT,
            bg=CARD
        ).pack(side="left", padx=(0, 12))

        tk.Label(
            row,
            text=sound.stem.replace("_", " "),
            font=("Arial", 11, "bold"),
            fg=WHITE,
            bg=CARD,
            anchor="w"
        ).pack(side="left", fill="x", expand=True)

        self.button(
            row,
            "▶ Play",
            lambda: self.play(sound)
        ).pack(side="left", padx=3)

        self.button(
            row,
            "■",
            self.stop,
            "#515873"
        ).pack(side="left", padx=3)

        self.button(
            row,
            "Delete",
            lambda: self.delete(sound),
            RED
        ).pack(side="left", padx=3)

    def play(self, sound):
        selected_player = player()

        if not selected_player:
            messagebox.showerror(
                "Missing player",
                "Install mpv, ffmpeg, or VLC."
            )
            return

        self.stop()

        if selected_player == "mpv":
            args = [
                "mpv",
                "--no-terminal",
                "--force-window=no"
            ]

            if virtual_mic_running():
                args.append(f"--audio-device=pulse/{SINK_NAME}")

            args.append(str(sound))

        elif selected_player == "ffplay":
            args = [
                "ffplay",
                "-nodisp",
                "-autoexit",
                "-loglevel",
                "error"
            ]

            if virtual_mic_running():
                args.extend([
                    "-f",
                    "pulse",
                    "-i",
                    SINK_NAME
                ])

            args.append(str(sound))

        else:
            args = [
                "cvlc",
                "--play-and-exit"
            ]

            if virtual_mic_running():
                args.extend([
                    "--aout=pulse",
                    "--pulse-audio-device",
                    SINK_NAME
                ])

            args.append(str(sound))

        try:
            self.process = subprocess.Popen(
                args,
                stdout=subprocess.DEVNULL,
                stderr=subprocess.DEVNULL
            )

            self.status.config(text=f"Playing: {sound.stem}")

        except OSError as error:
            messagebox.showerror("Playback error", str(error))

    def stop(self):
        if self.process and self.process.poll() is None:
            self.process.terminate()

        self.process = None
        self.status.config(text="Playback stopped")

    def delete(self, sound):
        if not messagebox.askyesno(
            "Delete sound",
            f"Are you sure you want to delete {sound.name}?"
        ):
            return

        self.stop()

        try:
            sound.unlink()
            self.refresh()

        except OSError as error:
            messagebox.showerror("Delete error", str(error))

    def open_downloader(self):
        python = sys.executable
        script = str(Path(__file__).resolve())

        terminals = [
            ("kitty", [python, script, "--download"]),
            ("alacritty", ["-e", python, script, "--download"]),
            ("konsole", ["-e", python, script, "--download"]),
            (
                "xfce4-terminal",
                ["-e", f'"{python}" "{script}" --download']
            ),
            ("gnome-terminal", ["--", python, script, "--download"]),
            ("foot", ["-e", python, script, "--download"]),
            ("xterm", ["-e", python, script, "--download"]),
            ("x-terminal-emulator", ["-e", python, script, "--download"])
        ]

        for terminal, args in terminals:
            executable = shutil.which(terminal)

            if executable:
                try:
                    subprocess.Popen([executable] + args)
                    self.status.config(text="Downloader opened")
                    return

                except OSError:
                    pass

        messagebox.showerror(
            "Terminal not found",
            "Install a terminal emulator such as Kitty or Konsole."
        )

    def settings(self):
        window = tk.Toplevel(self.root)

        window.title("PYBOARD Settings")
        window.geometry("510x390")
        window.configure(bg=BG)
        window.transient(self.root)
        window.grab_set()

        tk.Label(
            window,
            text="AUDIO SETTINGS",
            font=("Arial", 19, "bold"),
            fg=WHITE,
            bg=BG
        ).pack(pady=(24, 12))

        running = virtual_mic_running()

        status_text = (
            "Virtual microphone is RUNNING"
            if running
            else "Virtual microphone is STOPPED"
        )

        status_color = GREEN if running else RED

        status_label = tk.Label(
            window,
            text=status_text,
            font=("Arial", 11, "bold"),
            fg=status_color,
            bg=BG
        )

        status_label.pack(pady=10)

        tk.Label(
            window,
            text=f"Microphone: {MIC_NAME}\nAudio output: {SINK_NAME}",
            fg=MUTED,
            bg=BG,
            justify="center"
        ).pack(pady=10)

        def enable():
            result = command([
                "systemctl",
                "--user",
                "enable",
                "--now",
                SERVICE
            ], timeout=30)

            if not result or result.returncode != 0:
                messagebox.showerror(
                    "Setup failed",
                    result.stderr if result else "Could not run systemctl."
                )
                return

            status_label.config(
                text="Virtual microphone is RUNNING",
                fg=GREEN
            )

            messagebox.showinfo(
                "PYBOARD",
                f"Virtual microphone enabled!\n\n"
                f"Select {MIC_NAME} in Discord, OBS, or your game."
            )

        def disable():
            result = command([
                "systemctl",
                "--user",
                "disable",
                "--now",
                SERVICE
            ], timeout=30)

            if not result or result.returncode != 0:
                messagebox.showerror(
                    "Error",
                    result.stderr if result else "Could not run systemctl."
                )
                return

            status_label.config(
                text="Virtual microphone is STOPPED",
                fg=RED
            )

            messagebox.showinfo(
                "PYBOARD",
                "Virtual microphone disabled."
            )

        self.button(
            window,
            "Enable Virtual Microphone",
            enable,
            GREEN
        ).pack(pady=(25, 8))

        self.button(
            window,
            "Disable Virtual Microphone",
            disable,
            RED
        ).pack(pady=5)

        tk.Label(
            window,
            text="Your virtual microphone can start automatically at login.\n"
                 "Your existing audio devices will remain installed.",
            fg=MUTED,
            bg=BG,
            justify="center"
        ).pack(pady=18)

    def close(self):
        self.stop()
        self.root.destroy()


if __name__ == "__main__":
    if "--download" in sys.argv:
        downloader()
    else:
        root = tk.Tk()
        app = Pyboard(root)
        root.mainloop()
