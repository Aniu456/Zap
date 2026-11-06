# 一闪 Zap

一闪是常驻 macOS 菜单栏的效率工具，作者 Benny。功能用全局快捷键唤起。

**第 1 版**是这个公开仓库的第一个对外版本。Xcode 工程里的营销版本是 **1.0**，构建号是 **1**。对外发布的 tag 是 `v1.0.0`。发布构建会改写成版本 1.0.0，后面的 `v1.0.1` 才能被更新程序认成新版本。第 1 版包含：

- **应用启动器**。模糊搜索这台 Mac 上安装的应用，回车打开。
- **剪贴板历史**。一闪运行时记下复制过的文本和图片。选中一条，会粘贴进当前最前面的应用，而不只是复制回剪贴板。
- **区域截图**。拖出一块区域，用箭头、方框、文字、马赛克标注，然后复制或置顶。复制的图片会出现在剪贴板历史里。

没有账号，没有统计。剪贴板、截图和搜索都留在你自己的电脑上。菜单栏或设置里的「检查更新…」只向 [GitHub Releases](https://github.com/Aniu456/Zap/releases) 查询有没有新版本，不上传这些内容。

仓库：<https://github.com/Aniu456/Zap>

英文名是 Zap，界面是简体中文，面向 zh-Hans-SG。

## 环境

- macOS 14 或更高
- Xcode 16 或更高

第一次用 Xcode 打开工程时，会从 Swift Package Manager 拉取 [Sparkle 2.10.1](https://github.com/sparkle-project/Sparkle)。它只负责检查更新。

## 打开并运行

1. 克隆这个仓库。
2. 用 Xcode 打开 `Zap.xcodeproj`。
3. 顶部 scheme 选 **Zap**。
4. 选中 Zap target 的 Signing & Capabilities，把 Team 设成你的 Apple ID。只在本机运行时，也可以选 Sign to Run Locally。Team 写在本机，不要提交 `DEVELOPMENT_TEAM`。
5. 按 Run。

一闪不会出现在程序坞里。看屏幕最上方菜单栏里的图标：四角选区，中间一道闪电。

辅助功能权限和代码签名绑在一起。换了签名之后，系统里要重新勾选一次。

从 Xcode 直接 Run 的包没有写入 Sparkle 公钥。「检查更新…」要等下面的 GitHub Release 装上之后才验得过签名。

单元测试在 ZapTests。菜单 Product → Test，或按 ⌘U。

## 权限

区域截图需要**屏幕录制**：

系统设置 → 隐私与安全性 → 屏幕录制 → 打开「一闪」或 Zap。

可以在菜单栏或设置里点「去授权」。如果开关已经打开却仍截不到画面，退出并重新打开一闪。没有这项权限时，启动器和剪贴板历史照常使用。

把历史直接粘贴到当前应用，需要**辅助功能**：

系统设置 → 隐私与安全性 → 辅助功能 → 打开「一闪」或 Zap。

可以在菜单栏或设置里点「去授权」。系统会把一闪加进列表，你再打开开关。有的系统要退出并重新打开一闪，自动粘贴才会生效。

没有这项权限时：

- 启动器照常使用。
- 剪贴板历史照常浏览和搜索。选中一条会放回系统剪贴板，再按 ⌘V 粘贴。

全局快捷键走系统热键，一般不靠辅助功能。如果某个组合没反应，用菜单栏打开功能，再到设置里换一个。

## 默认快捷键

| 功能 | 快捷键 |
| --- | --- |
| 启动器 | ⌥Space |
| 剪贴板历史 | ⌥⇧Space |
| 区域截图 | ⌥⇧S |

三个都可以在设置里改。点按键框，按下新的组合，至少带一个修饰键。Esc 取消。功能之间不能用同一个组合。

启动器和剪贴板历史打开同一块浮动面板，只是模式不同。再按一次当前模式的快捷键，面板会关掉。每次打开都会清空搜索框。

面板里：

| 按键 | 作用 |
| --- | --- |
| ↑ ↓ | 选择 |
| ↩ | 打开应用，或粘贴这条历史 |
| esc | 关闭 |
| ⌘⌫ | 在剪贴板历史里删除当前这一条 |

中文输入法还在组词时，方向键、回车和 Esc 先交给候选窗。

## 启动器

启动时在后台扫描本机的「应用程序」目录，包括 `/Applications`、`~/Applications`、`/System/Applications` 和它们的实用工具文件夹，另外加上 Finder。扫到的列表留在内存里。面板打开时如果超过大约 30 秒没有扫过，会再扫一次。空搜索时，最近打开过的应用排在前面，这份最近列表存在本机偏好设置里，最多 12 个。

搜索是子序列模糊匹配，不区分大小写。名称里可以跳过若干字符，连续命中和词首更靠前。例如输入 `vsc` 可以找到 Visual Studio Code，输入 `term` 可以找到 Terminal。同名应用会在旁边标出父文件夹。

## 剪贴板历史记什么

- 纯文本
- 图片（PNG、JPEG、TIFF），包括一闪自己的区域截图
- 复制文件时，把路径记成文本，不把文件本体存进历史

最多 200 条，重启之后还在。选中一条后可以在行末置顶。置顶的记录留在列表前面，也不会被这 200 条的上限自动清掉。⌘⌫ 或行末的删除按钮只去掉这一条。大约超过 20 万字的文本，以及大于 8 MB 的图片会跳过。带 `org.nspasteboard.ConcealedType` 或 `org.nspasteboard.TransientType` 的剪贴板不会记。

有搜索词时，按同一套子序列规则匹配文本。每次打开历史，搜索框都是空的。

文件在：

```
~/Library/Application Support/Zap/
```

图片在其中的 `images/`，列表在 `history.json`。

## 区域截图

按 ⌥⇧S，或从菜单栏选「区域截图」。画面会停在按下快捷键的那一刻。

1. 拖出区域。不到 8 点的拖拽会忽略，可以重画。Esc 取消。
2. 选区出现之后，工具栏贴在选区下方；下方放不下就改到上方，并尽量留在屏幕里面。从左到右是文字按钮：箭头、方框、文字、马赛克、撤销、复制、置顶、取消。
3. 数字键 1 到 4 切换工具，⌘Z 撤销，回车或「复制」把 PNG 放进系统剪贴板，并写入剪贴板历史，标题是「截图」。
4. 「置顶」或 ⌘P 会同样复制，再把图钉在其他窗口上面。拖动可以挪位置，滚轮缩放，双击回到原始大小，悬停后点右上角或按 Esc 关闭。

再按一次截图快捷键会取消当前这次选择。正在截图时，启动器和剪贴板的快捷键先不响应。

大于 8 MB 的图仍会复制到系统剪贴板，但不会写入历史。

## 怎么验收截图

在 Mac 上用 Xcode 打开工程，签名后 Run，然后按 ⌘U 跑单元测试。界面按下面走一遍：

1. 设置里能看到区域截图的快捷键，改成另一个组合后仍能唤起，改回默认也行。和另外两项冲突时会提示，不会盖掉原来的快捷键。
2. 未授予屏幕录制时，快捷键会提示去授权，启动器仍能用。
3. 授权后拖一块区域，尺寸数字跟着变。画箭头、方框、文字、马赛克，撤销一次，回车。
4. 打开剪贴板历史，最上面是刚才那张图。选中它能粘贴。
5. 再截一张，点置顶。图留在其他窗口上面，拖得动，滚轮能缩放，能关掉。历史里也有这一张。
6. Esc 在选择过程中直接退出，不写入历史。

## 检查更新

菜单栏和设置里都有「检查更新…」。它使用 [Sparkle 2](https://sparkle-project.org)，更新说明和安装包放在这个公开仓库的 GitHub Releases 上。

更新地址写在应用里：

```
https://github.com/Aniu456/Zap/releases/latest/download/appcast.xml
```

正式包在构建时写入 EdDSA 公钥（`SUPublicEDKey`）。Sparkle 用它核对安装包的签名，再请你确认安装。私钥只放在 GitHub Actions 的 secret 里，仓库里没有私钥。

从 Xcode Run 出来的调试包没有这把公钥，自动检查也关着。要试更新，请安装 Release 里的 zip。

第一次发布之前，上面的地址还不存在，「检查更新…」会失败。推送 tag `v1.0.0` 并且 Actions 成功之后才有可装的包。

## 发布第 1 版

合并到 `main` 之后，在你自己的 Mac 上做一次密钥，再推送 tag。这个仓库的 Actions 会在 `macos-15` 上编译、打包、签名更新包，并创建 GitHub Release。不需要自己先做一个二进制再上传。

Linux 和云端环境编译不了这套 Xcode 工程，所以密钥要用 Mac 上的 Sparkle 工具生成。

### 1. 生成 EdDSA 密钥

密钥只生成一次。换密钥之后，已经发出去的旧包认不出新的更新。

```bash
curl -fsSL -o Sparkle-2.10.1.tar.xz \
  https://github.com/sparkle-project/Sparkle/releases/download/2.10.1/Sparkle-2.10.1.tar.xz
tar -xJf Sparkle-2.10.1.tar.xz
# 压缩包里的目录名以解压结果为准，进入含有 bin/generate_keys 的那一层。
./bin/generate_keys
./bin/generate_keys -x "$HOME/zap-sparkle-private-key.txt"
```

第一条命令会在「钥匙串访问」里保存私钥，并在终端打印 `SUPublicEDKey` 下面那一行公钥。第二条把同一把私钥导出到文本文件。文件内容是一行 Base64。

不要把 `zap-sparkle-private-key.txt` 提交进 git，也不要贴到 Issue 或 Pull Request 里。用完可以从钥匙串里留着，方便以后在本机签名；给 Actions 用的是导出的那一行。

### 2. 把密钥放进 GitHub Secrets

打开仓库的 Settings → Secrets and variables → Actions → New repository secret。

| Secret | 必填 | 内容 |
| --- | --- | --- |
| `SPARKLE_PRIVATE_KEY` | 是 | `zap-sparkle-private-key.txt` 里的那一行，不要加引号 |
| `SPARKLE_PUBLIC_KEY` | 是 | `generate_keys` 打印的 `SUPublicEDKey` 字符串 |

两个必须是一对。发布脚本会把公钥写进 `Zap.app` 的 Info.plist，再用私钥给 zip 做 EdDSA 签名。对不上的话，Actions 会在生成 appcast 时失败，不会发出一个无法验证的包。

下面这些是以后改用 Developer ID 时才需要的。现在不填，工作流就用 `CODE_SIGNING_ALLOWED=NO` 打未签名的包：

| Secret | 内容 |
| --- | --- |
| `APPLE_CERTIFICATE_P12_BASE64` | Developer ID Application 证书导出的 `.p12`，再做 Base64 |
| `APPLE_CERTIFICATE_PASSWORD` | 导出 p12 时设的密码 |
| `APPLE_SIGNING_IDENTITY` | 例如 `Developer ID Application: 名字 (TEAMID)` |
| `APPLE_TEAM_ID` | 10 位 Team ID。证书里已经带了团队时可以不填 |

这个工作流**不会**做 Apple 公证，也不读取公证专用的 secret。免费的 Personal Team 可以继续在自己的 Mac 上编译运行。对外下载的未签名包，第一次打开时 Gatekeeper 可能提示无法验证开发者：在访达里按住 Control 点按 `Zap.app`，选择「打开」。以后如果买了 Apple Developer Program，配上表里的证书 secret，同一次 tag 构建会改为 Developer ID 签名。要去掉首次打开的警告，还需要另做公证和 stapler，那一步还没放进这个工作流。

### 3. 推送 tag

```bash
git checkout main
git pull origin main
git tag v1.0.0
git push origin v1.0.0
```

推送之后打开 Actions 里的 Release 工作流。成功时，<https://github.com/Aniu456/Zap/releases/tag/v1.0.0> 上会有：

- `Zap-1.0.0.zip`：解压后是 `Zap.app`
- `appcast.xml`：Sparkle 的更新列表

下一次发布用更大的三段版本，例如 `v1.0.1`。工作流用 tag 覆盖应用里的营销版本和构建号，并把旧的 appcast 条目接在新条目后面。每条安装包的下载地址留在它自己的 tag 上。当前发布的是完整 zip。Sparkle 支持增量包；这个工作流先关闭增量（`--maximum-deltas 0`），避免未签名构建产生对不上的差分文件。

不要把 tag 强推到已经发出去的版本上。用户手里的包按构建号判断新旧。

## 参考与致谢

下面每一项都写明了许可，以及当前仓库实际用了什么。一闪的 Swift 和 Objective-C 源码是为本项目写的。树里没有 vendored 第三方源码目录，源文件里也没有这些项目的版权头。

| 项目 | 许可 | 地址 | 当前仓库里的关系 |
| --- | --- | --- | --- |
| [Raycast](https://www.raycast.com) | 专有软件 | <https://www.raycast.com> | 产品范围上的参考，只涉及启动器和剪贴板。一闪有自己的界面和实现。 |
| [Snipaste](https://www.snipaste.com) | 专有软件 | <https://www.snipaste.com> | 截图体验上的参考：框选区域、标注、贴在屏幕上。一闪的工具栏是自己的文字按钮，出现在选区下方。 |
| [capcap](https://github.com/realskyrin/capcap) | MIT，Copyright (c) 2026 realskyrin | [提交 3696064](https://github.com/realskyrin/capcap/tree/3696064b56330b23b40f4b9dfe19b693437ccb84) | 截图和应用外壳的既有实现，讨论时那一版 Info.plist 约为 1.7.23。当前树没有纳入 capcap 的源码，也没有 PermissionFlow 或 SystemSettingsKit。 |
| [Maccy](https://github.com/p0deje/Maccy) | MIT，Copyright (c) 2025 Alex Rodionov | <https://github.com/p0deje/Maccy> | 剪贴板历史的行为参考：跳过机密类型，把选中的内容贴回前台应用。参考了行为，未复制其代码。 |
| [Buffer](https://github.com/samirpatil2000/Buffer) | MIT，Copyright (c) 2026 Samir Patil | [提交 a1e3a17](https://github.com/samirpatil2000/Buffer/tree/a1e3a1762fe8308a252c8959e3eaafd94f7cc056) | 剪贴板界面的参考，看过搜索框、列表行和预览。参考了界面，未复制其代码。 |
| [tinycast](https://github.com/abue-ammar/tinycast) | AGPL-3.0，Copyright (C) 2026 Abue Ammar | <https://github.com/abue-ammar/tinycast> | 只参考启动器的交互：快捷键呼出、立刻可以输入、方向键选择、回车打开、Esc 退出。一闪的启动器是自己的代码，没有复制 tinycast。 |
| [Snapzy](https://github.com/duongductrong/Snapzy) | BSD-3-Clause，Copyright (c) 2026, Trong Duong Duc | <https://github.com/duongductrong/Snapzy> | 可以用来对照截图功能清单。当前树没有复用它的代码，所以没有附带它的版权声明。以后如果真的复用，必须保留上游的 BSD-3-Clause 声明。 |
| [macshot](https://github.com/sw33tLie/macshot) | GPL-3.0 | <https://github.com/sw33tLie/macshot> | 代码不得复制。当前树里没有它的源码。 |
| [Deck](https://github.com/yuzeguitarist/Deck) | `deckclip/` 为 AGPL-3.0-only；其余文件保留所有权利 | <https://github.com/yuzeguitarist/Deck> | 代码不得复制。当前树里没有它的源码。 |
| [OneClip](https://github.com/One-Clip/OneClip) | 仓库中早期源码为 MIT；现行完整应用是商业软件 | <https://github.com/One-Clip/OneClip> | 代码不得复制。当前树里没有它的源码。 |
| [Sparkle](https://github.com/sparkle-project/Sparkle) | MIT。版权人见 [ThirdParty/Sparkle/LICENSE](ThirdParty/Sparkle/LICENSE) | 2.10.1，<https://github.com/sparkle-project/Sparkle> | 实际链接的依赖，用来检查更新。许可全文放在 `ThirdParty/Sparkle/`。 |

tinycast、macshot、Deck、OneClip 这四个名字只作为不能复制的既有作品记在这里。核对过当前树的源文件、注释和目录，没有它们的代码。

capcap、Maccy、Buffer、Snapzy 同样没有被复制进这棵树。表里写的是参考了哪些行为和界面。Sparkle 是唯一打进应用的第三方代码，通过 Swift Package Manager 拉取 2.10.1 的二进制框架，源码不在本仓库里。

## 工程

```
Zap.xcodeproj          用 Xcode 打开这个
Config/Sparkle-Info.plist
                       公开的更新地址。公钥由发布构建写入
Zap/App                菜单栏应用入口，不占程序坞，并挂上 Sparkle
Zap/Launcher           扫描本机应用并做模糊搜索
Zap/Clipboard          监听剪贴板、保存历史、模拟粘贴
Zap/Palette            启动器和历史共用的浮动面板
Zap/Hotkeys            全局快捷键，可在设置里改
Zap/Capture            区域截图、标注、复制和置顶
ZapTests               模糊匹配、历史去重、选区和马赛克的单元测试
.github/workflows/release.yml
                       tag 发布：编译、zip、appcast、GitHub Release
ThirdParty/Sparkle     Sparkle 的许可文本
```

## 许可

一闪本身是 MIT，Copyright (c) 2026 Benny，见 [LICENSE](LICENSE)。

Sparkle 的 MIT 许可和它带上的其他声明见 [ThirdParty/Sparkle/LICENSE](ThirdParty/Sparkle/LICENSE)。随二进制分发时要保留这份声明。
