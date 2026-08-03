#if os(macOS)
import SwiftUI
import AppKit

extension ToolbarItemPlacement {
    static var topBarLeading: ToolbarItemPlacement { .navigation }
    static var topBarTrailing: ToolbarItemPlacement { .primaryAction }
}

extension NSColor {
    static let secondarySystemBackground = NSColor.controlBackgroundColor
}
#endif
