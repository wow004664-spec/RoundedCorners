import AppKit
import CoreGraphics

// ===== 画布参数 =====
var W: CGFloat = 1080
var H: CGFloat = 1920
let FPS: Int = 30
let DURATION: Double = 20.0
let TOTAL = Int(DURATION * Double(FPS))

let outDir = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "/tmp/promo_frames"
let iconPath = CommandLine.arguments.count > 2 ? CommandLine.arguments[2] : "build/icon_1024.png"
let iconImage = NSImage(contentsOfFile: iconPath)?.cgImage(forProposedRect: nil, context: nil, hints: nil)

// ===== 缓动 =====
func clamp(_ v: Double, _ a: Double = 0, _ b: Double = 1) -> Double { min(max(v, a), b) }
func easeOut(_ t: Double) -> Double { let x = clamp(t); return 1 - pow(1 - x, 3) }
func easeInOut(_ t: Double) -> Double {
    let x = clamp(t)
    return x < 0.5 ? 4 * x * x * x : 1 - pow(-2 * x + 2, 3) / 2
}
/// 区间进度 0..1
func prog(_ t: Double, _ start: Double, _ end: Double) -> Double { clamp((t - start) / (end - start)) }

// ===== 颜色 =====
func rgb(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat, _ a: CGFloat = 1) -> CGColor {
    CGColor(srgbRed: r, green: g, blue: b, alpha: a)
}
let accent = rgb(0.31, 0.56, 1.0)

func withAlpha(_ c: CGColor, _ a: CGFloat) -> CGColor { c.copy(alpha: a) ?? c }
let bgTop = rgb(0.043, 0.051, 0.071)
let bgBottom = rgb(0.086, 0.098, 0.137)

// ===== 字体 =====
func font(_ size: CGFloat, _ weight: NSFont.Weight = .semibold) -> NSFont {
    NSFont.systemFont(ofSize: size, weight: weight)
}

func drawText(_ text: String, center: CGPoint, size: CGFloat, weight: NSFont.Weight = .semibold,
              color: NSColor = .white, alpha: CGFloat = 1, tracking: CGFloat = 0) {
    guard alpha > 0.01 else { return }
    let para = NSMutableParagraphStyle()
    para.alignment = .center
    var attrs: [NSAttributedString.Key: Any] = [
        .font: font(size, weight),
        .foregroundColor: color.withAlphaComponent(alpha),
        .paragraphStyle: para,
    ]
    if tracking != 0 { attrs[.kern] = tracking }
    let s = NSAttributedString(string: text, attributes: attrs)
    let bounds = s.size()
    s.draw(at: CGPoint(x: center.x - bounds.width / 2, y: center.y - bounds.height / 2))
}

// ===== 背景 =====
func drawBackground(_ ctx: CGContext, t: Double) {
    let grad = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(),
                          colors: [bgTop, bgBottom] as CFArray, locations: [0, 1])!
    ctx.drawLinearGradient(grad, start: CGPoint(x: 0, y: H), end: CGPoint(x: W, y: 0), options: [])
    // 缓慢漂移的柔光
    let phase = sin(t * 0.35)
    let glow = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: [
        rgb(0.31, 0.56, 1.0, 0.26),
        rgb(0.31, 0.56, 1.0, 0),
    ] as CFArray, locations: [0, 1])!
    ctx.drawRadialGradient(glow,
        startCenter: CGPoint(x: W * 0.5 + CGFloat(phase) * 90, y: H * 0.66),
        startRadius: 0,
        endCenter: CGPoint(x: W * 0.5 + CGFloat(phase) * 90, y: H * 0.66),
        endRadius: 780, options: [])
}

// ===== 拟真 macOS 桌面 =====
func drawDesktop(_ ctx: CGContext, rect: CGRect, t: Double, cornerRadius: CGFloat) {
    ctx.saveGState()

    // 壁纸（Sonoma 风格渐变 + 光斑）
    let wallClip = CGPath(roundedRect: rect, cornerWidth: cornerRadius, cornerHeight: cornerRadius, transform: nil)
    ctx.addPath(wallClip)
    ctx.clip()
    let wg = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: [
        rgb(0.16, 0.20, 0.42), rgb(0.36, 0.20, 0.46), rgb(0.72, 0.32, 0.42),
    ] as CFArray, locations: [0, 0.55, 1])!
    ctx.drawLinearGradient(wg, start: CGPoint(x: rect.minX, y: rect.maxY),
                           end: CGPoint(x: rect.maxX, y: rect.minY), options: [])
    for (i, c) in [rgb(0.45, 0.35, 0.85, 0.55), rgb(0.95, 0.55, 0.45, 0.45), rgb(0.30, 0.60, 0.85, 0.40)].enumerated() {
        let g = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(),
                           colors: [c, withAlpha(c, 0)] as CFArray, locations: [0, 1])!
        let cx = rect.minX + rect.width * [0.22, 0.78, 0.55][i] + CGFloat(sin(t * 0.3 + Double(i)) * 12)
        let cy = rect.minY + rect.height * [0.72, 0.62, 0.25][i]
        ctx.drawRadialGradient(g, startCenter: CGPoint(x: cx, y: cy), startRadius: 0,
                               endCenter: CGPoint(x: cx, y: cy), endRadius: rect.width * 0.45, options: [])
    }

    // 顶部菜单栏
    let barH: CGFloat = rect.height * 0.035
    ctx.setFillColor(rgb(0.06, 0.07, 0.10, 0.55))
    ctx.fill(CGRect(x: rect.minX, y: rect.maxY - barH, width: rect.width, height: barH))
    // 菜单栏元素（左侧苹果点 + 右侧状态点）
    ctx.setFillColor(rgb(1, 1, 1, 0.85))
    let dotY = rect.maxY - barH / 2
    ctx.fillEllipse(in: CGRect(x: rect.minX + 22, y: dotY - 4, width: 8, height: 8))
    for i in 0..<3 {
        let x = rect.maxX - 30 - CGFloat(i) * 16
        ctx.fillEllipse(in: CGRect(x: x, y: dotY - 3.5, width: 7, height: 7))
    }
    // 菜单栏文字块
    ctx.setFillColor(rgb(1, 1, 1, 0.55))
    for i in 0..<3 {
        ctx.fill(CGRect(x: rect.minX + 46 + CGFloat(i) * 42, y: dotY - 3, width: 32, height: 6))
    }

    // 中央窗口
    let winW = rect.width * 0.62, winH = rect.height * 0.52
    let win = CGRect(x: rect.midX - winW / 2, y: rect.midY - winH / 2 - rect.height * 0.03, width: winW, height: winH)
    ctx.setShadow(offset: CGSize(width: 0, height: -14), blur: 40, color: rgb(0, 0, 0, 0.45))
    let winPath = CGPath(roundedRect: win, cornerWidth: 12, cornerHeight: 12, transform: nil)
    ctx.addPath(winPath)
    ctx.setFillColor(rgb(0.98, 0.98, 0.99))
    ctx.fillPath()
    ctx.setShadow(offset: .zero, blur: 0, color: nil)

    // 标题栏 + 红黄绿点
    ctx.saveGState()
    ctx.addPath(winPath)
    ctx.clip()
    ctx.setFillColor(rgb(0.94, 0.94, 0.96))
    ctx.fill(CGRect(x: win.minX, y: win.maxY - 34, width: win.width, height: 34))
    for (i, c) in [rgb(1.0, 0.37, 0.34), rgb(1.0, 0.74, 0.18), rgb(0.16, 0.79, 0.25)].enumerated() {
        ctx.setFillColor(c)
        ctx.fillEllipse(in: CGRect(x: win.minX + 16 + CGFloat(i) * 20, y: win.maxY - 24, width: 12, height: 12))
    }
    // 内容行
    ctx.setFillColor(rgb(0.80, 0.82, 0.86))
    for i in 0..<6 {
        let w = win.width * [0.72, 0.88, 0.64, 0.80, 0.55, 0.70][i]
        ctx.fill(CGRect(x: win.minX + 26, y: win.maxY - 78 - CGFloat(i) * 30, width: w, height: 11))
    }
    ctx.restoreGState()

    // Dock
    let dockW = rect.width * 0.34, dockH: CGFloat = 46
    let dock = CGRect(x: rect.midX - dockW / 2, y: rect.minY + 14, width: dockW, height: dockH)
    ctx.addPath(CGPath(roundedRect: dock, cornerWidth: 14, cornerHeight: 14, transform: nil))
    ctx.setFillColor(rgb(1, 1, 1, 0.22))
    ctx.fillPath()
    for i in 0..<5 {
        let s: CGFloat = 26
        let x = dock.minX + 16 + CGFloat(i) * (s + 12)
        ctx.addPath(CGPath(roundedRect: CGRect(x: x, y: dock.midY - s / 2, width: s, height: s),
                           cornerWidth: 7, cornerHeight: 7, transform: nil))
        ctx.setFillColor(rgb(1, 1, 1, 0.55))
        ctx.fillPath()
    }

    ctx.restoreGState()

    // 圆角遮罩（黑角）
    if cornerRadius > 0.5 {
        let path = CGMutablePath()
        path.addRect(rect)
        path.addRoundedRect(in: rect, cornerWidth: cornerRadius, cornerHeight: cornerRadius)
        ctx.addPath(path)
        ctx.setFillColor(rgb(0.02, 0.02, 0.03))
        ctx.fillPath(using: .evenOdd)
    }
}

// ===== 圆角高亮描边（演示用）=====
func drawCornerHighlight(_ ctx: CGContext, rect: CGRect, radius: CGFloat, alpha: CGFloat) {
    guard alpha > 0.01, radius > 1 else { return }
    ctx.saveGState()
    ctx.addPath(CGPath(roundedRect: rect.insetBy(dx: -3, dy: -3),
                       cornerWidth: radius + 3, cornerHeight: radius + 3, transform: nil))
    ctx.setStrokeColor(rgb(0.31, 0.56, 1.0, alpha))
    ctx.setLineWidth(4)
    ctx.strokePath()
    ctx.restoreGState()
}

// ===== 主渲染 =====
func renderFrame(_ t: Double) -> CGImage {
    let cs = CGColorSpaceCreateDeviceRGB()
    let ctx = CGContext(data: nil, width: Int(W), height: Int(H), bitsPerComponent: 8,
                        bytesPerRow: 0, space: cs,
                        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    ctx.setShouldAntialias(true)
    ctx.interpolationQuality = .high

    let gctx = NSGraphicsContext(cgContext: ctx, flipped: false)
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = gctx

    drawBackground(ctx, t: t)

    // 桌面 mock 位置与尺寸（16:10）
    let mockW = W * 0.82
    let mockH = mockW * 0.625
    let mock = CGRect(x: (W - mockW) / 2, y: H * 0.50 - mockH / 2 + 40, width: mockW, height: mockH)
    let scale = mockW / 1440.0     // 以 1440pt 屏幕为基准
    let targetRadius = 38 * scale

    // ---- 时间轴 ----
    // S1 0-3.2s 标题
    let s1 = easeOut(prog(t, 0.15, 0.9))
    let s1out = 1 - easeOut(prog(t, 2.9, 3.4))

    // S2 3.2-15.4s 桌面 mock（圆角动画发生在它身上）
    let s2in = easeOut(prog(t, 3.2, 4.0))
    let s2out = 1 - easeOut(prog(t, 14.8, 15.6))
    // "四角是方的" 文案单独淡出
    let s2textout = 1 - easeOut(prog(t, 9.0, 9.6))

    // 圆角动画：10.0 -> 11.4s
    let radiusT = easeInOut(prog(t, 10.0, 11.4))
    let radius = t < 10.0 ? 0 : targetRadius * radiusT

    // S3 文案
    let s3in = easeOut(prog(t, 11.5, 12.2))
    let s3out = 1 - easeOut(prog(t, 14.6, 15.2))

    // S4 预设 chips 15.2-18.2
    let s4in = easeOut(prog(t, 15.2, 16.0))
    let s4out = 1 - easeOut(prog(t, 18.0, 18.6))

    // S5 收尾 18.4-20
    let s5in = easeOut(prog(t, 18.4, 19.3))

    // ---- 绘制桌面 ----
    if s2in > 0.01 && s2out > 0.01 {
        let appear = easeOut(prog(t, 3.2, 4.4))
        let yOff = (1 - appear) * -80
        let m = mock.offsetBy(dx: 0, dy: yOff)
        ctx.saveGState()
        ctx.setAlpha(CGFloat(appear * s2out))
        drawDesktop(ctx, rect: m, t: t, cornerRadius: radius)
        // 方角状态下，四角画高亮提示
        if t < 10.0 {
            drawCornerHighlight(ctx, rect: m, radius: 6, alpha: CGFloat(0.55 * s2out))
        } else if radiusT > 0.98 {
            drawCornerHighlight(ctx, rect: m, radius: radius, alpha: CGFloat(0.45 * s3in * s3out))
        }
        ctx.restoreGState()
    }

    // ---- S1 标题 ----
    if s1 > 0.01 && s1out > 0.01 {
        let a = CGFloat(s1 * s1out)
        drawText("旧 MacBook", center: CGPoint(x: W / 2, y: H * 0.72 + 60), size: 96, weight: .bold,
                 color: .white, alpha: a, tracking: 2)
        drawText("也能有圆角屏", center: CGPoint(x: W / 2, y: H * 0.72 - 60), size: 96, weight: .bold,
                 color: NSColor(cgColor: accent)!, alpha: a, tracking: 2)
        drawText("一块免费开源的小工具", center: CGPoint(x: W / 2, y: H * 0.72 - 160), size: 40, weight: .medium,
                 color: .white, alpha: a * 0.65)
    }

    // ---- S2 文案：四角是方的 ----
    if s2in > 0.01 && s2textout > 0.01 {
        let a = CGFloat(s2in * s2textout)
        drawText("屏幕四角 又直又硬", center: CGPoint(x: W / 2, y: H * 0.80), size: 64, weight: .bold,
                 color: .white, alpha: a)
        drawText("边框到边角像刀切出来一样", center: CGPoint(x: W / 2, y: H * 0.80 - 90), size: 38, weight: .regular,
                 color: .white, alpha: a * 0.6)
    }

    // ---- S3 文案：变圆角 ----
    if s3in > 0.01 && s3out > 0.01 {
        let a = CGFloat(s3in * s3out)
        let pop = 1 + (1 - s3in) * 0.25
        drawText("一键变圆角", center: CGPoint(x: W / 2, y: H * 0.155), size: 76 * pop, weight: .bold,
                 color: NSColor(cgColor: accent)!, alpha: a)
        drawText("Pro 风格 · 半径 38pt", center: CGPoint(x: W / 2, y: H * 0.155 - 86), size: 36, weight: .medium,
                 color: .white, alpha: a * 0.62)
    }

    // ---- S4 预设 chips ----
    if s4in > 0.01 && s4out > 0.01 {
        let a = CGFloat(s4in * s4out)
        let items = [("Pro", "38pt"), ("Air", "42pt"), ("轻微", "24pt")]
        let chipW: CGFloat = 250, chipH: CGFloat = 116
        let gap: CGFloat = 26
        let totalW = chipW * 3 + gap * 2
        var x = (W - totalW) / 2
        let active = t > 16.0 && t < 16.45 ? 1 : (t >= 16.45 && t < 16.9 ? 1 : 0)
        _ = active
        for (i, item) in items.enumerated() {
            let appear = easeOut(prog(t, 15.3 + Double(i) * 0.12, 15.9 + Double(i) * 0.12))
            let y = H * 0.145 + (1 - appear) * -30
            let r = CGRect(x: x, y: y, width: chipW, height: chipH)
            let highlight = i == 0
            ctx.addPath(CGPath(roundedRect: r, cornerWidth: 28, cornerHeight: 28, transform: nil))
            ctx.setFillColor(highlight ? withAlpha(accent, 0.22 * a) : rgb(1, 1, 1, 0.07 * a))
            ctx.fillPath()
            if highlight {
                ctx.addPath(CGPath(roundedRect: r, cornerWidth: 28, cornerHeight: 28, transform: nil))
                ctx.setStrokeColor(withAlpha(accent, 0.9 * a))
                ctx.setLineWidth(3)
                ctx.strokePath()
            }
            drawText(item.0, center: CGPoint(x: r.midX, y: r.midY + 16), size: 42, weight: .semibold,
                     color: highlight ? NSColor(cgColor: accent)! : .white, alpha: a)
            drawText(item.1, center: CGPoint(x: r.midX, y: r.midY - 30), size: 30, weight: .regular,
                     color: .white, alpha: a * 0.6)
            x += chipW + gap
        }
        drawText("三种风格随便切", center: CGPoint(x: W / 2, y: H * 0.145 + chipH + 62), size: 46, weight: .semibold,
                 color: .white, alpha: a * 0.9)
    }

    // ---- S5 收尾 ----
    if s5in > 0.01 {
        let a = CGFloat(s5in)
        if let icon = iconImage {
            let size: CGFloat = 240
            let r = CGRect(x: (W - size) / 2, y: H * 0.60, width: size, height: size)
            ctx.saveGState()
            ctx.setShadow(offset: CGSize(width: 0, height: -12), blur: 50, color: rgb(0, 0, 0, 0.5))
            ctx.draw(icon, in: r)
            ctx.restoreGState()
        }
        drawText("RoundedCorners", center: CGPoint(x: W / 2, y: H * 0.44), size: 78, weight: .bold,
                 color: .white, alpha: a, tracking: 1)
        drawText("开源免费 · macOS 10.13+", center: CGPoint(x: W / 2, y: H * 0.44 - 86), size: 38, weight: .regular,
                 color: .white, alpha: a * 0.62)
        // 地址胶囊
        let pillW: CGFloat = 860, pillH: CGFloat = 96
        let pill = CGRect(x: (W - pillW) / 2, y: H * 0.24, width: pillW, height: pillH)
        ctx.addPath(CGPath(roundedRect: pill, cornerWidth: pillH / 2, cornerHeight: pillH / 2, transform: nil))
        ctx.setFillColor(withAlpha(accent, 0.16 * a))
        ctx.fillPath()
        ctx.addPath(CGPath(roundedRect: pill, cornerWidth: pillH / 2, cornerHeight: pillH / 2, transform: nil))
        ctx.setStrokeColor(withAlpha(accent, 0.55 * a))
        ctx.setLineWidth(2)
        ctx.strokePath()
        drawText("github.com/wow004664-spec/RoundedCorners",
                 center: CGPoint(x: pill.midX, y: pill.midY), size: 34, weight: .medium,
                 color: .white, alpha: a)
        drawText("GitHub 搜 RoundedCorners 即可下载", center: CGPoint(x: W / 2, y: H * 0.24 - 84), size: 32,
                 weight: .regular, color: .white, alpha: a * 0.55)
    }

    NSGraphicsContext.restoreGraphicsState()
    return ctx.makeImage()!
}

// ===== 输出 =====
let fm = FileManager.default
try? fm.createDirectory(atPath: outDir, withIntermediateDirectories: true)
let mode = CommandLine.arguments.count > 3 ? CommandLine.arguments[3] : "video"

func writePNG(_ img: CGImage, path: String) {
    let rep = NSBitmapImageRep(cgImage: img)
    try? rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: path))
}

if mode == "cover" {
    // 3:4 封面：标题在上 + 圆角桌面在下
    W = 1080; H = 1440
    let cs = CGColorSpaceCreateDeviceRGB()
    let ctx = CGContext(data: nil, width: Int(W), height: Int(H), bitsPerComponent: 8,
                        bytesPerRow: 0, space: cs,
                        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    let gctx = NSGraphicsContext(cgContext: ctx, flipped: false)
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = gctx
    drawBackground(ctx, t: 2.0)

    let mockW = W * 0.86
    let mockH = mockW * 0.625
    let mock = CGRect(x: (W - mockW) / 2, y: H * 0.46 - mockH / 2, width: mockW, height: mockH)
    let targetRadius = 38 * (mockW / 1440.0)
    drawDesktop(ctx, rect: mock, t: 4.0, cornerRadius: targetRadius)
    drawCornerHighlight(ctx, rect: mock, radius: targetRadius, alpha: 0.5)

    drawText("旧 MacBook", center: CGPoint(x: W / 2, y: H * 0.895), size: 104, weight: .bold,
             color: .white, tracking: 2)
    drawText("也能有圆角屏", center: CGPoint(x: W / 2, y: H * 0.805), size: 104, weight: .bold,
             color: NSColor(cgColor: accent)!, tracking: 2)
    // 底部胶囊
    let pillW: CGFloat = 720, pillH: CGFloat = 84
    let pill = CGRect(x: (W - pillW) / 2, y: 60, width: pillW, height: pillH)
    ctx.addPath(CGPath(roundedRect: pill, cornerWidth: pillH / 2, cornerHeight: pillH / 2, transform: nil))
    ctx.setFillColor(withAlpha(accent, 0.16))
    ctx.fillPath()
    ctx.addPath(CGPath(roundedRect: pill, cornerWidth: pillH / 2, cornerHeight: pillH / 2, transform: nil))
    ctx.setStrokeColor(withAlpha(accent, 0.55))
    ctx.setLineWidth(2)
    ctx.strokePath()
    drawText("开源免费 · GitHub 搜 RoundedCorners", center: CGPoint(x: pill.midX, y: pill.midY), size: 32,
             weight: .medium, color: .white)
    writePNG(ctx.makeImage()!, path: "\(outDir)/cover.png")
    print("cover written")
} else if mode == "preview" {
    // 导出若干关键帧用于检查
    for t in [1.5, 6.0, 9.0, 13.0, 17.0, 19.5] {
        writePNG(renderFrame(t), path: "\(outDir)/frame_\(String(format: "%.1f", t)).png")
    }
    print("previews written to \(outDir)")
} else {
    for i in 0..<TOTAL {
        let t = Double(i) / Double(FPS)
        let img = renderFrame(t)
        writePNG(img, path: "\(outDir)/f_\(String(format: "%04d", i)).png")
        if i % 60 == 0 { print("frame \(i)/\(TOTAL)") }
    }
    print("all frames written: \(TOTAL)")
}
