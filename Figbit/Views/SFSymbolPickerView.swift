import SwiftUI
import UIKit

struct SFSymbolPickerView: View {
    @Binding var selected: String
    @Environment(\.dismiss) private var dismiss
    @State private var searchText = ""

    private var filtered: [String] {
        searchText.isEmpty
            ? Self.symbols
            : Self.symbols.filter { $0.localizedCaseInsensitiveContains(searchText) }
    }

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 8), count: 5)

    var body: some View {
        NavigationStack {
            ScrollView {
                if filtered.isEmpty {
                    ContentUnavailableView(
                        "見つかりません",
                        systemImage: "magnifyingglass",
                        description: Text("「\(searchText)」に一致するシンボルがありません")
                    )
                    .padding(.top, 60)
                } else {
                    LazyVGrid(columns: columns, spacing: 8) {
                        ForEach(filtered, id: \.self) { name in
                            symbolCell(name: name)
                        }
                    }
                    .padding()
                }
            }
            .searchable(
                text: $searchText,
                placement: .navigationBarDrawer(displayMode: .always),
                prompt: "シンボルを検索"
            )
            .navigationTitle("アイコンを選択")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("キャンセル") { dismiss() }
                }
                if !selected.isEmpty {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button("クリア") { selected = ""; dismiss() }
                            .foregroundStyle(.red)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func symbolCell(name: String) -> some View {
        let isSelected = selected == name
        Button {
            selected = name
            dismiss()
        } label: {
            VStack(spacing: 4) {
                Image(systemName: name)
                    .font(.system(size: 24, weight: .regular))
                    .frame(height: 32)
                Text(name)
                    .font(.system(size: 7))
                    .lineLimit(2)
                    .multilineTextAlignment(.center)
                    .minimumScaleFactor(0.8)
            }
            .foregroundStyle(isSelected ? .white : .primary)
            .frame(maxWidth: .infinity)
            .frame(height: 76)
            .background(
                isSelected ? Color.accentColor : Color(.systemGray6),
                in: RoundedRectangle(cornerRadius: 10)
            )
        }
        .buttonStyle(.plain)
    }

    // Candidates are validated at first use so unavailable symbols on older OS are silently dropped.
    static let symbols: [String] = {
        let candidates: [String] = [
            // Arrows
            "arrow.up", "arrow.down", "arrow.left", "arrow.right",
            "arrow.up.left", "arrow.up.right", "arrow.down.left", "arrow.down.right",
            "arrow.clockwise", "arrow.counterclockwise",
            "arrow.uturn.backward", "arrow.uturn.forward",
            "arrow.left.right", "arrow.up.down",
            "arrows.up.down", "arrows.left.right",
            "arrow.up.left.and.arrow.down.right",
            "arrow.down.right.and.arrow.up.left",
            "arrow.up.left.and.down.right.magnifyingglass",
            "arrow.triangle.merge", "arrow.triangle.branch",
            "chevron.left", "chevron.right", "chevron.up", "chevron.down",
            "chevron.left.right", "chevron.up.down",
            "chevron.compact.left", "chevron.compact.right",
            // Documents
            "doc", "doc.fill", "doc.text", "doc.text.fill",
            "doc.on.doc", "doc.on.doc.fill",
            "doc.badge.plus",
            "folder", "folder.fill", "folder.badge.plus",
            "clipboard", "clipboard.fill",
            "note", "note.text",
            "paperclip",
            "tray", "tray.fill", "tray.and.arrow.up", "tray.and.arrow.down",
            "archivebox", "archivebox.fill",
            // Text & Editing
            "pencil", "pencil.circle", "pencil.circle.fill",
            "square.and.pencil", "pencil.tip", "pencil.tip.crop.circle",
            "eraser", "eraser.fill",
            "textformat", "textformat.size",
            "bold", "italic", "underline", "strikethrough",
            "text.alignleft", "text.aligncenter", "text.alignright", "text.justify",
            "character.cursor.ibeam",
            // Shapes
            "rectangle", "rectangle.fill", "rectangle.dashed",
            "circle", "circle.fill", "circle.dashed",
            "triangle", "triangle.fill",
            "diamond", "diamond.fill",
            "star", "star.fill", "star.leadinghalf.filled",
            "heart", "heart.fill",
            "square", "square.fill", "square.dashed",
            "hexagon", "hexagon.fill",
            "capsule", "capsule.fill",
            // Layers & Layout
            "square.on.square", "square.on.square.fill",
            "square.stack", "square.stack.fill",
            "square.3.layers.3d", "square.3.layers.3d.top.filled",
            "rectangle.on.rectangle", "rectangle.on.rectangle.fill",
            "mosaic", "mosaic.fill",
            "rectangle.grid.1x2", "rectangle.grid.2x2", "rectangle.grid.3x2",
            "circle.grid.2x2", "circle.grid.3x3",
            "rectangle.split.3x1",
            "sidebar.left", "sidebar.right",
            "square.split.2x1", "square.split.1x2", "square.split.2x2",
            // Alignment
            "align.horizontal.left", "align.horizontal.center", "align.horizontal.right",
            "align.vertical.top", "align.vertical.center", "align.vertical.bottom",
            "distribute.horizontal.left", "distribute.horizontal.center.horizontally",
            "distribute.vertical.top", "distribute.vertical.center.vertically",
            // Media
            "play", "play.fill", "play.circle", "play.circle.fill",
            "pause", "pause.fill",
            "stop", "stop.fill",
            "forward", "forward.fill", "backward", "backward.fill",
            "camera", "camera.fill", "camera.circle", "camera.circle.fill",
            "photo", "photo.fill", "photo.stack",
            "video", "video.fill", "video.slash",
            "mic", "mic.fill", "mic.slash", "mic.circle",
            "speaker", "speaker.fill", "speaker.slash",
            "speaker.wave.1", "speaker.wave.2", "speaker.wave.3",
            "music.note", "music.note.list", "waveform",
            // UI & Navigation
            "house", "house.fill",
            "gear", "gearshape", "gearshape.fill", "gearshape.2",
            "slider.horizontal.3", "slider.vertical.3",
            "ellipsis", "ellipsis.circle", "ellipsis.circle.fill",
            "ellipsis.rectangle", "ellipsis.rectangle.fill",
            "plus", "plus.circle", "plus.circle.fill", "plus.square",
            "minus", "minus.circle", "minus.circle.fill",
            "xmark", "xmark.circle", "xmark.circle.fill",
            "checkmark", "checkmark.circle", "checkmark.circle.fill", "checkmark.square",
            "info.circle", "info.circle.fill",
            "exclamationmark.circle", "exclamationmark.triangle",
            "questionmark.circle",
            "magnifyingglass", "magnifyingglass.circle", "magnifyingglass.circle.fill",
            "viewfinder", "viewfinder.circle",
            "eye", "eye.fill", "eye.slash", "eye.circle",
            // Hands & Cursors
            "hand.raised", "hand.raised.fill",
            "hand.point.up", "hand.point.up.fill",
            "hand.point.up.left", "hand.point.up.left.fill",
            "hand.tap", "hand.tap.fill",
            "hand.draw", "hand.draw.fill",
            "hands.clap", "hands.clap.fill",
            "cursorarrow", "cursorarrow.rays", "cursorarrow.motionlines",
            "lasso", "lasso.and.sparkles",
            // Persons
            "person", "person.fill", "person.circle", "person.circle.fill",
            "person.2", "person.2.fill", "person.3", "person.3.fill",
            "figure.walk", "figure.stand",
            // Devices
            "iphone", "ipad", "laptopcomputer", "desktopcomputer", "display",
            "applewatch", "tv", "keyboard", "mouse", "trackpad",
            // Lock & Security
            "lock", "lock.fill", "lock.open", "lock.open.fill",
            "key", "key.fill",
            "shield", "shield.fill",
            // Connectivity
            "wifi", "wifi.slash", "wifi.circle",
            "bluetooth", "antenna.radiowaves.left.and.right",
            // Power & Energy
            "battery.100", "battery.50", "battery.25", "battery.0",
            "bolt", "bolt.fill", "bolt.circle", "bolt.slash",
            // Nature
            "flame", "flame.fill",
            "drop", "drop.fill",
            "lightbulb", "lightbulb.fill",
            "sun.max", "sun.max.fill", "moon", "moon.fill",
            "cloud", "cloud.fill", "snow", "wind",
            "sparkles", "sparkle",
            // Communication
            "bubble.left", "bubble.right", "bubble.left.fill", "bubble.right.fill",
            "bubble.left.and.bubble.right",
            "envelope", "envelope.fill", "envelope.open", "envelope.open.fill",
            "paperplane", "paperplane.fill",
            "bell", "bell.fill", "bell.slash", "bell.badge",
            "tag", "tag.fill",
            "bookmark", "bookmark.fill",
            "flag", "flag.fill",
            "link", "link.circle", "link.circle.fill",
            // Art & Design
            "paintbrush", "paintbrush.fill", "paintbrush.pointed", "paintbrush.pointed.fill",
            "paintpalette", "paintpalette.fill",
            "wand.and.rays", "wand.and.rays.inverse", "wand.and.stars",
            "scissors", "scissors.badge.ellipsis",
            "ruler", "ruler.fill",
            "scope",
            "crop", "rotate.left", "rotate.right",
            "aspectratio", "aspectratio.fill",
            "skew",
            // Data & Charts
            "chart.bar", "chart.bar.fill",
            "chart.pie", "chart.pie.fill",
            "chart.line.uptrend.xyaxis",
            "list.bullet", "list.number", "list.dash",
            "grid", "grid.circle",
            // 3D & Objects
            "cube", "cube.fill", "cube.transparent",
            // Commerce
            "cart", "cart.fill",
            "bag", "bag.fill",
            "creditcard", "creditcard.fill",
            // Map
            "map", "map.fill", "location", "location.fill",
            // Share
            "square.and.arrow.up", "square.and.arrow.down",
            // Keyboard keys
            "command", "option", "control", "shift",
            "delete.left", "delete.backward", "return",
        ]
        return candidates.filter { UIImage(systemName: $0) != nil }
    }()
}
