import Foundation

@main struct MetadataCheck {
    static func main() throws {
        for path in CommandLine.arguments.dropFirst() {
            let url = URL(fileURLWithPath: path)
            let start = Date()
            guard let early = Photo.readMetadata(url) else { fatalError("Metadata missing: \(url.lastPathComponent)") }
            let elapsed = Date().timeIntervalSince(start)
            let full = try Photo.load(url)
            precondition(Dictionary(uniqueKeysWithValues: early.shooting.primary) == Dictionary(uniqueKeysWithValues: full.shooting.primary))
            precondition(Dictionary(uniqueKeysWithValues: early.shooting.details) == Dictionary(uniqueKeysWithValues: full.shooting.details))
            precondition(early.sections.map(\.id) == full.sections.map(\.id))
            for (a, b) in zip(early.sections, full.sections) {
                precondition(Dictionary(uniqueKeysWithValues: a.rows) == Dictionary(uniqueKeysWithValues: b.rows))
            }
            precondition(early.liveIdentifier == full.liveIdentifier)
            print("PASS early/full metadata agreement: \(url.lastPathComponent); metadata \(Int(elapsed * 1000)) ms")
        }
        precondition(Photo.readMetadata(URL(fileURLWithPath: "/nonexistent/qlphoto-metadata-check")) == nil)
    }
}
