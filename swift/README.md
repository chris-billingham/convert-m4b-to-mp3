# M4B → MP3 Chapter Splitter (Swift)

A native macOS GUI app that converts `.m4b` (and `.m4a`) audiobook files into chapter-split `.mp3` files. Built with SwiftUI and Swift Package Manager — no third-party dependencies.

## Prerequisites

1. **Xcode 15+** — install from the Mac App Store, or install just the command-line tools:

   ```bash
   xcode-select --install
   ```

2. **ffmpeg + ffprobe** — install with:

   ```bash
   brew install ffmpeg
   ```

## Building and Running

### Option A — Xcode (recommended)

1. Open the package in Xcode by double-clicking `Package.swift`, or from the terminal:

   ```bash
   cd swift
   open Package.swift
   ```

2. Select the **M4BtoMP3** scheme and press **Cmd+R** to build and run.

> **Note:** In Xcode's build settings, ensure **App Sandbox** is set to **No** (it should be by default for a Swift Package target). Sandboxing prevents the app from spawning ffmpeg as a child process.

### Option B — Command line (app bundle)

SwiftUI apps require a proper `.app` bundle to get a window server connection — running the raw binary directly from the terminal produces no window. Use the provided build script, which compiles the binary and packages it correctly:

```bash
cd swift
./build.sh
open M4BtoMP3.app
```

## Features

| Feature | Details |
|---|---|
| **Chapter splitting** | Reads embedded chapter metadata via `ffprobe` and splits accordingly. Falls back to a single file if no chapters are found. |
| **Bitrate** | 64k – 320k CBR (default: 128k), or VBR quality levels q0, q2, q4, q6, q9 |
| **Sample rate** | 22050 / 44100 / 48000 Hz (default: 44100) |
| **Channels** | Mono or Stereo (default: Stereo) |
| **File prefix** | Customisable output filename prefix (defaults to the input filename). Non-alphanumeric characters are replaced with `_`. |
| **Live log** | Scrollable monospace log with auto-scroll |
| **Progress bar** | Visual chapter-by-chapter progress |
| **Cancel** | Abort mid-conversion at any time |
| **Open Folder** | Button appears after conversion completes to open the output directory in Finder |
| **Persistent settings** | Bitrate, sample rate, channels, and rate mode are saved between sessions via `UserDefaults` |
| **Native file dialogs** | Uses `NSOpenPanel` for macOS-native file and folder pickers |

## Output

Files are written as:

```
<prefix> - 001 - <Chapter Title>.mp3
<prefix> - 002 - <Chapter Title>.mp3
...
```

Metadata from the source file (artist, album, etc.) is passed through to each MP3 via ID3v2 tags.

## Project Structure

```
swift/
├── Package.swift
├── Info.plist              # App bundle metadata (required for window server)
├── build.sh                # Compiles and packages into M4BtoMP3.app
├── icon_generator.swift    # Generates icon_1024.png (run once to regenerate)
├── AppIcon.icns            # App icon (pre-built — used by build.sh)
├── README.md
└── Sources/
    └── M4BtoMP3/
        ├── M4BtoMP3App.swift   # App entry point (@main), About panel
        ├── ContentView.swift   # SwiftUI UI
        └── Converter.swift     # ffprobe/ffmpeg logic, ObservableObject state
```

## Regenerating the Icon

The icon is pre-built as `AppIcon.icns`. To regenerate it from source:

```bash
cd swift
swift icon_generator.swift          # produces icon_1024.png
mkdir -p AppIcon.iconset
sips -z 16 16     icon_1024.png --out AppIcon.iconset/icon_16x16.png
sips -z 32 32     icon_1024.png --out AppIcon.iconset/icon_16x16@2x.png
sips -z 32 32     icon_1024.png --out AppIcon.iconset/icon_32x32.png
sips -z 64 64     icon_1024.png --out AppIcon.iconset/icon_32x32@2x.png
sips -z 128 128   icon_1024.png --out AppIcon.iconset/icon_128x128.png
sips -z 256 256   icon_1024.png --out AppIcon.iconset/icon_128x128@2x.png
sips -z 256 256   icon_1024.png --out AppIcon.iconset/icon_256x256.png
sips -z 512 512   icon_1024.png --out AppIcon.iconset/icon_256x256@2x.png
sips -z 512 512   icon_1024.png --out AppIcon.iconset/icon_512x512.png
cp icon_1024.png AppIcon.iconset/icon_512x512@2x.png
iconutil -c icns AppIcon.iconset -o AppIcon.icns
```

## Requirements

- macOS 14 (Sonoma) or later
- Xcode 15+ / Swift 5.9+
- ffmpeg (runtime dependency, not a Swift package dependency)
