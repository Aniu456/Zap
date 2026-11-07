import AppKit
import SwiftUI

@MainActor
final class ToastCenter {
    static let shared = ToastCenter()

    private var panel: NSPanel?
    private var hideWork: DispatchWorkItem?

    func show(_ message: String) {
        hideWork?.cancel()
        let panel = ensurePanel(message: message)
        place(panel)
        panel.orderFrontRegardless()
        let work = DispatchWorkItem { [weak panel] in
            panel?.orderOut(nil)
        }
        hideWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.6, execute: work)
    }

    private func ensurePanel(message: String) -> NSPanel {
        if let panel {
            if let host = panel.contentView as? NSHostingView<ToastView> {
                host.rootView = ToastView(message: message)
            }
            return panel
        }
        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 320, height: 46),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.isFloatingPanel = true
        panel.level = .floating
        WindowSpaces.apply(to: panel)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.hidesOnDeactivate = false
        panel.ignoresMouseEvents = true
        let host = NSHostingView(rootView: ToastView(message: message))
        panel.contentView = host
        self.panel = panel
        return panel
    }

    private func place(_ panel: NSPanel) {
        let mouse = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { $0.frame.contains(mouse) } ?? NSScreen.main
        guard let screen else { return }
        let visible = screen.visibleFrame
        let size = NSSize(width: 320, height: 46)
        let origin = NSPoint(x: visible.midX - size.width / 2, y: visible.maxY - size.height - 86)
        panel.setFrame(NSRect(origin: origin, size: size), display: true)
    }
}

private struct ToastView: View {
    let message: String
    @ObservedObject private var themes = ThemeController.shared
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        let colors = themes.colors(dark: colorScheme == .dark)
        Text(message)
            .font(.system(size: 13, weight: .medium))
            .foregroundStyle(colors.primary)
            .padding(.horizontal, 16)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background {
                if colors.vibrancy > 0.5 {
                    Capsule().fill(.regularMaterial)
                } else {
                    Capsule().fill(colors.background)
                }
            }
            .overlay(Capsule().strokeBorder(colors.separator, lineWidth: 1))
    }
}
