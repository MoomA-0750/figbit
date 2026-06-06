import Foundation
import SwiftUI

// ショートカット等の設定をどこに保存するか。
// local: この端末のUserDefaultsのみ（無料アカウントでも動作）。
// iCloud: NSUbiquitousKeyValueStoreで複数端末に同期（iCloud有効化＝要Developer Program）。
enum ShortcutStorageLocation: String, CaseIterable, Identifiable {
    case local
    case iCloud
    var id: String { rawValue }
    var label: LocalizedStringKey {
        switch self {
        case .local:  return "この端末に保存"
        case .iCloud: return "iCloudに同期"
        }
    }
}

@Observable
class ShortcutSyncManager {
    var shortcuts: [ShortcutItem] = ShortcutItem.defaults
    var pencilMode: PencilMode = .figurative

    // Apple Pencilのダブルタップで交互に切り替える2つのツール（MenuCommand.id を保存）。
    var pencilDoubleTapToolA: String = MenuCommandCatalog.tools.first { $0.title == "選択" }?.id ?? ""
    var pencilDoubleTapToolB: String = MenuCommandCatalog.tools.first { $0.title == "ペン" }?.id ?? ""
    // 次にBを送るか（交互トグル用。永続化不要）。
    // 初期値 true ＝ 初回ダブルタップはツール2を送る。Figmaは起動時に選択ツール
    // （＝既定のツール1）なので、初回で「もう片方」へ切り替わるのが自然なため。
    @ObservationIgnored private var pencilDoubleTapNextIsB = true

    // ダブルタップ時に呼ぶ。AとBを交互に返し、トグル状態を進める。
    func nextPencilDoubleTapTool() -> ShortcutItem? {
        let id = pencilDoubleTapNextIsB ? pencilDoubleTapToolB : pencilDoubleTapToolA
        pencilDoubleTapNextIsB.toggle()
        return MenuCommandCatalog.tools.first { $0.id == id }?.asShortcutItem()
    }

    // 保存先。切り替えると現在の内容を新しい保存先へ書き出す（移行）。
    var storageLocation: ShortcutStorageLocation {
        didSet {
            guard storageLocation != oldValue else { return }
            UserDefaults.standard.set(storageLocation.rawValue, forKey: storageKey)
            save()
        }
    }

    private let shortcutsKey = "figbit.shortcuts.v1"
    private let pencilModeKey = "figbit.pencilMode.v1"
    private let pencilTapAKey = "figbit.pencilTap.a.v1"
    private let pencilTapBKey = "figbit.pencilTap.b.v1"
    // 「どこに保存するか」の設定自体は常にローカルに置く（同期先に置くと鶏卵問題になるため）。
    private let storageKey = "figbit.shortcuts.storage.v1"

    private let cloud = NSUbiquitousKeyValueStore.default
    private let local = UserDefaults.standard
    private var notificationToken: NSObjectProtocol?

    init() {
        let raw = UserDefaults.standard.string(forKey: storageKey)
        storageLocation = ShortcutStorageLocation(rawValue: raw ?? "") ?? .local
        load()
        // iCloud側の外部変更を監視するが、反映するのはiCloud保存モードのときだけ。
        notificationToken = NotificationCenter.default.addObserver(
            forName: NSUbiquitousKeyValueStore.didChangeExternallyNotification,
            object: cloud,
            queue: .main
        ) { [weak self] _ in
            guard let self, self.storageLocation == .iCloud else { return }
            self.load()
        }
        if storageLocation == .iCloud { cloud.synchronize() }
    }

    func save() {
        guard let data = try? JSONEncoder().encode(shortcuts) else { return }
        switch storageLocation {
        case .local:
            local.set(data, forKey: shortcutsKey)
            local.set(pencilMode.rawValue, forKey: pencilModeKey)
            local.set(pencilDoubleTapToolA, forKey: pencilTapAKey)
            local.set(pencilDoubleTapToolB, forKey: pencilTapBKey)
        case .iCloud:
            cloud.set(data, forKey: shortcutsKey)
            cloud.set(pencilMode.rawValue, forKey: pencilModeKey)
            cloud.set(pencilDoubleTapToolA, forKey: pencilTapAKey)
            cloud.set(pencilDoubleTapToolB, forKey: pencilTapBKey)
            cloud.synchronize()
        }
    }

    private func load() {
        let data: Data?
        let modeRaw: String?
        let tapA: String?
        let tapB: String?
        switch storageLocation {
        case .local:
            data = local.data(forKey: shortcutsKey)
            modeRaw = local.string(forKey: pencilModeKey)
            tapA = local.string(forKey: pencilTapAKey)
            tapB = local.string(forKey: pencilTapBKey)
        case .iCloud:
            data = cloud.data(forKey: shortcutsKey)
            modeRaw = cloud.string(forKey: pencilModeKey)
            tapA = cloud.string(forKey: pencilTapAKey)
            tapB = cloud.string(forKey: pencilTapBKey)
        }
        if let data, let items = try? JSONDecoder().decode([ShortcutItem].self, from: data) {
            shortcuts = items
        }
        if let modeRaw, let mode = PencilMode(rawValue: modeRaw) {
            pencilMode = mode
        }
        if let tapA, !tapA.isEmpty { pencilDoubleTapToolA = tapA }
        if let tapB, !tapB.isEmpty { pencilDoubleTapToolB = tapB }
    }

    func addShortcut(_ item: ShortcutItem) {
        shortcuts.append(item)
        save()
    }

    func updateShortcut(_ item: ShortcutItem) {
        if let idx = shortcuts.firstIndex(where: { $0.id == item.id }) {
            shortcuts[idx] = item
            save()
        }
    }

    func removeShortcuts(at offsets: IndexSet) {
        shortcuts.remove(atOffsets: offsets)
        save()
    }

    func moveShortcut(from source: IndexSet, to destination: Int) {
        shortcuts.move(fromOffsets: source, toOffset: destination)
        save()
    }

    func resetToDefaults() {
        shortcuts = ShortcutItem.defaults
        save()
    }
}
