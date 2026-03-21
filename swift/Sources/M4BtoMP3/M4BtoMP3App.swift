import SwiftUI
import AppKit

@main
struct M4BtoMP3App: App {
    var body: some Scene {
        WindowGroup("M4B → MP3 Chapter Splitter") {
            ContentView()
        }
        .windowResizability(.contentMinSize)
        .commands {
            CommandGroup(replacing: .appInfo) {
                Button("About M4B → MP3") {
                    NSApp.orderFrontStandardAboutPanel(options: [
                        .applicationName: "M4B → MP3",
                        .applicationVersion: "1.0",
                        .version: "",
                        .credits: NSAttributedString(
                            string: "Converts .m4b and .m4a audiobook files into chapter-split .mp3 files.\n\nRequires ffmpeg — install with:\nbrew install ffmpeg",
                            attributes: [.font: NSFont.systemFont(ofSize: NSFont.smallSystemFontSize)]
                        ),
                    ])
                }
            }
        }
    }
}
