import Foundation
import ZIPFoundation

/// EPUB 解析：解压 → container.xml 找 OPF → 解析 manifest/spine → NCX 或 Nav 取章节标题
final class EPUBParser {

    func parse(epubFile: URL, extractTo destDir: URL) throws -> EPUBBook {
        let fm = FileManager.default
        if fm.fileExists(atPath: destDir.path) {
            try fm.removeItem(at: destDir)
        }
        try fm.createDirectory(at: destDir, withIntermediateDirectories: true)
        try fm.unzipItem(at: epubFile, to: destDir)

        // 1. META-INF/container.xml → OPF 路径
        let containerURL = destDir.appendingPathComponent("META-INF/container.xml")
        guard fm.fileExists(atPath: containerURL.path) else { throw EPUBError.notAnEPUB }
        let container: String? = XMLParser(contentsOf: containerURL).map { parser -> String in
            let delegate = ContainerDelegate()
            parser.delegate = delegate
            parser.parse()
            return delegate.rootfilePath
        }
        guard let opfPath = container, !opfPath.isEmpty else { throw EPUBError.missingOPF }

        let opfURL = destDir.appendingPathComponent(opfPath)
        let opfDir = opfURL.deletingLastPathComponent()

        // 2. OPF → metadata / manifest / spine
        let opfDelegate = OPFDelegate()
        let opfParser = XMLParser(contentsOf: opfURL)!
        opfParser.delegate = opfDelegate
        opfParser.parse()

        // 3. 章节标题：优先 NCX，其次 EPUB3 Nav 文档
        var titles: [String: String] = [:]
        if let ncxItem = opfDelegate.manifest.values.first(where: { $0.mediaType == "application/x-dtbncx+xml" }) {
            let ncxURL = opfDir.appendingPathComponent(ncxItem.href)
            if fm.fileExists(atPath: ncxURL.path) {
                titles = parseNCX(url: ncxURL)
            }
        }
        if titles.isEmpty, let navItem = opfDelegate.manifest.values.first(where: { $0.properties.contains("nav") }) {
            let navURL = opfDir.appendingPathComponent(navItem.href)
            if fm.fileExists(atPath: navURL.path) {
                titles = parseNav(url: navURL)
            }
        }

        // 4. spine 顺序组装章节
        var chapters: [EPUBChapter] = []
        for idref in opfDelegate.spine {
            guard let item = opfDelegate.manifest[idref],
                  item.mediaType.contains("html") else { continue }
            let href = item.href.removingPercentEncoding ?? item.href
            let cleanHref = href.components(separatedBy: "#")[0]
            let url = opfDir.appendingPathComponent(cleanHref)
            guard fm.fileExists(atPath: url.path) else { continue }
            let title = titles[cleanHref] ?? titles[url.lastPathComponent] ?? ""
            chapters.append(EPUBChapter(href: cleanHref, url: url,
                                        title: title.isEmpty ? "第 \(chapters.count + 1) 节" : title))
        }
        guard !chapters.isEmpty else { throw EPUBError.emptySpine }

        // 5. 封面
        var coverURL: URL?
        if let cover = opfDelegate.coverImageHREF {
            let url = opfDir.appendingPathComponent(cover.removingPercentEncoding ?? cover)
            if fm.fileExists(atPath: url.path) { coverURL = url }
        }

        return EPUBBook(
            title: opfDelegate.title ?? epubFile.deletingPathExtension().lastPathComponent,
            author: opfDelegate.creator ?? "",
            rootDir: destDir,
            chapters: chapters,
            coverImageURL: coverURL
        )
    }

    // MARK: - NCX（EPUB2 目录）

    private func parseNCX(url: URL) -> [String: String] {
        let delegate = NCXDelegate()
        let parser = XMLParser(contentsOf: url)
        parser?.delegate = delegate
        parser?.parse()
        return delegate.titles
    }

    // MARK: - Nav（EPUB3 目录）

    private func parseNav(url: URL) -> [String: String] {
        guard let data = try? Data(contentsOf: url),
              let html = String(data: data, encoding: .utf8) else { return [:] }
        var titles: [String: String] = [:]
        // 轻量正则即可：目录结构简单，避免引入完整 HTML 解析器
        let pattern = ##"<a[^>]+href\s*=\s*"([^"#]+)(?:#[^"]*)?"[^>]*>(.*?)</a>"##
        let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive, .dotMatchesLineSeparators])
        let ns = html as NSString
        for match in regex?.matches(in: html, range: NSRange(location: 0, length: ns.length)) ?? [] {
            let href = ns.substring(with: match.range(at: 1))
            var label = ns.substring(with: match.range(at: 2))
            label = label.replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
            label = label.trimmingCharacters(in: .whitespacesAndNewlines)
            if !href.isEmpty, !label.isEmpty, titles[href] == nil {
                titles[href] = label
                titles[URL(fileURLWithPath: href).lastPathComponent] = label
            }
        }
        return titles
    }
}

// MARK: - XMLParser delegates

private final class ContainerDelegate: NSObject, XMLParserDelegate {
    var rootfilePath: String = ""
    func parser(_ parser: XMLParser, didStartElement elementName: String,
                namespaceURI: String?, qualifiedName qName: String?,
                attributes attributeDict: [String: String] = [:]) {
        if elementName == "rootfile", rootfilePath.isEmpty {
            rootfilePath = attributeDict["full-path"] ?? ""
        }
    }
}

private final class OPFDelegate: NSObject, XMLParserDelegate {
    struct ManifestItem {
        var href: String
        var mediaType: String
        var properties: String
    }
    var title: String?
    var creator: String?
    var manifest: [String: ManifestItem] = [:]
    var spine: [String] = []
    var coverImageHREF: String?

    private var currentElement = ""
    private var textBuffer = ""
    private var coverMetaID: String?

    func parser(_ parser: XMLParser, didStartElement elementName: String,
                namespaceURI: String?, qualifiedName qName: String?,
                attributes attributeDict: [String: String] = [:]) {
        currentElement = elementName
        textBuffer = ""
        switch elementName {
        case "item":
            if let id = attributeDict["id"], let href = attributeDict["href"] {
                manifest[id] = ManifestItem(
                    href: href,
                    mediaType: attributeDict["media-type"] ?? "",
                    properties: attributeDict["properties"] ?? ""
                )
                if attributeDict["properties"]?.contains("cover-image") == true {
                    coverImageHREF = href
                }
            }
        case "itemref":
            if let idref = attributeDict["idref"] { spine.append(idref) }
        case "meta":
            if attributeDict["name"] == "cover", let content = attributeDict["content"] {
                coverMetaID = content
            }
        default: break
        }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        textBuffer += string
    }

    func parser(_ parser: XMLParser, didEndElement elementName: String,
                namespaceURI: String?, qualifiedName qName: String?) {
        let text = textBuffer.trimmingCharacters(in: .whitespacesAndNewlines)
        if elementName.hasSuffix("title"), title == nil, !text.isEmpty { title = text }
        if elementName.hasSuffix("creator"), creator == nil, !text.isEmpty { creator = text }
    }

    func parserDidEndDocument(_ parser: XMLParser) {
        if coverImageHREF == nil, let metaID = coverMetaID, let item = manifest[metaID] {
            coverImageHREF = item.href
        }
    }
}

private final class NCXDelegate: NSObject, XMLParserDelegate {
    var titles: [String: String] = [:]
    private var currentLabel = ""
    private var currentSrc = ""
    private var inNavLabel = false
    private var textBuffer = ""

    func parser(_ parser: XMLParser, didStartElement elementName: String,
                namespaceURI: String?, qualifiedName qName: String?,
                attributes attributeDict: [String: String] = [:]) {
        if elementName == "navLabel" { inNavLabel = true; textBuffer = "" }
        if elementName == "content", let src = attributeDict["src"] {
            currentSrc = src.components(separatedBy: "#")[0]
        }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        if inNavLabel { textBuffer += string }
    }

    func parser(_ parser: XMLParser, didEndElement elementName: String,
                namespaceURI: String?, qualifiedName qName: String?) {
        if elementName == "navLabel" {
            inNavLabel = false
            currentLabel = textBuffer.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        if elementName == "navPoint", !currentSrc.isEmpty, !currentLabel.isEmpty {
            titles[currentSrc] = currentLabel
            titles[URL(fileURLWithPath: currentSrc).lastPathComponent] = currentLabel
            currentLabel = ""
            currentSrc = ""
        }
    }
}

