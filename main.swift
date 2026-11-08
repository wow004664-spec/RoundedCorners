import AppKit
import ServiceManagement

let radiusKey = "cornerRadius"
let clampKey = "clampCursor"

// MARK: - 鼠标限制在圆角外（CGEventTap 改写坐标）
var clampTap: CFMachPort?
var clampRetryTimer: Timer?
var activeRadius: CGFloat = 38   // 由 OverlayController.setRadius 同步更新
var clampAppliedCount = 0        // 诊断计数

/// 文件诊断日志（统一日志不可靠时用它）
func diagLog(_ msg: String) {
    let path = "/tmp/rc_diag.log"
    let line = "\(DateFormatter.localizedString(from: Date(), dateStyle: .none, timeStyle: .medium)) \(msg)\n"
    if let handle = FileHandle(forWritingAtPath: path) {
        handle.seekToEndOfFile()
        handle.write(line.data(using: .utf8)!)
        handle.closeFile()
    } else {
        try? line.write(toFile: path, atomically: true, encoding: .utf8)
    }
}

/// 若 p 的箭头图案会压到圆角黑区，返回（光标应被钳制到的位置, 该角圆心=视觉圆角圆心）；否则 nil
/// rOuter = 视觉圆角半径（决定圆心位置）；margin = 图案距黑区的安全距离
/// glyph = 箭头图案相对 hotspot（尖端）向右/向下的延伸量，按角的方向取图案最远点判定
func cornerViolation(_ p: CGPoint, rect: CGRect, rOuter: CGFloat, margin: CGFloat, glyph: CGSize) -> (clamp: CGPoint, center: CGPoint)? {
    guard rect.contains(p), rOuter > margin else { return nil }
    let rLimit = rOuter - margin
    let lx = p.x - rect.minX, ly = p.y - rect.minY
    let w = rect.width, h = rect.height
    // 四个角的圆心（顶部下沉坐标系）——与视觉圆角同心
    let corners: [(CGFloat, CGFloat)] = [(rOuter, rOuter), (w - rOuter, rOuter), (rOuter, h - rOuter), (w - rOuter, h - rOuter)]
    for (cx, cy) in corners {
        let inX = (cx == rOuter) ? (lx < rOuter) : (lx > w - rOuter)
        let inY = (cy == rOuter) ? (ly < rOuter) : (ly > h - rOuter)
        guard inX && inY else { continue }
        // 图案朝该角方向的最远点（左角不偏移，右角偏右；上角不偏移，下角偏下）
        let offX: CGFloat = (cx == rOuter) ? 0 : glyph.width
        let offY: CGFloat = (cy == rOuter) ? 0 : glyph.height
        let wx = lx + offX, wy = ly + offY
        let dx = wx - cx, dy = wy - cy
        let d = (dx * dx + dy * dy).squareRoot()
        if d > rLimit, d > 0 {
            let s = rLimit / d
            let cwx = cx + dx * s, cwy = cy + dy * s
            let clamped = CGPoint(x: rect.minX + cwx - offX, y: rect.minY + cwy - offY)
            return (clamped, CGPoint(x: rect.minX + cx, y: rect.minY + cy))
        }
    }
    return nil
}

var lastClampLoc: CGPoint? = nil      // 上一次返回给系统的光标位置
var wallClampCount = 0                // 诊断计数

func clampCallback(_ proxy: CGEventTapProxy, _ type: CGEventType, _ event: CGEvent,
                   _ refcon: UnsafeMutableRawPointer?) -> Unmanaged<CGEvent>? {
    switch type {
    case .mouseMoved:
        // 只限制普通移动；拖拽不限制，避免拖窗口时卡住
        let loc = event.location
        let primary = NSScreen.screens.first { $0.frame.origin == .zero } ?? NSScreen.main
        let primaryH = primary?.frame.height ?? 0
        var violation: (clamp: CGPoint, center: CGPoint)? = nil
        let glyph = CGSize(width: 12, height: 18)   // 箭头图案相对 hotspot 的右下延伸
        let margin: CGFloat = 2                     // 图案距黑区的安全距离
        for screen in NSScreen.screens {
            let f = screen.frame
            // NSScreen 左下原点 -> CG 全局左上原点
            let topDown = CGRect(x: f.minX, y: primaryH - f.maxY, width: f.width, height: f.height)
            if topDown.insetBy(dx: -40, dy: -40).contains(loc) {
                violation = cornerViolation(loc, rect: topDown, rOuter: activeRadius, margin: margin, glyph: glyph)
                break
            }
        }
        if let v = violation {
            // 硬墙：任何想进入剔除区的移动一律挡在弧上
            // 往回退自然落回圆内不受影响，沿弧滑动也正常
            event.location = v.clamp
            // 关键：改写事件坐标不会移动屏幕光标，必须物理地把光标拉回墙内
            if hypot(v.clamp.x - loc.x, v.clamp.y - loc.y) > 0.5 {
                CGWarpMouseCursorPosition(v.clamp)
            }
            lastClampLoc = v.clamp
            wallClampCount += 1
            if wallClampCount <= 5 || wallClampCount % 50 == 0 {
                diagLog("wall clamp #\(wallClampCount): \(loc) -> \(v.clamp)")
            }
        } else {
            lastClampLoc = loc
        }
        return Unmanaged.passUnretained(event)
    case .tapDisabledByTimeout, .tapDisabledByUserInput:
        if let tap = clampTap { CGEvent.tapEnable(tap: tap, enable: true) }
        return nil
    default:
        return Unmanaged.passUnretained(event)
    }
}

/// warp 后系统会吞掉约 0.25s 的鼠标事件（光标卡顿感），运行时把抑制间隔清零
func disableWarpSuppression() {
    typealias SetIntervalFn = @convention(c) (CFTimeInterval) -> Void
    guard let handle = dlopen("/System/Library/Frameworks/CoreGraphics.framework/CoreGraphics", RTLD_LAZY),
          let sym = dlsym(handle, "CGSetLocalEventsSuppressionInterval") else { return }
    unsafeBitCast(sym, to: SetIntervalFn.self)(0)
}

/// 创建事件监听，返回是否成功（未授权辅助功能时失败）
@discardableResult
func setupClampTap() -> Bool {
    guard clampTap == nil else { return true }
    let mask = (1 << CGEventType.mouseMoved.rawValue)
        | (1 << CGEventType.leftMouseDragged.rawValue)
        | (1 << CGEventType.rightMouseDragged.rawValue)
        | (1 << CGEventType.otherMouseDragged.rawValue)
    guard let tap = CGEvent.tapCreate(tap: .cghidEventTap, place: .headInsertEventTap,
                                      options: .defaultTap, eventsOfInterest: CGEventMask(mask),
                                      callback: clampCallback, userInfo: nil) else {
        NSLog("RoundedCorners: clamp tap FAILED, AXIsProcessTrusted=\(AXIsProcessTrusted())")
        diagLog("tapCreate FAILED, AXIsProcessTrusted=\(AXIsProcessTrusted())")
        return false
    }
    let src = CFMachPortCreateRunLoopSource(nil, tap, 0)
    CFRunLoopAddSource(CFRunLoopGetMain(), src, .commonModes)
    CGEvent.tapEnable(tap: tap, enable: true)
    // warp 之后系统默认会吞掉 0.25s 的鼠标事件（表现为光标卡一下），清零
    disableWarpSuppression()
    clampTap = tap
    NSLog("RoundedCorners: clamp tap created OK")
    diagLog("tapCreate OK (radius=\(activeRadius))")
    return true
}

func teardownClampTap() {
    if let tap = clampTap {
        CGEvent.tapEnable(tap: tap, enable: false)
        CFMachPortInvalidate(tap)
        clampTap = nil
    }
}

// MARK: - 四角遮罩视图：整屏黑色，中间挖出圆角矩形（偶奇填充）
final class CornerOverlayView: NSView {
    var cornerRadius: CGFloat = 24 {
        didSet { needsDisplay = true }
    }

    override func draw(_ dirtyRect: NSRect) {
        let path = NSBezierPath(rect: bounds)
        path.append(NSBezierPath(roundedRect: bounds, xRadius: cornerRadius, yRadius: cornerRadius))
        path.windingRule = .evenOdd
        NSColor.black.setFill()
        path.fill()
    }
}

// MARK: - 覆盖窗口控制器：每个屏幕一个窗口
final class OverlayController: NSObject {
    private var windows: [NSWindow] = []
    private var statusItem: NSStatusItem?
    private var clampMenuItem: NSMenuItem?

    var defaultRadius: CGFloat {
        let v = UserDefaults.standard.double(forKey: radiusKey)
        return v > 0 ? CGFloat(v) : 38   // 匹配最新 MacBook 屏幕圆角（≈7.5mm）
    }

    func rebuild() {
        activeRadius = defaultRadius
        for w in windows { w.orderOut(nil) }
        windows.removeAll()

        let radius = defaultRadius
        for screen in NSScreen.screens {
            let w = NSWindow(
                contentRect: screen.frame,
                styleMask: .borderless,
                backing: .buffered,
                defer: false
            )
            w.backgroundColor = .clear
            w.isOpaque = false
            w.hasShadow = false
            w.level = .screenSaver          // 压在最上层，但在系统 UI 之下不干扰
            w.ignoresMouseEvents = true     // 不拦截任何点击
            w.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary]
            let view = CornerOverlayView(frame: NSRect(origin: .zero, size: screen.frame.size))
            view.cornerRadius = radius
            w.contentView = view
            windows.append(w)
        }
        show()
    }

    func show() {
        for w in windows {
            w.contentView?.needsDisplay = true
            w.orderFrontRegardless()
        }
    }

    func hide() {
        for w in windows { w.orderOut(nil) }
    }

    var isVisible: Bool { windows.first?.isVisible ?? false }

    func setRadius(_ r: CGFloat) {
        UserDefaults.standard.set(Double(r), forKey: radiusKey)
        activeRadius = r
        for w in windows {
            (w.contentView as? CornerOverlayView)?.cornerRadius = r
        }
    }

    // MARK: 菜单栏
    func setupStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.button?.title = "◌"
        let menu = NSMenu()

        let toggle = NSMenuItem(title: "隐藏圆角", action: #selector(toggleVisible), keyEquivalent: "h")
        toggle.target = self
        menu.addItem(toggle)

        let sliderItem = NSMenuItem()
        let slider = NSSlider(value: Double(defaultRadius), minValue: 8, maxValue: 80, target: self, action: #selector(radiusChanged(_:)))
        slider.frame = NSRect(x: 12, y: 6, width: 160, height: 22)
        slider.identifier = NSUserInterfaceItemIdentifier("radiusSlider")
        let label = NSTextField(labelWithString: "圆角")
        label.frame = NSRect(x: 0, y: 8, width: 44, height: 18)
        label.alignment = .right
        let container = NSView(frame: NSRect(x: 0, y: 0, width: 190, height: 34))
        container.addSubview(label)
        container.addSubview(slider)
        sliderItem.view = container
        menu.addItem(sliderItem)

        let presets = NSMenuItem(title: "预设风格", action: nil, keyEquivalent: "")
        let presetMenu = NSMenu()
        let presetList: [(String, CGFloat)] = [
            ("MacBook Pro 风格（38）", 38),
            ("MacBook Air 风格（42）", 42),
            ("轻微圆角（24）", 24),
        ]
        for (title, r) in presetList {
            let p = NSMenuItem(title: title, action: #selector(applyPreset(_:)), keyEquivalent: "")
            p.target = self
            p.representedObject = r
            p.state = abs(defaultRadius - r) < 0.5 ? .on : .off
            presetMenu.addItem(p)
        }
        presets.submenu = presetMenu
        menu.addItem(presets)

        let clamp = NSMenuItem(title: "鼠标避开圆角（贴边滑动）", action: #selector(toggleClamp), keyEquivalent: "m")
        clamp.target = self
        menu.addItem(clamp)
        clampMenuItem = clamp
        refreshClampItem()
        menu.addItem(.separator())

        let autoStart = NSMenuItem(title: "开机自启", action: #selector(toggleAutoStart), keyEquivalent: "s")
        autoStart.target = self
        menu.addItem(autoStart)
        refreshAutoStartItem()

        let quit = NSMenuItem(title: "退出 RoundedCorners", action: #selector(quit), keyEquivalent: "q")
        quit.target = self
        menu.addItem(quit)

        item.menu = menu
        statusItem = item
    }

    @objc private func toggleVisible() {
        if isVisible { hide() } else { show() }
        refreshMenuTitles()
    }

    @objc private func radiusChanged(_ sender: NSSlider) {
        setRadius(CGFloat(sender.doubleValue))
    }

    @objc private func applyPreset(_ sender: NSMenuItem) {
        guard let r = sender.representedObject as? CGFloat else { return }
        setRadius(r)
        if let presetMenu = sender.menu {
            for item in presetMenu.items {
                item.state = item == sender ? .on : .off
            }
        }
    }

    @objc private func toggleAutoStart() {
        let service = SMAppService.mainApp
        do {
            switch service.status {
            case .enabled:
                try service.unregister()
            case .notRegistered, .notFound:
                try service.register()
            case .requiresApproval:
                try service.register()
                SMAppService.openSystemSettingsLoginItems()
            @unknown default:
                break
            }
        } catch {
            NSLog("RoundedCorners autostart error: \(error.localizedDescription)")
        }
        refreshAutoStartItem()
    }

    private func refreshAutoStartItem() {
        guard let menu = statusItem?.menu,
              let item = menu.items.first(where: { $0.action == #selector(toggleAutoStart) }) else { return }
        item.state = SMAppService.mainApp.status == .enabled ? .on : .off
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }

    // MARK: 鼠标避开圆角
    @objc private func toggleClamp() {
        if clampTap != nil {
            teardownClampTap()
            UserDefaults.standard.set(false, forKey: clampKey)
        } else {
            UserDefaults.standard.set(true, forKey: clampKey)
            if !setupClampTap() {
                let alert = NSAlert()
                alert.messageText = "需要「辅助功能」权限"
                alert.informativeText = "限制鼠标需要监听鼠标事件。\n\n请到：系统设置 → 隐私与安全性 → 辅助功能，打开 RoundedCorners 的开关。\n\n授权后会自动生效，无需重启应用。"
                alert.addButton(withTitle: "好的")
                alert.runModal()
                // 轮询等待授权
                clampRetryTimer?.invalidate()
                clampRetryTimer = Timer.scheduledTimer(withTimeInterval: 1.5, repeats: true) { tm in
                    if AXIsProcessTrusted(), setupClampTap() {
                        tm.invalidate()
                        clampRetryTimer = nil
                        self.refreshClampItem()
                    }
                }
            }
        }
        refreshClampItem()
    }

    private func refreshClampItem() {
        guard let item = clampMenuItem else { return }
        if clampTap != nil {
            item.state = .on
            item.title = "鼠标避开圆角（已开启 · 监听运行中）"
        } else if UserDefaults.standard.bool(forKey: clampKey) {
            item.state = .off
            item.title = AXIsProcessTrusted()
                ? "鼠标避开圆角（点此重试开启）"
                : "鼠标避开圆角（需辅助功能权限）"
        } else {
            item.state = .off
            item.title = "鼠标避开圆角（贴边滑动）"
        }
    }

    private func refreshMenuTitles() {
        guard let menu = statusItem?.menu else { return }
        if let toggle = menu.items.first(where: { $0.action == #selector(toggleVisible) }) {
            toggle.title = isVisible ? "隐藏圆角" : "显示圆角"
        }
    }
}

// MARK: - 命令行开关（用于配置开机自启后立即退出）
let arguments = CommandLine.arguments
if arguments.contains("--enable-autostart") {
    do {
        try SMAppService.mainApp.register()
        print("AUTOSTART_ENABLED status=\(SMAppService.mainApp.status.rawValue)")
    } catch {
        print("AUTOSTART_ERROR \(error.localizedDescription)")
        exit(1)
    }
    exit(0)
}
if arguments.contains("--autostart-status") {
    print("AUTOSTART_STATUS=\(SMAppService.mainApp.status.rawValue)") // 0=未注册 1=已启用 2=需批准 3=未找到
    exit(0)
}

// MARK: - 入口
let app = NSApplication.shared
app.setActivationPolicy(.accessory)   // 常驻菜单栏，不出现在 Dock

let controller = OverlayController()
controller.rebuild()
controller.setupStatusItem()

// 恢复上次的鼠标限制设置
if UserDefaults.standard.bool(forKey: clampKey) {
    diagLog("startup: clampKey=true, AXIsProcessTrusted=\(AXIsProcessTrusted()), attempting tapCreate")
    let ok = setupClampTap()
    diagLog("startup: setupClampTap -> \(ok)")
    if !ok {
        // 没权限：后台轮询，一旦授权立即自动生效
        clampRetryTimer?.invalidate()
        clampRetryTimer = Timer.scheduledTimer(withTimeInterval: 1.5, repeats: true) { tm in
            if AXIsProcessTrusted(), setupClampTap() {
                tm.invalidate()
                clampRetryTimer = nil
                diagLog("retry: tapCreate OK after permission granted")
            }
        }
    }
} else {
    diagLog("startup: clampKey=false")
}

// 屏幕连接/断开/分辨率变化时重建窗口
NotificationCenter.default.addObserver(
    forName: NSApplication.didChangeScreenParametersNotification,
    object: nil, queue: .main
) { _ in
    controller.rebuild()
}

app.run()
