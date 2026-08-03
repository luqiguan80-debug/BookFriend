import SwiftUI

/// AI 输出统一渲染：Markdown（加粗/列表/标题）+ 衬线 + 宽行距，失败回退纯文本。
/// 侧边栏讲解气泡和笔记列表共用，保持同一阅读样式。
/// 字号跟随阅读器设置（reader.fontSize，13–32），调一处全局生效。
struct MarkdownText: View {
    let content: String
    @AppStorage("reader.fontSize") private var fontSize = 18

    var body: some View {
        rendered
            .font(.system(size: CGFloat(fontSize), design: .serif))
            .lineSpacing(8)
            .textSelection(.enabled)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var rendered: Text {
        if let md = try? AttributedString(markdown: content,
                options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)) {
            return Text(md)
        }
        return Text(content)
    }
}
