#!/usr/bin/env python3
"""
M4B to MP3 Chapter Splitter
A simple Mac GUI app to convert M4B audiobooks to chapter-split MP3 files.
Requires: ffmpeg (brew install ffmpeg) and Python 3.
"""

import json
import os
import subprocess
import threading
import tkinter as tk
from tkinter import filedialog, messagebox, scrolledtext, ttk


class M4BtoMP3App:
    def __init__(self, root):
        self.root = root
        self.root.title("M4B → MP3 Chapter Splitter")
        self.root.minsize(640, 620)
        self.root.resizable(True, True)

        self.converting = False
        self.process = None

        # ── Styling ──
        style = ttk.Style()
        style.configure("TLabel", padding=(4, 2))
        style.configure("Header.TLabel", font=("Helvetica", 13, "bold"))
        style.configure("Convert.TButton", font=("Helvetica", 13, "bold"))

        pad = {"padx": 10, "pady": 4}
        main = ttk.Frame(root, padding=12)
        main.pack(fill=tk.BOTH, expand=True)

        # ── Input file ──
        ttk.Label(main, text="Input / Output", style="Header.TLabel").pack(anchor="w", **pad)

        row_in = ttk.Frame(main)
        row_in.pack(fill=tk.X, **pad)
        ttk.Label(row_in, text="M4B File:").pack(side=tk.LEFT)
        self.input_var = tk.StringVar()
        ttk.Entry(row_in, textvariable=self.input_var).pack(side=tk.LEFT, fill=tk.X, expand=True, padx=(4, 4))
        ttk.Button(row_in, text="Browse…", command=self.browse_input).pack(side=tk.LEFT)

        # ── Output directory ──
        row_out = ttk.Frame(main)
        row_out.pack(fill=tk.X, **pad)
        ttk.Label(row_out, text="Output Dir:").pack(side=tk.LEFT)
        self.output_var = tk.StringVar()
        ttk.Entry(row_out, textvariable=self.output_var).pack(side=tk.LEFT, fill=tk.X, expand=True, padx=(4, 4))
        ttk.Button(row_out, text="Browse…", command=self.browse_output).pack(side=tk.LEFT)

        ttk.Separator(main, orient="horizontal").pack(fill=tk.X, pady=8)

        # ── MP3 Settings ──
        ttk.Label(main, text="MP3 Settings", style="Header.TLabel").pack(anchor="w", **pad)

        settings = ttk.Frame(main)
        settings.pack(fill=tk.X, **pad)
        settings.columnconfigure(1, weight=1)
        settings.columnconfigure(3, weight=1)

        # Bitrate
        ttk.Label(settings, text="Bitrate:").grid(row=0, column=0, sticky="w", padx=(0, 4))
        self.bitrate_var = tk.StringVar(value="128k")
        self.bitrate_combo = ttk.Combobox(
            settings, textvariable=self.bitrate_var, width=10,
            values=["64k", "96k", "128k", "160k", "192k", "224k", "256k", "320k"],
            state="readonly",
        )
        self.bitrate_combo.grid(row=0, column=1, sticky="w")

        # Sample rate
        ttk.Label(settings, text="Sample Rate:").grid(row=0, column=2, sticky="w", padx=(16, 4))
        self.samplerate_var = tk.StringVar(value="44100")
        sr_combo = ttk.Combobox(
            settings, textvariable=self.samplerate_var, width=10,
            values=["22050", "44100", "48000"],
            state="readonly",
        )
        sr_combo.grid(row=0, column=3, sticky="w")

        # Channels
        ttk.Label(settings, text="Channels:").grid(row=1, column=0, sticky="w", padx=(0, 4), pady=(6, 0))
        self.channels_var = tk.StringVar(value="Stereo")
        ch_combo = ttk.Combobox(
            settings, textvariable=self.channels_var, width=10,
            values=["Mono", "Stereo"],
            state="readonly",
        )
        ch_combo.grid(row=1, column=1, sticky="w", pady=(6, 0))

        # VBR / CBR
        ttk.Label(settings, text="Rate Mode:").grid(row=1, column=2, sticky="w", padx=(16, 4), pady=(6, 0))
        self.ratemode_var = tk.StringVar(value="CBR")
        rm_combo = ttk.Combobox(
            settings, textvariable=self.ratemode_var, width=10,
            values=["CBR", "VBR (q0 best)", "VBR (q2)", "VBR (q4)", "VBR (q6)", "VBR (q9 smallest)"],
            state="readonly",
        )
        rm_combo.grid(row=1, column=3, sticky="w", pady=(6, 0))
        self.ratemode_var.trace_add("write", self._on_ratemode_change)

        # Filename prefix
        ttk.Label(settings, text="File Prefix:").grid(row=2, column=0, sticky="w", padx=(0, 4), pady=(6, 0))
        self.prefix_var = tk.StringVar(value="")
        ttk.Entry(settings, textvariable=self.prefix_var, width=30).grid(
            row=2, column=1, columnspan=3, sticky="w", pady=(6, 0)
        )
        ttk.Label(settings, text="(blank = use book name)", font=("Helvetica", 10)).grid(
            row=3, column=1, columnspan=3, sticky="w"
        )

        ttk.Separator(main, orient="horizontal").pack(fill=tk.X, pady=8)

        # ── Buttons ──
        btn_row = ttk.Frame(main)
        btn_row.pack(fill=tk.X, **pad)
        self.convert_btn = ttk.Button(btn_row, text="▶  Convert", style="Convert.TButton", command=self.start_convert)
        self.convert_btn.pack(side=tk.LEFT)
        self.cancel_btn = ttk.Button(btn_row, text="Cancel", command=self.cancel_convert, state=tk.DISABLED)
        self.cancel_btn.pack(side=tk.LEFT, padx=(8, 0))
        self.open_btn = ttk.Button(btn_row, text="Open Folder", command=self.open_output, state=tk.DISABLED)
        self.open_btn.pack(side=tk.LEFT, padx=(8, 0))
        self.progress = ttk.Progressbar(btn_row, mode="determinate", length=200)
        self.progress.pack(side=tk.RIGHT)

        # ── Log ──
        ttk.Label(main, text="Log", style="Header.TLabel").pack(anchor="w", **pad)
        self.log = scrolledtext.ScrolledText(main, height=14, state=tk.DISABLED, font=("Menlo", 11), wrap=tk.WORD)
        self.log.pack(fill=tk.BOTH, expand=True, **pad)

        self.load_settings()
        self.root.protocol("WM_DELETE_WINDOW", self._on_close)

    # ── helpers ──

    def log_msg(self, msg):
        self.log.configure(state=tk.NORMAL)
        self.log.insert(tk.END, msg + "\n")
        self.log.see(tk.END)
        self.log.configure(state=tk.DISABLED)

    def browse_input(self):
        path = filedialog.askopenfilename(
            title="Select M4B file",
            filetypes=[("M4B Audiobooks", "*.m4b"), ("M4A Audio", "*.m4a"), ("All files", "*.*")],
        )
        if path:
            self.input_var.set(path)
            if not self.output_var.get():
                self.output_var.set(os.path.dirname(path))
            if not self.prefix_var.get():
                self.prefix_var.set(os.path.splitext(os.path.basename(path))[0])

    def browse_output(self):
        path = filedialog.askdirectory(title="Select output folder")
        if path:
            self.output_var.set(path)

    def _on_ratemode_change(self, *_):
        if self.ratemode_var.get() == "CBR":
            self.bitrate_combo.configure(state="readonly")
        else:
            self.bitrate_combo.configure(state="disabled")

    def open_output(self):
        path = self.output_var.get().strip()
        if path:
            subprocess.run(["open", path])

    _settings_path = os.path.expanduser("~/.config/m4b_to_mp3/settings.json")

    def load_settings(self):
        try:
            with open(self._settings_path) as f:
                s = json.load(f)
            self.bitrate_var.set(s.get("bitrate", "128k"))
            self.samplerate_var.set(s.get("samplerate", "44100"))
            self.channels_var.set(s.get("channels", "Stereo"))
            self.ratemode_var.set(s.get("ratemode", "CBR"))
        except (FileNotFoundError, json.JSONDecodeError, KeyError):
            pass

    def save_settings(self):
        os.makedirs(os.path.dirname(self._settings_path), exist_ok=True)
        with open(self._settings_path, "w") as f:
            json.dump({
                "bitrate": self.bitrate_var.get(),
                "samplerate": self.samplerate_var.get(),
                "channels": self.channels_var.get(),
                "ratemode": self.ratemode_var.get(),
            }, f)

    def _on_close(self):
        self.save_settings()
        self.root.destroy()

    def set_ui_state(self, converting):
        self.converting = converting
        state = tk.DISABLED if converting else tk.NORMAL
        self.convert_btn.configure(state=state)
        self.cancel_btn.configure(state=tk.NORMAL if converting else tk.DISABLED)
        if converting:
            self.open_btn.configure(state=tk.DISABLED)

    # ── ffmpeg helpers ──

    @staticmethod
    def find_ffmpeg():
        """Return (ffmpeg_path, ffprobe_path) or raise."""
        for d in ["/opt/homebrew/bin", "/usr/local/bin", "/usr/bin"]:
            ff = os.path.join(d, "ffmpeg")
            fp = os.path.join(d, "ffprobe")
            if os.path.isfile(ff) and os.path.isfile(fp):
                return ff, fp
        # fallback: rely on PATH
        return "ffmpeg", "ffprobe"

    def get_chapters(self, ffprobe, input_path):
        cmd = [
            ffprobe, "-v", "quiet", "-print_format", "json",
            "-show_chapters", "-show_format", input_path,
        ]
        result = subprocess.run(cmd, capture_output=True, text=True)
        if result.returncode != 0:
            raise RuntimeError(f"ffprobe failed:\n{result.stderr.strip()}")
        try:
            data = json.loads(result.stdout)
        except json.JSONDecodeError as e:
            raise RuntimeError(f"ffprobe returned unexpected output: {e}")
        chapters = data.get("chapters", [])
        return chapters, data.get("format", {})

    def build_ffmpeg_args(self, ffmpeg, input_path, output_path, start, end):
        """Build the ffmpeg command for one chapter."""
        args = [ffmpeg, "-y", "-ss", str(start), "-t", str(end - start), "-i", input_path]

        # Codec
        args += ["-codec:a", "libmp3lame"]

        # Rate mode
        rm = self.ratemode_var.get()
        if rm == "CBR":
            args += ["-b:a", self.bitrate_var.get()]
        else:
            q_map = {"VBR (q0 best)": "0", "VBR (q2)": "2", "VBR (q4)": "4", "VBR (q6)": "6", "VBR (q9 smallest)": "9"}
            args += ["-q:a", q_map.get(rm, "4")]

        # Sample rate
        args += ["-ar", self.samplerate_var.get()]

        # Channels
        args += ["-ac", "1" if self.channels_var.get() == "Mono" else "2"]

        # ID3 / metadata passthrough
        args += ["-map_metadata", "0", "-id3v2_version", "3"]

        args += [output_path]
        return args

    # ── conversion ──

    def start_convert(self):
        input_path = self.input_var.get().strip()
        output_dir = self.output_var.get().strip()
        if not input_path or not os.path.isfile(input_path):
            messagebox.showerror("Error", "Please select a valid M4B file.")
            return
        if not output_dir:
            messagebox.showerror("Error", "Please select an output directory.")
            return
        os.makedirs(output_dir, exist_ok=True)
        self.set_ui_state(True)
        self.progress["value"] = 0
        threading.Thread(target=self.run_convert, args=(input_path, output_dir), daemon=True).start()

    def cancel_convert(self):
        self.converting = False
        if self.process:
            try:
                self.process.kill()
            except Exception:
                pass
        self.root.after(0, lambda: self.log_msg("⛔ Cancelled by user."))
        self.root.after(0, lambda: self.set_ui_state(False))

    def run_convert(self, input_path, output_dir):
        def log(msg):
            self.root.after(0, lambda m=msg: self.log_msg(m))

        def set_progress(v):
            self.root.after(0, lambda: self.progress.configure(value=v))

        try:
            ffmpeg, ffprobe = self.find_ffmpeg()
            log(f"Using ffmpeg: {ffmpeg}")
            log(f"Reading chapters from:\n  {input_path}")

            chapters, fmt = self.get_chapters(ffprobe, input_path)
            if not chapters:
                log("⚠️  No chapter metadata found — converting as a single file.")
                chapters = [{
                    "start_time": "0",
                    "end_time": fmt.get("duration", "0"),
                    "tags": {"title": "Full"},
                }]

            total = len(chapters)
            log(f"Found {total} chapter(s). Starting conversion…\n")

            prefix = self.prefix_var.get().strip() or os.path.splitext(os.path.basename(input_path))[0]
            # sanitise prefix for filesystem
            prefix = "".join(c if c.isalnum() or c in " _-" else "_" for c in prefix)

            for i, ch in enumerate(chapters):
                if not self.converting:
                    return

                start = float(ch["start_time"])
                end = float(ch["end_time"])
                title = ch.get("tags", {}).get("title", f"Chapter {i+1}")
                safe_title = "".join(c if c.isalnum() or c in " _-" else "_" for c in title)
                out_name = f"{prefix} - {i+1:03d} - {safe_title}.mp3"
                out_path = os.path.join(output_dir, out_name)

                log(f"[{i+1}/{total}] {title}  ({end - start:.1f}s)")
                cmd = self.build_ffmpeg_args(ffmpeg, input_path, out_path, start, end)

                self.process = subprocess.Popen(cmd, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
                _, stderr = self.process.communicate()
                rc = self.process.returncode
                self.process = None

                if rc != 0:
                    log(f"   ⚠️  ffmpeg returned {rc}")
                    err_tail = stderr.decode(errors="replace").strip().split("\n")[-3:]
                    for line in err_tail:
                        log(f"      {line}")
                else:
                    size_kb = os.path.getsize(out_path) / 1024
                    log(f"   ✅  {size_kb:.0f} KB → {out_name}")

                set_progress((i + 1) / total * 100)

            log(f"\n🎉 Done! {total} file(s) written to:\n  {output_dir}")
            self.root.after(0, lambda: self.open_btn.configure(state=tk.NORMAL))

        except FileNotFoundError:
            log("❌ ffmpeg/ffprobe not found. Install with:  brew install ffmpeg")
        except Exception as e:
            log(f"❌ Error: {e}")
        finally:
            self.root.after(0, lambda: self.set_ui_state(False))


if __name__ == "__main__":
    root = tk.Tk()
    # macOS dark-mode-friendly defaults
    try:
        root.tk.call("tk::mac::useCompatibilityMetrics", False)
    except tk.TclError:
        pass
    app = M4BtoMP3App(root)
    root.mainloop()
