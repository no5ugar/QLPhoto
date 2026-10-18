import Cocoa
import SwiftUI

// Build with a temporary App.swift copy that omits its @main annotation.
@main struct LoadingCheck {
    @MainActor static func main() async throws {
        _ = NSApplication.shared
        NSApp.setActivationPolicy(.regular)
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("QLPhoto.LoadingCheck." + UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        func fixture(_ name: String, width: Int, height: Int, color: NSColor) throws -> URL {
            let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8,
                bytesPerRow: width * 4, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
            context.setFillColor(color.cgColor)
            context.fill(CGRect(x: 0, y: 0, width: width, height: height))
            let bitmap = NSBitmapImageRep(cgImage: context.makeImage()!)
            let url = directory.appendingPathComponent(name)
            try bitmap.representation(using: .jpeg, properties: [:])!.write(to: url)
            return url
        }
        let landscape = try fixture("landscape.jpg", width: 1800, height: 900, color: .red)
        let portrait = try fixture("portrait.jpg", width: 900, height: 1800, color: .blue)
        let first = CommandLine.arguments.count > 1 ? URL(fileURLWithPath: CommandLine.arguments[1]) : landscape
        let second = CommandLine.arguments.count > 2 ? URL(fileURLWithPath: CommandLine.arguments[2]) : portrait
        let broken = directory.appendingPathComponent("broken.jpg")
        try Data("invalid image".utf8).write(to: broken)
        let suite = "QLPhoto.LoadingCheck." + UUID().uuidString
        let preferences = UserDefaults(suiteName: suite)!
        defer { preferences.removePersistentDomain(forName: suite) }
        let delegate = AppDelegate(preferences: preferences)
        func waitForResult() async throws {
            for _ in 0..<400 {
                if delegate.pendingURL == nil { return }
                try await Task.sleep(nanoseconds: 25_000_000)
            }
            preconditionFailure("Preview decode timed out")
        }
        func canvas(in view: NSView) -> PhotoCanvasView? {
            if let result = view as? PhotoCanvasView { return result }
            return view.subviews.compactMap { canvas(in: $0) }.first
        }
        delegate.open(first)
        let window = delegate.preview!
        let frame = window.frame
        precondition(!window.isVisible && window.contentViewController == nil)
        let state = delegate.previewState!
        try await waitForResult()
        precondition(state.error == nil && state.photo?.url == first && window.isVisible)
        let host = window.contentViewController as! NSHostingController<PhotoLoadingView>
        host.view.layoutSubtreeIfNeeded()
        try await Task.sleep(nanoseconds: 100_000_000)
        let originalCanvas = canvas(in: host.view)!
        delegate.open(second)
        precondition(state.photo?.url == first && window.title == first.lastPathComponent)
        precondition(delegate.previewState === state && window.contentViewController === host)
        try await waitForResult()
        try await Task.sleep(nanoseconds: 100_000_000)
        precondition(state.error == nil && state.photo?.url == second && window.title == second.lastPathComponent)
        precondition(canvas(in: host.view) === originalCanvas && window.frame == frame)
        let size = originalCanvas.imageView.frame.size
        precondition(abs(size.width / size.height - state.photo!.image.size.width / state.photo!.image.size.height) < 0.01)
        print("PASS first window appears ready; switching retains previous image/title and reuses host/canvas with correct aspect ratio")
        delegate.open(first)
        delegate.open(second)
        try await waitForResult()
        try await Task.sleep(nanoseconds: 100_000_000)
        precondition(state.photo?.url == second && delegate.preview === window)
        print("PASS rapid switching never commits an obsolete decode")
        delegate.open(broken)
        try await waitForResult()
        precondition(state.photo == nil && state.error != nil && window.isVisible)
        delegate.open(second)
        try await waitForResult()
        precondition(state.error == nil && state.photo?.url == second)
        print("PASS corrupt file clears stale photo; a subsequent valid image recovers")
        delegate.open(first)
        window.close()
        try await Task.sleep(nanoseconds: 300_000_000)
        precondition(delegate.preview == nil && !window.isVisible)
        delegate.open(first)
        let pendingWindow = delegate.preview!
        precondition(!pendingWindow.isVisible)
        pendingWindow.close()
        try await Task.sleep(nanoseconds: 300_000_000)
        precondition(delegate.preview == nil && !pendingWindow.isVisible)
        print("PASS close during decoding, including before first display, cancels opening")
    }
}
