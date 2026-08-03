import Foundation

struct EPUBChapter {
    var href: String        // 相对 OPF 目录的路径（含 fragment 时已去除）
    var url: URL            // 解压后的本地文件 URL
    var title: String
}

struct EPUBBook {
    var title: String
    var author: String
    var rootDir: URL        // 解压根目录
    var chapters: [EPUBChapter]
    var coverImageURL: URL?
}

enum EPUBError: LocalizedError {
    case notAnEPUB, missingOPF, emptySpine

    var errorDescription: String? {
        switch self {
        case .notAnEPUB: return "不是有效的 EPUB 文件"
        case .missingOPF: return "EPUB 中找不到内容清单（OPF）"
        case .emptySpine: return "EPUB 没有可读章节"
        }
    }
}
