import AppKit
@main struct HTMLPreviewCheck {
    static func main() throws {
        precondition(HTMLPreview.escape("<script>'\"&") == "&lt;script&gt;&#39;&quot;&amp;")
        for path in CommandLine.arguments.dropFirst() {
            let preview = try HTMLPreview(photo: Photo.load(URL(fileURLWithPath: path)))
            let html = String(decoding: preview.html, as: UTF8.self)
            precondition(html.contains("cid:photo") && html.contains("拍摄参数") && html.contains("ISO"))
            precondition(preview.png.starts(with: [137,80,78,71,13,10,26,10]))
            print("PASS HTML preview + PNG attachment: \(URL(fileURLWithPath: path).lastPathComponent)")
        }
    }
}
