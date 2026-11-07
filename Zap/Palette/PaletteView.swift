import AppKit
import SwiftUI

struct PaletteView: View {
    @ObservedObject private var palette = PaletteController.shared
    @ObservedObject private var apps = AppIndex.shared
    @ObservedObject private var clipboard = ClipboardStore.shared
    @ObservedObject private var access = AccessibilityPermission.shared
    @ObservedObject private var settings = SettingsStore.shared
    @ObservedObject private var themes = ThemeController.shared
    @FocusState private var fieldFocused: Bool
    @Environment(\.displayScale) private var displayScale
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        VStack(spacing: 0) {
            searchRow
            Divider().overlay(colors.separator)
            resultList
            if let warning = clipboard.limitWarning, palette.mode == .clipboard {
                pinnedLimitBanner(L10n.clipboardLimitWarning(warning))
            }
            if palette.mode == .clipboard && !access.isTrusted {
                permissionBanner
            }
            Divider().overlay(colors.separator)
            footer
        }
        .frame(width: 640, height: 480)
        .background(colors.background.opacity(colors.cover))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(colors.separator, lineWidth: 1)
        )
        .onAppear { focusField() }
        .onChange(of: palette.isPresented) { _, shown in
            if shown { focusField() }
        }
        .onChange(of: palette.mode) { _, _ in
            focusField()
        }
    }

    private var searchRow: some View {
        HStack(spacing: 10) {
            Image(systemName: palette.mode == .launcher ? "magnifyingglass" : "doc.on.clipboard")
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(colors.secondary)
                .frame(width: 20)
            TextField(placeholder, text: $palette.query)
                .textFieldStyle(.plain)
                .font(.system(size: 18))
                .foregroundStyle(colors.primary)
                .focused($fieldFocused)
                .autocorrectionDisabled()
                .id(palette.fieldToken)
                .padding(.horizontal, colors.searchIsPill ? 12 : 0)
                .padding(.vertical, colors.searchIsPill ? 6 : 0)
                .background {
                    if colors.searchIsPill {
                        Capsule().fill(colors.inputFill)
                    }
                }
                .overlay {
                    if colors.searchIsPill {
                        Capsule().strokeBorder(fieldFocused ? colors.accent : colors.inputStroke, lineWidth: fieldFocused ? 1.5 : 1)
                    }
                }
            if !palette.query.isEmpty {
                Button {
                    palette.query = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(colors.secondary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
    }

    private var placeholder: String {
        palette.mode == .launcher ? L10n.searchApps : L10n.searchClipboard
    }

    @ViewBuilder
    private var resultList: some View {
        switch palette.mode {
        case .launcher:
            launcherList
        case .clipboard:
            clipboardList
        }
    }

    private var launcherList: some View {
        let rows = apps.ranked(matching: palette.query)
        let duplicates = duplicateNames
        return Group {
            if rows.isEmpty {
                emptyState(
                    title: apps.apps.isEmpty && apps.isScanning ? L10n.indexingApps : L10n.noAppMatch,
                    message: nil
                )
            } else {
                scrollList(count: rows.count) { index in
                    let row = rows[index]
                    resultButton(index: index, selected: safeIndex(rows.count) == index) {
                        appIcon(row.app)
                        VStack(alignment: .leading, spacing: 2) {
                            highlighted(row.app.name, indices: row.match.indices)
                                .lineLimit(1)
                                .foregroundStyle(colors.primary)
                            if duplicates.contains(row.app.name) {
                                Text(locationHint(row.app))
                                    .font(.caption)
                                    .foregroundStyle(colors.secondary)
                                    .lineLimit(1)
                            }
                        }
                    }
                }
            }
        }
    }

    private var clipboardList: some View {
        let rows = clipboard.ranked(matching: palette.query)
        return Group {
            if rows.isEmpty {
                emptyState(
                    title: clipboard.items.isEmpty ? L10n.clipboardEmpty : L10n.noClipMatch,
                    message: clipboard.items.isEmpty ? L10n.clipboardEmptyHint : nil
                )
            } else {
                scrollList(count: rows.count) { index in
                    let row = rows[index]
                    clipboardRow(
                        index: index,
                        item: row.item,
                        indices: row.match.indices,
                        selected: palette.selectedClipIDs.isEmpty
                            ? safeIndex(rows.count) == index
                            : palette.selectedClipIDs.contains(row.id)
                    )
                }
            }
        }
    }

    private func scrollList<Row: View>(count: Int, @ViewBuilder row: @escaping (Int) -> Row) -> some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 2) {
                    ForEach(0..<count, id: \.self) { index in
                        row(index)
                            .id(index)
                    }
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 6)
                .background {
                    if palette.mode == .clipboard {
                        CompactScrollbar()
                    }
                }
            }
            .onChange(of: palette.query) { _, _ in proxy.scrollTo(0, anchor: .top) }
            .onChange(of: palette.fieldToken) { _, _ in proxy.scrollTo(0, anchor: .top) }
            .onReceive(palette.scrollRequests) { index in
                guard count > 0 else { return }
                proxy.scrollTo(min(index, count - 1), anchor: nil)
            }
        }
    }

    private func resultButton<Content: View>(index: Int, selected: Bool, @ViewBuilder content: () -> Content) -> some View {
        Button {
            palette.selectedIndex = index
            palette.commitSelection()
        } label: {
            HStack(spacing: 10) {
                content()
            }
            .padding(.horizontal, 8)
            .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
            .background(rowFill(selected: selected))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .focusable(false)
        .onHover { inside in
            if inside { palette.selectedIndex = index }
        }
    }

    private func clipboardRow(index: Int, item: ClipboardItem, indices: [Int], selected: Bool) -> some View {
        HStack(spacing: 8) {
            Button {
                palette.clickClipboardRow(item, index: index, modifiers: NSEvent.modifierFlags)
            } label: {
                HStack(spacing: 10) {
                    if selected && !palette.selectedClipIDs.isEmpty {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(colors.accent)
                            .accessibilityHidden(true)
                    }
                    clipIcon(item)
                    highlighted(item.displayText, indices: indices.filter { $0 < item.displayText.count })
                        .lineLimit(1)
                        .foregroundStyle(colors.primary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    if item.pinnedAt != nil {
                        Image(systemName: "pin.fill")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(colors.accent)
                    }
                    if ClipboardPolicy.showsStoredSize(of: item) {
                        Text(DiskUsageFormat.bytes(item.byteCount))
                            .font(.caption)
                            .foregroundStyle(colors.secondary)
                            .layoutPriority(1)
                    }
                    Text(RelativeTime.string(from: item.createdAt))
                        .font(.caption)
                        .foregroundStyle(colors.secondary)
                        .layoutPriority(1)
                }
                .frame(maxWidth: .infinity, minHeight: 44)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            if selected && palette.selectedClipIDs.isEmpty {
                Button {
                    palette.selectedIndex = index
                    palette.togglePinSelected()
                } label: {
                    Image(systemName: item.pinnedAt == nil ? "pin" : "pin.slash")
                        .frame(width: 22, height: 22)
                }
                .buttonStyle(.plain)
                .help(item.pinnedAt == nil ? L10n.pin : L10n.unpin)
                Button {
                    palette.selectedIndex = index
                    palette.deleteSelectedClipboardItem()
                } label: {
                    Image(systemName: "trash")
                        .frame(width: 22, height: 22)
                }
                .buttonStyle(.plain)
                .help(L10n.deleteItem)
            }
        }
        .padding(.horizontal, 8)
        .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
        .background(rowFill(selected: selected))
        .onHover { inside in
            if inside { palette.selectedIndex = index }
        }
    }

    private func appIcon(_ app: LaunchableApp) -> some View {
        Image(nsImage: apps.icon(for: app))
            .resizable()
            .frame(width: 28, height: 28)
    }

    @ViewBuilder
    private func clipIcon(_ item: ClipboardItem) -> some View {
        if item.kind == .image, let image = clipboard.thumbnail(for: item, scale: displayScale) {
            Image(nsImage: image)
                .resizable()
                .interpolation(.high)
                .aspectRatio(contentMode: .fill)
                .frame(width: 32, height: 32)
                .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
        } else if item.kind == .image {
            Image(systemName: "photo")
                .font(.system(size: 16))
                .foregroundStyle(colors.secondary)
                .frame(width: 32, height: 32)
                .background(colors.keycap, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
        } else {
            Image(systemName: "text.alignleft")
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(colors.secondary)
                .frame(width: 32, height: 32)
                .background(colors.keycap, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
        }
    }

    private func emptyState(title: String, message: String?) -> some View {
        VStack(spacing: 6) {
            Spacer()
            Text(title)
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(colors.secondary)
            if let message {
                Text(message)
                    .font(.caption)
                    .foregroundStyle(colors.secondary)
                    .multilineTextAlignment(.center)
            }
            Spacer()
        }
        .padding(.horizontal, 24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func pinnedLimitBanner(_ message: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(colors.warning)
            Text(message)
                .font(.caption)
                .foregroundStyle(colors.primary)
            Spacer(minLength: 8)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(colors.warning.opacity(0.14))
    }

    private var permissionBanner: some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.circle.fill")
                .foregroundStyle(colors.warning)
            Text(L10n.accessibilityBanner)
                .font(.caption)
                .foregroundStyle(colors.primary)
            Spacer(minLength: 8)
            Button(L10n.grantAccess) {
                AccessibilityPermission.shared.prompt()
            }
            .controlSize(.small)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(colors.warning.opacity(0.14))
    }

    private var footer: some View {
        HStack(spacing: 14) {
            keyHint("↑↓", L10n.choose)
            keyHint("↩", palette.mode == .launcher ? L10n.open : L10n.paste)
            keyHint("esc", L10n.close)
            if palette.mode == .clipboard {
                if palette.selectedClipIDs.isEmpty {
                    keyHint("⇧点击", L10n.selectAll)
                    keyHint("⌘⌫", L10n.deleteItem)
                } else {
                    Button(role: .destructive) {
                        palette.deleteSelectedClipboardItem()
                    } label: {
                        Label(L10n.deleteSelection(palette.selectedClipIDs.count), systemImage: "trash.fill")
                            .fontWeight(.semibold)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.red)
                    .controlSize(.regular)
                }
            }
            Spacer()
            Text(palette.mode == .launcher ? settings.launcherHotkey.displayString : settings.clipboardHotkey.displayString)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(colors.secondary)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
    }

    private func keyHint(_ key: String, _ label: String) -> some View {
        HStack(spacing: 4) {
            Text(key)
                .font(.system(size: 11, weight: .semibold, design: .rounded))
                .padding(.horizontal, 5)
                .padding(.vertical, 2)
                .foregroundStyle(colors.primary)
                .background(colors.keycap, in: RoundedRectangle(cornerRadius: 4, style: .continuous))
            Text(label)
                .foregroundStyle(colors.secondary)
        }
        .font(.system(size: 11))
    }

    private func highlighted(_ source: String, indices: [Int]) -> Text {
        guard !indices.isEmpty else { return Text(source) }
        let hits = Set(indices)
        var result = AttributedString()
        for (index, character) in source.enumerated() {
            var piece = AttributedString(String(character))
            if hits.contains(index) {
                piece.font = .body.weight(.semibold)
            }
            result.append(piece)
        }
        return Text(result)
    }

    private var duplicateNames: Set<String> {
        var counts: [String: Int] = [:]
        for app in apps.apps {
            counts[app.name, default: 0] += 1
        }
        return Set(counts.filter { $0.value > 1 }.keys)
    }

    private func locationHint(_ app: LaunchableApp) -> String {
        if app.path.hasPrefix("/System/") { return L10n.systemLocation }
        let parent = URL(fileURLWithPath: app.path).deletingLastPathComponent().lastPathComponent
        if parent == "Applications" { return L10n.applicationsLocation }
        return parent
    }

    private func safeIndex(_ count: Int) -> Int {
        guard count > 0 else { return 0 }
        return min(palette.selectedIndex, count - 1)
    }

    private var colors: ZapColors {
        themes.colors(dark: colorScheme == .dark)
    }

    private func rowFill(selected: Bool) -> some View {
        RoundedRectangle(cornerRadius: 8, style: .continuous)
            .fill(selected ? colors.selection : Color.clear)
    }

    private func focusField() {
        DispatchQueue.main.async {
            fieldFocused = true
        }
    }
}

private struct CompactScrollbar: NSViewRepresentable {
    final class Probe: NSView {
        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            enclosingScrollView?.verticalScroller?.controlSize = .mini
        }
    }

    func makeNSView(context: Context) -> Probe { Probe() }

    func updateNSView(_ view: Probe, context: Context) {
        view.enclosingScrollView?.verticalScroller?.controlSize = .mini
    }
}
