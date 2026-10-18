import Cocoa
import QuickLookUI
import UniformTypeIdentifiers
import OSLog

final class PreviewProvider: QLPreviewProvider, QLPreviewingController {
    private let logger = Logger(subsystem: "dev.local.QLPhoto", category: "DataPreviewExtension")

    func providePreview(for request: QLFilePreviewRequest) async throws -> QLPreviewReply {
        logger.notice("Data-based Quick Look request received")
        do {
            let preview = try HTMLPreview(photo: Photo.load(request.fileURL))
            return QLPreviewReply(dataOfContentType: .html, contentSize: CGSize(width: 1100, height: 720)) { reply in
                reply.title = "QLPhoto · 拍摄参数"
                reply.stringEncoding = .utf8
                reply.attachments = ["photo": QLPreviewReplyAttachment(data: preview.png, contentType: .png)]
                return preview.html
            }
        } catch {
            logger.error("Data preview failed: \(error.localizedDescription, privacy: .public)")
            throw error
        }
    }
}
