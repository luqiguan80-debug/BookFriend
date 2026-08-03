import SwiftUI
import PDFKit

struct BookCoverView: View {
    let book: Book

    var body: some View {
        switch book.format {
        case .epub:
            if let coverName = book.coverName {
                #if os(macOS)
                if let image = NSImage(contentsOfFile: Storage.coverURL(coverName: coverName).path) {
                    Image(nsImage: image).resizable().scaledToFill()
                        .frame(maxWidth: .infinity, maxHeight: .infinity).clipped()
                } else { placeholder }
                #else
                if let image = UIImage(contentsOfFile: Storage.coverURL(coverName: coverName).path) {
                    Image(uiImage: image).resizable().scaledToFill()
                        .frame(maxWidth: .infinity, maxHeight: .infinity).clipped()
                } else { placeholder }
                #endif
            } else {
                placeholder
            }
        case .pdf:
            PDFThumbView(url: book.fileURL)
        case .txt:
            placeholder
        }
    }

    /// 无封面时的占位：米白纸面 + 顶部双细线书眉 + 衬线书名 + 底部作者，像精装书封
    private var placeholder: some View {
        ZStack {
            Color(red: 0.96, green: 0.945, blue: 0.92)
            VStack(spacing: 0) {
                VStack(spacing: 3) {
                    Rectangle().fill(Color.primary.opacity(0.18)).frame(height: 0.5)
                    Rectangle().fill(Color.primary.opacity(0.18)).frame(height: 0.5)
                }
                .padding(.horizontal, 14).padding(.top, 16)
                Spacer()
                Text(book.title)
                    .font(.system(size: 15, weight: .medium, design: .serif))
                    .foregroundStyle(Color(red: 0.25, green: 0.22, blue: 0.18))
                    .multilineTextAlignment(.center)
                    .lineLimit(4)
                    .padding(.horizontal, 12)
                Spacer()
                if !book.author.isEmpty {
                    Text(book.author)
                        .font(.system(size: 9, design: .serif))
                        .foregroundStyle(Color(red: 0.45, green: 0.42, blue: 0.37))
                        .lineLimit(1)
                        .padding(.bottom, 12)
                }
            }
        }
    }
}

#if os(macOS)
struct PDFThumbView: NSViewRepresentable {
    let url: URL
    func makeNSView(context: Context) -> PDFView {
        let pv = PDFView(); pv.autoScales = true; pv.displayMode = .singlePage
        if let doc = PDFDocument(url: url), let page = doc.page(at: 0) {
            let s = PDFDocument(); s.insert(page, at: 0); pv.document = s
        }
        return pv
    }
    func updateNSView(_ nsView: PDFView, context: Context) {}
}
#else
struct PDFThumbView: UIViewRepresentable {
    let url: URL
    func makeUIView(context: Context) -> PDFView {
        let pv = PDFView(); pv.isUserInteractionEnabled = false; pv.autoScales = true; pv.displayMode = .singlePage
        if let doc = PDFDocument(url: url), let page = doc.page(at: 0) {
            let s = PDFDocument(); s.insert(page, at: 0); pv.document = s
        }
        return pv
    }
    func updateUIView(_ uiView: PDFView, context: Context) {}
}
#endif
