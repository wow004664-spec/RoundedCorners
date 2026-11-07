import AppKit
import CoreGraphics

// 生成 1024x1024 应用图标：深色圆角底 + 白色大圆角"屏幕"
let S: CGFloat = 1024
let cs = CGColorSpaceCreateDeviceRGB()
let ctx = CGContext(data: nil, width: Int(S), height: Int(S), bitsPerComponent: 8,
                    bytesPerRow: 0, space: cs,
                    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!

// 底板（macOS 风格留边 + 连续圆角近似）
let inset: CGFloat = 100
let plate = CGRect(x: inset, y: inset, width: S - inset * 2, height: S - inset * 2)
let platePath = CGPath(roundedRect: plate, cornerWidth: plate.width * 0.2237,
                       cornerHeight: plate.height * 0.2237, transform: nil)
ctx.saveGState()
ctx.addPath(platePath)
ctx.clip()
let colors = [
    NSColor(calibratedRed: 0.13, green: 0.14, blue: 0.18, alpha: 1).cgColor,
    NSColor(calibratedRed: 0.29, green: 0.32, blue: 0.42, alpha: 1).cgColor,
] as CFArray
let grad = CGGradient(colorsSpace: cs, colors: colors, locations: [0, 1])!
ctx.drawLinearGradient(grad,
                       start: CGPoint(x: plate.minX, y: plate.maxY),
                       end: CGPoint(x: plate.maxX, y: plate.minY),
                       options: [])
ctx.restoreGState()

// 外发光描边
ctx.addPath(platePath)
ctx.setStrokeColor(NSColor(white: 1, alpha: 0.16).cgColor)
ctx.setLineWidth(6)
ctx.strokePath()

// 屏幕：白色大圆角矩形，四角夸张以呼应"圆角屏幕"
let screenInsetX: CGFloat = 178
let screenInsetY: CGFloat = 232
let screen = plate.insetBy(dx: screenInsetX, dy: screenInsetY)
let radius = screen.width * 0.30
let screenPath = CGPath(roundedRect: screen, cornerWidth: radius, cornerHeight: radius, transform: nil)

ctx.saveGState()
ctx.setShadow(offset: .zero, blur: 40, color: NSColor(white: 0, alpha: 0.35).cgColor)
ctx.addPath(screenPath)
ctx.setFillColor(NSColor(calibratedWhite: 0.97, alpha: 1).cgColor)
ctx.fillPath()
ctx.restoreGState()

// 屏幕内的顶部菜单栏暗示
let barHeight = screen.height * 0.13
let barRect = CGRect(x: screen.minX, y: screen.maxY - barHeight, width: screen.width, height: barHeight)
ctx.saveGState()
ctx.addPath(screenPath)
ctx.clip()
ctx.setFillColor(NSColor(calibratedRed: 0.35, green: 0.42, blue: 0.95, alpha: 1).cgColor)
ctx.fill(barRect)
ctx.restoreGState()

// 输出 PNG
let image = ctx.makeImage()!
let rep = NSBitmapImageRep(cgImage: image)
let out = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "icon_1024.png"
try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: out))
print("icon written: \(out)")
