import AppKit
import ImageIO

@main struct LivePhotoCheck {
    @MainActor static func main() async throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let url = folder.appendingPathComponent("still.HEIC")
        try FileManager.default.copyItem(at: URL(fileURLWithPath: CommandLine.arguments[1]), to: url)
        let decoded = try Photo.load(url)
        print("PASS HEIC decode; resource identifier: \(decoded.liveIdentifier ?? "none")")
        let still = Photo(url: url, liveIdentifier: "test-resource-id", image: decoded.image,
                          name: decoded.name, shooting: decoded.shooting, sections: decoded.sections,
                          histogram: decoded.histogram, coordinate: decoded.coordinate)
        let loader = LivePhotoLoader()
        await loader.load(still)
        precondition(loader.photo == nil && loader.status == "实况功能已停用")
        print("PASS disabled Live Photo preserves static preview")
        try Data("not a movie".utf8).write(to: folder.appendingPathComponent("still.MOV"))
        await loader.load(still)
        precondition(loader.photo == nil && loader.status == "实况功能已停用")
        print("PASS disabled Live Photo ignores neighboring movie")
        loader.cancel()
        precondition(loader.photo == nil)
        print("PASS cancel clears live resource")
        let ordinary = Photo(url: url, liveIdentifier: nil, image: decoded.image,
                             name: decoded.name, shooting: decoded.shooting, sections: decoded.sections,
                             histogram: decoded.histogram, coordinate: decoded.coordinate)
        await loader.load(ordinary)
        precondition(loader.photo == nil)
        print("PASS ordinary still skips movie lookup")
    }
}
