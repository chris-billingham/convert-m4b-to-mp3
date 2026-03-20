# M4B → MP3 Chapter Splitter

Converts `.m4b` (and `.m4a`) audiobook files into chapter-split `.mp3` files with configurable encoding settings. Available as two independent implementations — pick whichever suits you.

![Platform](https://img.shields.io/badge/Platform-macOS-lightgrey)

| Implementation | Stack | File |
|---|---|---|
| **Python** | tkinter (stdlib GUI) | [`m4b_to_mp3.py`](./m4b_to_mp3.py) |
| **Rust** | egui / eframe | [`rust/`](./rust/) |

Both implementations are feature-equivalent and produce identical output.

---

## Prerequisites

**Both implementations require ffmpeg:**

```bash
brew install ffmpeg
```

The Python version additionally requires Python 3 (ships with macOS). The Rust version requires the Rust toolchain — install via [rustup](https://rustup.rs):

```bash
curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh
```

---

## Quick Start

**Python:**

```bash
python3 m4b_to_mp3.py
```

Or with [uv](https://docs.astral.sh/uv/) (no virtual environment setup needed):

```bash
uv run m4b_to_mp3.py
```

**Rust:**

```bash
cd rust
cargo run --release
```

---

## Features

| Feature | Details |
|---|---|
| **Chapter splitting** | Reads embedded chapter metadata via `ffprobe` and splits accordingly. Falls back to a single file if no chapters are found. |
| **Bitrate** | 64k – 320k CBR (default: 128k), or VBR quality levels q0, q2, q4, q6, q9 |
| **Sample rate** | 22050 / 44100 / 48000 Hz (default: 44100) |
| **Channels** | Mono or Stereo (default: Stereo) |
| **File prefix** | Customisable output filename prefix (defaults to the input filename). Non-alphanumeric characters are replaced with `_`. |
| **Live log** | Scrollable log panel showing progress, file sizes, and any ffmpeg errors |
| **Progress bar** | Visual chapter-by-chapter progress |
| **Cancel** | Abort mid-conversion at any time |
| **Open Folder** | Button appears after conversion completes to open the output directory in Finder |
| **Persistent settings** | Bitrate, sample rate, channels, and rate mode are saved between sessions |

---

## Output

Files are written as:

```
<prefix> - 001 - <Chapter Title>.mp3
<prefix> - 002 - <Chapter Title>.mp3
...
```

Metadata from the source file (artist, album, etc.) is passed through to each MP3 via ID3v2 tags.

---

## Choosing an Implementation

**Python** — good if you want zero build step and already have Python 3. Launch directly from the terminal with no dependencies beyond ffmpeg.

**Rust** — good if you want a standalone binary you can copy anywhere. Faster startup, no Python runtime required. Build once with `cargo build --release` and distribute the binary.
