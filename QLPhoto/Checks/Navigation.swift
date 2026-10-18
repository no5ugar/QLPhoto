import Cocoa

// Compile with App.swift's @main annotation removed in a temporary copy.
@main struct NavigationCheck {
    @MainActor static func main() {
        _ = NSApplication.shared
        let window = PhotoWindow(contentRect: NSRect(x: 0, y: 0, width: 700, height: 450),
                                 styleMask: [.titled, .closable], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        var directions: [Int] = []
        window.onNavigate = { directions.append($0) }
        func press(_ key: UInt16, modifiers: NSEvent.ModifierFlags = [], repeating: Bool = false) {
            let event = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: modifiers,
                                        timestamp: 0, windowNumber: window.windowNumber, context: nil,
                                        characters: "", charactersIgnoringModifiers: "",
                                        isARepeat: repeating, keyCode: key)!
            window.sendEvent(event)
        }
        press(125)
        press(126)
        press(125, repeating: true)
        precondition(directions == [1, -1, 1])
        press(125, modifiers: .command)
        press(126, modifiers: .shift)
        precondition(directions == [1, -1, 1])
        print("PASS up/down, key repeat and modifier routing")
        precondition(adjacentFinderIndex(current: 0, direction: -1, count: 3) == nil)
        precondition(adjacentFinderIndex(current: 2, direction: 1, count: 3) == nil)
        precondition(adjacentFinderIndex(current: 0, direction: 1, count: 3) == 1)
        precondition(adjacentFinderIndex(current: 2, direction: -1, count: 3) == 1)
        precondition(adjacentFinderIndex(current: 0, direction: 1, count: 0) == nil)
        print("PASS first/last boundary, both directions and empty list")
        window.close()
    }
}
