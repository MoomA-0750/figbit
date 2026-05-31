import Foundation
import SwiftUI

@Observable
class ShortcutSyncManager {
    var shortcuts: [ShortcutItem] = ShortcutItem.defaults
    var pencilMode: PencilMode = .figurative

    private let shortcutsKey = "figbit.shortcuts.v1"
    private let pencilModeKey = "figbit.pencilMode.v1"
    private let store = NSUbiquitousKeyValueStore.default
    private var notificationToken: NSObjectProtocol?

    init() {
        load()
        notificationToken = NotificationCenter.default.addObserver(
            forName: NSUbiquitousKeyValueStore.didChangeExternallyNotification,
            object: store,
            queue: .main
        ) { [weak self] _ in
            self?.load()
        }
        store.synchronize()
    }

    func save() {
        guard let data = try? JSONEncoder().encode(shortcuts) else { return }
        store.set(data, forKey: shortcutsKey)
        store.set(pencilMode.rawValue, forKey: pencilModeKey)
        store.synchronize()
    }

    private func load() {
        if let data = store.data(forKey: shortcutsKey),
           let items = try? JSONDecoder().decode([ShortcutItem].self, from: data) {
            shortcuts = items
        }
        if let raw = store.string(forKey: pencilModeKey),
           let mode = PencilMode(rawValue: raw) {
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
