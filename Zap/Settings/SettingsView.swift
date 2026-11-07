import AppKit
import Carbon
import SwiftUI

struct SettingsView: View {
    @ObservedObject private var settings = SettingsStore.shared
    @ObservedObject private var access = AccessibilityPermission.shared
    @ObservedObject private var screenRecording = ScreenRecordingPermission.shared
    @ObservedObject private var clipboard = ClipboardStore.shared
    @Environment(\.colorScheme) private var colorScheme
    @State private var confirmClear = false

    var body: some View {
        Form {
            Section {
                HStack(spacing: 12) {
                    Image(nsImage: AppIconArtwork.image())
                        .resizable()
                        .interpolation(.high)
                        .frame(width: 48, height: 48)
                        .clipShape(RoundedRectangle(cornerRadius: CGFloat(48) * 0.225, style: .continuous))
                    VStack(alignment: .leading, spacing: 2) {
                        Text(L10n.appName)
                            .font(.title2.bold())
                            .foregroundStyle(colors.primary)
                        Text(versionSubtitle)
                            .foregroundStyle(colors.secondary)
                    }
                }
                .padding(.vertical, 4)
                VStack(alignment: .leading, spacing: 8) {
                    Text(L10n.aboutIntro)
                    Text(L10n.aboutLauncher)
                    Text(L10n.aboutClipboard)
                    Text(L10n.aboutCapture)
                    Text(L10n.aboutPrivacy)
                }
                .font(.callout)
                .foregroundStyle(colors.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                Text(L10n.aboutCopyright)
                    .font(.caption)
                    .foregroundStyle(colors.secondary)
                HStack {
                    Button(L10n.checkForUpdates) {
                        (NSApp.delegate as? AppDelegate)?.checkForUpdates(nil)
                    }
                    if let github = URL(string: L10n.githubURL) {
                        Link(L10n.github, destination: github)
                    }
                }
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
                HotkeyRow(
                    title: L10n.capture,
                    chord: settings.captureHotkey,
                    warning: settings.captureWarning
                ) { settings.setCaptureHotkey($0) }
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
                LabeledContent(L10n.screenRecordingTitle) {
                    Text(screenRecording.isTrusted ? "已授权" : "未授权")
                        .foregroundStyle(screenRecording.isTrusted ? .green : .orange)
                }
                Text(L10n.screenRecordingBody)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                Text(L10n.screenRecordingPath)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(L10n.screenRecordingRestart)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                HStack {
                    Button(L10n.grantAccess) {
                        screenRecording.prompt()
                    }
                    .disabled(screenRecording.isTrusted)
                    Button(L10n.openSystemSettings) {
                        screenRecording.openSystemSettings()
                    }
                }
            } header: {
                Text(L10n.screenRecordingTitle)
            }

            Section {
                LabeledContent(L10n.diskUsage) {
                    Text(clipboard.usageLine)
                        .monospacedDigit()
                        .foregroundStyle(clipboard.limitWarning == nil ? Color.primary : Color.orange)
                }
                if let warning = clipboard.limitWarning {
                    Text(L10n.clipboardLimitWarning(warning))
                        .font(.callout)
                        .foregroundStyle(.orange)
                }
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
                Text(L10n.updatesHelp)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Button(L10n.checkForUpdates) {
                    (NSApp.delegate as? AppDelegate)?.checkForUpdates(nil)
                }
            } header: {
                Text(L10n.updates)
            }
        }
        .formStyle(.grouped)
        .frame(width: 560)
        .tint(colors.accent)
        .scrollContentBackground(.hidden)
        .background(colors.background)
        .environment(\.locale, Locale(identifier: "zh-Hans-SG"))
        .alert(L10n.clearTitle, isPresented: $confirmClear) {
            Button(L10n.clearConfirm, role: .destructive) {
                clipboard.removeAll()
            }
            Button(L10n.cancel, role: .cancel) {}
        } message: {
            Text(L10n.clearMessage)
        }
        .onAppear {
            access.refresh()
            screenRecording.refresh()
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            access.refresh()
            screenRecording.refresh()
        }
    }

    private var colors: ZapColors {
        ZapSwatch.colors(dark: colorScheme == .dark)
    }

    private var versionSubtitle: String {
        AppVersion.subtitle(
            short: Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String,
            build: Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String
        )
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
            let code = event.keyCode
            let modifiers = event.modifierFlags.rawValue
            let consumed = MainActor.assumeIsolated {
                HotkeyCapture.active?.consume(keyCode: code, modifierRaw: modifiers) ?? false
            }
            return consumed ? nil : event
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

    fileprivate func consume(keyCode: UInt16, modifierRaw: UInt) -> Bool {
        guard recording else { return false }
        if keyCode == UInt16(kVK_Escape) {
            stop()
            return true
        }
        let modifiers = NSEvent.ModifierFlags(rawValue: modifierRaw).intersection([.command, .option, .shift, .control])
        if modifiers.isEmpty || HotkeyChord.isModifierOnly(keyCode) {
            NSSound.beep()
            return true
        }
        let chord = HotkeyChord(keyCode: keyCode, modifiers: modifiers.rawValue)
        onCapture?(chord)
        stop()
        return true
    }
}
