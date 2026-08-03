import Foundation
import SwiftData
import ZIPFoundation
import PDFKit
import Vision
#if os(iOS)
import UIKit
typealias PlatformFont = UIFont
typealias PlatformColor = UIColor
#else
typealias PlatformFont = NSFont
typealias PlatformColor = NSColor
#endif

enum ImportError: LocalizedError {
    case unsupportedFormat
    var errorDescription: String? { "不支持的格式，目前支持 EPUB / PDF / TXT" }
}

enum BookImporter {

    @MainActor
    static func importBook(from sourceURL: URL, into context: ModelContext,
                           onStatus: (@Sendable (String) -> Void)? = nil) async throws -> Book {
        let accessed = sourceURL.startAccessingSecurityScopedResource()
        defer { if accessed { sourceURL.stopAccessingSecurityScopedResource() } }
        NSLog("[BookFriend] importBook 进入, 沙盒访问=\(accessed), ext=\(sourceURL.pathExtension)")

        let ext = sourceURL.pathExtension
        guard let format = BookFormat(fileExtension: ext) else { throw ImportError.unsupportedFormat }

        let bookID = UUID()
        let fileName = "\(bookID.uuidString).\(ext.lowercased())"
        let destURL = Storage.bookFileURL(fileName: fileName)
        try FileManager.default.copyItem(at: sourceURL, to: destURL)
        NSLog("[BookFriend] 文件已拷入书库")

        var title = sourceURL.deletingPathExtension().lastPathComponent
        var author = ""
        var coverName: String?

        switch format {
        case .epub:
            let extractedDir = Storage.extractedDir(for: bookID)
            let epub = try EPUBParser().parse(epubFile: destURL, extractTo: extractedDir)
            title = epub.title; author = epub.author
            if let coverURL = epub.coverImageURL {
                let name = "\(bookID.uuidString).\(coverURL.pathExtension)"
                try? FileManager.default.copyItem(at: coverURL, to: Storage.coverURL(coverName: name))
                coverName = name
            }
        case .pdf:
            let needsOCR = await Task.detached(priority: .userInitiated) {
                canSelectText(in: destURL)
            }.value == false
            if needsOCR {
                // 图片版 PDF：Vision OCR 生成带文字层的 PDF，保持原排版（页级进度上报）
                onStatus?("识别文字中…")
                let ocredURL = await Task.detached(priority: .userInitiated) {
                    Self.addTextLayer(to: destURL, outputName: bookID.uuidString) { page, total in
                        if page % 10 == 0 || page == total {
                            onStatus?("识别文字 \(page)/\(total) 页…")
                        }
                    }
                }.value
                if let ocredURL {
                    try FileManager.default.removeItem(at: destURL)
                    try FileManager.default.moveItem(at: ocredURL, to: destURL)
                }
            }
        case .txt:
            break
        }

        let book = Book(id: bookID, title: title, author: author,
                        format: format, fileName: fileName, coverName: coverName)
        context.insert(book)
        try context.save()
        return book
    }

    private static func canSelectText(in url: URL) -> Bool {
        guard let doc = PDFDocument(url: url), doc.pageCount > 0 else { return false }
        for i in 0..<min(5, doc.pageCount) {
            guard let page = doc.page(at: i), let text = page.string else { continue }
            if text.trimmingCharacters(in: .whitespacesAndNewlines).count >= 50 { return true }
        }
        return false
    }

    /// 用 Vision OCR 识别每页文字 → 在对应位置放透明文本 → 生成带文字层的 PDF（iOS/macOS 通用）
    private static func addTextLayer(to url: URL, outputName: String,
                                     progress: (@Sendable (Int, Int) -> Void)? = nil) -> URL? {
        guard let sourceDoc = PDFDocument(url: url) else { return nil }
        let outDoc = PDFDocument()
        let totalPages = sourceDoc.pageCount

        for i in 0..<totalPages {
            progress?(i + 1, totalPages)
            guard let srcPage = sourceDoc.page(at: i) else { continue }
            let bounds = srcPage.bounds(for: .cropBox)

            // 渲染页面为图片（2x，保证 OCR 精度）
            let scale: CGFloat = 2.0
            let cgImage: CGImage
            #if os(macOS)
            // 线程安全：直接用 CGBitmapContext，不碰 NSGraphicsContext
            let pixelW = max(1, Int(bounds.width * scale))
            let pixelH = max(1, Int(bounds.height * scale))
            guard let ctx = CGContext(
                data: nil, width: pixelW, height: pixelH,
                bitsPerComponent: 8, bytesPerRow: 0,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            ) else { continue }
            ctx.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
            ctx.fill(CGRect(x: 0, y: 0, width: pixelW, height: pixelH))
            ctx.scaleBy(x: scale, y: scale)
            srcPage.draw(with: .cropBox, to: ctx)
            guard let img = ctx.makeImage() else { continue }
            cgImage = img
            #else
            // iOS：PDFPage.thumbnail 由系统保证渲染方向正确
            let thumb = srcPage.thumbnail(of: CGSize(width: bounds.width * scale,
                                                     height: bounds.height * scale),
                                          for: .cropBox)
            guard let img = thumb.cgImage else { continue }
            cgImage = img
            #endif

            // OCR 识别
            let observations = performOCR(on: cgImage)
            guard !observations.isEmpty else {
                // 识别失败，原样放入
                if let copied = srcPage.copy() as? PDFPage { outDoc.insert(copied, at: outDoc.pageCount) }
                continue
            }

            // 创建新页面：原图 + 透明文本层
            let newPage = createPageWithTextLayer(
                image: cgImage, bounds: bounds,
                observations: observations,
                pageSize: bounds.size
            )
            if let newPage { outDoc.insert(newPage, at: outDoc.pageCount) }
        }

        // 保留原书书签目录：重建 PDF 会丢 outline，按页码 1:1 拷回
        if let srcRoot = sourceDoc.outlineRoot, srcRoot.numberOfChildren > 0 {
            func cloneOutline(_ src: PDFOutline, into parent: PDFOutline) {
                let node = PDFOutline()
                node.label = src.label
                if let dstPage = src.destination?.page {
                    let idx = min(sourceDoc.index(for: dstPage), outDoc.pageCount - 1)
                    if idx >= 0, let p = outDoc.page(at: idx) {
                        node.destination = PDFDestination(page: p, at: src.destination?.point ?? .zero)
                    }
                }
                parent.insertChild(node, at: parent.numberOfChildren)
                for i in 0..<src.numberOfChildren {
                    if let child = src.child(at: i) { cloneOutline(child, into: node) }
                }
            }
            let newRoot = PDFOutline()
            for i in 0..<srcRoot.numberOfChildren {
                if let child = srcRoot.child(at: i) { cloneOutline(child, into: newRoot) }
            }
            outDoc.outlineRoot = newRoot
        }

        let outURL = FileManager.default.temporaryDirectory.appendingPathComponent("\(outputName)-ocred.pdf")
        guard outDoc.write(to: outURL) else { return nil }
        return outURL
    }

    /// Vision OCR 识别 CGImage，返回文字块和位置
    private static func performOCR(on cgImage: CGImage) -> [VNRecognizedTextObservation] {
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.recognitionLanguages = ["zh-Hans", "zh-Hant", "en"]
        request.usesLanguageCorrection = true
        do {
            try VNImageRequestHandler(cgImage: cgImage, options: [:]).perform([request])
            return (request.results as? [VNRecognizedTextObservation]) ?? []
        } catch { return [] }
    }

    /// 创建新 PDF 页面：原图 + 透明文本层
    private static func createPageWithTextLayer(
        image: CGImage, bounds: CGRect,
        observations: [VNRecognizedTextObservation],
        pageSize: CGSize
    ) -> PDFPage? {
        // 创建 PDF 数据：draw image + transparent text
        let pdfData = NSMutableData()
        var mediaBox = CGRect(origin: .zero, size: pageSize)

        guard let consumer = CGDataConsumer(data: pdfData as CFMutableData),
              let ctx = CGContext(consumer: consumer, mediaBox: &mediaBox, nil) else { return nil }

        ctx.beginPDFPage(nil)

        // 1. 画原图
        ctx.draw(image, in: CGRect(origin: .zero, size: pageSize))

        // 2. 画透明文本层（文字可选中但不可见）
        ctx.setFillColor(PlatformColor.clear.cgColor)
        let fontSize: CGFloat = 12.0

        for obs in observations {
            guard let text = obs.topCandidates(1).first?.string else { continue }
            // Vision boundingBox 是归一化 [0,1]，原点在左下
            let box = obs.boundingBox
            let rect = CGRect(
                x: box.origin.x * pageSize.width,
                y: box.origin.y * pageSize.height,
                width: box.width * pageSize.width,
                height: box.height * pageSize.height
            )

            // 调整字体大小使文字宽度匹配
            let font = PlatformFont.systemFont(ofSize: fontSize)
            let textSize = (text as NSString).size(withAttributes: [.font: font])
            let scale = rect.width / max(textSize.width, 1)
            let scaledFont = PlatformFont.systemFont(ofSize: fontSize * scale)

            let attrs: [NSAttributedString.Key: Any] = [
                .font: scaledFont,
                .foregroundColor: PlatformColor.clear,
            ]
            let attrStr = NSAttributedString(string: text, attributes: attrs)
            let line = CTLineCreateWithAttributedString(attrStr)
            ctx.textPosition = CGPoint(x: rect.origin.x, y: rect.origin.y)
            CTLineDraw(line, ctx)
        }

        ctx.endPDFPage()
        ctx.closePDF()

        // 必须从画好文字层的 pdfData 建页；用原图建页会丢掉文字层
        guard let pageDoc = PDFDocument(data: pdfData as Data),
              let page = pageDoc.page(at: 0) else { return nil }
        return page
    }
}
