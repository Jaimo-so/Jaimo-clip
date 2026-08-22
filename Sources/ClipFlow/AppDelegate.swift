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
        panelController = PanelController(model: model, preferences: preferences)
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

        // 首次启动直接显示完整工具站完成可发现性引导。
        // 后续登录启动保持隐藏，由 ⌥Space 或菜单栏直接唤起完整工具站。
        if preferences.consumeIslandOnboardingPresentation() {
            panelController.show()
        }
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
