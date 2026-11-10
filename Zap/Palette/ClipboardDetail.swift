import AppKit
import SwiftUI

struct ClipboardDetail: View {
    let item: ClipboardItem
    @ObservedObject var store: ClipboardStore
    @ObservedObject var palette: PaletteController
    @State private var draft = ""
    @State private var turns = 0
    @State private var failed = false
    @FocusState private var textFocused: Bool

    private var selection: [ClipboardItem] { palette.orderedSelection }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 5) {
                Spacer()
                button("trash", L10n.deleteItem) { palette.deleteSelectedClipboardItem() }
                if selection.isEmpty {
                    button(item.pinnedAt == nil ? "pin" : "pin.slash", item.pinnedAt == nil ? L10n.pin : L10n.unpin) {
                        store.togglePin(item.id)
                    }
                    if palette.editingClip && item.kind == .image {
                        button("rotate.right", "向右旋转") { turns = (turns + 1) % 4 }
                    }
                    button(palette.editingClip ? "checkmark" : "pencil", palette.editingClip ? "保存编辑" : "编辑", action: toggleEditing)
                }
                if selection.isEmpty {
                    // Same control as the row's trailing icon: both read and set store.pasteboardItemID.
                    let current = store.pasteboardItemID == item.id
                    Button { _ = store.placeOnPasteboard(item) } label: {
                        Image(systemName: current ? "checkmark" : "doc.on.clipboard")
                            .contentTransition(.symbolEffect(.replace))
                            .frame(width: 24, height: 22)
                    }
                    .buttonStyle(.bordered)
                    .accessibilityLabel(current ? "已在剪贴板中" : "设为下次粘贴内容")
                    .disabled(palette.editingClip)
                } else {
                    button("doc.on.clipboard", L10n.pasteInOrder) { palette.commitSelection() }
                }
            }
            if failed { Text("无法保存，请检查内容是否为空、重复或超过容量限制。").font(.caption) }
            if !selection.isEmpty {
                ScrollView {
                    VStack(alignment: .leading, spacing: 4) {
                        ForEach(Array(selection.enumerated()), id: \.element.id) { index, clip in
                            HStack(alignment: .top) {
                                Text("\(index + 1)").foregroundStyle(.secondary).monospacedDigit()
                                if clip.kind == .image, let thumb = store.thumbnail(for: clip, pointSize: 96) {
                                    Image(nsImage: thumb).resizable().scaledToFit()
                                        .frame(maxWidth: 160, maxHeight: 96, alignment: .leading)
                                        .clipShape(RoundedRectangle(cornerRadius: 4))
                                } else {
                                    Text(verbatim: clip.text ?? clip.displayText)
                                }
                            }
                        }
                    }.frame(maxWidth: .infinity, alignment: .leading)
                }
            } else if item.kind == .image, let url = store.imageURL(for: item) {
                ClipboardImagePreview(url: url, turns: palette.editingClip ? turns : 0)
            } else if palette.editingClip {
                TextEditor(text: $draft).focused($textFocused)
            } else {
                ScrollView {
                    Text(verbatim: item.text ?? "")
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
        .padding(4)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .onChange(of: palette.editingClip) { _, editing in textFocused = editing && item.kind == .text }
    }

    private func button(_ symbol: String, _ label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) { Image(systemName: symbol).frame(width: 24, height: 22) }
            .buttonStyle(.bordered).accessibilityLabel(label)
    }

    private func toggleEditing() {
        failed = false
        if palette.editingClip {
            guard store.edit(item, text: draft, quarterTurns: turns) else { failed = true; return }
        } else {
            draft = item.text ?? ""
            turns = 0
        }
        palette.editingClip.toggle()
    }
}

private struct ClipboardImagePreview: View {
    let url: URL
    let turns: Int
    @State private var image: NSImage?
    @State private var zoom: CGFloat = 1
    @GestureState private var magnification: CGFloat = 1

    var body: some View {
        GeometryReader { geometry in
            if let image, image.size.width > 0, image.size.height > 0 {
                let rotated = !turns.isMultiple(of: 2)
                let w = rotated ? image.size.height : image.size.width
                let h = rotated ? image.size.width : image.size.height
                let scale = min(geometry.size.width / w, geometry.size.height / h) * bounded(zoom * magnification)
                ScrollView([.horizontal, .vertical]) {
                    Image(nsImage: image).resizable().interpolation(.high)
                        .frame(width: image.size.width * scale, height: image.size.height * scale)
                        .rotationEffect(.degrees(Double(turns) * 90))
                        .frame(width: w * scale, height: h * scale)
                        .accessibilityLabel(L10n.imagePreview)
                }
                .defaultScrollAnchor(.topLeading)
                .gesture(MagnifyGesture()
                    .updating($magnification) { value, state, _ in state = value.magnification }
                    .onEnded { zoom = bounded(zoom * $0.magnification) })
                .onTapGesture(count: 2) { zoom = zoom == 1 ? 2 : 1 }
                .accessibilityAction(named: "放大") { zoom = bounded(zoom * 2) }
                .accessibilityAction(named: "缩小") { zoom = bounded(zoom / 2) }
            } else {
                Text(L10n.imagePreviewUnavailable).foregroundStyle(.secondary)
            }
        }
        .task(id: url) { image = NSImage(contentsOf: url); zoom = 1 }
    }

    private func bounded(_ value: CGFloat) -> CGFloat { min(8, max(1, value)) }
}
