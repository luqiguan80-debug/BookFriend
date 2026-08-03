import AppKit

// BookFriend App 图标：午夜深底 + 书脊竖条，一本琥珀色斜出（Friend）
// 用法: swift Tools/render_icon.swift <输出.png>

let size: CGFloat = 1024
let outPath = CommandLine.arguments[1]

let image = NSImage(size: NSSize(width: size, height: size))
image.lockFocus()
let ctx = NSGraphicsContext.current!.cgContext

// ── 背景：午夜蓝黑，中心微提亮 ──
let bgDeep = NSColor(calibratedRed: 0.066, green: 0.078, blue: 0.098, alpha: 1) // #11141A
let bgLift = NSColor(calibratedRed: 0.105, green: 0.122, blue: 0.152, alpha: 1) // #1B1F27
ctx.setFillColor(bgDeep.cgColor)
ctx.fill(CGRect(x: 0, y: 0, width: size, height: size))
if let grad = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(),
                         colors: [bgLift.cgColor, bgDeep.cgColor] as CFArray,
                         locations: [0, 1]) {
    ctx.drawRadialGradient(grad,
        startCenter: CGPoint(x: 512, y: 540), startRadius: 0,
        endCenter: CGPoint(x: 512, y: 540), endRadius: 780,
        options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])
}

// ── 书脊：微圆角矩形（书是方的，半圆顶会变冰棍）──
let cream = NSColor(calibratedRed: 0.953, green: 0.933, blue: 0.898, alpha: 1)  // #F3EEE5
let amber = NSColor(calibratedRed: 0.85, green: 0.63, blue: 0.25, alpha: 1)     // #D9A140

func bookSpine(x: CGFloat, y0: CGFloat, w: CGFloat, h: CGFloat, color: NSColor) {
    let p = NSBezierPath(roundedRect: CGRect(x: x, y: y0, width: w, height: h),
                         xRadius: 10, yRadius: 10)
    color.setFill()
    p.fill()
}

// 两根奶油色书脊，等高齐底
bookSpine(x: 330, y0: 300, w: 84, h: 400, color: cream)
bookSpine(x: 438, y0: 300, w: 84, h: 400, color: cream)

// 琥珀色书脊：贴着第二根、绕左下角斜出 15°（正在被抽出的那本 = Friend）
ctx.saveGState()
ctx.translateBy(x: 518, y: 300)
ctx.rotate(by: -15 * .pi / 180)
ctx.translateBy(x: -518, y: -300)
bookSpine(x: 518, y0: 300, w: 84, h: 400, color: amber)
ctx.restoreGState()

// 书架线：把三根书脊「放」在同一平面上
let shelf = NSBezierPath(roundedRect: CGRect(x: 296, y: 262, width: 384, height: 12),
                         xRadius: 6, yRadius: 6)
cream.withAlphaComponent(0.35).setFill()
shelf.fill()

image.unlockFocus()

// ── 导出 PNG ──
guard let tiff = image.tiffRepresentation,
      let rep = NSBitmapImageRep(data: tiff),
      let png = rep.representation(using: .png, properties: [:]) else {
    fatalError("PNG 导出失败")
}
try png.write(to: URL(fileURLWithPath: outPath))
print("已生成: \(outPath)")
