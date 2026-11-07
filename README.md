# 一闪 Zap

一闪是常驻 macOS 菜单栏的效率工具，作者 Benny。功能用全局快捷键唤起。

**第 1 版**是这个公开仓库的第一个对外版本。Xcode 工程里的营销版本是 **1.0**，构建号是 **1**。对外发布的 tag 是 `v1.0.0`。发布构建会改写成版本 1.0.0，后面的 `v1.0.1` 才能被更新程序认成新版本。第 1 版包含：

- **应用启动器**。从本机保存的应用索引里搜索，允许漏字和少量错字，回车打开。
- **剪贴板历史**。一闪运行时记下复制过的文本和图片。选中一条，会粘贴进当前最前面的应用，而不只是复制回剪贴板。
- **区域截图**。拖出一块区域，用可拖动的图标标注栏画上方框、箭头、铅笔、记号笔、马赛克、文字，或用橡皮擦改，然后复制、保存或置顶。复制的图片会出现在剪贴板历史里。

没有账号，没有统计。剪贴板、截图和搜索都留在你自己的电脑上。菜单栏或设置里的「检查更新…」只向 [GitHub Releases](https://github.com/Aniu456/Zap/releases) 查询有没有新版本，不上传这些内容。

仓库：<https://github.com/Aniu456/Zap>

参考了哪些公开项目、地址在哪，写在下面的[来源说明](#来源说明)。那一节用来核对许可，避免许可和开源社区上的纠纷。

英文名是 Zap，界面是简体中文，面向 zh-Hans-SG。

## 下载

到 [GitHub Releases](https://github.com/Aniu456/Zap/releases) 下载安装包。除了已经发出的 `v1.0.0`，每个版本有两份正式压缩包，按这台 Mac 的芯片选一份：

| 这台 Mac | 下载 |
| --- | --- |
| Apple 芯片（M 系列） | `Zap-<版本>-apple-silicon.zip` |
| Intel | `Zap-<版本>-intel.zip` |

M 系列 Mac 用 Apple 芯片版，Intel Mac 用 Intel 版。芯片写在苹果菜单 → 关于本机。M1、M2、M3、M4 以及以后的 M 系列都是 Apple 芯片。

安装：

1. 解压下载的 zip。
2. 把里面的 `Zap.app` 拖进「应用程序」文件夹。
3. 打开后，菜单栏里的名字是「一闪」。它不出现在程序坞。

这些构建默认没有做 Apple 公证。第一次打开如果系统提示无法验证开发者：在访达里按住 Control 点按 `Zap.app`，选择「打开」。

`v1.0.0` 仍是一份同时包含两种芯片的 `Zap-1.0.0.zip`，两种 Mac 都可以装。那个 tag 不再改写。

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

每次打开都会清空搜索框。已安装的应用写在：

```
~/Library/Application Support/Zap/app-index.json
```

这份索引在的时候，列表马上出现，打开面板不会先转圈等待扫描。一闪监听 `/Applications`、`~/Applications`、`/System/Applications`，以及它们的实用工具文件夹；这些目录有变化时在后台更新索引。Finder 也会收进索引。还没有索引文件时，列表处显示「正在读取本机应用…」。空搜索时，最近打开过的应用排在前面，最近 12 个记在本机偏好设置里。

搜索不区分大小写。先按子序列匹配：名称里可以跳过若干字符，连续命中和词首更靠前，所以 `vsc` 可以找到 Visual Studio Code，`term` 可以找到 Terminal。对不上子序列时，再用编辑距离容错。查询至少 3 个字符时允许一个错字，更长则允许两个，所以 `Xocode` 仍然可以找到 Xcode。同名应用会在旁边标出父文件夹。

## 剪贴板历史记什么

- 纯文本
- 图片（PNG、JPEG、TIFF），包括一闪自己的区域截图
- 复制文件时，把路径记成文本，不把文件本体存进历史

最多 200 条，磁盘占用默认 256 MB，两项同时生效，重启之后还在。放不下时先删掉最早、且没有置顶的记录。置顶的记录留在列表前面，会计入条数和占用，但不会被自动删除。如果只剩下置顶内容却仍然超限，设置和历史面板会提示，而不会悄悄删掉。⌘⌫ 或行末的删除按钮只去掉这一条。图片和较长的文本会在列表里标出占用。大约超过 20 万字的文本，以及大于 8 MB 的图片会跳过。带 `org.nspasteboard.ConcealedType` 或 `org.nspasteboard.TransientType` 的剪贴板不会记。

有搜索词时，用和启动器同一套匹配：先子序列，再容错少量错字。每次打开历史，搜索框都是空的。

文件在：

```
~/Library/Application Support/Zap/
```

图片在其中的 `images/`，列表在 `history.json`。

## 区域截图

按 ⌥⇧S，或从菜单栏选「区域截图」。画面会停在按下快捷键的那一刻。

1. 拖出区域。不到 8 点的拖拽会忽略，可以重画。Esc 取消。
2. 选区出现之后，标注栏是一条可拖动的图标条。默认在选区右下角：栏的右边缘和选区的右边缘对齐，选区的底边穿过栏的中线。这个位置若超出屏幕，只把它拉回可见区域。拖动整条栏可以改位置。
3. 从左到右是：方框、箭头、铅笔、记号笔、马赛克、文字、橡皮擦，然后是撤销、重做、关闭、置顶、保存、复制。数字键 1 到 7 分别是箭头、方框、文字、马赛克、铅笔、记号笔、橡皮擦。⌘Z 撤销，⌘⇧Z 重做，⌘S 把 PNG 存到你选的位置。回车、⌘C 或「复制」把 PNG 放进系统剪贴板，并写入剪贴板历史，标题是「截图」。
截图时移动鼠标可查看原图像素，置顶图也可右键开启「取色器」。按 Shift 循环切换 HEX、RGB、RGBA、Flutter 十六进制和 Flutter 十进制格式，按 C 复制当前色值。

4. 「置顶」或 ⌘P 会把图钉在其他窗口上面。拖动可以挪位置，滚轮缩放，双击、点右上角或按 Esc 都能关闭。

再按一次截图快捷键会取消当前这次选择。正在截图时，启动器和剪贴板的快捷键先不响应。

大于 8 MB 的图仍会复制到系统剪贴板，但不会写入历史。

## 怎么验收截图

在 Mac 上用 Xcode 打开工程，签名后 Run，然后按 ⌘U 跑单元测试。界面按下面走一遍：

1. 设置里能看到区域截图的快捷键，改成另一个组合后仍能唤起，改回默认也行。和另外两项冲突时会提示，不会盖掉原来的快捷键。
2. 未授予屏幕录制时，快捷键会提示去授权，启动器仍能用。
3. 授权后拖一块区域，尺寸数字跟着变。标注栏出现在选区右下角，可以拖开。画方框、箭头、铅笔、记号笔、马赛克、文字，用橡皮擦改一笔，撤销再重做，回车。也可以 ⌘S 存成 PNG。
4. 打开剪贴板历史，最上面是刚才那张图。选中它能粘贴。
5. 再截一张，点置顶。图留在其他窗口上面，拖得动，滚轮能缩放，能关掉。剪贴板保留置顶前的内容。
6. Esc 在选择过程中直接退出，不写入历史。

## 检查更新

菜单栏和设置里都有「检查更新…」。它使用 [Sparkle 2](https://sparkle-project.org)，更新说明和安装包放在这个公开仓库的 GitHub Releases 上。

更新地址写在应用里：

```
https://github.com/Aniu456/Zap/releases/latest/download/appcast.xml
```

正式包在构建时写入 EdDSA 公钥（`SUPublicEDKey`）。Sparkle 用它核对安装包的签名，再请你确认安装。私钥只放在 GitHub Actions 的 secret 里，仓库里没有私钥。

Apple 芯片安装包的更新地址是：

```
https://github.com/Aniu456/Zap/releases/latest/download/appcast-apple-silicon.xml
```

Intel 安装包的更新地址是：

```
https://github.com/Aniu456/Zap/releases/latest/download/appcast-intel.xml
```

仓库里的默认地址仍是上面的 `appcast.xml`。`v1.0.0` 的通用包继续用它。这份合并列表里，Apple 芯片的条目排在前面，并带 Sparkle 2.9 起的 `sparkle:hardwareRequirements`（值为 `arm64`）；Intel 的条目没有这项要求。Intel 机会跳过 Apple 芯片的包。Apple 芯片上如果两条版本号相同，Sparkle 2.10.1 会采用排在前面的那一条。

从 Xcode Run 出来的调试包没有这把公钥，自动检查也关着。要试更新，请安装 Release 里对应芯片的 zip。

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

下面这些是以后改用 Developer ID 时才需要的。现在不填，工作流就用 `CODE_SIGNING_ALLOWED=NO` 编译：

| Secret | 内容 |
| --- | --- |
| `APPLE_CERTIFICATE_P12_BASE64` | Developer ID Application 证书导出的 `.p12`，再做 Base64 |
| `APPLE_CERTIFICATE_PASSWORD` | 导出 p12 时设的密码 |
| `APPLE_SIGNING_IDENTITY` | 例如 `Developer ID Application: 名字 (TEAMID)` |
| `APPLE_TEAM_ID` | 10 位 Team ID。证书里已经带了团队时可以不填 |

这个工作流**不会**做 Apple 公证，也不读取公证专用的 secret。免费的 Personal Team 可以继续在自己的 Mac 上编译运行。没有 Developer ID 时，arm64 主程序的链接器签名缺少外层应用的资源封印，Sparkle 2.10.1 的 `generate_appcast` 会拒绝该包。Xcode 嵌入 Sparkle 框架时也会移除原签名覆盖的头文件等资源。打包前用 `codesign -s -` 依次给嵌入后的框架和 Zap.app 做临时签名，再递归校验。第一次打开时 Gatekeeper 仍可能提示无法验证开发者：在访达里按住 Control 点按 `Zap.app`，选择「打开」。以后如果买了 Apple Developer Program，配上表里的证书 secret，同一次 tag 构建会改为 Developer ID 签名，不再做这次临时重封。要去掉首次打开的警告，还需要另做公证和 stapler，那一步还没放进这个工作流。

### 3. 推送 tag

```bash
git checkout main
git pull origin main
git tag v1.0.1
git push origin v1.0.1
```

`v1.0.0` 已经发布，附件是通用包 `Zap-1.0.0.zip` 和 `appcast.xml`。不要强推这个 tag，也不要改写已经发出的附件。

下一次发布用更大的三段版本，例如 `v1.0.1`。工作流在 `macos-15` 上分别用 `ARCHS=arm64` 和 `ARCHS=x86_64` 编译，各自打包。成功时，Release 上会有：

- `Zap-1.0.1-apple-silicon.zip`：只含 Apple 芯片
- `Zap-1.0.1-intel.zip`：只含 Intel
- `appcast-apple-silicon.xml`：写进 Apple 芯片包的更新地址。`generate_appcast` 看到没有 Intel 切片时，会加上 `sparkle:hardwareRequirements` 为 `arm64`
- `appcast-intel.xml`：写进 Intel 包的更新地址，不声明硬件要求
- `appcast.xml`：把上面两条新版本叠在旧的通用包条目前面，给仍安装着 `v1.0.0` 的人用

两种架构分开跑 `generate_appcast`。Sparkle 2.10.1 用构建号当作唯一键，同一目录里放两份相同版本的 zip 会被拒绝。工作流用 tag 覆盖应用里的营销版本和构建号，并把旧的 appcast 条目接在新条目后面。每条安装包的下载地址留在它自己的 tag 上。当前发布的是完整 zip。Sparkle 支持增量包；这个工作流先关闭增量（`--maximum-deltas 0`），避免未签名构建产生对不上的差分文件。

不要把 tag 强推到已经发出去的版本上。用户手里的包按构建号判断新旧。

## 来源说明

这一节说明一闪参考了哪些公开项目，以及每个项目的地址。地址写在这里，是为了让任何人都能打开原件、核对许可，避免法律和开源社区上的纠纷。

一闪自己的地址是 <https://github.com/Aniu456/Zap>。许可证是 MIT，Copyright (c) 2026 Benny，全文见 [LICENSE](LICENSE)。

每个项目给两个地址。仓库地址是上游主页。对照地址固定到一次提交，相当于把参考的那一版单独指出来：对方以后继续改默认分支，这里仍能打开当时看到的树。capcap 和 Buffer 用的是讨论时指定的提交。其余 GitHub 项目没有指定提交，对照地址是写这份说明时（2026-11-07，新加坡时间）默认分支上的提交。Raycast 和 Snipaste 没有公开的源码仓库，只记产品网站。

本仓库的应用源码是为一闪编写的。下面除 Sparkle 以外，都是参考其公开的产品、交互、行为或界面；那些提交里的源文件没有放进本仓库。tinycast、macshot、Deck、OneClip 的代码不复制。Sparkle 是实际链接的依赖，许可全文随仓库放在 [ThirdParty/Sparkle/LICENSE](ThirdParty/Sparkle/LICENSE)。同一份名单也写在 [NOTICE](NOTICE)，方便随源码一起分发。

### Raycast

- 仓库地址：没有公开源码仓库。产品网站 <https://www.raycast.com>
- 许可：专有软件
- 说明：产品范围上的参考，限于启动器和剪贴板。一闪有自己的界面和实现。

### Snipaste

- 仓库地址：没有公开源码仓库。产品网站 <https://www.snipaste.com>
- 许可：专有软件
- 说明：截图体验上的参考，包括框选区域、可拖动的图标标注栏，以及贴在屏幕上。一闪的标注栏默认在选区右下角。

### capcap

- 仓库地址：<https://github.com/realskyrin/capcap>
- 对照地址：<https://github.com/realskyrin/capcap/tree/3696064b56330b23b40f4b9dfe19b693437ccb84>
- 许可：MIT，Copyright (c) 2026 realskyrin。<https://github.com/realskyrin/capcap/blob/3696064b56330b23b40f4b9dfe19b693437ccb84/LICENSE>
- 说明：参考了这一版的截图和应用外壳。该提交的 Info.plist 约为 1.7.23。本仓库没有放入 capcap 的源码，也没有放入 PermissionFlow 或 SystemSettingsKit。

### Maccy

- 仓库地址：<https://github.com/p0deje/Maccy>
- 对照地址：<https://github.com/p0deje/Maccy/tree/f0b571e32e4031d7b91ba811f50d0f33e8e5548b>
- 许可：MIT，Copyright (c) 2025 Alex Rodionov。<https://github.com/p0deje/Maccy/blob/f0b571e32e4031d7b91ba811f50d0f33e8e5548b/LICENSE>
- 说明：参考了剪贴板历史的行为，包括跳过机密类型，以及把选中内容贴回前台应用。对照过的实现说明见 <https://github.com/p0deje/Maccy/blob/f0b571e32e4031d7b91ba811f50d0f33e8e5548b/Maccy/Clipboard.swift>。参考了行为，该文件的代码没有进入本仓库。

### Buffer

- 仓库地址：<https://github.com/samirpatil2000/Buffer>
- 对照地址：<https://github.com/samirpatil2000/Buffer/tree/a1e3a1762fe8308a252c8959e3eaafd94f7cc056>
- 许可：MIT，Copyright (c) 2026 Samir Patil。<https://github.com/samirpatil2000/Buffer/blob/a1e3a1762fe8308a252c8959e3eaafd94f7cc056/LICENSE>
- 说明：只参考这一提交的剪贴板界面，包括搜索框、列表行和预览。界面目录：<https://github.com/samirpatil2000/Buffer/tree/a1e3a1762fe8308a252c8959e3eaafd94f7cc056/Views>。参考了界面，这些文件的代码没有进入本仓库。

### tinycast

- 仓库地址：<https://github.com/abue-ammar/tinycast>
- 对照地址：<https://github.com/abue-ammar/tinycast/tree/9df93751eb7fa9b56a1f0f8d0559ad4f063d272b>
- 许可：AGPL-3.0，Copyright (C) 2026 Abue Ammar。<https://github.com/abue-ammar/tinycast/blob/9df93751eb7fa9b56a1f0f8d0559ad4f063d272b/LICENSE>
- 说明：只参考启动器的交互：快捷键呼出、立刻可以输入、方向键选择、回车打开、Esc 退出。一闪的启动器是自己的代码。tinycast 的代码没有复制，也没有放进本仓库。

### Snapzy

- 仓库地址：<https://github.com/duongductrong/Snapzy>
- 对照地址：<https://github.com/duongductrong/Snapzy/tree/77d3d3feb7f46d1909dce8824f3b35d5709378a2>
- 许可：BSD-3-Clause，Copyright (c) 2026, Trong Duong Duc。<https://github.com/duongductrong/Snapzy/blob/77d3d3feb7f46d1909dce8824f3b35d5709378a2/LICENSE>
- 说明：用来对照截图功能清单。本仓库没有使用它的代码，因此没有附带它的版权声明。以后如果使用，必须保留上游的 BSD-3-Clause 声明，并在这里补上用了哪些文件。

### macshot

- 仓库地址：<https://github.com/sw33tLie/macshot>
- 对照地址：<https://github.com/sw33tLie/macshot/tree/ec1b4e9b4b94788cd07a5ba1ced4161d772c8c4c>
- 许可：GPL-3.0。<https://github.com/sw33tLie/macshot/blob/ec1b4e9b4b94788cd07a5ba1ced4161d772c8c4c/LICENSE>
- 说明：只登记地址。它的代码不复制，本仓库里没有它的源码。

### Deck

- 仓库地址：<https://github.com/yuzeguitarist/Deck>
- 对照地址：<https://github.com/yuzeguitarist/Deck/tree/34d3e0d305d789dd85f5a0b73302b51779f6f3cd>
- 许可：`deckclip/` 为 AGPL-3.0-only；其余文件保留所有权利。见该提交的 LICENSE。
- 说明：只登记地址。它的代码不复制，本仓库里没有它的源码。

### OneClip

- 仓库地址：<https://github.com/One-Clip/OneClip>
- 对照地址：<https://github.com/One-Clip/OneClip/tree/65926e371b7f2b8001b45191265381ddf9066484>
- 许可：该仓库标为 MIT。作者说明其中早期源码开源，现行完整应用是商业软件。见 <https://github.com/One-Clip/OneClip>
- 说明：只登记地址。它的代码不复制，本仓库里没有它的源码。

### Sparkle

- 仓库地址：<https://github.com/sparkle-project/Sparkle>
- 对照地址：<https://github.com/sparkle-project/Sparkle/tree/2.10.1>（提交 `ab7d71291238df6e0492143b120c9b696a35f603`）
- 许可：MIT。版权人见 <https://github.com/sparkle-project/Sparkle/blob/2.10.1/LICENSE>，同一份文本在 [ThirdParty/Sparkle/LICENSE](ThirdParty/Sparkle/LICENSE)。
- 说明：这是本仓库实际链接的第三方代码，版本 2.10.1，通过 Swift Package Manager 拉取二进制框架，用于「检查更新…」。Sparkle 的源码树没有整份放进本仓库。随一闪分发时保留上述许可。

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
                       tag 发布：分别编译 arm64 与 x86_64，打两份 zip，生成 appcast
ThirdParty/Sparkle     Sparkle 的许可文本
```

## 许可

一闪本身是 MIT，Copyright (c) 2026 Benny，见 [LICENSE](LICENSE)。

参考项目的上游地址和固定提交写在[来源说明](#来源说明)，并复制在 [NOTICE](NOTICE)。随源码分发时保留 LICENSE 和 NOTICE。

Sparkle 的 MIT 许可和它带上的其他声明见 [ThirdParty/Sparkle/LICENSE](ThirdParty/Sparkle/LICENSE)。随二进制分发时要保留这份声明。
