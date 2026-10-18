import Cocoa

// Build with a temporary App.swift copy with its @main annotation removed.
@main struct WindowMotionCheck {
    @MainActor static func main() async throws {
        _ = NSApplication.shared
        let window = PhotoWindow(contentRect: NSRect(x: 100, y: 100, width: 700, height: 450),
                                 styleMask: [.titled, .closable, .resizable], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        let frame = window.frame
        window.presentPreview()
        try await Task.sleep(nanoseconds: 400_000_000)
        precondition(window.isVisible && window.alphaValue == 1 && window.frame == frame)
        let commandW = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: .command,
                                       timestamp: 0, windowNumber: window.windowNumber, context: nil,
                                       characters: "w", charactersIgnoringModifiers: "w", isARepeat: false, keyCode: 13)!
        window.sendEvent(commandW)
        window.close() // Repeated close must not schedule another close animation.
        try await Task.sleep(nanoseconds: 400_000_000)
        precondition(!window.isVisible && window.frame == frame)
        window.presentPreview()
        window.close()
        window.presentPreview() // Reopening during close must invalidate the stale completion.
        try await Task.sleep(nanoseconds: 400_000_000)
        precondition(window.isVisible && window.alphaValue == 1 && window.frame == frame)
        window.cancelOperation(nil)
        try await Task.sleep(nanoseconds: 400_000_000)
        precondition(!window.isVisible)
        print("PASS open, Command-W, repeated close, reopen during close, Esc and stable frame")
    }
}
