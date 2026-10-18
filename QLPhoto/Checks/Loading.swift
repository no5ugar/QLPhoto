import Cocoa
import SwiftUI

// Build with a temporary App.swift copy that omits its @main annotation.
@main struct LoadingCheck {
    @MainActor static func main() async throws {
        _ = NSApplication.shared
        let raw = URL(fileURLWithPath: CommandLine.arguments[1])
        let jpeg = URL(fileURLWithPath: CommandLine.arguments[2])
        if let image = Photo.quickPreview(raw) {
            precondition(image.size.width > 0 && image.size.height > 0)
            print("PASS embedded DNG preview: \(image.size)")
        } else { print("DNG has no available embedded thumbnail; skeleton fallback") }
        let suite = "QLPhoto.LoadingCheck." + UUID().uuidString
        let preferences = UserDefaults(suiteName: suite)!
        defer { preferences.removePersistentDomain(forName: suite) }
        let delegate = AppDelegate(preferences: preferences)
        delegate.open(raw)
        let originalWindow = delegate.preview!
        let frame = originalWindow.frame
        delegate.open(jpeg)
        let host = delegate.preview!.contentViewController as! NSHostingController<PhotoLoadingView>
        let state = host.rootView.state
        for _ in 0..<200 {
            if state.photo != nil || state.error != nil { break }
            try await Task.sleep(nanoseconds: 50_000_000)
        }
        precondition(state.error == nil && state.photo?.url == jpeg)
        try await Task.sleep(nanoseconds: 300_000_000)
        precondition(state.photo?.url == jpeg && delegate.preview === originalWindow)
        precondition(originalWindow.frame == frame)
        print("PASS rapid DNG-to-JPEG switch, final ownership and stable window frame")
        delegate.open(raw)
        originalWindow.close()
        try await Task.sleep(nanoseconds: 300_000_000)
        precondition(delegate.preview == nil)
        print("PASS closing preview cancels queued work without reopening the window")
    }
}
