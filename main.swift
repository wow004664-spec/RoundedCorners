import AppKit
import ServiceManagement

let radiusKey = "cornerRadius"

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

    var defaultRadius: CGFloat {
        let v = UserDefaults.standard.double(forKey: radiusKey)
        return v > 0 ? CGFloat(v) : 38   // 匹配最新 MacBook 屏幕圆角（≈7.5mm）
    }

    func rebuild() {
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

// 屏幕连接/断开/分辨率变化时重建窗口
NotificationCenter.default.addObserver(
    forName: NSApplication.didChangeScreenParametersNotification,
    object: nil, queue: .main
) { _ in
    controller.rebuild()
}

app.run()
