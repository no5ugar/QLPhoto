import Cocoa
import SwiftUI
import ApplicationServices
import ServiceManagement
import UniformTypeIdentifiers

@main
struct QLPhotoApp {
    @MainActor static func main() {
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        // All windows are owned by AppDelegate; do not create an extra SwiftUI Settings scene.
        withExtendedLifetime(delegate) { app.run() }
    }
}
struct SettingsView: View {
    @ObservedObject var delegate: AppDelegate
    @AppStorage("previewBackground") private var previewBackground = PreviewBackground.system.rawValue
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("QLPhoto").font(.largeTitle.bold())
            Text("Finder 选中 JPG / HEIC / DNG，按空格查看照片与拍摄参数。")
            Text(delegate.status).foregroundStyle(.secondary)
            HStack {
                Button("启用空格预览") { delegate.enable() }
                Button("暂停") { delegate.pause() }
                Button("打开照片…") { delegate.choose() }
            }
            Divider()
            Text("图标显示").font(.headline)
            Toggle("在菜单栏显示图标", isOn: $delegate.showMenuBarIcon)
            Toggle("在 Dock 显示图标", isOn: $delegate.showDockIcon)
            Text("设置立即生效并自动保存。两个图标都关闭后，空格预览仍可运行；在“应用程序”中再次打开 QLPhoto 即可回到设置。")
                .font(.callout).foregroundStyle(.secondary)
            Divider()
            Text("预览背景").font(.headline)
            Picker("图片区域背景", selection: $previewBackground) {
                ForEach(PreviewBackground.allCases, id: \.rawValue) { style in
                    Text(style.title).tag(style.rawValue)
                }
            }.pickerStyle(.segmented)
            Text("跟随系统：浅色模式显示白色，深色模式显示黑色。设置立即生效并自动保存。")
                .font(.callout).foregroundStyle(.secondary)
            Divider()
            Text("首次使用").font(.headline)
            Text("在系统设置 → 隐私与安全 → 辅助功能中允许 QLPhoto，然后返回点击“启用空格预览”。程序需要保持运行，可以关闭此设置窗口。")
            Button("打开辅助功能设置") {
                if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") { NSWorkspace.shared.open(url) }
            }
            Divider()
            Text("开机后自动启动").font(.headline)
            Text("先将 QLPhoto 放入“应用程序”。打开系统设置 → 通用 → 登录项与扩展（部分系统称“登录项”），在“登录时打开”中点 ＋，添加 QLPhoto。这样每次开机登录账户后都会自动启动。")
                .font(.callout)
            Button("打开登录项设置") { SMAppService.openSystemSettingsLoginItems() }
            Text("请先完成辅助功能授权，并点击一次“启用空格预览”；下次启动会恢复启用状态。")
                .font(.callout).foregroundStyle(.secondary)
            Text("仅处理 Finder 中无修饰键的空格；文件重命名、搜索和其他文件继续使用系统行为。预览中按空格或 Esc 关闭。图片、元数据和键盘事件均不上传。")
                .font(.callout).foregroundStyle(.secondary)
            HStack {
                Spacer()
                Button("退出 QLPhoto") { NSApp.terminate(nil) }
            }
        }.padding(30).frame(width: 550)
    }
}
final class PhotoWindow: NSWindow {
    var onNavigate: ((Int) -> Void)?
    func presentPreview() {
        animationBehavior = .none
        makeKeyAndOrderFront(nil)
    }

    override func sendEvent(_ event: NSEvent) {
        let modifiers = event.modifierFlags.intersection([.command, .control, .option, .shift])
        if event.type == .keyDown, event.keyCode == 13, modifiers == .command {
            if !event.isARepeat { performClose(nil) }
            return
        }
        if event.type == .keyDown, event.modifierFlags.intersection([.command, .control, .option, .shift]).isEmpty {
            if event.keyCode == 125 || event.keyCode == 126 {
                onNavigate?(event.keyCode == 125 ? 1 : -1)
                return
            }
            if event.keyCode == 49 || event.keyCode == 53 {
                if !event.isARepeat { close() }
                return
            }
        }
        super.sendEvent(event)
    }
    override func cancelOperation(_ sender: Any?) { close() }
}
final class AppDelegate: NSObject, NSApplicationDelegate, ObservableObject, NSWindowDelegate {
    private let preferences: UserDefaults
    @Published var showMenuBarIcon: Bool {
        didSet { preferences.set(showMenuBarIcon, forKey: "showMenuBarIcon"); updateMenuBarIcon() }
    }
    @Published var showDockIcon: Bool {
        didSet { preferences.set(showDockIcon, forKey: "showDockIcon"); updateDockIcon() }
    }
    var settingsWindow: NSWindow?
    @Published var status = "空格预览尚未启用"
    let monitor = FinderSpace()
    var preview: PhotoWindow?
    var statusItem: NSStatusItem?
    var generation = 0
    var returnToFinder = false
    var finderNavigation: FinderNavigation?
    private(set) var previewState: PhotoLoadingState?
    private(set) var pendingURL: URL?
    private let decodeQueue: OperationQueue = {
        let queue = OperationQueue()
        queue.name = "QLPhoto.previewDecode"
        queue.qualityOfService = .userInitiated
        queue.maxConcurrentOperationCount = 1
        return queue
    }()

    override convenience init() { self.init(preferences: .standard) }
    init(preferences: UserDefaults) {
        self.preferences = preferences
        preferences.register(defaults: ["showMenuBarIcon": true, "showDockIcon": true])
        showMenuBarIcon = preferences.bool(forKey: "showMenuBarIcon")
        showDockIcon = preferences.bool(forKey: "showDockIcon")
        super.init()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        configureMainMenu()
        monitor.onStatus = { [weak self] value in self?.status = value }
        monitor.onPreview = { [weak self] url in
            guard let self else { return }
            // A second space press while the initial decode is pending cancels opening.
            if let preview = self.preview, !preview.isVisible, self.pendingURL == url {
                preview.close()
            } else {
                self.open(url, fromFinder: true)
            }
        }
        updateMenuBarIcon()
        updateDockIcon()
        if UserDefaults.standard.bool(forKey: "spacePreviewEnabled") { enable() }
        showSettings()
    }
    func configureMainMenu() {
        let main = NSMenu()
        let appItem = NSMenuItem()
        let appMenu = NSMenu(title: "QLPhoto")
        let settings = NSMenuItem(title: "设置…", action: #selector(showSettings), keyEquivalent: ",")
        settings.target = self
        appMenu.addItem(settings)
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "退出 QLPhoto", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        appItem.submenu = appMenu
        main.addItem(appItem)
        let fileItem = NSMenuItem()
        let fileMenu = NSMenu(title: "文件")
        fileMenu.addItem(withTitle: "关闭窗口", action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w")
        fileItem.submenu = fileMenu
        main.addItem(fileItem)
        let editItem = NSMenuItem()
        let editMenu = NSMenu(title: "编辑")
        editMenu.addItem(withTitle: "复制", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        editMenu.addItem(withTitle: "全选", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        editItem.submenu = editMenu
        main.addItem(editItem)
        NSApp.mainMenu = main
    }
    func updateDockIcon() {
        NSApp.setActivationPolicy(showDockIcon ? .regular : .accessory)
    }
    func updateMenuBarIcon() {
        guard showMenuBarIcon else {
            if let statusItem { NSStatusBar.system.removeStatusItem(statusItem) }
            statusItem = nil
            return
        }
        guard statusItem == nil else { return }
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.button?.image = NSImage(systemSymbolName: "photo.on.rectangle", accessibilityDescription: "QLPhoto")
        let menu = NSMenu()
        for (title, action) in [("设置…", #selector(showSettings)), ("启用空格预览", #selector(enable)), ("暂停空格预览", #selector(pause)), ("打开照片…", #selector(choose))] {
            let entry = NSMenuItem(title: title, action: action, keyEquivalent: ""); entry.target = self; menu.addItem(entry)
        }
        menu.addItem(.separator())
        let quit = NSMenuItem(title: "退出 QLPhoto", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        menu.addItem(quit); item.menu = menu; statusItem = item
    }
    @objc func showSettings() {
        if settingsWindow == nil {
            let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 610, height: 760),
                                  styleMask: [.titled, .closable, .miniaturizable], backing: .buffered, defer: false)
            window.title = "QLPhoto"
            window.isReleasedWhenClosed = false
            window.contentViewController = NSHostingController(rootView:
                ScrollView { SettingsView(delegate: self) }.frame(width: 610, height: 760))
            window.center()
            settingsWindow = window
        }
        NSApp.activate(ignoringOtherApps: true)
        settingsWindow?.makeKeyAndOrderFront(nil)
    }
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        showSettings()
        return false
    }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }
    @objc func enable() {
        UserDefaults.standard.set(true, forKey: "spacePreviewEnabled")
        guard AXIsProcessTrusted() else {
            status = "请先在系统设置中授予 QLPhoto 辅助功能权限"
            let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
            _ = AXIsProcessTrustedWithOptions(options)
            return
        }
        status = monitor.start() ? "空格预览已启用 · 仅在 Finder 选中图片时生效" : "无法启动按键处理，请确认辅助功能权限后重新启动 QLPhoto"
    }
    @objc func pause() {
        monitor.stop(); UserDefaults.standard.set(false, forKey: "spacePreviewEnabled"); status = "空格预览已暂停"
    }
    @objc func choose() {
        let panel = NSOpenPanel(); panel.allowedContentTypes = [.jpeg, .heic, .heif, UTType(importedAs: "com.adobe.raw-image")]
        if panel.runModal() == .OK, let url = panel.url { open(url) }
    }
    func application(_ sender: NSApplication, openFiles filenames: [String]) {
        if let filename = filenames.first { open(URL(fileURLWithPath: filename)) }
        sender.reply(toOpenOrPrint: .success)
    }
    func open(_ url: URL, fromFinder: Bool = false, navigating: Bool = false) {
        decodeQueue.cancelAllOperations()
        if !navigating {
            finderNavigation = fromFinder ? FinderNavigation.capture(selected: url) : nil
        }
        generation += 1
        let request = generation
        returnToFinder = fromFinder
        let window: PhotoWindow
        if let existing = preview { window = existing } else {
            window = PhotoWindow(contentRect: NSRect(x: 0, y: 0, width: 1100, height: 720), styleMask: [.titled, .closable, .resizable, .miniaturizable], backing: .buffered, defer: false)
            window.isReleasedWhenClosed = false; window.delegate = self; preview = window
            let screen = (fromFinder ? finderPreviewScreen() : nil)
                ?? NSScreen.screens.first(where: { $0.frame.contains(NSEvent.mouseLocation) })
                ?? NSScreen.main
            if let screen {
                let saved = preferences.string(forKey: previewFrameKey(screen)).map(NSRectFromString)
                window.setFrame(fittedPreviewFrame(saved: saved, size: window.frame.size, visible: screen.visibleFrame), display: false)
            }
        }
        window.onNavigate = { [weak self] direction in self?.navigate(direction) }
        if previewState == nil {
            previewState = PhotoLoadingState()
        }
        guard let loading = previewState else { return }
        pendingURL = url
        let regular = (try? url.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true
        guard regular, ["jpg", "jpeg", "heic", "heif", "dng"].contains(url.pathExtension.lowercased()) else {
            window.title = url.lastPathComponent
            showNavigationMessage("暂不支持预览此项目", detail: url.lastPathComponent + "\n按 ↑ / ↓ 继续切换，空格或 Esc 关闭")
            return
        }
        let operation = BlockOperation()
        operation.addExecutionBlock { [weak operation, weak self, weak window] in
            guard let operation, !operation.isCancelled else { return }
            let result = Result { try Photo.load(url) }
            guard !operation.isCancelled else { return }
            DispatchQueue.main.async { [weak self, weak window] in
                guard let self, let window, self.generation == request, self.preview === window else { return }
                // Commit the image and its information in one main-thread turn. Never clear
                // the visible photo while decoding or rebuild its hosting controller.
                loading.error = nil
                switch result {
                case .success(let photo): loading.photo = photo
                case .failure(let error):
                    loading.photo = nil
                    loading.error = error.localizedDescription
                }
                self.pendingURL = nil
                if window.contentViewController == nil {
                    self.setPreviewContent(PhotoLoadingView(state: loading), in: window)
                }
                window.title = url.lastPathComponent
                if !window.isVisible {
                    window.contentView?.layoutSubtreeIfNeeded()
                    NSApp.activate(ignoringOtherApps: true)
                    window.presentPreview()
                }
            }
        }
        decodeQueue.addOperation(operation)
    }
    private func setPreviewContent<Content: View>(_ content: Content, in window: PhotoWindow) {
        let frame = window.frame
        window.contentViewController = NSHostingController(rootView: content)
        window.setFrame(frame, display: false)
    }
    private func previewFrameKey(_ screen: NSScreen) -> String {
        if let number = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber,
           let uuid = CGDisplayCreateUUIDFromDisplayID(number.uint32Value) {
            return "previewFrame." + (CFUUIDCreateString(nil, uuid.takeRetainedValue()) as String)
        }
        return "previewFrame." + screen.localizedName
    }
    private func savePreviewFrame() {
        guard let preview, let screen = preview.screen else { return }
        preferences.set(NSStringFromRect(preview.frame), forKey: previewFrameKey(screen))
    }
    func windowDidMove(_ notification: Notification) {
        guard let window = notification.object as? NSWindow, window === preview, window.isVisible else { return }
        savePreviewFrame()
    }
    func windowDidEndLiveResize(_ notification: Notification) {
        guard notification.object as? NSWindow === preview else { return }
        savePreviewFrame()
    }
    func navigate(_ direction: Int) {
        guard let finderNavigation else {
            showNavigationMessage("无法读取 Finder 文件列表", detail: "请在 Finder 列表视图中选中照片，再按空格打开预览。\n按空格或 Esc 关闭")
            return
        }
        switch finderNavigation.move(by: direction) {
        case .selected(let url): open(url, fromFinder: true, navigating: true)
        case .boundary: NSSound.beep()
        case .unavailable:
            generation += 1
            showNavigationMessage("无法切换 Finder 选中项", detail: "列表可能已变化或当前视图不可访问。请关闭预览后重新选择文件。")
        }
    }
    func showNavigationMessage(_ title: String, detail: String) {
        decodeQueue.cancelAllOperations()
        generation += 1
        pendingURL = nil
        guard let preview, let state = previewState else { return }
        state.photo = nil
        state.error = title + "\n" + detail
        if preview.contentViewController == nil {
            setPreviewContent(PhotoLoadingView(state: state), in: preview)
        }
        if !preview.isVisible {
            NSApp.activate(ignoringOtherApps: true)
            preview.presentPreview()
        }
    }

    func windowWillClose(_ notification: Notification) {
        guard notification.object as? NSWindow === preview else { return }
        savePreviewFrame()
        decodeQueue.cancelAllOperations()
        generation += 1; preview = nil; previewState = nil; pendingURL = nil; finderNavigation = nil
        if returnToFinder {
            NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.finder").first?.activate(options: [])
        }
    }
}
