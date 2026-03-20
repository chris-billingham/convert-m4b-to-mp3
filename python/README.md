# M4B → MP3 Chapter Splitter

A lightweight Mac GUI app that converts `.m4b` (and `.m4a`) audiobook files into chapter-split `.mp3` files with configurable encoding settings.

![Python](https://img.shields.io/badge/Python-3.8+-blue) ![Platform](https://img.shields.io/badge/Platform-macOS-lightgrey)

## Prerequisites

1. **Python 3** (ships with macOS or install via `brew install python`)
2. **ffmpeg + ffprobe** — install with:

   ```bash
   brew install ffmpeg
   ```

## Running

**With plain Python:**

```bash
python3 m4b_to_mp3.py
```

**With [uv](https://docs.astral.sh/uv/):**

If you have `uv` installed, you can run the script directly without managing a virtual environment yourself:

```bash
uv run m4b_to_mp3.py
```

`uv` will automatically use a compatible Python version. Since the script has no third-party dependencies, no `pyproject.toml` is needed.

Either way, a window will open.

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

## Output

Files are written as:

```
<prefix> - 001 - <Chapter Title>.mp3
<prefix> - 002 - <Chapter Title>.mp3
...
```

Metadata from the source file (artist, album, etc.) is passed through to each MP3 via ID3v2 tags.
