import AppKit
import Carbon
import SwiftUI

struct SettingsView: View {
    @ObservedObject private var settings = SettingsStore.shared
    @ObservedObject private var access = AccessibilityPermission.shared
    @ObservedObject private var clipboard = ClipboardStore.shared
    @State private var confirmClear = false

    var body: some View {
        Form {
            Section {
                HStack(spacing: 12) {
                    Image(nsImage: NSApp.applicationIconImage)
                        .resizable()
                        .frame(width: 48, height: 48)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(L10n.appName)
                            .font(.title2.bold())
                        Text("Zap · \(L10n.tagline)")
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.vertical, 4)
                Text(L10n.laterCapture)
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }

            Section {
                HotkeyRow(
                    title: L10n.launcher,
                    chord: settings.launcherHotkey,
                    warning: settings.launcherWarning
                ) { settings.setLauncherHotkey($0) }
                HotkeyRow(
                    title: L10n.clipboard,
                    chord: settings.clipboardHotkey,
                    warning: settings.clipboardWarning
                ) { settings.setClipboardHotkey($0) }
                Text(L10n.hotkeyHelp)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(L10n.defaultHotkeys)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Button(L10n.restoreDefaults) {
                    settings.restoreDefaultHotkeys()
                }
            } header: {
                Text(L10n.hotkeys)
            }

            Section {
                LabeledContent(L10n.accessibilityTitle) {
                    Text(access.isTrusted ? "已授权" : "未授权")
                        .foregroundStyle(access.isTrusted ? .green : .orange)
                }
                Text(L10n.accessibilityBody)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                Text(L10n.accessibilityPath)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(L10n.accessibilityRestart)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                HStack {
                    Button(L10n.grantAccess) {
                        access.prompt()
                    }
                    .disabled(access.isTrusted)
                    Button(L10n.openSystemSettings) {
                        access.openSystemSettings()
                    }
                }
            } header: {
                Text(L10n.accessibilityTitle)
            }

            Section {
                Text(L10n.clipboardLimit)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                Button(L10n.clearHistory, role: .destructive) {
                    confirmClear = true
                }
                .disabled(clipboard.items.isEmpty)
            } header: {
                Text(L10n.clipboardSection)
            }

            Section {
                Text(versionText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .frame(width: 560)
        .environment(\.locale, Locale(identifier: "zh-Hans-SG"))
        .alert(L10n.clearTitle, isPresented: $confirmClear) {
            Button(L10n.clearConfirm, role: .destructive) {
                clipboard.removeAll()
            }
            Button(L10n.cancel, role: .cancel) {}
        } message: {
            Text(L10n.clearMessage)
        }
    }

    private var versionText: String {
        let short = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0"
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "1"
        return "版本 \(short) (\(build))"
    }
}

private struct HotkeyRow: View {
    let title: String
    let chord: HotkeyChord
    let warning: String?
    let onChange: (HotkeyChord) -> Void

    @StateObject private var capture = HotkeyCapture()

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            LabeledContent(title) {
                Button(capture.recording ? L10n.recording : chord.displayString) {
                    capture.onCapture = onChange
                    capture.toggle()
                }
                .font(.system(.body, design: .rounded))
            }
            if let warning {
                Text(warning)
                    .font(.caption)
                    .foregroundStyle(.orange)
            }
        }
        .onAppear { capture.onCapture = onChange }
        .onDisappear { capture.stop() }
    }
}

@MainActor
private final class HotkeyCapture: ObservableObject {
    @Published var recording = false
    var onCapture: ((HotkeyChord) -> Void)?
    private var monitor: Any?
    private static weak var active: HotkeyCapture?

    func toggle() {
        if recording {
            stop()
        } else {
            begin()
        }
    }

    func begin() {
        HotkeyCapture.active?.stop()
        recording = true
        HotkeyCapture.active = self
        HotkeyManager.shared.setSuspended(true)
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            MainThread.run { () -> NSEvent? in
                guard let capture = HotkeyCapture.active else { return event }
                return capture.handle(event)
            }
        }
    }

    func stop() {
        let shouldRestore = HotkeyCapture.active === self || monitor != nil
        recording = false
        if HotkeyCapture.active === self {
            HotkeyCapture.active = nil
        }
        if let monitor {
            NSEvent.removeMonitor(monitor)
            self.monitor = nil
        }
        if shouldRestore {
            HotkeyManager.shared.setSuspended(false)
        }
    }

    private func handle(_ event: NSEvent) -> NSEvent? {
        guard recording else { return event }
        if event.keyCode == UInt16(kVK_Escape) {
            stop()
            return nil
        }
        let modifiers = event.modifierFlags.intersection([.command, .option, .shift, .control])
        if modifiers.isEmpty || HotkeyChord.isModifierOnly(event.keyCode) {
            NSSound.beep()
            return nil
        }
        let chord = HotkeyChord(keyCode: event.keyCode, modifiers: modifiers.rawValue)
        onCapture?(chord)
        stop()
        return nil
    }
}
