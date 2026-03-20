# M4B → MP3 Chapter Splitter

A lightweight Mac GUI app that converts `.m4b` audiobook files into chapter-split `.mp3` files with configurable encoding settings.

![Python](https://img.shields.io/badge/Python-3.8+-blue) ![Platform](https://img.shields.io/badge/Platform-macOS-lightgrey)

## Prerequisites

1. **Python 3** (ships with macOS or install via `brew install python`)
2. **ffmpeg + ffprobe** — install with:

   ```bash
   brew install ffmpeg
   ```

## Running

```bash
python3 m4b_to_mp3.py
```

That's it — a window will open.

## Features

| Feature | Details |
|---|---|
| **Chapter splitting** | Reads embedded chapter metadata via `ffprobe` and splits accordingly. Falls back to a single file if no chapters are found. |
| **Bitrate** | 64k – 320k CBR, or VBR quality levels q0–q9 |
| **Sample rate** | 22050 / 44100 / 48000 Hz |
| **Channels** | Mono or Stereo |
| **File prefix** | Customisable output filename prefix (defaults to the input filename) |
| **Live log** | Scrollable log panel showing progress, file sizes, and any ffmpeg errors |
| **Progress bar** | Visual chapter-by-chapter progress |
| **Cancel** | Abort mid-conversion at any time |

## Output

Files are written as:

```
<prefix> - 001 - <Chapter Title>.mp3
<prefix> - 002 - <Chapter Title>.mp3
...
```

Metadata from the source file (artist, album, etc.) is passed through to each MP3 via ID3v2 tags.
