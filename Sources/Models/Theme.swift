import SwiftUI

enum ReaderTheme: String, CaseIterable {
    case light, green

    var icon: String {
        switch self {
        case .light: return "sun.max"
        case .green: return "leaf"
        }
    }
    var name: String {
        switch self {
        case .light: return "浅色"
        case .green: return "护眼"
        }
    }
    var next: ReaderTheme {
        switch self {
        case .light: return .green
        case .green: return .light
        }
    }
    // EPUB 背景/文字色
    var epubBg: String {
        switch self {
        case .light: return "#FBF9F4"
        case .green: return "#DEF0DE"
        }
    }
    var epubFg: String {
        switch self {
        case .light: return "#2B2B2B"
        case .green: return "#1A2E1A"
        }
    }
    // PDF 背景色（仅 macOS 使用）
    #if os(macOS)
    var pdfBg: NSColor {
        switch self {
        case .light: return .white
        case .green: return NSColor(red: 0.87, green: 0.94, blue: 0.87, alpha: 1)
        }
    }
    #endif
    // TXT 背景色
    var txtBg: Color {
        switch self {
        case .light: return .white
        case .green: return Color(red: 0.87, green: 0.94, blue: 0.87)
        }
    }
    // AI 侧边栏背景色（跟随阅读主题；浅色用系统默认底色）
    var panelBg: Color {
        switch self {
        case .light:
            #if os(macOS)
            return Color(nsColor: .windowBackgroundColor)
            #else
            return Color(.systemBackground)
            #endif
        case .green:
            return Color(red: 0.87, green: 0.94, blue: 0.87)
        }
    }
}
