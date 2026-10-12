# 聚在工大 · iOS 首版

目标为 **iOS / iPadOS 26.0+**，同一 IPA 支持 iPhone 与 iPad。采用 Kotlin Multiplatform + Compose Multiplatform，SwiftUI 只负责承载共享界面。

## 本次范围

- 离线课程新增、编辑、删除，星期、节次、任意周次与学期起始日期设置。
- 窄窗口按天显示；宽度达到 840 dp 时显示七天课程，随 iPad 分屏窗口宽度自动切换。
- 安全区、软键盘、横竖屏和系统深浅色适配。
- 本机保存课表；损坏或不支持的数据不会被自动覆盖，需用户明确重置。
- 信息门户、教务、WebVPN、图书馆、新闻的浏览器入口，地址沿用 Android 的 `Constant.kt`。
- `Campus` / `CampusRegion` 从 Android 目录抽到 `common-logic/src/commonMain/kotlin`，Android 和 KMP 编译同一份源码。

**尚未迁移**：统一认证、教务自动同步、成绩、校园卡、宿舍服务、通知、桌面组件、Android 备份导入等。校园网站登录不会自动导入课程。卸载会删除本机课表。

## 目录与构建隔离

`multiplatform/core` 放共享模型、规则与存储接口；`multiplatform/composeApp` 放共享 Compose 界面以及 iOS 存储/浏览器适配器；`iosApp` 放 Swift 入口、XcodeGen 配置和构建脚本。

现有 Android 构建依赖 AGP、Android 专属库与 Kotlin 2.1.21。iOS 构建使用独立 Gradle settings，以便采用支持 Xcode 26 的 Kotlin 2.2.21 / Compose 1.9.3，不要求配置 Android SDK 或改动现有 Android 依赖版本。两个构建复用仓库的 Gradle 8.11.1 wrapper。当前 Android 尚未接入新的课表模块；后续按业务逐步接入，避免形成两套业务实现。

## 手动构建并发布 Release

1. 将本次代码提交、推送到自己的 GitHub 仓库，确保默认分支包含 `.github/workflows/ios-release.yml`。GitHub 才会显示手动运行入口。
2. 打开 **Actions → iOS IPA Release → Run workflow**。
3. 选择分支，填写 `version`（如 `0.1.0`）；默认发布为预发行版。
4. 流程先运行共享逻辑测试、共享 UI 编译及 iPhone/iPad 模拟器启动/旋转测试，然后归档真机 arm64 应用、生成 IPA、校验包结构，最后发布 Release。
5. 在 Release 下载 `HFUT-Schedule-iOS-<版本>-<构建号>-unsigned.ipa` 和 `.sha256`。即使发布步骤失败，成功构建的包仍可在 Actions 的 `ios-ipa` artifact 下载。

工作流仅 `workflow_dispatch` 触发，不会随 push 自动构建。Release 使用 `ios-v<版本>-build.<运行号>.<重试号>` 标签并指向本次构建 commit；不会覆盖 Android Release，也不会标为仓库最新正式版。

无需配置签名 Secrets。工作流使用自带 `GITHUB_TOKEN`，仅发布 job 申请 `contents: write`；仓库/组织需允许 Actions 创建 Release，并有可用的 macOS runner 配额。工具链固定 Xcode 26.0.1，runner 如果移除此版本会明确失败，升级时需同步检查 Kotlin 兼容性。

## IPA 签名说明

这里的“自签 IPA”指**下载后自行签名的未签名安装包**。CI 不冒充 Apple 签名，也不把临时 ad-hoc 代码签名当成可直接安装的签名。

下载后使用支持当前 iOS 的侧载工具，以自己的 Apple ID 或开发者证书及匹配的 provisioning profile 重签，再安装到设备。有效期、设备数量、开发者模式及权限由所用签名方式决定。仅下载 IPA 不能直接安装；不要向本仓库提交 Apple ID、密码或证书。

## 本地开发

需要 macOS、Xcode 26.0.1、JDK 17、XcodeGen（`brew install xcodegen`）。首次运行需要联网下载 Gradle、Kotlin/Native 和依赖。

```bash
# 仓库根目录；Linux 也可执行共享测试与 UI 编译
bash ./gradlew -p multiplatform :core:jvmTest :composeApp:compileKotlinJvm

# macOS：生成工程后选择 iPhone / iPad 模拟器运行
cd iosApp
xcodegen generate
open HFUTSchedule.xcodeproj

# 仓库根目录：生成待重签 IPA
IOS_VERSION=0.1.0 IOS_BUILD_NUMBER=1 bash iosApp/scripts/package-ipa.sh
```

工程默认为不签名。用 Xcode 直装真机时，需自行设置开发团队、匹配的 Bundle ID，并启用代码签名；这些个人配置不要提交。生成的 `.xcodeproj` 和 `Info.plist` 不入库，以 `project.yml` 为准。

## 验证与下一步

共享测试覆盖周次边界、跨年、周日、课程筛选与排序、输入校验、持久化往返、编辑删除、损坏数据保护。CI 的 XCUITest 覆盖两类设备启动与旋转并保留截图；仍需真机检查侧载、中文输入、动态字体、VoiceOver、iPad 分屏及冷启动数据恢复。

后续迁移优先顺序：统一认证与凭据 Keychain 存储 → Ktor 网络适配及教务课表解析 → Android/iOS 共用课表仓库 → 成绩与更多校园服务。不要将现有 Retrofit、Jsoup、Room、Context 或 SharedPreferences 引入 `commonMain`。

工具链依据：[Kotlin/Xcode 兼容表](https://kotlinlang.org/docs/multiplatform/multiplatform-compatibility-guide.html)、[macOS runner 工具清单](https://github.com/actions/runner-images/blob/main/images/macos/macos-26-Readme.md)、[Apple 注册设备分发说明](https://developer.apple.com/documentation/xcode/distributing-your-app-to-registered-devices)。
