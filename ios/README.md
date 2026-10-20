# 聚在工大 · 原生 iOS

使用 Swift + SwiftUI 实现，仅支持 iOS/iPadOS 26 及以上，适配 iPhone 和 iPad；通过 SwiftPM + [xtool](https://github.com/xtool-org/xtool) 交叉编译和打包，不依赖 Android 运行时、Kotlin 桥接或网页壳。独立放在 `ios/` 中，不改变 Android 构建。

## 功能覆盖

| 功能 | iOS 实现 |
| --- | --- |
| 登录 | 官方 CAS 页面完成学号、密码、验证码认证；将教务域 Cookie 交给原生 URLSession |
| 今日概览 | 今日课程、下一节课、教学周、个人日程、常用服务 |
| 课表 | 按周切换、日程列表、按实际时间排布的周视图、详情、ICS 学期日历导出 |
| 成绩 | 所有学期、学期筛选、课程搜索、按返回学分与绩点加权的参考 GPA |
| 考试 | 考试时间、地点、距考试日期天数，保留待定安排 |
| 课程 | 学期课程汇总、搜索；教务开课查询及分页 |
| 培养方案 | 手动加载，递归模块与课程列表，离线缓存 |
| 个人信息 | 姓名、学号、院系、专业、班级、校区，不缓存证件号 |
| 日程 | 本地新增、查看、删除，显示于今日概览 |
| 离线 | 原子写入缓存，断网或部分接口失败保留对应旧数据 |
| 备份 | JSON 导出和恢复；与 Android 备份格式不同，不能互相导入 |
| 偏好 | 合肥/宣城校区、深浅色、同步学期、常用服务收藏 |
| 导航 | 原生 Liquid Glass Tab 栏；iPhone 向下滚动时收起，iPad 可切换侧栏，无旧系统兼容分支 |
| iPad | 通用设备包、横竖屏与窗口缩放、宽屏双栏首页、随窗口宽度伸缩的周课表、触控板输入 |
| 其他校园服务 | 24 个官方网页入口，按学习/生活/校园分类，部分随校区切换地址 |
| 游客体验 | 明确标注的本地演示数据，不需要账号或网络 |

这是一版原生教务与校园入口客户端，尚未达到 Android 40+ 服务的完整原生功能覆盖。校园卡交易/消费分析、图书馆借阅、宿舍分数、淋浴、洗衣、校园网登录、第二课堂等目前通过官方站点入口使用；选退课、教评也交由官方教务页面完成。Android 小组件、后台服务、实时课程通知、OCR、选课自动化和 Android 专属接口没有直接移植。

## 构建

需要 xtool 1.22.2 及匹配的 SDK/工具链：Linux/WSL 使用 Swift 6.4+ 与包含 iOS 26+ SDK 的 Darwin SDK，macOS 使用 Xcode 26+ 的 Swift/iOS SDK。此工程采用 Swift 5 语言兼容模式；最低运行版本为 iOS/iPadOS 26。本机实际使用 Swift 6.4、Darwin SDK 和 xtool 1.22.2 进行 arm64 交叉编译。

- [xtool Linux/WSL 安装](https://xtool.sh/documentation/xtooldocs/installation-linux)
- [xtool macOS 安装](https://xtool.sh/documentation/xtooldocs/installation-macos)
- [xtool 配置说明](https://github.com/xtool-org/xtool/blob/main/Documentation/xtool.docc/Control.md)

在仓库根目录执行：

```sh
cd ios
python3 scripts/prepare_version.py --local
xtool dev build --configuration release --ipa
python3 scripts/check_ipa.py xtool/HFUTSchedule.ipa
```

WSL 无法挂载 AppImage 时使用：

```sh
APPIMAGE_EXTRACT_AND_RUN=1 xtool dev build --configuration release --ipa
```

构建仅生成 `ios/xtool/HFUTSchedule.ipa`，不会安装、启动、枚举设备或运行模拟器。不要在本机使用 `xtool dev`（默认会构建并运行）或 `xtool dev run`。受限环境如不能写入默认 xtool 缓存，可另外设置 `XDG_CACHE_HOME=/tmp/hfut-ios-cache`。

该 IPA **未进行开发者签名**，不能直接安装到普通 iPhone/iPad；正式安装/分发还需要自己的 Apple 开发者签名与描述文件。自动预发布的附件同样为未签名 IPA。

## 版本与自动预发布

版本格式为 `YYYY.M.D.X`，例如 `2026.10.20.3`。App 关于页面、IPA 附件名和预发布标题均显示完整版本；标签使用 `ios-2026.10.20.3`，避免与 Android 的标签混淆。

- 日期以本工作流运行创建时的 **Asia/Shanghai（北京时间）** 为准，月份和日期不补零。
- `X` 从 1 开始，按当天本 iOS 工作流的运行顺序计算，跨分支统一编号；失败、取消的运行也占用编号。它不是仓库总 `run_number`，也不把测试矩阵的每个 job 计为一次构建。
- 重跑同一次工作流沿用原日期和编号，已经发布的附件不被替换，标签不移动。当天计数依赖 GitHub 保留的运行历史；如果过滤查询超过 GitHub 的 1000 条限制，则明确失败，不使用可能重复的版本号。
- 每次分支 **push** 为其 head commit 创建一次构建，无文件路径过滤，不使用 PR、手动或 tag 触发；一次 push 含多个提交时发布其 head commit。旧提交不会被新 push 自动取消。
- 构建、核心测试、iPhone 和 iPad UI 测试全部成功后，才自动发布 **prerelease**；说明正文为触发提交的完整 commit message，保留多行信息。标签指向该 SHA，附件为 `HFUTSchedule-YYYY.M.D.X.ipa`。上传失败只留下草稿，不公开空预发布。
- 自动预发布使用 GitHub 自带的 `GITHUB_TOKEN`，仅发布 job 申请 `contents: write`，其余 job 使用只读权限；不需要额外 PAT 或 Apple 账号。

Apple 的 `CFBundleShortVersionString` 要求三段数字，因此包内使用 `YYYY.M.D`，`CFBundleVersion` 保存 `X`，自定义 `HFUTDisplayVersion` 保存四段展示版本。`scripts/prepare_version.py` 统一写入这些字段，App、xtool 和 CI 的 XCTest 宿主共用 `Info.plist`。本地构建使用当天日期和 `X=0`，不消耗 GitHub Actions 编号，也不发布。

## CI 验证

[`.github/workflows/ios.yml`](../.github/workflows/ios.yml) 的任务如下：

1. `version`：验证发布脚本，用 GitHub Actions API 获取本次运行的日内编号，后续所有 job 共用同一版本。
2. `core-tests`：macOS 上执行 `swift test --package-path ios/Core`，检查课程/成绩/考试/个人信息/培养方案解析、课程查询包装、HTTP 状态、课表 POST 请求字段、学期和教学周边界、ICS 时区/转义/UTF-8 折行，以及备份序列化。
3. `xtool-build`：使用固定 xtool 1.22.2 构建 release arm64 通用 IPA，检查 iOS 26 最低版本、iPhone/iPad 设备族、版本元数据、图标及 ATS 范围，上传带版本的 artifact。
4. `simulator-ui`：通过 iPhone/iPad 两组矩阵，分别选择最新可用的 iOS 26+ 模拟器；iPad 测试横屏导航与课表。使用演示数据运行导航、成绩和日程冒烟测试，分别上传含截图的 `.xcresult`。XcodeGen 仅生成 XCTest 宿主，发行包仍由 xtool 构建。
5. `prerelease`：等待上述所有检查成功，下载本次 IPA，然后创建草稿、上传附件、发布预发布版本；提交信息作为数据传给 API，不插入 shell 命令。

`scripts/ci-ui-tests.sh` 会拒绝在 `CI=true` 以外的环境运行。真实学校账号、校园网络与接口响应不在公共 CI 中测试，也不需要将学校密码写入 GitHub secrets。

本机不运行应用、真机或模拟器测试；可以检查发布脚本并编译核心测试代码而不执行应用测试：

```sh
swift build --package-path Core --build-tests
node --test scripts/tests/*.test.cjs
python3 -m unittest discover -s scripts/tests -p 'test_*.py'
```

演示 UI 测试使用 `--demo` 启动参数。测试数据来自 `DemoData` 和合成 fixture，不包含真实学生信息。本机没有运行该应用或任何模拟器/真机测试；CI 测试是否通过需以 Actions 执行结果为准。

## 连接与数据

- 默认使用 `https://cas.hfut.edu.cn/cas/login?service=...` 官方认证。登录页面使用非持久 WKWebView，应用不读取输入框、不注入脚本、不保存密码。
- 认证完成进入教务首页后点“完成登录”；原生客户端验证学生 ID 和业务 ID，随后同步课表、全部成绩、考试、个人信息。培养方案较大，按需加载。
- 教务地址与字段来源为现有 `network-api/.../JxglstuService.kt`、`JxglstuCourseTableResponse.kt`、`JxglstuTermLessonResponse.kt` 和 `app/.../JxglstuRepository.kt`。特别地，课表 datum 请求使用当前代码的 `{lessonIds, studentId, weekIndex}` 对象，而非旧 `docs/HfutApi.md` 中的数组示例。
- 教务域仍使用 HTTP。因此仅对 `jxglstu.hfut.edu.cn` 开启 ATS HTTP 例外；CAS 保持 HTTPS，未全局允许明文流量。使用可信校园网或系统 VPN；仅登录 WebVPN 网页不能给原生请求提供系统级网络。
- Cookie 只在内存中的 ephemeral URLSession 内使用，重启应用后需重新登录才能同步。离线查看不需重新登录。过期会话会提示重新登录，缓存保持可用。
- 账号切换时清空旧账号数据，避免混合。演示/备份恢复也不会成为真实登录状态。
- 缓存使用 iOS 完整文件保护、原子写入并排除系统云备份。备份不包含 Cookie/密码。退出删除本地个人缓存；用户分享出去的文件需自行管理。
- GPA 按筛选后的返回记录计算，没有推断重修覆盖规则或专业排名，以学校认定为准。同步时间表示最近有数据成功更新；部分接口失败会提示并保留旧数据。

## 目录与依赖

```text
ios/
  Package.swift, xtool.yml, Info.plist  # 原生应用打包
  Sources/HFUTSchedule/                # SwiftUI、状态、认证与本地持久化
  Core/                               # 独立可测试的 Foundation 数据与网络层
    Sources/HFUTCore/
    Tests/HFUTCoreTests/               # 合成 HTML/JSON fixture 与契约测试
  Resources/AppIcon.png               # 复用本项目现有应用图标
  UITests/, project.yml               # CI 专用 XCTest 宿主工程
  scripts/                            # 版本注入、预发布、静态 IPA 检查及 CI 测试
  Licenses/SwiftSoup-MIT.txt
```

唯一应用外部依赖为 [SwiftSoup 2.8.8](https://github.com/scinfu/SwiftSoup/tree/2.8.8)，固定版本并提交 `Package.resolved`，用于容错解析教务 HTML。应用与原项目沿用根目录 Apache-2.0 许可；SwiftSoup 使用 MIT 许可。应用无统计上报或第三方业务后端。
