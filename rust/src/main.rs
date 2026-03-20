use eframe::egui;
use rfd::FileDialog;
use serde::Deserialize;
use std::path::PathBuf;
use std::process::{Command, Stdio};
use std::sync::{Arc, Mutex};
use std::thread;

// ─── ffprobe JSON structures ────────────────────────────────────────────────

#[derive(Debug, Deserialize)]
struct ProbeOutput {
    #[serde(default)]
    chapters: Vec<ProbeChapter>,
    #[serde(default)]
    format: Option<ProbeFormat>,
}

#[derive(Debug, Deserialize)]
struct ProbeChapter {
    start_time: String,
    end_time: String,
    #[serde(default)]
    tags: Option<ChapterTags>,
}

#[derive(Debug, Deserialize)]
struct ChapterTags {
    title: Option<String>,
}

#[derive(Debug, Deserialize)]
struct ProbeFormat {
    duration: Option<String>,
}

// ─── Shared conversion state ────────────────────────────────────────────────

#[derive(Clone)]
struct ConversionState {
    inner: Arc<Mutex<ConversionInner>>,
}

struct ConversionInner {
    running: bool,
    cancelled: bool,
    conversion_done: bool,
    log: Vec<String>,
    progress: f32, // 0.0 – 1.0
}

impl ConversionState {
    fn new() -> Self {
        Self {
            inner: Arc::new(Mutex::new(ConversionInner {
                running: false,
                cancelled: false,
                conversion_done: false,
                log: Vec::new(),
                progress: 0.0,
            })),
        }
    }

    fn log(&self, msg: &str) {
        if let Ok(mut s) = self.inner.lock() {
            s.log.push(msg.to_string());
        }
    }

    fn set_progress(&self, v: f32) {
        if let Ok(mut s) = self.inner.lock() {
            s.progress = v;
        }
    }

    fn is_cancelled(&self) -> bool {
        self.inner.lock().map(|s| s.cancelled).unwrap_or(true)
    }

    fn set_running(&self, v: bool) {
        if let Ok(mut s) = self.inner.lock() {
            s.running = v;
            if v {
                s.cancelled = false;
            }
        }
    }

    fn cancel(&self) {
        if let Ok(mut s) = self.inner.lock() {
            s.cancelled = true;
        }
    }

    fn set_conversion_done(&self, v: bool) {
        if let Ok(mut s) = self.inner.lock() {
            s.conversion_done = v;
        }
    }

    fn is_conversion_done(&self) -> bool {
        self.inner.lock().map(|s| s.conversion_done).unwrap_or(false)
    }
}

// ─── Settings enums ─────────────────────────────────────────────────────────

const BITRATES: &[&str] = &["64k", "96k", "128k", "160k", "192k", "224k", "256k", "320k"];
const SAMPLE_RATES: &[&str] = &["22050", "44100", "48000"];
const CHANNELS: &[&str] = &["Mono", "Stereo"];
const RATE_MODES: &[&str] = &[
    "CBR",
    "VBR q0 (best)",
    "VBR q2",
    "VBR q4",
    "VBR q6",
    "VBR q9 (smallest)",
];

// ─── App ────────────────────────────────────────────────────────────────────

struct App {
    input_path: String,
    output_dir: String,
    prefix: String,

    bitrate_idx: usize,       // into BITRATES
    samplerate_idx: usize,    // into SAMPLE_RATES
    channels_idx: usize,      // into CHANNELS
    ratemode_idx: usize,      // into RATE_MODES

    state: ConversionState,
    log_auto_scroll: bool,
}

impl App {
    fn new(cc: &eframe::CreationContext<'_>) -> Self {
        let load = |key: &str, default: usize| -> usize {
            cc.storage
                .and_then(|s| s.get_string(key))
                .and_then(|v| v.parse().ok())
                .unwrap_or(default)
        };
        Self {
            input_path: String::new(),
            output_dir: String::new(),
            prefix: String::new(),
            bitrate_idx: load("bitrate_idx", 2),       // default 128k
            samplerate_idx: load("samplerate_idx", 1), // default 44100
            channels_idx: load("channels_idx", 1),     // default Stereo
            ratemode_idx: load("ratemode_idx", 0),     // default CBR
            state: ConversionState::new(),
            log_auto_scroll: true,
        }
    }
}

impl eframe::App for App {
    fn save(&mut self, storage: &mut dyn eframe::Storage) {
        storage.set_string("bitrate_idx", self.bitrate_idx.to_string());
        storage.set_string("samplerate_idx", self.samplerate_idx.to_string());
        storage.set_string("channels_idx", self.channels_idx.to_string());
        storage.set_string("ratemode_idx", self.ratemode_idx.to_string());
    }

    fn update(&mut self, ctx: &egui::Context, _frame: &mut eframe::Frame) {
        // Repaint continuously while converting so log + progress update
        if self.state.inner.lock().map(|s| s.running).unwrap_or(false) {
            ctx.request_repaint();
        }

        egui::CentralPanel::default().show(ctx, |ui| {
            ui.heading("M4B → MP3 Chapter Splitter");
            ui.add_space(6.0);

            // ── Input / Output ──────────────────────────────────────────
            ui.group(|ui| {
                ui.label(egui::RichText::new("Input / Output").strong());
                ui.add_space(2.0);

                ui.horizontal(|ui| {
                    ui.label("M4B File:");
                    ui.add(
                        egui::TextEdit::singleline(&mut self.input_path)
                            .desired_width(f32::INFINITY),
                    );
                    if ui.button("Browse…").clicked() {
                        if let Some(p) = FileDialog::new()
                            .add_filter("M4B Audiobook", &["m4b", "m4a"])
                            .pick_file()
                        {
                            self.input_path = p.display().to_string();
                            if self.output_dir.is_empty() {
                                if let Some(parent) = p.parent() {
                                    self.output_dir = parent.display().to_string();
                                }
                            }
                            if self.prefix.is_empty() {
                                if let Some(stem) = p.file_stem() {
                                    self.prefix = stem.to_string_lossy().into_owned();
                                }
                            }
                        }
                    }
                });

                ui.horizontal(|ui| {
                    ui.label("Output Dir:");
                    ui.add(
                        egui::TextEdit::singleline(&mut self.output_dir)
                            .desired_width(f32::INFINITY),
                    );
                    if ui.button("Browse…").clicked() {
                        if let Some(p) = FileDialog::new().pick_folder() {
                            self.output_dir = p.display().to_string();
                        }
                    }
                });
            });

            ui.add_space(4.0);

            // ── Settings ────────────────────────────────────────────────
            ui.group(|ui| {
                ui.label(egui::RichText::new("MP3 Settings").strong());
                ui.add_space(2.0);

                egui::Grid::new("settings_grid")
                    .num_columns(4)
                    .spacing([16.0, 6.0])
                    .show(ui, |ui| {
                        // Row 1
                        let is_cbr = self.ratemode_idx == 0;
                        ui.label("Bitrate:");
                        ui.add_enabled_ui(is_cbr, |ui| {
                            egui::ComboBox::from_id_salt("bitrate")
                                .selected_text(BITRATES[self.bitrate_idx])
                                .show_ui(ui, |ui| {
                                    for (i, b) in BITRATES.iter().enumerate() {
                                        ui.selectable_value(&mut self.bitrate_idx, i, *b);
                                    }
                                });
                        });

                        ui.label("Sample Rate:");
                        egui::ComboBox::from_id_salt("samplerate")
                            .selected_text(SAMPLE_RATES[self.samplerate_idx])
                            .show_ui(ui, |ui| {
                                for (i, s) in SAMPLE_RATES.iter().enumerate() {
                                    ui.selectable_value(&mut self.samplerate_idx, i, *s);
                                }
                            });
                        ui.end_row();

                        // Row 2
                        ui.label("Channels:");
                        egui::ComboBox::from_id_salt("channels")
                            .selected_text(CHANNELS[self.channels_idx])
                            .show_ui(ui, |ui| {
                                for (i, c) in CHANNELS.iter().enumerate() {
                                    ui.selectable_value(&mut self.channels_idx, i, *c);
                                }
                            });

                        ui.label("Rate Mode:");
                        egui::ComboBox::from_id_salt("ratemode")
                            .selected_text(RATE_MODES[self.ratemode_idx])
                            .show_ui(ui, |ui| {
                                for (i, r) in RATE_MODES.iter().enumerate() {
                                    ui.selectable_value(&mut self.ratemode_idx, i, *r);
                                }
                            });
                        ui.end_row();

                        // Row 3
                        ui.label("File Prefix:");
                        ui.add(
                            egui::TextEdit::singleline(&mut self.prefix)
                                .desired_width(200.0)
                                .hint_text("(blank = use book name)"),
                        );
                        ui.end_row();
                    });
            });

            ui.add_space(6.0);

            // ── Buttons + progress ──────────────────────────────────────
            let is_running = self.state.inner.lock().map(|s| s.running).unwrap_or(false);

            let conversion_done = self.state.is_conversion_done();

            ui.horizontal(|ui| {
                ui.add_enabled_ui(!is_running, |ui| {
                    if ui
                        .button(egui::RichText::new("▶  Convert").strong().size(15.0))
                        .clicked()
                    {
                        self.start_conversion();
                    }
                });

                ui.add_enabled_ui(is_running, |ui| {
                    if ui.button("Cancel").clicked() {
                        self.state.cancel();
                    }
                });

                ui.add_enabled_ui(conversion_done && !is_running, |ui| {
                    if ui.button("Open Folder").clicked() {
                        let _ = std::process::Command::new("open")
                            .arg(&self.output_dir)
                            .spawn();
                    }
                });

                let progress = self
                    .state
                    .inner
                    .lock()
                    .map(|s| s.progress)
                    .unwrap_or(0.0);
                ui.add(
                    egui::ProgressBar::new(progress)
                        .show_percentage()
                        .desired_width(ui.available_width()),
                );
            });

            ui.add_space(6.0);

            // ── Log ─────────────────────────────────────────────────────
            ui.label(egui::RichText::new("Log").strong());

            let log_lines: Vec<String> = self
                .state
                .inner
                .lock()
                .map(|s| s.log.clone())
                .unwrap_or_default();

            egui::ScrollArea::vertical()
                .max_height(ui.available_height())
                .stick_to_bottom(self.log_auto_scroll)
                .show(ui, |ui| {
                    ui.add(
                        egui::TextEdit::multiline(&mut log_lines.join("\n").as_str())
                            .font(egui::TextStyle::Monospace)
                            .desired_width(f32::INFINITY)
                            .interactive(true),
                    );
                });
        });
    }
}

// ─── Conversion logic ───────────────────────────────────────────────────────

impl App {
    fn start_conversion(&mut self) {
        let input = PathBuf::from(&self.input_path);
        let output_dir = PathBuf::from(&self.output_dir);

        if !input.is_file() {
            self.state.log("❌ Please select a valid M4B file.");
            return;
        }
        if self.output_dir.is_empty() {
            self.state.log("❌ Please select an output directory.");
            return;
        }
        let _ = std::fs::create_dir_all(&output_dir);

        // snapshot settings for the thread
        let bitrate = BITRATES[self.bitrate_idx].to_string();
        let samplerate = SAMPLE_RATES[self.samplerate_idx].to_string();
        let channels = if self.channels_idx == 0 { "1" } else { "2" }.to_string();
        let ratemode_idx = self.ratemode_idx;
        let prefix = if self.prefix.is_empty() {
            input
                .file_stem()
                .map(|s| s.to_string_lossy().into_owned())
                .unwrap_or_else(|| "audiobook".into())
        } else {
            self.prefix.clone()
        };

        let state = self.state.clone();
        state.set_running(true);
        state.set_conversion_done(false);
        // clear previous log
        if let Ok(mut s) = state.inner.lock() {
            s.log.clear();
            s.progress = 0.0;
        }

        thread::spawn(move || {
            run_conversion(
                &state,
                &input,
                &output_dir,
                &prefix,
                &bitrate,
                &samplerate,
                &channels,
                ratemode_idx,
            );
            state.set_running(false);
        });
    }
}

fn find_ffmpeg() -> (String, String) {
    for dir in &["/opt/homebrew/bin", "/usr/local/bin", "/usr/bin"] {
        let ff = format!("{}/ffmpeg", dir);
        let fp = format!("{}/ffprobe", dir);
        if PathBuf::from(&ff).is_file() && PathBuf::from(&fp).is_file() {
            return (ff, fp);
        }
    }
    ("ffmpeg".into(), "ffprobe".into())
}

fn sanitise(s: &str) -> String {
    s.chars()
        .map(|c| {
            if c.is_alphanumeric() || c == ' ' || c == '_' || c == '-' {
                c
            } else {
                '_'
            }
        })
        .collect()
}

fn run_conversion(
    state: &ConversionState,
    input: &PathBuf,
    output_dir: &PathBuf,
    prefix: &str,
    bitrate: &str,
    samplerate: &str,
    channels: &str,
    ratemode_idx: usize,
) {
    let (ffmpeg, ffprobe) = find_ffmpeg();
    state.log(&format!("Using ffmpeg: {}", ffmpeg));
    state.log(&format!("Reading chapters from:\n  {}", input.display()));

    // ── probe chapters ──
    let probe_out = match Command::new(&ffprobe)
        .args([
            "-v", "quiet",
            "-print_format", "json",
            "-show_chapters",
            "-show_format",
        ])
        .arg(input)
        .output()
    {
        Ok(o) => o,
        Err(e) => {
            state.log(&format!("❌ Failed to run ffprobe: {}", e));
            state.log("Install ffmpeg with:  brew install ffmpeg");
            return;
        }
    };

    if !probe_out.status.success() {
        let stderr = String::from_utf8_lossy(&probe_out.stderr);
        state.log(&format!("❌ ffprobe failed:\n{}", stderr.trim()));
        return;
    }

    let probe: ProbeOutput = match serde_json::from_slice(&probe_out.stdout) {
        Ok(p) => p,
        Err(e) => {
            state.log(&format!("❌ Failed to parse ffprobe output: {}", e));
            return;
        }
    };

    let chapters: Vec<(f64, f64, String)> = if probe.chapters.is_empty() {
        state.log("⚠️  No chapter metadata found — converting as single file.");
        let dur: f64 = probe
            .format
            .as_ref()
            .and_then(|f| f.duration.as_deref())
            .and_then(|d| d.parse().ok())
            .unwrap_or(0.0);
        vec![(0.0, dur, "Full".into())]
    } else {
        probe
            .chapters
            .iter()
            .enumerate()
            .map(|(i, ch)| {
                let start: f64 = ch.start_time.parse().unwrap_or(0.0);
                let end: f64 = ch.end_time.parse().unwrap_or(0.0);
                let title = ch
                    .tags
                    .as_ref()
                    .and_then(|t| t.title.as_deref())
                    .unwrap_or(&format!("Chapter {}", i + 1))
                    .to_string();
                (start, end, title)
            })
            .collect()
    };

    let total = chapters.len();
    state.log(&format!("Found {} chapter(s). Starting conversion…\n", total));

    let safe_prefix = sanitise(prefix);

    for (i, (start, end, title)) in chapters.iter().enumerate() {
        if state.is_cancelled() {
            state.log("⛔ Cancelled by user.");
            return;
        }

        let safe_title = sanitise(title);
        let out_name = format!("{} - {:03} - {}.mp3", safe_prefix, i + 1, safe_title);
        let out_path = output_dir.join(&out_name);

        state.log(&format!(
            "[{}/{}] {}  ({:.1}s)",
            i + 1,
            total,
            title,
            end - start
        ));

        let mut args: Vec<String> = vec![
            "-y".into(),
            "-ss".into(),
            format!("{}", start),
            "-t".into(),
            format!("{}", end - start),
            "-i".into(),
            input.display().to_string(),
            "-codec:a".into(),
            "libmp3lame".into(),
        ];

        // rate mode
        if ratemode_idx == 0 {
            // CBR
            args.extend(["-b:a".into(), bitrate.to_string()]);
        } else {
            let q = match ratemode_idx {
                1 => "0",
                2 => "2",
                3 => "4",
                4 => "6",
                5 => "9",
                _ => "4",
            };
            args.extend(["-q:a".into(), q.into()]);
        }

        args.extend(["-ar".into(), samplerate.to_string()]);
        args.extend(["-ac".into(), channels.to_string()]);
        args.extend([
            "-map_metadata".into(),
            "0".into(),
            "-id3v2_version".into(),
            "3".into(),
        ]);
        args.push(out_path.display().to_string());

        let result = Command::new(&ffmpeg)
            .args(&args)
            .stdout(Stdio::piped())
            .stderr(Stdio::piped())
            .output();

        match result {
            Ok(output) => {
                if output.status.success() {
                    let size_kb = std::fs::metadata(&out_path)
                        .map(|m| m.len() / 1024)
                        .unwrap_or(0);
                    state.log(&format!("   ✅  {} KB → {}", size_kb, out_name));
                } else {
                    state.log(&format!(
                        "   ⚠️  ffmpeg returned {}",
                        output.status.code().unwrap_or(-1)
                    ));
                    let stderr = String::from_utf8_lossy(&output.stderr);
                    for line in stderr.lines().rev().take(3).collect::<Vec<_>>().into_iter().rev() {
                        state.log(&format!("      {}", line));
                    }
                }
            }
            Err(e) => {
                state.log(&format!("   ❌  Failed to run ffmpeg: {}", e));
            }
        }

        state.set_progress((i + 1) as f32 / total as f32);
    }

    state.log(&format!(
        "\n🎉 Done! {} file(s) written to:\n  {}",
        total,
        output_dir.display()
    ));
    state.set_conversion_done(true);
}

// ─── Entry point ────────────────────────────────────────────────────────────

fn main() -> eframe::Result {
    let options = eframe::NativeOptions {
        viewport: egui::ViewportBuilder::default()
            .with_inner_size([700.0, 600.0])
            .with_min_inner_size([580.0, 480.0]),
        ..Default::default()
    };

    eframe::run_native(
        "M4B → MP3 Chapter Splitter",
        options,
        Box::new(|cc| Ok(Box::new(App::new(cc)))),
    )
}
