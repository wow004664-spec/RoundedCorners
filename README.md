# RoundedCorners

把 Mac 屏幕的四个角变成圆角的菜单栏小工具，效果对标最新 MacBook（MacBook Pro / Air）的屏幕圆角。

![](https://img.shields.io/badge/platform-macOS%2010.13%2B-lightgrey) ![](https://img.shields.io/badge/license-MIT-blue) ![](https://img.shields.io/badge/swift-5-orange)

## 功能

- 屏幕四角黑色遮罩，中间挖出圆角——整块屏幕看起来就是圆角屏
- **预设风格**：MacBook Pro（38）/ MacBook Air（42）/ 轻微圆角（24），一键切换
- 滑杆自由调整圆角半径（8–80），设置自动保存
- 菜单栏常驻（◌ 图标），可随时显示 / 隐藏
- 支持多显示器、多桌面空间、全屏应用
- 不拦截鼠标点击、不抢焦点
- 开机自启（基于系统登录项 SMAppService）

## 安装

从 [Releases](../../releases) 下载 `RoundedCorners-x.x.x.dmg`，把应用拖进 Applications 文件夹，双击打开即可。

> 首次打开如果提示"无法验证开发者"，在应用上右键 → 打开，或到
> 系统设置 → 隐私与安全性 → 点"仍要打开"。
> （本应用为 ad-hoc 签名的开源工具，没有付费的开发者证书）

## 从源码构建

```bash
./build.sh
# 产物: build/RoundedCorners.app 和 dist/RoundedCorners-1.0.0.dmg
```

只需要 macOS 自带的 Command Line Tools（`xcode-select --install`），不需要完整 Xcode。

## 使用

运行后菜单栏右侧出现 ◌ 图标：

| 菜单项 | 说明 |
|---|---|
| 显示/隐藏圆角 | 临时开关遮罩 |
| 圆角（滑杆） | 8–80 自由调节 |
| 预设风格 | 三档预设一键切换 |
| 开机自启 | 注册/取消系统登录项 |
| 退出 | 结束应用 |

## 原理

应用为每块屏幕创建一个无边框透明覆盖窗口（`level = .screenSaver`，不拦截鼠标事件，跟随所有桌面空间），用 `NSBezierPath` 偶奇填充绘制四个角的黑色遮罩、挖出中间圆角区域，视觉上屏幕即为圆角。

## License

MIT
