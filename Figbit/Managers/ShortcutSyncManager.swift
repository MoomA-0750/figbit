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
        case .iCloud:
            cloud.set(data, forKey: shortcutsKey)
            cloud.set(pencilMode.rawValue, forKey: pencilModeKey)
            cloud.synchronize()
        }
    }

    private func load() {
        let data: Data?
        let modeRaw: String?
        switch storageLocation {
        case .local:
            data = local.data(forKey: shortcutsKey)
            modeRaw = local.string(forKey: pencilModeKey)
        case .iCloud:
            data = cloud.data(forKey: shortcutsKey)
            modeRaw = cloud.string(forKey: pencilModeKey)
        }
        if let data, let items = try? JSONDecoder().decode([ShortcutItem].self, from: data) {
            shortcuts = items
        }
        if let modeRaw, let mode = PencilMode(rawValue: modeRaw) {
            pencilMode = mode
        }
    }

    func addShortcut(_ item: ShortcutItem) {
        shortcuts.append(item)
        save()
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
