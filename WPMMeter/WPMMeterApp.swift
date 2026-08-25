import AppKit
import ServiceManagement
import SwiftUI

@main
struct WPMMeterApp: App {
    @StateObject private var meter = MeterModel()
    @AppStorage("danish") private var danish = false
    @AppStorage("paused") private var paused = false
    @AppStorage("targetEnabled") private var targetEnabled = false
    @AppStorage("targetWPM") private var targetWPM = 300
    @AppStorage("permissionIntroduced") private var permissionIntroduced = false
    @State private var belowTarget = false

    var body: some Scene {
        MenuBarExtra {
            VStack(spacing: 14) {
                Text(meter.wordsPerMinute.map { "\($0) WPM" } ?? "—")
                    .font(.system(size: 42, weight: .medium, design: .rounded).monospacedDigit())
                    .foregroundStyle(belowTarget ? .red : .primary)
                    .frame(minWidth: 230)
                Text(meter.status.message).font(.caption).foregroundStyle(.secondary)
                Divider()
                Toggle("Danish", isOn: $danish)
                Toggle("Target", isOn: $targetEnabled)
                if targetEnabled { Stepper("\(targetWPM) WPM", value: $targetWPM, in: 50...1_000, step: 10) }
                Divider()
                Button(paused ? "Resume WPM Meter" : "Pause WPM Meter") { paused.toggle(); applyRunningState() }
                LaunchAtLoginToggle()
                if meter.status == .permissionRequired {
                    Button("Enable WPM Meter") {
                        permissionIntroduced = true
                        meter.start(danish: danish)
                    }
                    Button("Open System Audio Settings") { openAudioSettings() }
                    Text("Audio is processed locally and never saved. After granting access, quit and reopen WPM Meter.")
                        .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                }
                Divider()
                Button("Quit WPM Meter") { NSApplication.shared.terminate(nil) }.keyboardShortcut("q")
            }
            .padding()
            .onChange(of: danish) { _, _ in if !paused { meter.start(danish: danish) } }
            .onChange(of: meter.wordsPerMinute) { oldValue, _ in updateTargetState(reset: oldValue == nil) }
            .onChange(of: targetEnabled) { _, _ in updateTargetState(reset: true) }
            .onChange(of: targetWPM) { _, _ in updateTargetState(reset: true) }
        } label: {
            Text(meter.wordsPerMinute.map { "\($0) WPM" } ?? "—")
                .monospacedDigit().foregroundStyle(belowTarget ? .red : .primary)
                .accessibilityLabel(meter.wordsPerMinute.map { "\($0) words per minute" } ?? "No WPM measurement")
        }
        .menuBarExtraStyle(.window)
    }

    private func applyRunningState() {
        if paused { meter.stop() }
        else if permissionIntroduced { meter.start(danish: danish) }
        else { meter.requirePermission() }
    }

    private func updateTargetState(reset: Bool = false) {
        guard targetEnabled, let wpm = meter.wordsPerMinute else { belowTarget = false; return }
        if reset { belowTarget = wpm < targetWPM; return }
        if belowTarget, wpm >= targetWPM { belowTarget = false }
        if !belowTarget, wpm < Int(Double(targetWPM) * 0.95) { belowTarget = true }
    }

    private func openAudioSettings() {
        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture")!)
    }
}

private struct LaunchAtLoginToggle: View {
    @State private var enabled = SMAppService.mainApp.status == .enabled
    var body: some View {
        Toggle("Launch at Login", isOn: Binding(get: { enabled }, set: { value in
            do {
                if value { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
                enabled = value
            } catch { enabled = SMAppService.mainApp.status == .enabled }
        }))
    }
}
