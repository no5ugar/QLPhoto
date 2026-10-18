import AppKit
@main struct Decode {
 static func main() throws {
  for path in CommandLine.arguments.dropFirst() {
   let p = try Photo.load(URL(fileURLWithPath: path))
   precondition(p.image.size.width > 0 && p.histogram.count == 256)
   precondition(p.histogram.reduce(0,+) > 0)
   print("PASS decode + metadata + histogram: \(p.name), \(p.image.size)")
  }
  let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".jpg")
  try Data("invalid".utf8).write(to: url)
  defer { try? FileManager.default.removeItem(at: url) }
  do { _ = try Photo.load(url); fatalError("invalid accepted") } catch { print("PASS invalid file rejected") }
 }
}
