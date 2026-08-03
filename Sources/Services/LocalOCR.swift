import Vision
import PDFKit
#if os(macOS)
import AppKit
#else
import UIKit
#endif

struct OCRResult {
    var fullText: String
    var lines: [OCRLine]
}

struct OCRLine {
    var text: String
    var boundingBox: CGRect
}

enum LocalOCR {
    #if os(macOS)
    static func recognize(_ image: NSImage) async throws -> OCRResult {
        guard let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            throw OCRFailure.noImage
        }
        return try await recognize(cgImage: cgImage)
    }
    #else
    static func recognize(_ image: UIImage) async throws -> OCRResult {
        guard let cgImage = image.cgImage else {
            throw OCRFailure.noImage
        }
        return try await recognize(cgImage: cgImage)
    }
    #endif

    private static func recognize(cgImage: CGImage) async throws -> OCRResult {
        try await withCheckedThrowingContinuation { cont in
            let request = VNRecognizeTextRequest { request, error in
                if let error { cont.resume(throwing: error); return }
                guard let observations = request.results as? [VNRecognizedTextObservation] else {
                    cont.resume(returning: OCRResult(fullText: "", lines: [])); return }
                var lines: [OCRLine] = []
                for obs in observations {
                    guard let top = obs.topCandidates(1).first else { continue }
                    lines.append(OCRLine(text: top.string, boundingBox: obs.boundingBox))
                }
                lines.sort {
                    if abs($0.boundingBox.midY - $1.boundingBox.midY) > 0.02 {
                        return $0.boundingBox.midY > $1.boundingBox.midY
                    }
                    return $0.boundingBox.midX < $1.boundingBox.midX
                }
                let fullText = lines.map(\.text).joined(separator: "\n")
                cont.resume(returning: OCRResult(fullText: fullText, lines: lines))
            }
            request.recognitionLevel = .accurate
            request.recognitionLanguages = ["zh-Hans", "zh-Hant", "en", "ja", "ko"]
            request.usesLanguageCorrection = true
            do { try VNImageRequestHandler(cgImage: cgImage, options: [:]).perform([request]) }
            catch { cont.resume(throwing: error) }
        }
    }

    static func pageHasText(_ page: PDFPage) -> Bool {
        guard let str = page.string else { return false }
        return !str.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    enum OCRFailure: LocalizedError {
        case noImage
        var errorDescription: String? { "无法从页面提取图片" }
    }
}
