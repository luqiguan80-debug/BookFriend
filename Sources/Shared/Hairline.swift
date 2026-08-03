import SwiftUI

/// 全局发丝分隔线：0.5pt 极淡，替代系统 Divider 的粗灰线。
/// 面板边界、列表分节、工具栏收边统一用它。
struct Hairline: View {
    let vertical: Bool

    init(_ vertical: Bool = false) {
        self.vertical = vertical
    }

    var body: some View {
        Rectangle()
            .fill(Color.primary.opacity(0.06))
            .frame(width: vertical ? 0.5 : nil, height: vertical ? nil : 0.5)
    }
}

/// 阅读进度细条：2pt 轨道 + 中性填充，替代系统 ProgressView
struct ProgressLine: View {
    let fraction: Double

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(Color.primary.opacity(0.08))
                Capsule().fill(Color.primary.opacity(0.4))
                    .frame(width: geo.size.width * min(max(fraction, 0), 1))
            }
        }
        .frame(height: 2)
    }
}
