import AppKit
import ImageIO
import SwiftUI
import Photos
import AVFoundation

enum PreviewBackground: String, CaseIterable {
    case system, white, black
    var title: String {
        switch self { case .system: return "跟随系统"; case .white: return "白色"; case .black: return "黑色" }
    }
    func color(dark: Bool) -> NSColor {
        switch self {
        case .system: return dark ? .black : .white
        case .white: return .white
        case .black: return .black
        }
    }
}

struct MetadataSection: Identifiable {
    let id: String
    let rows: [(String, String)]
}
struct PhotoMetadata {
    let liveIdentifier: String?
    let shooting: ShootingInfo
    let sections: [MetadataSection]
    let coordinate: (Double, Double)?
}
struct Photo {
    let url: URL
    let liveIdentifier: String?
    let image: NSImage
    let name: String
    let shooting: ShootingInfo
    let sections: [MetadataSection]
    let histogram: [Double]
    let coordinate: (Double, Double)?

    static func load(_ url: URL) throws -> Photo {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [String: Any],
              let cg = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceThumbnailMaxPixelSize: 3200,
                kCGImageSourceShouldCacheImmediately: true
              ] as CFDictionary) else {
            throw NSError(domain: "QLPhoto", code: 1, userInfo: [NSLocalizedDescriptionKey: url.pathExtension.lowercased() == "dng" ? "无法解码此 DNG：文件可能损坏，或当前 macOS 不支持该相机的 RAW 数据" : "无法解码这张照片"])
        }
        let info = metadata(url, source: source, properties: properties)
        return Photo(url: url, liveIdentifier: info.liveIdentifier, image: NSImage(cgImage: cg, size: .zero), name: url.lastPathComponent, shooting: info.shooting, sections: info.sections, histogram: luminanceBins(cg), coordinate: info.coordinate)
    }
    var metadata: PhotoMetadata {
        PhotoMetadata(liveIdentifier: liveIdentifier, shooting: shooting, sections: sections, coordinate: coordinate)
    }
    static func readMetadata(_ url: URL) -> PhotoMetadata? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, [kCGImageSourceShouldCache: false] as CFDictionary),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [String: Any] else { return nil }
        return metadata(url, source: source, properties: properties)
    }
    private static func metadata(_ url: URL, source: CGImageSource, properties: [String: Any]) -> PhotoMetadata {
        let apple = properties[kCGImagePropertyMakerAppleDictionary as String] as? [String: Any]
        let liveIdentifier = apple?["17"] as? String
        let size = (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
        var sections = [MetadataSection(id: "文件", rows: [
            ("文件名", url.lastPathComponent),
            ("文件大小", ByteCountFormatter.string(fromByteCount: Int64(size), countStyle: .file)),
            ("格式", CGImageSourceGetType(source).map { $0 as String } ?? "未知"),
            ("像素尺寸", "\(properties[kCGImagePropertyPixelWidth as String] ?? "?") × \(properties[kCGImagePropertyPixelHeight as String] ?? "?")"),
            ("容器图像数量", "\(CGImageSourceGetCount(source))"),
            ("预览", "最长边最多 3200 像素；直方图基于降采样预览"),
        ])]
        let names = ["{Exif}": "EXIF 拍摄参数", "{TIFF}": "相机与图像", "{GPS}": "GPS 原始数据", "{ExifAux}": "镜头与辅助参数", "{MakerApple}": "Apple 原始字段", "{IPTC}": "IPTC", "{DNG}": "DNG / RAW 参数"]
        var root: [(String, String)] = []
        for key in properties.keys.sorted() {
            if let dict = properties[key] as? [String: Any] {
                sections.append(MetadataSection(id: names[key] ?? key, rows: dict.keys.sorted().map { ($0, String(describing: dict[$0]!)) }))
            } else { root.append((key, String(describing: properties[key]!))) }
        }
        sections.append(MetadataSection(id: "图像属性", rows: root))
        let gps = properties[kCGImagePropertyGPSDictionary as String] as? [String: Any]
        var coordinate: (Double, Double)?
        if let lat = gps?[kCGImagePropertyGPSLatitude as String] as? NSNumber,
           let lon = gps?[kCGImagePropertyGPSLongitude as String] as? NSNumber {
            let a = lat.doubleValue * ((gps?[kCGImagePropertyGPSLatitudeRef as String] as? String) == "S" ? -1 : 1)
            let b = lon.doubleValue * ((gps?[kCGImagePropertyGPSLongitudeRef as String] as? String) == "W" ? -1 : 1)
            if abs(a) <= 90 && abs(b) <= 180 { coordinate = (a,b) }
        }
        if gps == nil { sections.append(MetadataSection(id: "位置", rows: [("GPS", "文件未包含位置信息")])) }
        return PhotoMetadata(liveIdentifier: liveIdentifier, shooting: ShootingInfo(properties: properties), sections: sections, coordinate: coordinate)
    }
    /// Single-channel exposure histogram of an sRGB sample capped at 256 pixels per side (Rec. 709 luminance).
    static func luminanceBins(_ image: CGImage) -> [Double] {
        let scale = min(1.0, 256.0 / Double(max(image.width, image.height)))
        let w = max(1, Int(Double(image.width) * scale))
        let h = max(1, Int(Double(image.height) * scale))
        var pixels = [UInt8](repeating: 0, count: w*h*4)
        let success = pixels.withUnsafeMutableBytes { raw -> Bool in
            guard let context = CGContext(data: raw.baseAddress, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w*4, space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return false }
            context.draw(image, in: CGRect(x: 0,y: 0,width: w,height: h))
            return true
        }
        var bins = Array(repeating: 0.0, count: 256)
        if success {
            for i in stride(from: 0, to: pixels.count, by: 4) {
                let red: Double = Double(pixels[i]) * 0.2126
                let green: Double = Double(pixels[i + 1]) * 0.7152
                let blue: Double = Double(pixels[i + 2]) * 0.0722
                let luminance: Double = red + green + blue
                let bin: Int = min(255, Int(luminance))
                bins[bin] += 1
            }
        }
        return bins
    }
}

struct ShootingInfo {
    let primary: [(String, String)]
    let details: [(String, String)]

    init(properties: [String: Any]) {
        let exif = properties[kCGImagePropertyExifDictionary as String] as? [String: Any] ?? [:]
        let tiff = properties[kCGImagePropertyTIFFDictionary as String] as? [String: Any] ?? [:]
        func number(_ key: CFString) -> Double? {
            guard let n = exif[key as String] as? NSNumber, n.doubleValue.isFinite else { return nil }
            return n.doubleValue
        }
        func positive(_ key: CFString) -> Double? {
            guard let n = number(key), n > 0 else { return nil }
            return n
        }
        func compact(_ n: Double) -> String {
            String(format: "%.2f", locale: Locale(identifier: "en_US_POSIX"), n)
                .replacingOccurrences(of: #"\.?0+$"#, with: "", options: .regularExpression)
        }
        var iso: String = "未包含"
        if let values = exif[kCGImagePropertyExifISOSpeedRatings as String] as? [NSNumber] {
            let valid = values.filter { $0.doubleValue.isFinite && $0.doubleValue > 0 }
            if !valid.isEmpty { iso = valid.map { compact($0.doubleValue) }.joined(separator: " / ") }
        } else if let n = positive(kCGImagePropertyExifISOSpeedRatings) { iso = compact(n) }
        let shutter: String
        if let seconds = positive(kCGImagePropertyExifExposureTime) {
            if seconds < 1 {
                let reciprocal = 1 / seconds
                if reciprocal.isFinite && reciprocal <= 1_000_000_000 {
                    shutter = "1/" + compact(reciprocal.rounded()) + " s"
                } else { shutter = String(format: "%.3g s", seconds) }
            } else { shutter = compact(seconds) + " s" }
        } else { shutter = "未包含" }
        primary = [
            ("ISO", iso),
            ("快门", shutter),
            ("光圈", positive(kCGImagePropertyExifFNumber).map { "ƒ/" + compact($0) } ?? "未包含"),
            ("焦距", positive(kCGImagePropertyExifFocalLength).map { compact($0) + " mm" } ?? "未包含"),
            ("曝光补偿", number(kCGImagePropertyExifExposureBiasValue).map { ($0 > 0 ? "+" : "") + compact($0) + " EV" } ?? "未包含"),
            ("等效焦距", positive(kCGImagePropertyExifFocalLenIn35mmFilm).map { compact($0) + " mm" } ?? "未包含")
        ]
        var rows: [(String, String)] = []
        func append(_ label: String, _ value: Any?) {
            if let value = value as? String, !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                rows.append((label, value))
            }
        }
        append("相机", tiff[kCGImagePropertyTIFFModel as String])
        append("镜头", exif[kCGImagePropertyExifLensModel as String])
        append("拍摄时间", exif[kCGImagePropertyExifDateTimeOriginal as String])
        details = rows
    }
}

final class PhotoLoadingState: ObservableObject {
    @Published var photo: Photo?
    @Published var error: String?
}

struct PhotoLoadingView: View {
    @ObservedObject var state: PhotoLoadingState
    @AppStorage("previewBackground") private var previewBackground = PreviewBackground.system.rawValue
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        Group {
            if let photo = state.photo {
                PhotoView(photo: photo)
            } else {
                HStack(spacing: 0) {
                    ZStack {
                        Color((PreviewBackground(rawValue: previewBackground) ?? .system).color(dark: colorScheme == .dark))
                        if let error = state.error {
                            VStack(spacing: 10) {
                                Image(systemName: "exclamationmark.triangle").font(.title)
                                Text(error).multilineTextAlignment(.center)
                            }.foregroundStyle(.white).padding(24)
                                .background(.black.opacity(0.7), in: RoundedRectangle(cornerRadius: 12))
                        }
                    }.frame(maxWidth: .infinity, maxHeight: .infinity)
                    Divider()
                    Color.clear.frame(width: 320)
                }
            }
        }.frame(minWidth: 700, minHeight: 450)
            .transaction { $0.animation = nil; $0.disablesAnimations = true }
    }
}

struct PhotoView: View {
    let photo: Photo
    var body: some View {
        HStack(spacing: 0) {
            ZoomPhotoCanvas(image: photo.image)
            Divider()
            PhotoInfoView(metadata: photo.metadata, histogram: photo.histogram)
        }.frame(minWidth: 700, minHeight: 450)
    }
}

struct PhotoInfoView: View {
    let metadata: PhotoMetadata
    let histogram: [Double]?
    var body: some View {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 12) {
                            Text("拍摄参数").font(.headline)
                            LazyVGrid(columns: [GridItem(.flexible(), alignment: .leading), GridItem(.flexible(), alignment: .leading)], alignment: .leading, spacing: 6) {
                                ForEach(metadata.shooting.primary.indices, id: \.self) { i in
                                    VStack(alignment: .leading, spacing: 3) {
                                        Text(metadata.shooting.primary[i].0).font(.caption).foregroundStyle(.secondary)
                                        Text(metadata.shooting.primary[i].1)
                                            .font(.system(size: 15, weight: .semibold, design: .rounded))
                                            .monospacedDigit().textSelection(.enabled)
                                    }.frame(maxWidth: .infinity, minHeight: 36, alignment: .leading)
                                        .padding(8)
                                        .background(Color.primary.opacity(0.05))
                                        .clipShape(RoundedRectangle(cornerRadius: 8))
                                }
                            }
                            ForEach(metadata.shooting.details.indices, id: \.self) { i in
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(metadata.shooting.details[i].0).font(.caption).foregroundStyle(.secondary)
                                    Text(metadata.shooting.details[i].1).font(.callout).textSelection(.enabled)
                                }
                            }
                            Divider()
                            Text("直方图").font(.headline)
                            if let histogram {
                                Histogram(values: histogram).frame(height: 100)
                            } else {
                                RoundedRectangle(cornerRadius: 6).fill(Color.primary.opacity(0.05)).frame(height: 112)
                            }
                            if let (lat, lon) = metadata.coordinate {
                                Text("位置").font(.headline)
                                Text(String(format: "%.6f, %.6f", lat, lon)).textSelection(.enabled)
                                if let url = URL(string: "https://maps.apple.com/?ll=\(lat),\(lon)") {
                                    Link("在地图中查看", destination: url)
                                }
                                Text("地址需联网查询；本版本仅显示文件中的坐标。地图入口会将坐标交给地图服务。")
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                            ForEach(metadata.sections) { section in
                                DisclosureGroup(section.id) {
                                    VStack(alignment: .leading, spacing: 10) {
                                        ForEach(section.rows.indices, id: \.self) { i in
                                            VStack(alignment: .leading, spacing: 3) {
                                                Text(section.rows[i].0).font(.caption).foregroundStyle(.secondary)
                                                Text(section.rows[i].1).font(.system(size: 12)).textSelection(.enabled)
                                            }
                                        }
                                    }.frame(maxWidth: .infinity, alignment: .leading).padding(.top, 8)
                                }
                            }
                        }.padding(16)
                    }.frame(width: 320)
    }
}

// Temporarily disabled. Keep pairing implementation for a future release.
enum PhotoFeatures {
    static let livePhotosEnabled = false
}

/// Read only neighboring movie resources; Photos validates the complete resource pair.
@MainActor
final class LivePhotoLoader: ObservableObject {
    @Published var photo: PHLivePhoto?
    @Published var status = "正在查找配对视频…"
    private var request: PHLivePhotoRequestID?
    private var generation = 0

    func cancel() {
        generation += 1
        if let request { PHLivePhoto.cancelRequest(withRequestID: request) }
        request = nil
        photo = nil
    }

    func load(_ still: Photo) async {
        cancel()
        guard PhotoFeatures.livePhotosEnabled else {
            status = "实况功能已停用"
            return
        }
        let current = generation
        guard let identifier = still.liveIdentifier, !identifier.isEmpty else { return }
        status = "正在查找配对视频…"
        do {
            let files = try FileManager.default.contentsOfDirectory(
                at: still.url.deletingLastPathComponent(), includingPropertiesForKeys: [.isRegularFileKey],
                options: [.skipsHiddenFiles])
            let stem = still.url.deletingPathExtension().lastPathComponent
            let candidates = files.filter {
                ["mov", "mp4"].contains($0.pathExtension.lowercased()) &&
                (try? $0.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true
            }.sorted {
                let a = $0.deletingPathExtension().lastPathComponent.caseInsensitiveCompare(stem) == .orderedSame
                let b = $1.deletingPathExtension().lastPathComponent.caseInsensitiveCompare(stem) == .orderedSame
                return a != b ? a : $0.lastPathComponent < $1.lastPathComponent
            }
            for url in candidates {
                guard !Task.isCancelled, current == generation else { return }
                let asset = AVURLAsset(url: url)
                guard let metadata = try? await asset.load(.metadata) else { continue }
                var matched = false
                for item in metadata where item.identifier == .quickTimeMetadataContentIdentifier {
                    if let value = try? await item.load(.stringValue), value == identifier { matched = true; break }
                }
                guard matched else { continue }
                guard !Task.isCancelled, current == generation else { return }
                status = "正在载入实况…"
                request = PHLivePhoto.request(withResourceFileURLs: [still.url, url],
                    placeholderImage: still.image, targetSize: CGSize(width: 1600, height: 1600),
                    contentMode: .aspectFit) { [weak self] result, info in
                    let degraded = info[PHLivePhotoInfoIsDegradedKey] as? Bool ?? false
                    let cancelled = info[PHLivePhotoInfoCancelledKey] as? Bool ?? false
                    DispatchQueue.main.async {
                        guard let self, self.generation == current, !cancelled, !degraded else { return }
                        self.request = nil
                        self.photo = result
                        self.status = result == nil ? "配对资源无法播放，已显示静态照片" : "实况照片 · 点击图片左下角“播放实况”"
                    }
                }
                return
            }
            guard current == generation else { return }
            status = "缺少配对视频：请将原始 HEIC 与对应 MOV 放在同一目录"
        } catch {
            guard current == generation else { return }
            status = "无法读取配对视频目录，已显示静态照片"
        }
    }
}

/// A clipped native canvas keeps scroll events local and zooms around the pointer.
struct ZoomPhotoCanvas: NSViewRepresentable {
    @AppStorage("previewBackground") private var previewBackground = PreviewBackground.system.rawValue
    @Environment(\.colorScheme) private var colorScheme
    let image: NSImage
    func makeNSView(context: Context) -> PhotoCanvasView { PhotoCanvasView() }
    func updateNSView(_ view: PhotoCanvasView, context: Context) {
        view.configure(image: image)
        view.layer?.backgroundColor = (PreviewBackground(rawValue: previewBackground) ?? .system).color(dark: colorScheme == .dark).cgColor
    }

}

final class PhotoCanvasView: NSView {
    let imageView = NSImageView()
    private(set) var zoom: CGFloat = 1
    private var offset = CGPoint.zero
    private var dragStart: CGPoint?
    private var dragOrigin = CGPoint.zero
    override var isFlipped: Bool { true }

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        layer?.backgroundColor = NSColor.windowBackgroundColor.cgColor
        layer?.masksToBounds = true
        imageView.imageScaling = .scaleProportionallyUpOrDown
        addSubview(imageView)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func configure(image: NSImage) {
        if imageView.image !== image {
            zoom = 1
            offset = .zero
            imageView.image = image
            // Position the new image in the same update, rather than drawing it once
            // with the previous photo's aspect ratio or zoom before the next layout.
            positionContent()
        }
        needsLayout = true
    }
    private var fittedSize: CGSize {
        guard let size = imageView.image?.size, size.width > 0, size.height > 0 else { return .zero }
        let scale = min(bounds.width / size.width, bounds.height / size.height)
        return CGSize(width: size.width * scale, height: size.height * scale)
    }
    override func layout() {
        super.layout()
        positionContent()
    }
    private func positionContent() {
        let fit = fittedSize
        let size = CGSize(width: fit.width * zoom, height: fit.height * zoom)
        let limitX = max(0, (size.width - bounds.width) / 2)
        let limitY = max(0, (size.height - bounds.height) / 2)
        offset.x = min(limitX, max(-limitX, offset.x))
        offset.y = min(limitY, max(-limitY, offset.y))
        let rect = CGRect(x: bounds.midX - size.width / 2 + offset.x,
                          y: bounds.midY - size.height / 2 + offset.y,
                          width: size.width, height: size.height)
        imageView.frame = rect
        window?.invalidateCursorRects(for: self)
    }
    override func hitTest(_ point: NSPoint) -> NSView? {
        bounds.contains(convert(point, from: superview)) ? self : nil
    }
    override func resetCursorRects() {
        addCursorRect(bounds, cursor: zoom > 1 ? .openHand : .arrow)
    }
    override func scrollWheel(with event: NSEvent) {
        // Ignore trackpad inertia so releasing the gesture leaves the chosen zoom stable.
        guard event.momentumPhase.isEmpty else { return }
        let delta = event.scrollingDeltaY
        guard delta.isFinite, delta != 0 else { return }
        let point = convert(event.locationInWindow, from: nil)
        let old = zoom
        let sensitivity: CGFloat = event.hasPreciseScrollingDeltas ? 0.008 : 0.08
        zoom = min(8, max(1, old * exp(min(1, max(-1, delta * sensitivity)))))
        let ratio = zoom / old
        offset.x = point.x - bounds.midX - (point.x - bounds.midX - offset.x) * ratio
        offset.y = point.y - bounds.midY - (point.y - bounds.midY - offset.y) * ratio
        positionContent()
    }
    override func mouseDown(with event: NSEvent) {
        if event.clickCount == 2 { zoom = 1; offset = .zero; positionContent(); return }
        dragStart = convert(event.locationInWindow, from: nil)
        dragOrigin = offset
        if zoom > 1 { NSCursor.closedHand.set() }
    }
    override func mouseDragged(with event: NSEvent) {
        guard let start = dragStart, zoom > 1 else { return }
        let point = convert(event.locationInWindow, from: nil)
        offset = CGPoint(x: dragOrigin.x + point.x - start.x, y: dragOrigin.y + point.y - start.y)
        positionContent()
    }
    override func mouseUp(with event: NSEvent) {
        dragStart = nil
        (zoom > 1 ? NSCursor.openHand : NSCursor.arrow).set()
    }
}
struct Histogram: View {
    let values: [Double]
    var body: some View {
        Canvas { context, size in
            let peak = max(1, values.max() ?? 1)
            var path = Path()
            path.move(to: CGPoint(x: 0, y: size.height))
            for i in 0..<256 {
                path.addLine(to: CGPoint(x: Double(i) / 255 * size.width,
                                        y: size.height * (1 - values[i] / peak)))
            }
            path.addLine(to: CGPoint(x: size.width, y: size.height))
            path.closeSubpath()
            context.fill(path, with: .color(Color(white: 0.75)))
        }.padding(6).background(Color.black.opacity(0.85)).clipShape(RoundedRectangle(cornerRadius: 6))
    }
}
