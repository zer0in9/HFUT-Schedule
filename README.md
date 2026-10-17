# 聚在工大 · iOS 适配版（HFUT-Schedule）

本项目是对 [Chiu-xaH/HFUT-Schedule](https://github.com/Chiu-xaH/HFUT-Schedule) 的 **iOS / iPadOS 适配**，面向合肥工业大学学生，支持 **iOS / iPadOS 26.0 及以上的 iPhone 和 iPad**。

采用 Kotlin Multiplatform（KMP）与 Compose Multiplatform，逐步迁移上游的校园服务功能。通过 **GitHub Actions 手动触发构建供自行签名安装的 IPA，并自动发布到本仓库的 Release**。

## 下载与安装

前往 [本项目 Releases](https://github.com/zer0in9/HFUT-Schedule/releases) 下载构建成功后发布的 `.ipa`，同一安装包支持 iPhone 和 iPad。Release 同时提供 SHA-256 校验文件。

这里的“自签 IPA”指供用户下载后自行重签的安装包：**CI 生成的是未签名 IPA，不能直接安装**。请使用自己的 Apple ID 或开发者证书，通过侧载工具完成签名和安装，无需向本仓库提供 Apple ID、密码或签名证书。

### AltStore 订阅安装

在 **AltStore Classic → Sources → +** 中添加以下订阅地址：

```text
https://github.com/zer0in9/HFUT-Schedule/releases/download/altstore/source.json
```

订阅源在包含此功能的工作流首次成功发布后生效，之后每次发布自动更新，包含预览版本。添加后可在 AltStore 中安装或更新「聚在工大」，仍需通过自己的 Apple ID 签名，要求 iOS / iPadOS 26.0 及以上。本订阅用于 AltStore Classic。

## 手动构建与发布

1. 打开本仓库的 [Actions → iOS IPA Release](https://github.com/zer0in9/HFUT-Schedule/actions/workflows/ios-release.yml)。
2. 点击 **Run workflow**，选择构建分支并填写版本号（如 `0.1.0`）。
3. 按需选择是否发布为预发行版，默认开启。
4. 工作流依次执行共享代码测试、iPhone / iPad 模拟器检查、真机应用归档和 IPA 打包校验，成功后自动发布到 **Release**。

工作流仅通过手动触发运行，不随代码 push 自动构建。成功构建的 IPA 也会保存在该次 Actions 运行的 `ios-ipa` artifact 中。

如需在自己的 Fork 中构建，请先确保默认分支包含工作流文件，并在自己的仓库中执行以上操作；仓库需允许 GitHub Actions 创建 Release。

## 适配进度

当前为 iOS 适配首版，已实现：

- 离线课程新增、编辑、删除及本机保存。
- 学期起始日期、星期、节次和周次设置。
- iPhone 按天查看、iPad 宽屏整周展示及窗口宽度自适应。
- 横竖屏、安全区、软键盘和系统深浅色适配。
- 信息门户、教务、WebVPN、图书馆和新闻的浏览器入口。

统一认证、教务课表自动同步、成绩、校园卡、通知和桌面组件等功能尚未迁移。校园网站登录不会自动导入课程，当前也不支持导入上游备份；卸载应用会删除本机课表。

## 开发文档

- [iOS 本地构建、安装与迁移说明](iosApp/README.md)
- [GitHub Actions 构建工作流](.github/workflows/ios-release.yml)
- [KMP 迁移规划](docs/technical/ToKmp.md)
- [上游开发文档](docs/Developer.md)
- [上游校园 API 资料](docs/HfutApi.md)

仓库保留上游代码及历史文档以支持逐步迁移；其中的原平台功能描述不代表 iOS 版已实现。

## 上游与致谢

感谢 [Chiu-xaH/HFUT-Schedule](https://github.com/Chiu-xaH/HFUT-Schedule) 原作者及所有贡献者。本项目基于其代码进行 iOS 适配，原项目的代码、资源及贡献归属保持不变。

许可证见 [LICENSE](LICENSE)。
