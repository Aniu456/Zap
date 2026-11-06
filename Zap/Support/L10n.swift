import Foundation

/// Simplified Chinese UI copy. The app targets zh-Hans-SG and does not
/// switch language with the system: every user-facing string lives here.
enum L10n {
    static let appName = "一闪"
    static let tagline = "菜单栏效率工具"
    static let aboutMenu = "关于一闪"
    static let settings = "设置…"
    static let quit = "退出一闪"

    static let openLauncher = "打开启动器"
    static let openClipboard = "剪贴板历史"
    static let launcher = "启动器"
    static let clipboard = "剪贴板"

    static let searchApps = "搜索应用"
    static let searchClipboard = "搜索剪贴板历史"
    static let indexingApps = "正在读取本机应用…"
    static let noAppMatch = "没有匹配的应用"
    static let noClipMatch = "没有匹配的记录"
    static let clipboardEmpty = "还没有复制内容"
    static let clipboardEmptyHint = "复制文本或图片后，会按时间出现在这里。"
    static let imageLabel = "图片"
    static let systemLocation = "系统"
    static let applicationsLocation = "应用程序"

    static let choose = "选择"
    static let open = "打开"
    static let paste = "粘贴"
    static let close = "关闭"

    static let accessibilityGranted = "辅助功能：已授权"
    static let accessibilityMissing = "辅助功能：未授权…"
    static let accessibilityTitle = "辅助功能"
    static let accessibilityBody = "把历史直接粘贴到当前应用，需要「辅助功能」权限。未授权时，选中一条记录仍会放回系统剪贴板，再用 ⌘V 粘贴即可。启动器不依赖这项权限。"
    static let accessibilityBanner = "还没有辅助功能权限。选中后请按 ⌘V 粘贴。"
    static let accessibilityRestart = "如果刚刚打开了权限却仍不能自动粘贴，退出并重新打开一闪。"
    static let accessibilityPath = "系统设置 → 隐私与安全性 → 辅助功能 → 打开「一闪」或 Zap"
    static let grantAccess = "去授权"
    static let openSystemSettings = "打开系统设置"

    static let hotkeys = "快捷键"
    static let hotkeyHelp = "点按按键框，再按下新的组合。至少要有一个修饰键。Esc 取消。"
    static let recording = "请按下快捷键…"
    static let restoreDefaults = "恢复默认快捷键"
    static let defaultHotkeys = "默认是 ⌥Space 打开启动器，⌥⇧Space 打开剪贴板历史。"
    static let hotkeyConflict = "这个快捷键已经用于另一项功能"
    static let hotkeyRejected = "系统没有接受这个快捷键，它可能已被占用"

    static let clipboardSection = "剪贴板"
    static let clipboardLimit = "最多保留 200 条。超过约 20 万字的文本，以及大于 8 MB 的图片不会记入。标记为密码或临时内容的剪贴板会被跳过。"
    static let clearHistory = "清空历史"
    static let clearTitle = "清空剪贴板历史？"
    static let clearMessage = "本机保存的文本和图片记录会被删除。此操作无法撤销。"
    static let clearConfirm = "清空"
    static let cancel = "取消"

    static let pasteFallback = "已放回剪贴板，按 ⌘V 粘贴"
    static let launchFailed = "无法打开此应用"
    static let laterCapture = "区域截图、标注和置顶会在以后的版本加入。"
}
