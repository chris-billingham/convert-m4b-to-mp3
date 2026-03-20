# M4B → MP3 Chapter Splitter (Rust)

A native Mac GUI app built with Rust + [egui](https://github.com/emilk/egui) that converts `.m4b` (and `.m4a`) audiobook files into chapter-split `.mp3` files.

## Prerequisites

1. **Rust toolchain** — install via [rustup](https://rustup.rs/):
   ```bash
   curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh
   ```

2. **ffmpeg + ffprobe**:
   ```bash
   brew install ffmpeg
   ```

## Build & Run

```bash
# Debug (fast compile, slower runtime)
cargo run

# Release (slower compile, optimised binary)
cargo run --release
```

The release binary lands in `target/release/m4b2mp3` — you can copy it anywhere or drop it in `/usr/local/bin`.

## Features

| Feature | Details |
|---|---|
| **Chapter splitting** | Reads embedded chapter metadata via `ffprobe`; falls back to single-file conversion if none found |
| **Bitrate** | 64k – 320k CBR (default: 128k), or VBR quality levels q0, q2, q4, q6, q9 |
| **Sample rate** | 22050 / 44100 / 48000 Hz (default: 44100) |
| **Channels** | Mono or Stereo (default: Stereo) |
| **File prefix** | Customisable output filename prefix (defaults to the input filename). Non-alphanumeric characters are replaced with `_`. |
| **Live log** | Scrollable monospace log with auto-scroll |
| **Progress bar** | Visual chapter-by-chapter progress with percentage |
| **Cancel** | Abort mid-conversion |
| **Open Folder** | Button appears after conversion completes to open the output directory in Finder |
| **Persistent settings** | Bitrate, sample rate, channels, and rate mode are saved between sessions |
| **Native file dialogs** | Uses `rfd` for macOS-native open/save panels |

## Output

```
<prefix> - 001 - <Chapter Title>.mp3
<prefix> - 002 - <Chapter Title>.mp3
...
```

ID3v2 metadata (artist, album, etc.) is passed through from the source file.

## Project Structure

```
├── Cargo.toml
├── README.md
└── src/
    └── main.rs      # ~630 lines — GUI + conversion logic
```

## Dependencies

| Crate | Purpose |
|---|---|
| `eframe` / `egui` | Immediate-mode GUI framework |
| `rfd` | Native file dialog (open file, pick folder) |
| `serde` / `serde_json` | Deserialise ffprobe JSON output |
