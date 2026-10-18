import Cocoa
import ApplicationServices

/// Finder-only interception. Never records or transmits keyboard input.
final class FinderSpace {
    var onStatus: ((String) -> Void)?
    var onPreview: ((URL) -> Void)?
    private var tap: CFMachPort?
    private var source: CFRunLoopSource?
    private var swallowedSpace = false
    var running: Bool { tap != nil }

    func start() -> Bool {
        if running { return true }
        guard AXIsProcessTrusted() else { return false }
        let mask = (CGEventMask(1) << CGEventType.keyDown.rawValue) | (CGEventMask(1) << CGEventType.keyUp.rawValue)
        let callback: CGEventTapCallBack = { _, type, event, context in
            guard let context else { return Unmanaged.passUnretained(event) }
            let monitor = Unmanaged<FinderSpace>.fromOpaque(context).takeUnretainedValue()
            if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
                if let tap = monitor.tap { CGEvent.tapEnable(tap: tap, enable: true) }
                return Unmanaged.passUnretained(event)
            }
            guard event.getIntegerValueField(.keyboardEventKeycode) == 49 else { return Unmanaged.passUnretained(event) }
            if type == .keyUp, monitor.swallowedSpace {
                monitor.swallowedSpace = false
                return nil
            }
            guard type == .keyDown,
                  NSWorkspace.shared.frontmostApplication?.bundleIdentifier == "com.apple.finder",
                  event.flags.intersection([.maskCommand, .maskControl, .maskAlternate, .maskShift]).isEmpty else {
                return Unmanaged.passUnretained(event)
            }
            if event.getIntegerValueField(.keyboardEventAutorepeat) != 0 {
                return monitor.swallowedSpace ? nil : Unmanaged.passUnretained(event)
            }
            guard let url = selectedFinderImage(report: { monitor.onStatus?($0) }) else { return Unmanaged.passUnretained(event) }
            monitor.swallowedSpace = true
            DispatchQueue.main.async { monitor.onPreview?(url) }
            return nil
        }
        guard let tap = CGEvent.tapCreate(tap: .cgSessionEventTap, place: .headInsertEventTap,
                                          options: .defaultTap, eventsOfInterest: mask,
                                          callback: callback, userInfo: Unmanaged.passUnretained(self).toOpaque()) else { return false }
        self.tap = tap
        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        self.source = source
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        return true
    }

    func stop() {
        if let tap { CGEvent.tapEnable(tap: tap, enable: false); CFMachPortInvalidate(tap) }
        if let source { CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes) }
        tap = nil; source = nil; swallowedSpace = false
    }
    deinit { stop() }
}

private func attribute(_ element: AXUIElement, _ name: CFString) -> CFTypeRef? {
    var value: CFTypeRef?
    guard AXUIElementCopyAttributeValue(element, name, &value) == .success else { return nil }
    return value
}

/// Finder AX coordinates have a top-left origin on the primary display.
func finderPreviewScreen() -> NSScreen? {
    guard let finder = NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.finder").first else { return nil }
    let app = AXUIElementCreateApplication(finder.processIdentifier)
    AXUIElementSetMessagingTimeout(app, 0.02)
    guard let raw = attribute(app, kAXFocusedWindowAttribute as CFString) else { return nil }
    let window = raw as! AXUIElement
    guard let p = attribute(window, kAXPositionAttribute as CFString), CFGetTypeID(p) == AXValueGetTypeID(),
          let s = attribute(window, kAXSizeAttribute as CFString), CFGetTypeID(s) == AXValueGetTypeID() else { return nil }
    var point = CGPoint.zero
    var size = CGSize.zero
    guard AXValueGetValue(p as! AXValue, .cgPoint, &point), AXValueGetValue(s as! AXValue, .cgSize, &size),
          let primary = NSScreen.screens.first else { return nil }
    let rect = CGRect(x: point.x, y: primary.frame.maxY - point.y - size.height, width: size.width, height: size.height)
    return NSScreen.screens.filter { $0.frame.intersects(rect) }.max {
        let a = $0.frame.intersection(rect), b = $1.frame.intersection(rect)
        return a.width * a.height < b.width * b.height
    }
}

func fittedPreviewFrame(saved: CGRect?, size: CGSize, visible: CGRect) -> CGRect {
    let valid = saved.flatMap { rect -> CGRect? in
        [rect.minX, rect.minY, rect.width, rect.height].allSatisfy(\.isFinite) && rect.width > 0 && rect.height > 0 ? rect : nil
    }
    let width = min(visible.width, max(700, valid?.width ?? size.width))
    let height = min(visible.height, max(450, valid?.height ?? size.height))
    let x = valid?.minX ?? (visible.midX - width / 2)
    let y = valid?.minY ?? (visible.midY - height / 2)
    return CGRect(x: min(max(x, visible.minX), visible.maxX - width),
                  y: min(max(y, visible.minY), visible.maxY - height), width: width, height: height)
}

/// The accessibility children/rows preserve Finder's presented order, including unsupported files.
/// Keep the originating container rather than following whichever Finder window is frontmost later.
final class FinderNavigation {
    private let container: AXUIElement
    private var currentURL: URL

    private init(container: AXUIElement, url: URL) {
        self.container = container
        currentURL = url
    }

    static func capture(selected url: URL) -> FinderNavigation? {
        guard let finder = NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.finder").first else { return nil }
        let app = AXUIElementCreateApplication(finder.processIdentifier)
        AXUIElementSetMessagingTimeout(app, 0.02)
        guard let raw = attribute(app, kAXFocusedWindowAttribute as CFString) else { return nil }
        let window = raw as! AXUIElement
        let deadline = Date().addingTimeInterval(0.5)
        var visited = 0
        func search(_ element: AXUIElement) -> AXUIElement? {
            visited += 1
            guard visited < 1200, Date() < deadline else { return nil }
            let role = attribute(element, kAXRoleAttribute as CFString) as? String
            if ["AXList", "AXOutline", "AXTable"].contains(role ?? ""),
               let selected = (attribute(element, kAXSelectedChildrenAttribute as CFString) as? [AXUIElement])
                    ?? (attribute(element, "AXSelectedRows" as CFString) as? [AXUIElement]),
               selected.contains(where: { itemURL($0) == url }) {
                return element
            }
            for child in attribute(element, kAXChildrenAttribute as CFString) as? [AXUIElement] ?? [] {
                if let found = search(child) { return found }
            }
            return nil
        }
        guard let container = search(window) else { return nil }
        return FinderNavigation(container: container, url: url)
    }

    enum MoveResult { case selected(URL), boundary, unavailable }

    func move(by direction: Int) -> MoveResult {
        let rows = (attribute(container, "AXRows" as CFString) as? [AXUIElement])
            ?? (attribute(container, kAXChildrenAttribute as CFString) as? [AXUIElement]) ?? []
        // Unknown rows remain in the sequence so we never silently skip a Finder item.
        let urls = rows.map { Self.itemURL($0) }
        guard let index = urls.firstIndex(where: { $0 == currentURL }) else { return .unavailable }
        guard let next = adjacentFinderIndex(current: index, direction: direction, count: rows.count) else { return .boundary }
        guard let url = urls[next] else { return .unavailable }
        let row = rows[next]
        var result = AXUIElementSetAttributeValue(container, kAXSelectedChildrenAttribute as CFString, [row] as CFArray)
        if result != .success {
            result = AXUIElementSetAttributeValue(container, "AXSelectedRows" as CFString, [row] as CFArray)
        }
        if result != .success {
            result = AXUIElementSetAttributeValue(row, kAXSelectedAttribute as CFString, kCFBooleanTrue)
        }
        guard result == .success else { return .unavailable }
        // Do not report success merely because a settable attribute accepted the request.
        let selected = (attribute(container, kAXSelectedChildrenAttribute as CFString) as? [AXUIElement])
            ?? (attribute(container, "AXSelectedRows" as CFString) as? [AXUIElement]) ?? []
        guard selected.contains(where: { Self.itemURL($0) == url }) else { return .unavailable }
        _ = AXUIElementPerformAction(row, "AXScrollToVisible" as CFString)
        currentURL = url
        return .selected(url)
    }

    private static func itemURL(_ element: AXUIElement, depth: Int = 0) -> URL? {
        guard depth < 5 else { return nil }
        if let raw = attribute(element, kAXURLAttribute as CFString) {
            if let url = (raw as? URL) ?? (raw as? String).flatMap(URL.init(string:)), url.isFileURL { return url }
        }
        let children = attribute(element, kAXChildrenAttribute as CFString) as? [AXUIElement] ?? []
        for child in children {
            if let url = itemURL(child, depth: depth + 1) { return url }
        }
        return nil
    }
}

func adjacentFinderIndex(current: Int, direction: Int, count: Int) -> Int? {
    guard count > 0, current >= 0, current < count, direction == -1 || direction == 1 else { return nil }
    let next = current + direction
    return next >= 0 && next < count ? next : nil
}

/// Bounded, fresh AX read at the key press; failure leaves system Quick Look untouched.
func selectedFinderImage(report: (String) -> Void = { _ in }) -> URL? {
    guard let finder = NSWorkspace.shared.frontmostApplication, finder.bundleIdentifier == "com.apple.finder" else { return nil }
    let app = AXUIElementCreateApplication(finder.processIdentifier)
    AXUIElementSetMessagingTimeout(app, 0.02)
    let focusedValue = attribute(app, kAXFocusedUIElementAttribute as CFString)
    if let focus = focusedValue {
        let focused = focus as! AXUIElement
        let role = attribute(focused, kAXRoleAttribute as CFString) as? String
        if role == kAXTextFieldRole || role == kAXTextAreaRole || role == kAXComboBoxRole { report("空格保留系统行为：当前焦点为输入框（\(role ?? "未知")）"); return nil }
    }
    guard let value = attribute(app, kAXFocusedWindowAttribute as CFString) else { return nil }
    let window = value as! AXUIElement
    // Sheets such as Go To Folder must retain their normal keyboard behavior.
    if let sheets = attribute(window, "AXSheets" as CFString) as? [AXUIElement], !sheets.isEmpty { return nil }
    let deadline = Date().addingTimeInterval(0.3)
    var visited = 0
    func imageURL(_ element: AXUIElement, depth: Int) -> URL? {
        guard depth < 5, Date() < deadline else { return nil }
        if let raw = attribute(element, kAXURLAttribute as CFString) {
            let url = (raw as? URL) ?? (raw as? String).flatMap(URL.init(string:))
            if let url, url.isFileURL, ["jpg", "jpeg", "heic", "heif", "dng"].contains(url.pathExtension.lowercased()),
               (try? url.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true { return url }
        }
        for child in attribute(element, kAXChildrenAttribute as CFString) as? [AXUIElement] ?? [] {
            if let url = imageURL(child, depth: depth + 1) { return url }
        }
        return nil
    }
    func search(_ element: AXUIElement) -> URL? {
        visited += 1
        guard visited <= 600, Date() < deadline else { return nil }
        if let selected = attribute(element, kAXSelectedChildrenAttribute as CFString) as? [AXUIElement] {
            for child in selected { if let url = imageURL(child, depth: 0) { return url } }
        }
        if (attribute(element, kAXSelectedAttribute as CFString) as? Bool) == true,
           let url = imageURL(element, depth: 0) { return url }
        for child in attribute(element, kAXChildrenAttribute as CFString) as? [AXUIElement] ?? [] {
            if let url = search(child) { return url }
        }
        return nil
    }
    if let focus = focusedValue {
        let focused = focus as! AXUIElement
        if let url = search(focused) { return url }
        var current = focused
        for _ in 0..<5 {
            guard Date() < deadline, let parentValue = attribute(current, kAXParentAttribute as CFString) else { break }
            current = parentValue as! AXUIElement
            if let selected = attribute(current, kAXSelectedChildrenAttribute as CFString) as? [AXUIElement] {
                for child in selected { if let url = imageURL(child, depth: 0) { return url } }
            }
        }
    }
    let result = search(window)
    if result == nil { report("未找到选中图片：检查了 \(visited) 个节点，\(Date() < deadline ? "未超时" : "读取超时")") }
    return result
}
