import SwiftUI
import UniformTypeIdentifiers

// MARK: - Constants

private let bitrates    = ["64k", "96k", "128k", "160k", "192k", "224k", "256k", "320k"]
private let sampleRates = ["22050", "44100", "48000"]
private let channelOpts = ["Mono", "Stereo"]
private let rateModes   = ["CBR", "VBR q0 (best)", "VBR q2", "VBR q4", "VBR q6", "VBR q9 (smallest)"]

// MARK: - ContentView

struct ContentView: View {

    // ── Paths ──
    @State private var inputPath = ""
    @State private var outputDir = ""
    @State private var prefix    = ""

    // ── Settings (persisted via UserDefaults) ──
    @AppStorage("bitrateIdx")    private var bitrateIdx    = 2  // 128k
    @AppStorage("sampleRateIdx") private var sampleRateIdx = 1  // 44100
    @AppStorage("channelsIdx")   private var channelsIdx   = 1  // Stereo
    @AppStorage("rateModeIdx")   private var rateModeIdx   = 0  // CBR

    @StateObject private var converter = Converter()

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {

            // ── Input / Output ───────────────────────────────────────────────
            GroupBox("Input / Output") {
                VStack(spacing: 8) {
                    fileRow(label: "M4B File:", path: $inputPath, isFile: true)
                    fileRow(label: "Output Dir:", path: $outputDir, isFile: false)
                }
                .padding(4)
            }

            // ── MP3 Settings ─────────────────────────────────────────────────
            GroupBox("MP3 Settings") {
                Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 8) {
                    GridRow {
                        Text("Bitrate:")
                        Picker("", selection: $bitrateIdx) {
                            ForEach(bitrates.indices, id: \.self) { Text(bitrates[$0]).tag($0) }
                        }
                        .labelsHidden()
                        .disabled(rateModeIdx != 0)

                        Text("Sample Rate:")
                        Picker("", selection: $sampleRateIdx) {
                            ForEach(sampleRates.indices, id: \.self) { Text(sampleRates[$0]).tag($0) }
                        }
                        .labelsHidden()
                    }

                    GridRow {
                        Text("Channels:")
                        Picker("", selection: $channelsIdx) {
                            ForEach(channelOpts.indices, id: \.self) { Text(channelOpts[$0]).tag($0) }
                        }
                        .labelsHidden()

                        Text("Rate Mode:")
                        Picker("", selection: $rateModeIdx) {
                            ForEach(rateModes.indices, id: \.self) { Text(rateModes[$0]).tag($0) }
                        }
                        .labelsHidden()
                    }

                    GridRow {
                        Text("File Prefix:")
                        TextField("blank = use book name", text: $prefix)
                            .gridCellColumns(3)
                    }
                }
                .padding(4)
            }

            // ── Buttons + Progress ───────────────────────────────────────────
            HStack(spacing: 10) {
                Button {
                    startConversion()
                } label: {
                    Text("▶  Convert").bold()
                }
                .buttonStyle(.borderedProminent)
                .disabled(converter.isRunning)

                Button("Cancel") { converter.cancel() }
                    .disabled(!converter.isRunning)

                Button("Open Folder") {
                    NSWorkspace.shared.open(URL(fileURLWithPath: outputDir))
                }
                .disabled(!converter.conversionDone || converter.isRunning)

                Spacer()

                ProgressView(value: converter.progress)
                    .frame(width: 180)
            }

            // ── Log ──────────────────────────────────────────────────────────
            Text("Log").font(.headline)

            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 1) {
                        ForEach(converter.log.indices, id: \.self) { i in
                            Text(converter.log[i])
                                .font(.system(.caption, design: .monospaced))
                                .textSelection(.enabled)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .id(i)
                        }
                    }
                    .padding(6)
                }
                .background(Color(NSColor.textBackgroundColor))
                .clipShape(RoundedRectangle(cornerRadius: 6))
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(Color(NSColor.separatorColor), lineWidth: 1)
                )
                .onChange(of: converter.log.count) { _, newCount in
                    if newCount > 0 {
                        proxy.scrollTo(newCount - 1, anchor: .bottom)
                    }
                }
            }
        }
        .padding()
        .frame(minWidth: 660, minHeight: 560)
    }

    // MARK: File row

    @ViewBuilder
    private func fileRow(label: String, path: Binding<String>, isFile: Bool) -> some View {
        HStack {
            Text(label).frame(width: 80, alignment: .trailing)
            TextField("", text: path)
            Button("Browse…") {
                if isFile {
                    let panel = NSOpenPanel()
                    panel.allowedContentTypes = [
                        UTType(filenameExtension: "m4b") ?? .audio,
                        UTType(filenameExtension: "m4a") ?? .audio
                    ]
                    panel.allowsMultipleSelection = false
                    guard panel.runModal() == .OK, let url = panel.url else { return }
                    path.wrappedValue = url.path
                    if outputDir.isEmpty {
                        outputDir = url.deletingLastPathComponent().path
                    }
                    if prefix.isEmpty {
                        prefix = url.deletingPathExtension().lastPathComponent
                    }
                } else {
                    let panel = NSOpenPanel()
                    panel.canChooseFiles       = false
                    panel.canChooseDirectories = true
                    panel.canCreateDirectories = true
                    guard panel.runModal() == .OK, let url = panel.url else { return }
                    path.wrappedValue = url.path
                }
            }
        }
    }

    // MARK: Start conversion

    private func startConversion() {
        guard !inputPath.isEmpty, FileManager.default.fileExists(atPath: inputPath) else {
            converter.log.append("❌ Please select a valid M4B file.")
            return
        }
        guard !outputDir.isEmpty else {
            converter.log.append("❌ Please select an output directory.")
            return
        }
        converter.start(
            inputPath:    inputPath,
            outputDir:    outputDir,
            prefix:       prefix,
            bitrateIdx:   bitrateIdx,
            sampleRateIdx: sampleRateIdx,
            channelsIdx:  channelsIdx,
            rateModeIdx:  rateModeIdx
        )
    }
}
