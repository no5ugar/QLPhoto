import Cocoa

@main struct PlacementCheck {
    static func main() {
        let visible = CGRect(x: -1920, y: 40, width: 1920, height: 1016)
        let size = CGSize(width: 1100, height: 742)
        let centered = fittedPreviewFrame(saved: nil, size: size, visible: visible)
        precondition(centered.midX == visible.midX && centered.midY == visible.midY)
        precondition(visible.contains(centered))
        let moved = CGRect(x: -1700, y: 100, width: 900, height: 600)
        precondition(fittedPreviewFrame(saved: moved, size: size, visible: visible) == moved)
        let disconnected = CGRect(x: 4000, y: 2000, width: 2500, height: 1400)
        precondition(visible.contains(fittedPreviewFrame(saved: disconnected, size: size, visible: visible)))
        let small = CGRect(x: 0, y: 20, width: 640, height: 400)
        precondition(fittedPreviewFrame(saved: disconnected, size: size, visible: small) == small)
        precondition(fittedPreviewFrame(saved: .zero, size: size, visible: visible) == centered)
        print("PASS centered placement, negative-coordinate display, saved position, offscreen recovery, small display and invalid saved frame")
    }
}
