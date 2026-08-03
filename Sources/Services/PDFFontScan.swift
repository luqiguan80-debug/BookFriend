import Foundation
import CoreGraphics

/// PDF 内容流字体扫描：遍历每页 Tf/Tj/TJ 操作符，产出按流序排列的
/// 「连续文本块 → 字号/字体名/字符数」序列。
/// 文本本身由 PDFKit 的 page.string 提供（CID 字体解码复杂），
/// 这里只负责把字号信息按字符数对齐回去。
final class PDFFontScan {

    struct Run {
        let size: CGFloat
        let name: String
        let chars: Int
    }

    private(set) var runs: [Run] = []
    private var curSize: CGFloat = 12
    private var curName = ""

    static func scan(page: CGPDFPage) -> [Run] {
        let scanner = PDFFontScan()
        scanner.scanPage(page)
        return scanner.runs
    }

    private func scanPage(_ page: CGPDFPage) {
        let stream = CGPDFContentStreamCreateWithPage(page)
        guard let table = CGPDFOperatorTableCreate() else { return }

        CGPDFOperatorTableSetCallback(table, "Tf") { scanner, info in
            let me = Unmanaged<PDFFontScan>.fromOpaque(info!).takeUnretainedValue()
            var size: CGPDFReal = 0
            var namePtr: UnsafePointer<CChar>?
            _ = CGPDFScannerPopNumber(scanner, &size)
            if CGPDFScannerPopName(scanner, &namePtr), let namePtr {
                me.curSize = size
                me.curName = String(cString: namePtr)
            }
        }

        CGPDFOperatorTableSetCallback(table, "Tj") { scanner, info in
            let me = Unmanaged<PDFFontScan>.fromOpaque(info!).takeUnretainedValue()
            var pdfStr: CGPDFStringRef?
            if CGPDFScannerPopString(scanner, &pdfStr), let pdfStr {
                me.addString(pdfStr)
            }
        }

        CGPDFOperatorTableSetCallback(table, "TJ") { scanner, info in
            let me = Unmanaged<PDFFontScan>.fromOpaque(info!).takeUnretainedValue()
            var arr: CGPDFArrayRef?
            guard CGPDFScannerPopArray(scanner, &arr), let arr else { return }
            for i in 0..<CGPDFArrayGetCount(arr) {
                var obj: CGPDFObjectRef?
                var str: CGPDFStringRef?
                if CGPDFArrayGetObject(arr, i, &obj), let obj,
                   CGPDFObjectGetValue(obj, .string, &str), let str {
                    me.addString(str)
                }
            }
        }

        // ' 与 " 也是画文字（" 前两个操作数是字距参数，栈顶是字符串）
        CGPDFOperatorTableSetCallback(table, "'") { scanner, info in
            let me = Unmanaged<PDFFontScan>.fromOpaque(info!).takeUnretainedValue()
            var pdfStr: CGPDFStringRef?
            if CGPDFScannerPopString(scanner, &pdfStr), let pdfStr {
                me.addString(pdfStr)
            }
        }
        CGPDFOperatorTableSetCallback(table, "\"") { scanner, info in
            let me = Unmanaged<PDFFontScan>.fromOpaque(info!).takeUnretainedValue()
            var pdfStr: CGPDFStringRef?
            var num: CGPDFReal = 0
            if CGPDFScannerPopString(scanner, &pdfStr), let pdfStr {
                me.addString(pdfStr)
                _ = CGPDFScannerPopNumber(scanner, &num)
                _ = CGPDFScannerPopNumber(scanner, &num)
            }
        }

        let scanner = CGPDFScannerCreate(stream, table, Unmanaged.passUnretained(self).toOpaque())
        CGPDFScannerScan(scanner)
    }

    /// 计字符数：能按简单编码解出文本就用真实长度；CID 字体按 2 字节/字估算
    private func addString(_ str: CGPDFStringRef) {
        let n: Int
        if let cf = CGPDFStringCopyTextString(str) {
            n = (cf as String).count
        } else {
            n = CGPDFStringGetLength(str) / 2
        }
        guard n > 0 else { return }
        // 同字体同号的连续块合并，减少 run 数量
        if let last = runs.last, last.size == curSize, last.name == curName {
            runs[runs.count - 1] = Run(size: curSize, name: curName, chars: last.chars + n)
        } else {
            runs.append(Run(size: curSize, name: curName, chars: n))
        }
    }
}
