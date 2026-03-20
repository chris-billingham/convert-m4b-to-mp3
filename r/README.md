# M4B → MP3 Chapter Splitter (R)

A Shiny web app that converts `.m4b` (and `.m4a`) audiobook files into chapter-split `.mp3` files. The UI runs in your browser; the app itself runs locally — no data leaves your machine.

Conversion runs in a background R process via `callr`, keeping the UI responsive. Chapter data is processed using tidyverse packages (`purrr`, `dplyr`, `stringr`).

## Prerequisites

1. **R 4.1+** — install from [cran.r-project.org](https://cran.r-project.org)

2. **ffmpeg + ffprobe** — install with:

   ```bash
   brew install ffmpeg
   ```

3. **R packages** — install from an R session:

   ```r
   install.packages(c(
     "shiny", "shinyFiles", "shinyjs", "callr",  # app infrastructure
     "jsonlite", "purrr", "dplyr", "stringr"      # data processing (tidyverse)
   ))
   ```

   Or install the full tidyverse meta-package, which covers the data packages:

   ```r
   install.packages(c("tidyverse", "shiny", "shinyFiles", "shinyjs", "callr"))
   ```

## Running

From the repo root:

```bash
Rscript -e "shiny::runApp('r')"
```

Or from within R:

```r
shiny::runApp("r")
```

The app will open automatically in your default browser.

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
| **Persistent settings** | Bitrate, sample rate, channels, and rate mode are saved between sessions (`~/.config/m4b_to_mp3/r_settings.json`) |

## Output

Files are written as:

```
<prefix> - 001 - <Chapter Title>.mp3
<prefix> - 002 - <Chapter Title>.mp3
...
```

Metadata from the source file (artist, album, etc.) is passed through to each MP3 via ID3v2 tags.

## How it works

| Concern | Approach |
|---|---|
| UI | Shiny (`fluidPage`, `wellPanel`, `reactiveValues`) |
| File picking | `shinyFiles` — native filesystem browser, no file upload |
| Background work | `callr::r_bg()` — conversion runs in a separate R process so the UI stays responsive |
| IPC | Log lines and progress written to temp files; Shiny polls every 500 ms via `reactiveTimer` |
| Cancellation | `bg_process$kill()` terminates the R subprocess and any running ffmpeg child process |
| JSON parsing | `jsonlite::fromJSON()` for ffprobe chapter metadata |
| Chapter data | `purrr::map()` + `dplyr::bind_rows()` + `dplyr::mutate()` to build and transform the chapter table |
| Filename sanitisation | `stringr::str_replace_all()` |
| Settings persistence | `jsonlite::write_json()` / `read_json()` |

## Dependencies

| Package | Purpose |
|---|---|
| `shiny` | Web UI framework |
| `shinyFiles` | Native file and directory picker dialogs |
| `shinyjs` | Enable/disable UI elements (Cancel, Open Folder, Bitrate dropdown) |
| `callr` | Run conversion in a non-blocking background R process |
| `jsonlite` | Parse ffprobe JSON output; persist settings |
| `purrr` | Functional iteration over chapter list (`map`, `walk`) |
| `dplyr` | Chapter data transformation (`bind_rows`, `mutate`, `coalesce`) |
| `stringr` | Filename sanitisation (`str_replace_all`) |
