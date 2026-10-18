import Cocoa

// Build with a temporary App.swift copy with its @main annotation removed.
@main struct WindowMotionCheck {
    @MainActor static func main() async throws {
        _ = NSApplication.shared
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        let window = PhotoWindow(contentRect: NSRect(x: 100, y: 100, width: 700, height: 450),
                                 styleMask: [.titled, .closable, .resizable], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        let frame = window.frame
        window.presentPreview()
        precondition(window.animationBehavior == .none)
        try await Task.sleep(nanoseconds: 400_000_000)
        precondition(window.isVisible && window.alphaValue == 1 && window.frame == frame)
        let commandW = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: .command,
                                       timestamp: 0, windowNumber: window.windowNumber, context: nil,
                                       characters: "w", charactersIgnoringModifiers: "w", isARepeat: false, keyCode: 13)!
        window.sendEvent(commandW)
        window.close() // Repeated close must remain safe.
        try await Task.sleep(nanoseconds: 400_000_000)
        precondition(!window.isVisible && window.frame == frame)
        window.presentPreview()
        window.close()
        window.presentPreview() // Reopening after an immediate close must remain visible.
        try await Task.sleep(nanoseconds: 400_000_000)
        precondition(window.isVisible && window.alphaValue == 1 && window.frame == frame)
        window.cancelOperation(nil)
        window.close() // Repeated immediate close must remain safe.
        try await Task.sleep(nanoseconds: 400_000_000)
        precondition(!window.isVisible)
        window.presentPreview()
        try await Task.sleep(nanoseconds: 50_000_000)
        window.close() // A quick open and close must not reopen later.
        try await Task.sleep(nanoseconds: 500_000_000)
        precondition(!window.isVisible && window.frame == frame && window.alphaValue == 1)
        print("PASS open, Command-W, repeated close, immediate reopen, Esc and stable frame")
    }
}
