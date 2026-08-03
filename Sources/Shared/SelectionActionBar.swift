import SwiftUI

/// 选段悬浮动作条：讲解 / 翻译 / 展开 / 批注（+ 可选关闭）
/// 极简单色风格：超薄材质胶囊、发丝分隔线、无彩色底
struct SelectionActionBar: View {
    var onExplain: () -> Void
    var onTranslate: () -> Void
    var onExpand: () -> Void
    var onHighlight: () -> Void
    var onClose: (() -> Void)? = nil

    // iOS 触屏放大一档；macOS 鼠标点击保持紧凑
    #if os(iOS)
    private let iconSize: CGFloat = 17
    private let labelSize: CGFloat = 11
    private let buttonWidth: CGFloat = 52
    private let buttonVPad: CGFloat = 6
    private let closeSize: CGFloat = 40
    private let hairlineHeight: CGFloat = 26
    #else
    private let iconSize: CGFloat = 14
    private let labelSize: CGFloat = 9
    private let buttonWidth: CGFloat = 44
    private let buttonVPad: CGFloat = 3
    private let closeSize: CGFloat = 30
    private let hairlineHeight: CGFloat = 22
    #endif

    var body: some View {
        HStack(spacing: 2) {
            actionButton("lightbulb", "讲解", action: onExplain)
            actionButton("translate", "翻译", action: onTranslate)
            actionButton("text.append", "展开", action: onExpand)
            hairline
            actionButton("square.and.pencil", "批注", action: onHighlight)
            if let onClose {
                hairline
                Button(action: onClose) {
                    Image(systemName: "xmark")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.tertiary)
                        .frame(width: closeSize, height: closeSize)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(.ultraThinMaterial)
        .clipShape(Capsule())
        .overlay(Capsule().strokeBorder(Color.primary.opacity(0.06), lineWidth: 0.5))
        .shadow(color: .black.opacity(0.08), radius: 16, y: 6)
        .padding(.horizontal, 16)
        .padding(.bottom, 10)
    }

    private var hairline: some View {
        Rectangle()
            .fill(Color.primary.opacity(0.08))
            .frame(width: 0.5, height: hairlineHeight)
            .padding(.horizontal, 5)
    }

    private func actionButton(_ icon: String, _ label: String,
                              action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 3) {
                Image(systemName: icon)
                    .font(.system(size: iconSize, weight: .regular))
                Text(label)
                    .font(.system(size: labelSize))
                    .foregroundStyle(.secondary)
            }
            .frame(minWidth: buttonWidth)
            .padding(.vertical, buttonVPad)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
