# Sparkle

一闪通过 Swift Package Manager 链接 [Sparkle](https://github.com/sparkle-project/Sparkle) 2.10.1，用来检查更新。这里不存放 Sparkle 的源码，只保留它要求随软件分发的许可文本。

- 项目：https://github.com/sparkle-project/Sparkle
- 版本：2.10.1（提交 `ab7d71291238df6e0492143b120c9b696a35f603`）
- 许可：MIT，全文见 [LICENSE](LICENSE)
- 用途：菜单栏和设置里的「检查更新…」，以及 GitHub Releases 上的 appcast

仓库里只有公钥会在发布构建时写入应用。EdDSA 私钥留在本机钥匙串和 GitHub Actions secret `SPARKLE_PRIVATE_KEY` 里，不进入 git。
