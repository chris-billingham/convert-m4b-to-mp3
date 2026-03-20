import Foundation

// MARK: - ffprobe JSON structures

private struct ProbeOutput: Decodable {
    var chapters: [ProbeChapter] = []
    var format: ProbeFormat?
}

private struct ProbeChapter: Decodable {
    let start_time: String
    let end_time: String
    let tags: ChapterTags?
}

private struct ChapterTags: Decodable {
    let title: String?
}

private struct ProbeFormat: Decodable {
    let duration: String?
}

// MARK: - Converter

final class Converter: ObservableObject {
    @Published var log: [String] = []
    @Published var progress: Double = 0
    @Published var isRunning = false
    @Published var conversionDone = false

    // Accessed across threads — benign races for a cancel flag and process handle
    private var cancelFlag = false
    private var currentProcess: Process?

    private let queue = DispatchQueue(label: "com.m4b2mp3.conversion", qos: .userInitiated)

    // MARK: Public API (call from main thread)

    func start(
        inputPath: String,
        outputDir: String,
        prefix: String,
        bitrateIdx: Int,
        sampleRateIdx: Int,
        channelsIdx: Int,
        rateModeIdx: Int
    ) {
        guard !isRunning else { return }
        isRunning = true
        cancelFlag = false
        conversionDone = false
        log = []
        progress = 0

        let resolvedPrefix = prefix.isEmpty
            ? URL(fileURLWithPath: inputPath).deletingPathExtension().lastPathComponent
            : prefix

        queue.async { [weak self] in
            guard let self else { return }
            self.runConversion(
                inputPath: inputPath,
                outputDir: outputDir,
                prefix: resolvedPrefix,
                bitrateIdx: bitrateIdx,
                sampleRateIdx: sampleRateIdx,
                channelsIdx: channelsIdx,
                rateModeIdx: rateModeIdx
            )
            DispatchQueue.main.async { self.isRunning = false }
        }
    }

    func cancel() {
        cancelFlag = true
        currentProcess?.terminate()
    }

    // MARK: Private helpers

    private func appendLog(_ msg: String) {
        DispatchQueue.main.async { self.log.append(msg) }
    }

    private func setProgress(_ v: Double) {
        DispatchQueue.main.async { self.progress = v }
    }

    // MARK: Conversion (runs on background queue)

    private func runConversion(
        inputPath: String,
        outputDir: String,
        prefix: String,
        bitrateIdx: Int,
        sampleRateIdx: Int,
        channelsIdx: Int,
        rateModeIdx: Int
    ) {
        let bitrates    = ["64k", "96k", "128k", "160k", "192k", "224k", "256k", "320k"]
        let sampleRates = ["22050", "44100", "48000"]

        let (ffmpeg, ffprobe) = findFFmpeg()
        appendLog("Using ffmpeg: \(ffmpeg)")
        appendLog("Reading chapters from:\n  \(inputPath)")

        // ── ffprobe ──────────────────────────────────────────────────────────

        let probeProcess = Process()
        probeProcess.executableURL = URL(fileURLWithPath: ffprobe)
        probeProcess.arguments = [
            "-v", "quiet",
            "-print_format", "json",
            "-show_chapters",
            "-show_format",
            inputPath
        ]
        let probePipe    = Pipe()
        let probeErrPipe = Pipe()
        probeProcess.standardOutput = probePipe
        probeProcess.standardError  = probeErrPipe

        do {
            try probeProcess.run()
        } catch {
            appendLog("❌ Failed to run ffprobe: \(error.localizedDescription)")
            appendLog("Install ffmpeg with:  brew install ffmpeg")
            return
        }
        probeProcess.waitUntilExit()

        guard probeProcess.terminationStatus == 0 else {
            let err = String(data: probeErrPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
            appendLog("❌ ffprobe failed:\n\(err.trimmingCharacters(in: .whitespacesAndNewlines))")
            return
        }

        let probeData = probePipe.fileHandleForReading.readDataToEndOfFile()
        let probe: ProbeOutput
        do {
            probe = try JSONDecoder().decode(ProbeOutput.self, from: probeData)
        } catch {
            appendLog("❌ Failed to parse ffprobe output: \(error.localizedDescription)")
            return
        }

        // ── Build chapter list ────────────────────────────────────────────────

        struct Chapter { let start, end: Double; let title: String }

        let chapters: [Chapter]
        if probe.chapters.isEmpty {
            appendLog("⚠️  No chapter metadata found — converting as single file.")
            let dur = Double(probe.format?.duration ?? "0") ?? 0
            chapters = [Chapter(start: 0, end: dur, title: "Full")]
        } else {
            chapters = probe.chapters.enumerated().map { i, ch in
                Chapter(
                    start: Double(ch.start_time) ?? 0,
                    end:   Double(ch.end_time)   ?? 0,
                    title: ch.tags?.title ?? "Chapter \(i + 1)"
                )
            }
        }

        let total = chapters.count
        appendLog("Found \(total) chapter(s). Starting conversion…\n")

        let safePrefix = sanitise(prefix)
        try? FileManager.default.createDirectory(atPath: outputDir, withIntermediateDirectories: true)

        // ── Convert each chapter ──────────────────────────────────────────────

        for (i, chapter) in chapters.enumerated() {
            if cancelFlag {
                appendLog("⛔ Cancelled by user.")
                return
            }

            let duration  = chapter.end - chapter.start
            let safeTitle = sanitise(chapter.title)
            let outName   = "\(safePrefix) - \(String(format: "%03d", i + 1)) - \(safeTitle).mp3"
            let outPath   = URL(fileURLWithPath: outputDir).appendingPathComponent(outName).path

            appendLog("[\(i + 1)/\(total)] \(chapter.title)  (\(String(format: "%.1f", duration))s)")

            // Build ffmpeg args — input seeking for fast chapter extraction
            var args = [
                "-y",
                "-ss", String(chapter.start),
                "-t",  String(duration),
                "-i",  inputPath,
                "-codec:a", "libmp3lame"
            ]

            if rateModeIdx == 0 {
                args += ["-b:a", bitrates[bitrateIdx]]
            } else {
                let qValues = ["0", "2", "4", "6", "9"]
                args += ["-q:a", qValues[min(rateModeIdx - 1, qValues.count - 1)]]
            }

            args += [
                "-ar", sampleRates[sampleRateIdx],
                "-ac", channelsIdx == 0 ? "1" : "2",
                "-map_metadata", "0",
                "-id3v2_version", "3",
                outPath
            ]

            let process = Process()
            process.executableURL = URL(fileURLWithPath: ffmpeg)
            process.arguments     = args
            process.standardOutput = Pipe()
            let errPipe = Pipe()
            process.standardError = errPipe

            currentProcess = process
            do {
                try process.run()
            } catch {
                appendLog("   ❌  Failed to run ffmpeg: \(error.localizedDescription)")
                setProgress(Double(i + 1) / Double(total))
                continue
            }
            process.waitUntilExit()
            currentProcess = nil

            if process.terminationStatus == 0 {
                let attrs  = try? FileManager.default.attributesOfItem(atPath: outPath)
                let sizeKB = (attrs?[.size] as? Int ?? 0) / 1024
                appendLog("   ✅  \(sizeKB) KB → \(outName)")
            } else {
                appendLog("   ⚠️  ffmpeg returned \(process.terminationStatus)")
                let errLines = String(data: errPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8)?
                    .components(separatedBy: "\n")
                    .filter { !$0.isEmpty }
                    .suffix(3) ?? []
                for line in errLines { appendLog("      \(line)") }
            }

            setProgress(Double(i + 1) / Double(total))
        }

        appendLog("\n🎉 Done! \(total) file(s) written to:\n  \(outputDir)")
        DispatchQueue.main.async { self.conversionDone = true }
    }

    // MARK: Utilities

    private func findFFmpeg() -> (String, String) {
        for dir in ["/opt/homebrew/bin", "/usr/local/bin", "/usr/bin"] {
            let ff = "\(dir)/ffmpeg"
            let fp = "\(dir)/ffprobe"
            if FileManager.default.fileExists(atPath: ff),
               FileManager.default.fileExists(atPath: fp) {
                return (ff, fp)
            }
        }
        return ("ffmpeg", "ffprobe")
    }

    private func sanitise(_ s: String) -> String {
        s.map { $0.isLetter || $0.isNumber || $0 == " " || $0 == "_" || $0 == "-" ? String($0) : "_" }
         .joined()
    }
}
