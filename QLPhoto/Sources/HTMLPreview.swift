import AppKit

/// Self-contained HTML; all metadata is escaped and all image bytes are supplied by the extension.
struct HTMLPreview {
    let html: Data
    let png: Data

    init(photo: Photo) throws {
        guard let cg = photo.image.cgImage(forProposedRect: nil, context: nil, hints: nil),
              let png = NSBitmapImageRep(cgImage: cg).representation(using: .png, properties: [:]) else {
            throw NSError(domain: "QLPhoto", code: 2, userInfo: [NSLocalizedDescriptionKey: "无法生成预览附件"])
        }
        self.png = png
        let cards = photo.shooting.primary.map { label, value in
            "<div class='card'><span>\(Self.escape(label))</span><strong>\(Self.escape(value))</strong></div>"
        }.joined()
        let details = photo.shooting.details.map { label, value in
            "<div class='detail'><span>\(Self.escape(label))</span><div>\(Self.escape(value))</div></div>"
        }.joined()
        let sections = photo.sections.map { section in
            let rows = section.rows.map { label, value in
                "<tr><th>\(Self.escape(label))</th><td>\(Self.escape(value))</td></tr>"
            }.joined()
            return "<details><summary>\(Self.escape(section.id))</summary><table>\(rows)</table></details>"
        }.joined()
        let bins = photo.histogram
        let peak = max(1, bins.max() ?? 1)
        let points = bins.enumerated().map { i, value in "\(i),\(100 * (1 - value / peak))" }.joined(separator: " ")
        let curves = "<polygon points='0,100 \(points) 255,100' fill='#bfbfbf'/>"
        let location: String
        if let (lat, lon) = photo.coordinate {
            location = "<h2>位置</h2><p>" + String(format: "%.6f, %.6f", lat, lon) + "</p><p class='muted'>坐标来自文件；不联网查询地址。</p>"
        } else { location = "" }
        html = Data("""
        <!doctype html><html lang="zh-CN"><head><meta charset="utf-8">
        <meta http-equiv="Content-Security-Policy" content="default-src 'none'; img-src cid:; style-src 'unsafe-inline'">
        <style>
        :root {color-scheme:light dark} *{box-sizing:border-box}
        body{margin:0;font:13px -apple-system,BlinkMacSystemFont,sans-serif;background:Canvas;color:CanvasText}
        header{padding:14px 20px;border-bottom:1px solid #8884;overflow-wrap:anywhere}
        header small{display:block;margin-top:4px;color:GrayText}
        main{display:flex;height:calc(100vh - 72px);min-height:450px}
        .image{flex:1;min-width:0;background:#151515;display:flex;align-items:center;justify-content:center;padding:12px}
        .image img{max-width:100%;max-height:100%;object-fit:contain}
        aside{width:340px;flex-shrink:0;padding:18px;overflow:auto}
        h2{font-size:15px;margin:0 0 12px}.cards{display:grid;grid-template-columns:1fr 1fr;gap:10px;margin-bottom:16px}
        .card{padding:12px 10px;background:#8881;border-radius:8px;overflow-wrap:anywhere}
        .card span,.detail span{display:block;color:GrayText;font-size:11px;margin-bottom:6px}
        .card strong{font-size:20px;font-variant-numeric:tabular-nums}
        .detail{margin-bottom:12px;overflow-wrap:anywhere}hr{border:0;border-top:1px solid #8884;margin:18px 0}
        svg{width:100%;height:100px;background:#181818;border-radius:6px;margin-bottom:18px}
        details{padding:10px 0;border-top:1px solid #8883}summary{cursor:pointer;font-weight:600}
        table{width:100%;table-layout:fixed;border-collapse:collapse;font-size:12px;margin-top:10px}
        th,td{text-align:left;vertical-align:top;padding:6px 3px;overflow-wrap:anywhere}th{width:40%;font-weight:400;color:GrayText}
        .muted{font-size:11px;color:GrayText}
        </style></head><body>
        <header><b>\(Self.escape(photo.name))</b><small>QLPhoto · 数据型原生预览</small></header>
        <main><section class="image"><img src="cid:photo" alt="照片"></section><aside>
        <h2>拍摄参数</h2><div class="cards">\(cards)</div>\(details)<hr>
        <h2>直方图</h2><svg viewBox="0 0 255 100" preserveAspectRatio="none">\(curves)</svg>
        \(location)\(sections)</aside></main></body></html>
        """.utf8)
    }

    static func escape(_ value: String) -> String {
        value.replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
            .replacingOccurrences(of: "'", with: "&#39;")
    }
}
