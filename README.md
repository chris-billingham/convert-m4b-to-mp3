# M4B → MP3 Chapter Splitter

Converts `.m4b` (and `.m4a`) audiobook files into chapter-split `.mp3` files with configurable encoding settings. Available as four independent implementations — pick whichever suits you.

![Platform](https://img.shields.io/badge/Platform-macOS-lightgrey)

| Implementation | Stack | Location |
|---|---|---|
| **Python** | tkinter (stdlib GUI) | [`m4b_to_mp3.py`](./m4b_to_mp3.py) |
| **Rust** | egui / eframe | [`rust/`](./rust/) |
| **Swift** | SwiftUI | [`swift/`](./swift/) |
| **R** | Shiny (browser UI) | [`r/`](./r/) |

All four implementations are feature-equivalent and produce identical output.

---

## Prerequisites

**All implementations require ffmpeg:**

```bash
brew install ffmpeg
```

Additional requirements per implementation:

- **Python** — Python 3 (ships with macOS, no extra install needed)
- **Rust** — Rust toolchain via [rustup](https://rustup.rs): `curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh`
- **Swift** — Xcode 15+ (macOS 14 required at runtime)
- **R** — R 4.1+ from [cran.r-project.org](https://cran.r-project.org), plus several R packages (see [`r/README.md`](./r/README.md))

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

**Swift:**

```bash
cd swift
open Package.swift   # then Cmd+R in Xcode
```

Or from the command line:

```bash
swift run
```

**R:**

```bash
Rscript -e "shiny::runApp('r')"
```

The app opens automatically in your default browser.

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

**Rust** — good if you want a standalone binary you can copy anywhere. No runtime required. Build once with `cargo build --release` and distribute the binary.

**Swift** — the most native macOS experience. Uses SwiftUI and standard system dialogs. Best choice if you're already in the Apple ecosystem and have Xcode installed. Requires macOS 14+.

**R** — best if you already work in R or want to inspect/extend the data processing logic. Runs as a Shiny app in the browser. The only implementation that doesn't produce a native desktop window — requires R and a handful of packages to be installed first.
