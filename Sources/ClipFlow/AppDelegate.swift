import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var preferences: PreferencesStore!
    private var model: AppModel!
    private var monitor: ClipboardMonitor!
    private var panelController: PanelController!
    private var statusController: StatusItemController!
    private var hotKeyManager: HotKeyManager?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)

        preferences = PreferencesStore()
        model = AppModel(preferences: preferences)
        monitor = ClipboardMonitor()
        panelController = PanelController(model: model)
        statusController = StatusItemController(panelController: panelController)

        model.clipboardMonitor = monitor
        monitor.isSourceExcluded = { [weak preferences] bundleID in
            preferences?.isExcluded(bundleID: bundleID) ?? false
        }
        monitor.onCapture = { [weak model] captured in
            model?.receive(captured)
        }
        model.updateManager.onUpdateAvailable = { [weak model] version in
            model?.showToast("发现新版本 \(version)，可在设置中一键更新")
        }

        do {
            hotKeyManager = try HotKeyManager { [weak panelController] in
                DispatchQueue.main.async { panelController?.toggle() }
            }
        } catch {
            model.showToast(error.localizedDescription)
        }

        model.load()
        monitor.start()
        DispatchQueue.main.asyncAfter(deadline: .now() + 3) { [weak model] in
            model?.updateManager.checkIfNeeded()
        }

        // Finder 双击启动时必须给出可见反馈。Jaimo clip 是 LSUIElement 菜单栏应用，
        // 不主动展示面板会让用户误以为应用没有打开。
        panelController.show()
    }

    func applicationShouldHandleReopen(
        _ sender: NSApplication,
        hasVisibleWindows flag: Bool
    ) -> Bool {
        panelController?.show()
        return true
    }

    func applicationWillTerminate(_ notification: Notification) {
        monitor?.stop()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }
}
