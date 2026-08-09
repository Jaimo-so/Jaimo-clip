import AppKit
import ClipFlowKit
import Foundation

@MainActor
final class AppModel: ObservableObject {
    enum FocusArea {
        case search
        case tabs
        case other
    }

    @Published private(set) var items: [ClipItem] = [] {
        didSet {
            itemsRevision &+= 1
            filteredCache = nil
        }
    }
    @Published var phase: ClipFlowPhase = .loading
    @Published var query = "" {
        didSet { resetSelection() }
    }
    @Published var filter: ClipFilter = .all
    @Published var selectedID: Int64?
    @Published var settingsOpen = false
    @Published var toastMessage: String?
    @Published var focusArea: FocusArea = .other

    let preferences: PreferencesStore
    let updateManager: UpdateManager
    var clipboardMonitor: ClipboardMonitor?
    var onRequestClose: (() -> Void)?

    private var store: SQLiteClipStore?
    private var loadGeneration = UUID()
    private var toastDismissal: DispatchWorkItem?
    private var itemsRevision = 0
    private var filteredCache: (revision: Int, filter: ClipFilter, query: String, items: [ClipItem])?

    init(preferences: PreferencesStore) {
        self.preferences = preferences
        updateManager = UpdateManager()
    }

    var filteredItems: [ClipItem] {
        let needle = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if let filteredCache,
           filteredCache.revision == itemsRevision,
           filteredCache.filter == filter,
           filteredCache.query == needle {
            return filteredCache.items
        }
        let result = items.filter { item in
            let matchesFilter: Bool
            switch filter {
            case .all: matchesFilter = true
            case .text: matchesFilter = item.category == .text
            case .image: matchesFilter = item.category == .image
            case .link: matchesFilter = item.category == .link
            case .favorite: matchesFilter = item.isFavorite
            }
            guard matchesFilter else { return false }
            guard !needle.isEmpty else { return true }
            return item.title.lowercased().contains(needle)
                || item.sourceAppName.lowercased().contains(needle)
                || (item.fullText?.lowercased().contains(needle) ?? false)
        }
        filteredCache = (itemsRevision, filter, needle, result)
        return result
    }

    var selectedItem: ClipItem? {
        guard let selectedID else { return filteredItems.first }
        return filteredItems.first { $0.id == selectedID }
    }

    func count(for filter: ClipFilter) -> Int {
        switch filter {
        case .all: return items.count
        case .text: return items.filter { $0.category == .text }.count
        case .image: return items.filter { $0.category == .image }.count
        case .link: return items.filter { $0.category == .link }.count
        case .favorite: return items.filter(\.isFavorite).count
        }
    }

    func load() {
        let generation = UUID()
        loadGeneration = generation
        phase = .loading
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.18) { [weak self] in
            guard let self, self.loadGeneration == generation else { return }
            do {
                if self.store == nil { self.store = try SQLiteClipStore() }
                self.items = try self.store?.loadAll() ?? []
                self.phase = .ready
                self.normalizeSelection()
            } catch {
                self.phase = .failed(error.localizedDescription)
                self.announce("无法读取剪贴板历史")
            }
        }
    }

    func receive(_ captured: CapturedClip) {
        guard case .ready = phase, let store else { return }
        do {
            guard try store.insert(captured) != nil else { return }
            items = try store.loadAll()
            normalizeSelection(preferFirst: true)
        } catch {
            phase = .failed(error.localizedDescription)
            announce("无法写入剪贴板历史")
        }
    }

    func setFilter(_ newFilter: ClipFilter) {
        filter = newFilter
        filteredCache = nil
        selectedID = filteredItems.first?.id
    }

    func cycleFilter(_ offset: Int) {
        let filters = ClipFilter.allCases
        guard let current = filters.firstIndex(of: filter) else { return }
        let next = (current + offset + filters.count) % filters.count
        setFilter(filters[next])
    }

    func moveSelection(_ offset: Int) {
        let visible = filteredItems
        guard !visible.isEmpty else { return }
        let current = visible.firstIndex { $0.id == selectedID } ?? 0
        let next = min(max(0, current + offset), visible.count - 1)
        selectedID = visible[next].id
    }

    func copySelected() {
        guard case .ready = phase,
              let item = selectedItem,
              let clipboardMonitor else { return }
        switch clipboardMonitor.write(item) {
        case .text(let count):
            showToast("已复制到剪贴板 · \(count) 个字符")
        case .image(let size):
            showToast("已复制图片到剪贴板 · \(size)")
        case .failure:
            showToast("复制失败，请检查剪贴板权限")
            return
        }

        if preferences.closeAfterCopy {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { [weak self] in
                self?.onRequestClose?()
            }
        }
    }

    func toggleFavorite() {
        guard case .ready = phase, let item = selectedItem, let store else { return }
        do {
            try store.setFavorite(id: item.id, isFavorite: !item.isFavorite)
            items = try store.loadAll()
            normalizeSelection()
            showToast(item.isFavorite ? "已取消收藏" : "已加入收藏")
        } catch {
            showToast("收藏状态更新失败")
        }
    }

    func deleteSelected() {
        guard case .ready = phase, let item = selectedItem, let store else { return }
        let current = filteredItems.firstIndex { $0.id == item.id } ?? 0
        do {
            try store.delete(id: item.id)
            items = try store.loadAll()
            let visible = filteredItems
            selectedID = visible.isEmpty ? nil : visible[min(current, visible.count - 1)].id
            let shortTitle = item.title.count > 14 ? String(item.title.prefix(14)) + "…" : item.title
            showToast("已删除「\(shortTitle)」")
        } catch {
            showToast("删除失败")
        }
    }

    @discardableResult
    func clearHistory() -> Int {
        let currentCount = items.count
        do {
            let deleted: Int
            if let store {
                do {
                    deleted = try store.clear()
                } catch {
                    self.store = nil
                    try SQLiteClipStore.resetDefaultStorage()
                    self.store = try SQLiteClipStore()
                    deleted = currentCount
                }
            } else {
                try SQLiteClipStore.resetDefaultStorage()
                store = try SQLiteClipStore()
                deleted = currentCount
            }
            items = []
            selectedID = nil
            phase = .ready
            settingsOpen = false
            showToast("已清空 \(deleted) 条历史记录")
            return deleted
        } catch {
            showToast("清空失败，请重试")
            return 0
        }
    }

    func showToast(_ message: String) {
        toastDismissal?.cancel()
        toastMessage = message
        announce(message)
        let work = DispatchWorkItem { [weak self] in self?.toastMessage = nil }
        toastDismissal = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5, execute: work)
    }

    private func announce(_ message: String) {
        NSAccessibility.post(
            element: NSApp as Any,
            notification: .announcementRequested,
            userInfo: [
                .announcement: message,
                .priority: NSAccessibilityPriorityLevel.medium.rawValue
            ]
        )
    }

    func prepareForPresentation() {
        selectedID = filteredItems.first?.id
    }

    private func resetSelection() {
        filteredCache = nil
        selectedID = filteredItems.first?.id
    }

    private func normalizeSelection(preferFirst: Bool = false) {
        let visible = filteredItems
        guard !visible.isEmpty else {
            selectedID = nil
            return
        }
        if preferFirst || !visible.contains(where: { $0.id == selectedID }) {
            selectedID = visible.first?.id
        }
    }

}
