# app.R — M4B → MP3 Chapter Splitter (R / Shiny)

library(shiny)
library(shinyFiles)
library(shinyjs)
library(jsonlite)
library(purrr)
library(stringr)
library(dplyr)
library(callr)

`%||%` <- function(x, y) if (is.null(x) || length(x) == 0) y else x

BITRATES     <- c("64k", "96k", "128k", "160k", "192k", "224k", "256k", "320k")
SAMPLE_RATES <- c("22050", "44100", "48000")
CHANNEL_OPTS <- c("Mono", "Stereo")
RATE_MODES   <- c("CBR", "VBR q0 (best)", "VBR q2", "VBR q4",
                  "VBR q6", "VBR q9 (smallest)")

SETTINGS_FILE <- path.expand("~/.config/m4b_to_mp3/r_settings.json")

# ─── Background conversion function ──────────────────────────────────────────
# Runs in a separate R process via callr::r_bg(). Must be fully self-contained:
# loads its own libraries, defines its own helpers, communicates via temp files.

run_conversion_bg <- function(input_path, output_dir, prefix,
                               bitrate, sample_rate, channels,
                               rate_mode_idx, log_file, progress_file) {
  library(jsonlite)
  library(purrr)
  library(stringr)
  library(dplyr)

  `%||%` <- function(x, y) if (is.null(x) || length(x) == 0) y else x

  write_log <- function(msg) {
    cat(msg, "\n", file = log_file, append = TRUE, sep = "")
  }

  write_progress <- function(v) {
    writeLines(as.character(v), progress_file)
  }

  sanitise <- function(s) {
    str_replace_all(s, "[^a-zA-Z0-9 _\\-]", "_")
  }

  # Locate ffmpeg / ffprobe
  ffmpeg  <- "ffmpeg"
  ffprobe <- "ffprobe"
  for (dir in c("/opt/homebrew/bin", "/usr/local/bin", "/usr/bin")) {
    ff <- file.path(dir, "ffmpeg")
    fp <- file.path(dir, "ffprobe")
    if (file.exists(ff) && file.exists(fp)) {
      ffmpeg <- ff; ffprobe <- fp; break
    }
  }

  write_log(paste0("Using ffmpeg: ", ffmpeg))
  write_log(paste0("Reading chapters from:\n  ", input_path))

  # ── ffprobe ────────────────────────────────────────────────────────────────
  probe_raw <- system2(
    ffprobe,
    args   = c("-v", "quiet", "-print_format", "json",
               "-show_chapters", "-show_format", input_path),
    stdout = TRUE,
    stderr = FALSE
  )

  if ((attr(probe_raw, "status") %||% 0L) != 0L) {
    write_log("\u274c ffprobe failed. Is the file a valid M4B/M4A?")
    write_log("   Install ffmpeg with:  brew install ffmpeg")
    return(invisible(NULL))
  }

  probe <- tryCatch(
    fromJSON(paste(probe_raw, collapse = "\n"),
             simplifyDataFrame = FALSE, simplifyVector = FALSE),
    error = function(e) {
      write_log(paste0("\u274c Failed to parse ffprobe output: ", e$message))
      NULL
    }
  )
  if (is.null(probe)) return(invisible(NULL))

  # ── Build chapter table with purrr + dplyr ─────────────────────────────────
  raw_chapters <- probe$chapters %||% list()

  if (length(raw_chapters) == 0) {
    write_log("\u26a0\ufe0f  No chapter metadata found \u2014 converting as single file.")
    dur      <- as.numeric(probe$format$duration %||% "0")
    chapters <- data.frame(start = 0, end = dur, title = "Full",
                           duration = dur, stringsAsFactors = FALSE)
  } else {
    chapters <- map(raw_chapters, function(ch) {
      list(
        start = as.numeric(ch$start_time %||% "0"),
        end   = as.numeric(ch$end_time   %||% "0"),
        title = ch$tags$title %||% NA_character_
      )
    }) |>
      bind_rows() |>
      mutate(
        title    = coalesce(title, paste0("Chapter ", row_number())),
        duration = end - start
      )
  }

  total <- nrow(chapters)
  write_log(paste0("Found ", total, " chapter(s). Starting conversion\u2026\n"))

  safe_prefix <- sanitise(prefix)
  dir.create(output_dir, showWarnings = FALSE, recursive = TRUE)

  # ── Convert each chapter ───────────────────────────────────────────────────
  walk(seq_len(total), function(i) {
    ch         <- chapters[i, ]
    safe_title <- sanitise(ch$title)
    out_name   <- sprintf("%s - %03d - %s.mp3", safe_prefix, i, safe_title)
    out_path   <- file.path(output_dir, out_name)

    write_log(sprintf("[%d/%d] %s  (%.1fs)", i, total, ch$title, ch$duration))

    # Input seeking: -ss / -t before -i for fast chapter extraction
    args <- c(
      "-y",
      "-ss", sprintf("%.6f", ch$start),
      "-t",  sprintf("%.6f", ch$duration),
      "-i",  input_path,
      "-codec:a", "libmp3lame"
    )

    if (rate_mode_idx == 1L) {
      args <- c(args, "-b:a", bitrate)
    } else {
      q_values <- c("0", "2", "4", "6", "9")
      args <- c(args, "-q:a", q_values[rate_mode_idx - 1L])
    }

    args <- c(
      args,
      "-ar", sample_rate,
      "-ac", if (channels == "Mono") "1" else "2",
      "-map_metadata", "0",
      "-id3v2_version", "3",
      out_path
    )

    stderr_tmp <- tempfile()
    rc <- system2(ffmpeg, args = args, stdout = FALSE, stderr = stderr_tmp)

    if (rc == 0L) {
      size_kb <- as.integer(file.info(out_path)$size %/% 1024)
      write_log(sprintf("   \u2705  %d KB \u2192 %s", size_kb, out_name))
    } else {
      write_log(sprintf("   \u26a0\ufe0f  ffmpeg returned %d", rc))
      err_lines <- tryCatch(tail(readLines(stderr_tmp), 3),
                            error = function(e) character(0))
      walk(err_lines, function(l) write_log(paste0("      ", l)))
    }

    write_progress(i / total)
  })

  write_log(sprintf("\n\U0001f389 Done! %d file(s) written to:\n  %s",
                    total, output_dir))
  write_progress(1.0)
}

# ─── UI ───────────────────────────────────────────────────────────────────────

ui <- fluidPage(
  title = "M4B \u2192 MP3 Chapter Splitter",
  useShinyjs(),

  tags$head(tags$style(HTML("
    body { padding-top: 20px; max-width: 860px; margin: auto; }
    .log-container {
      height: 260px; overflow-y: auto;
      background: #f5f5f5; border: 1px solid #ddd;
      border-radius: 4px; padding: 8px;
    }
    .log-container pre.shiny-text-output {
      background: transparent; border: none;
      margin: 0; padding: 0;
      font-size: 12px; white-space: pre-wrap; word-break: break-word;
    }
  "))),

  # Auto-scroll log to bottom when new lines arrive
  tags$script(HTML("
    Shiny.addCustomMessageHandler('scroll_log', function(msg) {
      var c = document.getElementById('log-container');
      if (c) c.scrollTop = c.scrollHeight;
    });
  ")),

  h3("M4B \u2192 MP3 Chapter Splitter"),
  hr(),

  # ── Input / Output ──────────────────────────────────────────────────────────
  wellPanel(
    h4("Input / Output"),
    fluidRow(
      column(9, textInput("input_path", "M4B File:", width = "100%")),
      column(3, br(),
             shinyFilesButton("browse_input", "Browse\u2026",
                              title    = "Select M4B / M4A file",
                              multiple = FALSE,
                              style    = "width:100%;"))
    ),
    fluidRow(
      column(9, textInput("output_dir", "Output Dir:", width = "100%")),
      column(3, br(),
             shinyDirButton("browse_output", "Browse\u2026",
                            title = "Select output directory",
                            style = "width:100%;"))
    )
  ),

  # ── MP3 Settings ────────────────────────────────────────────────────────────
  wellPanel(
    h4("MP3 Settings"),
    fluidRow(
      column(3, selectInput("bitrate",     "Bitrate:",
                            choices = BITRATES,     selected = "128k")),
      column(3, selectInput("sample_rate", "Sample Rate:",
                            choices = SAMPLE_RATES, selected = "44100")),
      column(3, selectInput("channels",    "Channels:",
                            choices = CHANNEL_OPTS, selected = "Stereo")),
      column(3, selectInput("rate_mode",   "Rate Mode:",
                            choices = RATE_MODES,   selected = "CBR"))
    ),
    fluidRow(
      column(6, textInput("prefix", "File Prefix:",
                          placeholder = "blank = use book name"))
    )
  ),

  # ── Buttons + progress ──────────────────────────────────────────────────────
  fluidRow(
    column(12,
           actionButton("convert",     "\u25b6  Convert",  class = "btn-primary btn-lg"),
           tags$span(style = "margin-left:6px;"),
           actionButton("cancel",      "Cancel",           class = "btn-warning"),
           tags$span(style = "margin-left:6px;"),
           actionButton("open_folder", "Open Folder",      class = "btn-default"),
           uiOutput("progress_ui")
    )
  ),

  br(),

  # ── Log ─────────────────────────────────────────────────────────────────────
  h4("Log"),
  div(id = "log-container", class = "log-container",
      verbatimTextOutput("log"))
)

# ─── Server ───────────────────────────────────────────────────────────────────

server <- function(input, output, session) {

  volumes <- c(Home = path.expand("~"), Root = "/")
  shinyFileChoose(input, "browse_input",  roots = volumes,
                  filetypes = c("m4b", "m4a"))
  shinyDirChoose(input,  "browse_output", roots = volumes)

  rv <- reactiveValues(
    state         = "idle",   # idle | running | done | cancelled
    bg_process    = NULL,
    log_file      = NULL,
    progress_file = NULL,
    progress      = 0,
    log_lines     = character(0),
    output_dir    = ""
  )

  # Initial button states
  disable("cancel")
  disable("open_folder")

  # ── Load persisted settings ───────────────────────────────────────────────
  if (file.exists(SETTINGS_FILE)) {
    s <- tryCatch(read_json(SETTINGS_FILE), error = function(e) NULL)
    if (!is.null(s)) {
      updateSelectInput(session, "bitrate",     selected = s$bitrate     %||% "128k")
      updateSelectInput(session, "sample_rate", selected = s$sample_rate %||% "44100")
      updateSelectInput(session, "channels",    selected = s$channels    %||% "Stereo")
      updateSelectInput(session, "rate_mode",   selected = s$rate_mode   %||% "CBR")
    }
  }

  # ── File pickers ──────────────────────────────────────────────────────────
  observeEvent(input$browse_input, {
    sel <- parseFilePaths(volumes, input$browse_input)
    if (nrow(sel) > 0) {
      path <- as.character(sel$datapath)
      updateTextInput(session, "input_path", value = path)
      if (nchar(trimws(input$output_dir)) == 0)
        updateTextInput(session, "output_dir", value = dirname(path))
      if (nchar(trimws(input$prefix)) == 0)
        updateTextInput(session, "prefix",
                        value = tools::file_path_sans_ext(basename(path)))
    }
  })

  observeEvent(input$browse_output, {
    path <- parseDirPath(volumes, input$browse_output)
    if (length(path) > 0)
      updateTextInput(session, "output_dir", value = as.character(path))
  })

  # ── Disable Bitrate dropdown when VBR selected ────────────────────────────
  observe({
    if (isTRUE(input$rate_mode == "CBR")) enable("bitrate") else disable("bitrate")
  })

  # ── Convert ───────────────────────────────────────────────────────────────
  observeEvent(input$convert, {
    req(rv$state != "running")

    input_path <- trimws(input$input_path)
    output_dir <- trimws(input$output_dir)

    if (!file.exists(input_path)) {
      rv$log_lines <- c(rv$log_lines, "\u274c Please select a valid M4B file.")
      return()
    }
    if (nchar(output_dir) == 0) {
      rv$log_lines <- c(rv$log_lines, "\u274c Please select an output directory.")
      return()
    }

    # Persist settings
    dir.create(dirname(SETTINGS_FILE), showWarnings = FALSE, recursive = TRUE)
    tryCatch(
      write_json(list(bitrate     = input$bitrate,
                      sample_rate = input$sample_rate,
                      channels    = input$channels,
                      rate_mode   = input$rate_mode),
                 SETTINGS_FILE, auto_unbox = TRUE),
      error = function(e) NULL
    )

    rv$log_file      <- tempfile(fileext = ".log")
    rv$progress_file <- tempfile(fileext = ".txt")
    rv$log_lines     <- character(0)
    rv$progress      <- 0
    rv$output_dir    <- output_dir
    rv$state         <- "running"

    prefix <- trimws(input$prefix)
    if (nchar(prefix) == 0)
      prefix <- tools::file_path_sans_ext(basename(input_path))

    rate_mode_idx <- which(RATE_MODES == input$rate_mode)

    rv$bg_process <- r_bg(
      func = run_conversion_bg,
      args = list(
        input_path    = input_path,
        output_dir    = output_dir,
        prefix        = prefix,
        bitrate       = input$bitrate,
        sample_rate   = input$sample_rate,
        channels      = input$channels,
        rate_mode_idx = rate_mode_idx,
        log_file      = rv$log_file,
        progress_file = rv$progress_file
      ),
      supervise = TRUE
    )

    disable("convert")
    enable("cancel")
    disable("open_folder")
  })

  # ── Cancel ────────────────────────────────────────────────────────────────
  observeEvent(input$cancel, {
    if (!is.null(rv$bg_process) && rv$bg_process$is_alive())
      rv$bg_process$kill()
    rv$state     <- "cancelled"
    rv$log_lines <- c(rv$log_lines, "\u26d4 Cancelled by user.")
    enable("convert")
    disable("cancel")
  })

  # ── Open folder ───────────────────────────────────────────────────────────
  observeEvent(input$open_folder, {
    if (nchar(rv$output_dir) > 0)
      system2("open", args = rv$output_dir)
  })

  # ── Polling — update log + progress while conversion runs ─────────────────
  timer <- reactiveTimer(500)

  observe({
    timer()
    req(rv$state == "running")

    if (!is.null(rv$log_file) && file.exists(rv$log_file)) {
      lines <- tryCatch(readLines(rv$log_file), error = function(e) character(0))
      if (!identical(lines, rv$log_lines)) {
        rv$log_lines <- lines
        session$sendCustomMessage("scroll_log", list())
      }
    }

    if (!is.null(rv$progress_file) && file.exists(rv$progress_file)) {
      p <- tryCatch(suppressWarnings(as.numeric(readLines(rv$progress_file)[1])),
                    error = function(e) NA_real_)
      if (!is.na(p)) rv$progress <- p
    }

    if (!is.null(rv$bg_process) && !rv$bg_process$is_alive()) {
      if (!is.null(rv$log_file) && file.exists(rv$log_file))
        rv$log_lines <- tryCatch(readLines(rv$log_file),
                                 error = function(e) rv$log_lines)
      rv$progress <- 1
      rv$state    <- "done"
      enable("convert")
      disable("cancel")
      enable("open_folder")
      session$sendCustomMessage("scroll_log", list())
    }
  })

  # ── Outputs ───────────────────────────────────────────────────────────────
  output$log <- renderText({
    paste(rv$log_lines, collapse = "\n")
  })

  output$progress_ui <- renderUI({
    p <- round(rv$progress * 100)
    div(
      style = "margin-top: 12px;",
      div(class = "progress", style = "margin-bottom: 0;",
          div(class = "progress-bar",
              role  = "progressbar",
              style = paste0("width:", p, "%; min-width:2em;"),
              `aria-valuenow` = p, `aria-valuemin` = 0, `aria-valuemax` = 100,
              paste0(p, "%")
          )
      )
    )
  })
}

shinyApp(ui, server)
