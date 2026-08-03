import Foundation

/// 本地文件目录约定：
/// Documents/Library/<uuid>.<ext>        原始书文件
/// Documents/Library/extracted/<uuid>/   EPUB 解压目录
/// Documents/Covers/<uuid>.jpg           封面图
enum Storage {
    static var documents: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
    }
    static var library: URL { documents.appendingPathComponent("Library", isDirectory: true) }
    static var extracted: URL { library.appendingPathComponent("extracted", isDirectory: true) }
    static var covers: URL { documents.appendingPathComponent("Covers", isDirectory: true) }

    static func ensureDirectories() {
        let fm = FileManager.default
        for dir in [library, extracted, covers] {
            try? fm.createDirectory(at: dir, withIntermediateDirectories: true)
        }
    }

    static func bookFileURL(fileName: String) -> URL { library.appendingPathComponent(fileName) }
    static func coverURL(coverName: String) -> URL { covers.appendingPathComponent(coverName) }
    static func extractedDir(for bookID: UUID) -> URL {
        extracted.appendingPathComponent(bookID.uuidString, isDirectory: true)
    }
}
