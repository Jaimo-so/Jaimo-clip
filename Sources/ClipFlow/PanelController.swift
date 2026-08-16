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
    private var localKeyMonitor: Any?
    private var globalMouseMonitor: Any?

    init(model: AppModel) {
        self.model = model
        panel = ClipFlowPanel(
            contentRect: NSRect(x: 0, y: 0, width: 780, height: 553),
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
        // LSUIElement apps are intentionally not activated by a nonactivating panel.
        // hidesOnDeactivate would therefore hide the panel immediately after orderFront.
        panel.hidesOnDeactivate = false
        panel.becomesKeyOnlyIfNeeded = false
        // Treating the full borderless panel as draggable makes AppKit steal drags from
        // overlay scroll bars. Window movement is handled by WindowDragRegion instead.
        panel.isMovableByWindowBackground = false
        panel.titleVisibility = .hidden
        panel.titlebarAppearsTransparent = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
        panel.minSize = NSSize(width: 520, height: 380)
        panel.maxSize = NSSize(width: 780, height: 680)
        panel.animationBehavior = .utilityWindow
        panel.isReleasedWhenClosed = false

        let hostingView = ClipFlowHostingView(rootView: ContentView(model: model))
        hostingView.translatesAutoresizingMaskIntoConstraints = false
        hostingView.wantsLayer = true
        hostingView.layer?.backgroundColor = NSColor.clear.cgColor
        hostingView.layer?.cornerRadius = WindowMetrics.cornerRadius
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
        model.prepareForPresentation()
        model.settingsOpen = openSettings
        centerOnActiveScreen()
        panel.makeKeyAndOrderFront(nil)
        panel.orderFrontRegardless()
        DispatchQueue.main.async {
            NotificationCenter.default.post(name: .clipFlowFocusSearch, object: nil)
        }
    }

    func showUpdateSettings() {
        show(openSettings: true)
        model.updateManager.checkForUpdates()
    }

    func hide() {
        model.settingsOpen = false
        panel.orderOut(nil)
    }

    private func centerOnActiveScreen() {
        let mouseLocation = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { NSMouseInRect(mouseLocation, $0.frame, false) }
            ?? NSScreen.main
            ?? NSScreen.screens.first
        guard let visible = screen?.visibleFrame else {
            panel.center()
            return
        }
        let frame = panel.frame
        let x = visible.midX - frame.width / 2
        let y = visible.midY - frame.height / 2 + min(28, visible.height * 0.04)
        panel.setFrameOrigin(NSPoint(x: x, y: y))
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
            DispatchQueue.main.async {
                self?.hide()
            }
        }
    }

    private func handleKey(keyCode: UInt16, flags: NSEvent.ModifierFlags, key: String) -> Bool {
        guard panel.isVisible else { return false }
        let command = flags.contains(.command)
        let shift = flags.contains(.shift)

        // Jaimo clip is an LSUIElement app without a conventional Edit menu. AppKit normally
        // routes these key equivalents through that menu, so explicitly forward them to the
        // key panel's first responder. This keeps paste/cut/copy/select-all working in every
        // SwiftUI TextField and TextEditor hosted by the nonactivating panel.
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

        if command && key == "f" {
            NotificationCenter.default.post(name: .clipFlowFocusSearch, object: nil)
            DispatchQueue.main.async { [weak panel] in
                panel?.firstResponder?.tryToPerform(#selector(NSText.selectAll(_:)), with: nil)
            }
            return true
        }

        if command && key == "1" {
            model.setMode(.history)
            return true
        }
        if command && key == "2" {
            model.setMode(.prompts)
            return true
        }

        if command && key == "n" {
            model.setMode(.prompts)
            model.beginCreatePrompt()
            return true
        }

        if command && key == "e", model.libraryMode == .prompts {
            model.beginEditSelectedPrompt()
            return true
        }

        if keyCode == UInt16(kVK_Escape) {
            if model.libraryMode == .history {
                if model.query.isEmpty { hide() }
                else { model.query = "" }
            } else {
                if model.promptQuery.isEmpty { hide() }
                else { model.promptQuery = "" }
            }
            return true
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
