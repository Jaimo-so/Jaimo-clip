import AppKit
import Carbon
import ClipFlowKit
import SwiftUI

final class ClipFlowPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

final class ClipFlowHostingView<Content: View>: NSHostingView<Content> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
        true
    }
}

@MainActor
final class PanelController: NSObject, NSWindowDelegate {
    let panel: ClipFlowPanel
    private let model: AppModel
    private let shellModel: IslandShellModel
    private let homeModel: HomeDashboardModel
    private let applicationsModel: ApplicationsModel
    private var localKeyMonitor: Any?
    private var globalMouseMonitor: Any?

    private let expandedTargetSize = NSSize(width: 948, height: 680)

    init(model: AppModel, preferences: PreferencesStore) {
        self.model = model
        shellModel = IslandShellModel()
        homeModel = HomeDashboardModel()
        applicationsModel = ApplicationsModel()
        panel = ClipFlowPanel(
            contentRect: NSRect(origin: .zero, size: expandedTargetSize),
            styleMask: [
                .borderless,
                .nonactivatingPanel,
                .hudWindow,
                .utilityWindow,
                .resizable,
                .fullSizeContentView
            ],
            backing: .buffered,
            defer: false
        )
        super.init()

        panel.delegate = self
        panel.level = .floating
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.hidesOnDeactivate = false
        panel.becomesKeyOnlyIfNeeded = false
        panel.isMovableByWindowBackground = false
        panel.titleVisibility = .hidden
        panel.titlebarAppearsTransparent = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
        panel.animationBehavior = .none
        panel.isReleasedWhenClosed = false

        let rootView = IslandRootView(
            model: model,
            shell: shellModel,
            homeModel: homeModel,
            applicationsModel: applicationsModel,
            onClose: { [weak self] in self?.hide() }
        )
        let hostingView = ClipFlowHostingView(rootView: rootView)
        hostingView.translatesAutoresizingMaskIntoConstraints = false
        hostingView.wantsLayer = true
        hostingView.layer?.backgroundColor = NSColor.clear.cgColor
        hostingView.layer?.cornerRadius = 28
        hostingView.layer?.cornerCurve = .continuous
        hostingView.layer?.masksToBounds = true
        panel.contentView = hostingView

        model.onRequestClose = { [weak self] in self?.hide() }
        installKeyMonitor()
        installOutsideClickMonitor()
    }

    deinit {
        if let localKeyMonitor { NSEvent.removeMonitor(localKeyMonitor) }
        if let globalMouseMonitor { NSEvent.removeMonitor(globalMouseMonitor) }
    }

    func toggle() {
        panel.isVisible ? hide() : show()
    }

    func show(openSettings: Bool = false) {
        showExpanded(destination: shellModel.destination, openSettings: openSettings)
    }

    func showExpanded(
        destination: ToolDestination? = nil,
        openSettings: Bool = false
    ) {
        if let destination { selectDestination(destination) }
        model.settingsOpen = openSettings
        model.prepareForPresentation()
        applicationsModel.loadIfNeeded()
        present(size: expandedSizeForActiveScreen())

        if shellModel.destination == .prompts || shellModel.destination == .clipboard {
            DispatchQueue.main.async {
                NotificationCenter.default.post(name: .clipFlowFocusSearch, object: nil)
            }
        }
    }

    func showUpdateSettings() {
        showExpanded(openSettings: true)
        model.updateManager.checkForUpdates()
    }

    func hide() {
        model.settingsOpen = false
        panel.orderOut(nil)
    }

    private func present(size: NSSize) {
        positionAtTop(size: size)
        panel.makeKeyAndOrderFront(nil)
        panel.orderFrontRegardless()
    }

    private func expandedSizeForActiveScreen() -> NSSize {
        guard let visible = activeScreen()?.visibleFrame else { return expandedTargetSize }
        return NSSize(
            width: min(expandedTargetSize.width, max(520, visible.width - 24)),
            height: min(expandedTargetSize.height, max(420, visible.height - 16))
        )
    }

    private func positionAtTop(size: NSSize) {
        guard let visible = activeScreen()?.visibleFrame else {
            panel.setContentSize(size)
            panel.center()
            return
        }
        let fittedSize = NSSize(
            width: min(size.width, visible.width - 12),
            height: min(size.height, visible.height - 12)
        )
        panel.minSize = fittedSize
        panel.maxSize = fittedSize
        let origin = NSPoint(
            x: visible.midX - fittedSize.width / 2,
            y: visible.maxY - fittedSize.height - 8
        )
        panel.setFrame(NSRect(origin: origin, size: fittedSize), display: true)
    }

    private func activeScreen() -> NSScreen? {
        let mouseLocation = NSEvent.mouseLocation
        return NSScreen.screens.first { NSMouseInRect(mouseLocation, $0.frame, false) }
            ?? NSScreen.main
            ?? NSScreen.screens.first
    }

    private func selectDestination(_ destination: ToolDestination) {
        shellModel.destination = destination
        switch destination {
        case .prompts: model.setMode(.prompts)
        case .clipboard: model.setMode(.history)
        case .home, .applications: break
        }
    }

    private func installKeyMonitor() {
        localKeyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self else { return event }
            let keyCode = event.keyCode
            let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
            let key = event.charactersIgnoringModifiers?.lowercased() ?? ""
            let handled = MainActor.assumeIsolated {
                self.handleKey(keyCode: keyCode, flags: flags, key: key)
            }
            return handled ? nil : event
        }
    }

    private func installOutsideClickMonitor() {
        globalMouseMonitor = NSEvent.addGlobalMonitorForEvents(
            matching: [.leftMouseDown, .rightMouseDown]
        ) { [weak self] _ in
            DispatchQueue.main.async { self?.hide() }
        }
    }

    private func handleKey(keyCode: UInt16, flags: NSEvent.ModifierFlags, key: String) -> Bool {
        guard panel.isVisible else { return false }
        let command = flags.contains(.command)
        let shift = flags.contains(.shift)

        if command, routeStandardTextCommand(key) {
            return true
        }

        if command && key == "," {
            guard !model.promptEditorOpen,
                  !model.promptRunnerOpen,
                  !model.promptDeleteConfirmationOpen else { return true }
            model.settingsOpen.toggle()
            return true
        }

        if model.promptDeleteConfirmationOpen {
            if keyCode == UInt16(kVK_Escape) {
                model.promptDeleteConfirmationOpen = false
                return true
            }
            return false
        }

        if model.promptRunnerOpen {
            if keyCode == UInt16(kVK_Escape) {
                model.promptRunnerOpen = false
                return true
            }
            return false
        }

        if model.promptEditorOpen {
            if keyCode == UInt16(kVK_Escape) {
                model.promptEditorOpen = false
                return true
            }
            if command && key == "s" {
                model.savePromptDraft()
                return true
            }
            return false
        }

        if model.settingsOpen {
            if keyCode == UInt16(kVK_Escape) {
                model.settingsOpen = false
                return true
            }
            return false
        }

        if command, let destination = destinationForShortcut(key) {
            showExpanded(destination: destination)
            return true
        }

        if command && key == "f" {
            switch shellModel.destination {
            case .applications:
                NotificationCenter.default.post(name: .jaimoFocusApplicationSearch, object: nil)
                return true
            case .prompts, .clipboard:
                NotificationCenter.default.post(name: .clipFlowFocusSearch, object: nil)
                DispatchQueue.main.async { [weak panel] in
                    panel?.firstResponder?.tryToPerform(#selector(NSText.selectAll(_:)), with: nil)
                }
                return true
            case .home:
                return false
            }
        }

        if command && key == "n" {
            showExpanded(destination: .prompts)
            model.beginCreatePrompt()
            return true
        }

        if command && key == "e", shellModel.destination == .prompts {
            model.beginEditSelectedPrompt()
            return true
        }

        if keyCode == UInt16(kVK_Escape) {
            if shellModel.destination == .clipboard, !model.query.isEmpty {
                model.query = ""
            } else if shellModel.destination == .prompts, !model.promptQuery.isEmpty {
                model.promptQuery = ""
            } else {
                hide()
            }
            return true
        }

        guard shellModel.destination == .prompts || shellModel.destination == .clipboard else {
            return false
        }
        guard case .ready = model.phase else { return false }

        if command && key == "s" {
            model.toggleFavorite()
            return true
        }
        if command && (keyCode == UInt16(kVK_Delete) || keyCode == UInt16(kVK_ForwardDelete)) {
            model.deleteSelected()
            return true
        }

        switch keyCode {
        case UInt16(kVK_UpArrow):
            model.moveSelection(-1)
            return true
        case UInt16(kVK_DownArrow):
            model.moveSelection(1)
            return true
        case UInt16(kVK_LeftArrow) where model.focusArea == .tabs:
            model.cycleFilter(-1)
            return true
        case UInt16(kVK_RightArrow) where model.focusArea == .tabs:
            model.cycleFilter(1)
            return true
        case UInt16(kVK_Home) where model.focusArea == .tabs:
            if model.libraryMode == .history { model.setFilter(.all) }
            else { model.setPromptScope(.all) }
            return true
        case UInt16(kVK_End) where model.focusArea == .tabs:
            if model.libraryMode == .history { model.setFilter(.favorite) }
            else if let last = model.promptScopes.last { model.setPromptScope(last) }
            return true
        case UInt16(kVK_Tab) where model.focusArea == .other:
            model.cycleFilter(shift ? -1 : 1)
            return true
        default:
            return false
        }
    }

    private func destinationForShortcut(_ key: String) -> ToolDestination? {
        switch key {
        case "1": return .home
        case "2": return .applications
        case "3": return .prompts
        case "4": return .clipboard
        default: return nil
        }
    }

    private func routeStandardTextCommand(_ key: String) -> Bool {
        let action: Selector
        switch key {
        case "a": action = #selector(NSText.selectAll(_:))
        case "c": action = #selector(NSText.copy(_:))
        case "v": action = #selector(NSText.paste(_:))
        case "x": action = #selector(NSText.cut(_:))
        default: return false
        }
        guard let responder = panel.firstResponder else { return false }
        return responder.tryToPerform(action, with: nil)
    }
}
