import SwiftUI

@main
struct WPMMeterApp: App {
    private let wordsPerMinute = 0

    var body: some Scene {
        MenuBarExtra("\(wordsPerMinute) WPM") {
            VStack(alignment: .leading, spacing: 10) {
                Text("Words per minute")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Text("\(wordsPerMinute) WPM")
                    .font(.title2.monospacedDigit())

                Divider()

                Button("Quit WPM Meter") {
                    NSApplication.shared.terminate(nil)
                }
                .keyboardShortcut("q")
            }
            .padding()
        }
        .menuBarExtraStyle(.window)
    }
}
