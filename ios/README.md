# 聚在工大 · 原生 iOS

使用 Swift + SwiftUI 实现，仅支持 iOS/iPadOS 26 及以上，适配 iPhone 和 iPad；通过 SwiftPM + [xtool](https://github.com/xtool-org/xtool) 交叉编译和打包，不依赖 Android 运行时、Kotlin 桥接或网页壳。独立放在 `ios/` 中，不改变 Android 构建。

## 功能覆盖

| 功能 | iOS 实现 |
| --- | --- |
| 登录 | 官方 CAS 页面完成学号、密码、验证码认证；将教务域 Cookie 交给原生 URLSession |
| 账号配置 | “我的 → 账号与密码”统一管理 CAS、慧新易校校园卡、呱呱淋浴；直接新增、修改或删除，无需额外设备身份验证 |
| 今日概览 | 校园卡余额、浴室水费余额、今日课程、下一节课、教学周、个人日程、常用服务 |
| 自动刷新 | 冷启动、各数据页下拉和同步按钮共用调度；汇总教务、余额及已提交开课查询的进度和结果 |
| 课表 | 按周切换、日程列表、按实际时间排布的周视图、详情、ICS 学期日历导出 |
| 成绩 | 所有学期、学期筛选、课程搜索、按返回学分与绩点加权的参考 GPA |
| 考试 | 考试时间、地点、距考试日期天数，保留待定安排 |
| 课程 | 学期课程汇总、搜索；教务开课查询及分页 |
| 培养方案 | 随统一刷新更新，递归模块与课程列表，离线缓存；页面也可手动触发统一刷新 |
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

Apple 的 `CFBundleShortVersionString` 要求三段数字，因此包内使用 `YYYY.M.D`，`CFBundleVersion` 保存 `X`，自定义 `HFUTDisplayVersion` 保存四段展示版本。`scripts/prepare_version.py` 统一写入这些字段，App、xtool 和 CI 的 XCTest 宿主共用 `HFUTSchedule/Info.plist`。本地构建使用当天日期和 `X=0`，不消耗 GitHub Actions 编号，也不发布。

## CI 验证

[`.github/workflows/ios.yml`](../.github/workflows/ios.yml) 的任务如下：

1. `version`：验证发布脚本，用 GitHub Actions API 获取本次运行的日内编号，后续所有 job 共用同一版本。
2. `core-tests`：macOS 上执行 `swift test --package-path ios/Packages/HFUTCore`，检查课程/成绩/考试/个人信息/培养方案解析、课程查询包装、HTTP 状态、课表 POST 请求字段、学期和教学周边界、ICS 时区/转义/UTF-8 折行，以及备份序列化。
3. `xtool-build`：使用固定 xtool 1.22.2 构建 release arm64 通用 IPA，检查 iOS 26 最低版本、iPhone/iPad 设备族、版本元数据、图标及 ATS 范围，上传带版本的 artifact。CI 直接调用 macOS 应用内部程序时设置 `XTL_CLI=1`，与官方 CLI 启动脚本一致，避免启动 GUI 后一直等待；安装步骤先输出版本以检查入口。
4. `simulator-ui`：通过 iPhone/iPad 两组矩阵，分别选择最新可用的 iOS 26+ 模拟器；iPad 测试横屏导航与课表。宿主单元测试使用内存会话和假网络验证冷启动恢复、并发刷新合并、登录期间排队、等待余额结束、余额与培养方案失败汇总、过期仅重试失败项、查询分页重置和退出后丢弃迟到响应；UI 冒烟测试使用演示数据检查导航、成绩和日程，分别上传含截图的 `.xcresult`。XcodeGen 生成共享源码的应用与 XCTest 工程，发行包仍由 xtool 构建。
5. `prerelease`：等待上述所有检查成功，下载本次 IPA，然后创建草稿、上传附件、发布预发布版本；提交信息作为数据传给 API，不插入 shell 命令。

`scripts/ci-ui-tests.sh` 会拒绝在 `CI=true` 以外的环境运行。真实学校账号、校园网络与接口响应不在公共 CI 中测试，也不需要将学校密码写入 GitHub secrets。

本机不运行应用、真机或模拟器测试；可以检查发布脚本并编译核心测试代码而不执行应用测试：

```sh
swift build --package-path Packages/HFUTCore --build-tests
node --test scripts/tests/*.test.cjs
python3 -m unittest discover -s scripts/tests -p 'test_*.py'
```

演示 UI 测试使用 `--demo` 启动参数。测试数据来自 `DemoData` 和合成 fixture，不包含真实学生信息。本机没有运行该应用或任何模拟器/真机测试；CI 测试是否通过需以 Actions 执行结果为准。

## 连接与数据

- 默认使用 `https://cas.hfut.edu.cn/cas/login?service=...` 官方认证。登录页面使用非持久 WKWebView，并从本机钥匙串恢复有效的 CAS 会话；不读取网页输入的密码。用户主动点“填入已保存账号”时，通过 WebKit 参数绑定向官方 HTTPS CAS 表单填入配置的凭据，不自动提交验证码表单、不把密码插入脚本源码。
- 认证完成进入教务首页后点“完成登录”；原生客户端验证学生 ID 和业务 ID，随后统一同步课表与学期课程、全部成绩、考试、个人信息、培养方案，并刷新已配置的余额账号。
- 教务地址与字段来源为现有 `network-api/.../JxglstuService.kt`、`JxglstuCourseTableResponse.kt`、`JxglstuTermLessonResponse.kt` 和 `app/.../JxglstuRepository.kt`。特别地，课表 datum 请求使用当前代码的 `{lessonIds, studentId, weekIndex}` 对象，而非旧 `docs/HfutApi.md` 中的数组示例。
- 教务和慧新易校沿用学校现有 HTTP 接口，仅对 `jxglstu.hfut.edu.cn` 与 `121.251.19.62` 开启 ATS HTTP 例外；CAS 和呱呱淋浴保持 HTTPS，未全局允许明文流量。使用可信校园网或系统 VPN；仅登录 WebVPN 网页不能给原生请求提供系统级网络。
- 网络层使用 ephemeral URLSession；将严格限定到教务域和 CAS 域的 Cookie 与对应学生 ID 存入本机钥匙串，保留 Secure、HttpOnly 和过期属性。CAS Cookie 强制仅通过 HTTPS 发送，TGC 保持 HttpOnly。不再以本地三小时期限淘汰会话：冷启动先恢复未到 Cookie 过期时间的会话，再以服务端身份校验为准。
- 教务过期后，每轮刷新最多续登一次：先尝试 CAS 单点登录；若需重新认证且用户保存了统一认证密码，则按 Android 上游 `checkInitParams`（`vercode`）、`LOGIN_FLAVORING`、AES/ECB/PKCS7 与表单字段契约登录。密码仅提交到官方 HTTPS CAS 地址。验证码或认证拒绝会持久暂停该账号的密码自动尝试，修改并保存可重新启用；仍可手动完成官方网页认证。
- 所有重定向逐跳检查主机、协议和端口。教务业务请求不会自动跳到 CAS；独立续登流程只访问 CAS 与教务官方地址，跨跳转重新创建 GET，不转发密码 POST。403、未知跳转和网络故障不当作凭据失效。退出时取消旧 URLSession 并替换独立 Cookie 存储，防止迟到响应重新带入旧会话。
- 密码只在“我的 → 账号与密码”中明确保存，使用独立的 `WhenUnlockedThisDeviceOnly` 钥匙串条目，关闭同步，不写入 UserDefaults、缓存、日志或导出文件。管理入口直接打开，无需额外的 Face ID、Touch ID 或设备密码验证。密码不回显，留空修改仅保留同一账号的原密码。非活动时清空密码输入并遮蔽页面；设备解锁时，自动续登可按需读取密码。
- 账号切换时清空旧账号数据，避免混合。演示/备份恢复也不会成为真实登录状态。
- 缓存使用 iOS 完整文件保护、原子写入并排除系统云备份。备份不包含 Cookie/密码。退出、切换教务账号、进入演示和导入备份都会清理保存的账号密码；退出还删除本地个人缓存。用户分享出去的文件需自行管理。
- GPA 按筛选后的返回记录计算，没有推断重修覆盖规则或专业排名，以学校认定为准。同步时间表示最近有数据成功更新；部分接口失败会提示并保留旧数据。

## 刷新交互

“今天”页在问候卡片下显示校园卡与浴室水费余额。首次点按各自卡片连接账号：校园卡使用学号和慧新易校校园卡查询密码，浴室水费使用呱呱淋浴手机号和密码；这两个会话与教务会话独立。详情页支持刷新、更换账号和断开连接。校园卡将 `db_balance` 与 `unsettle_amount` 相加后由分换算为元，与 Android 端保持一致；淋浴读取 `accountMoney`，由千分之一元换算为元，不合并赠送余额。金额显示两位小数。首页余额卡片不显示上次更新时间，详情页保留最近更新时间；首页仍显示连接、刷新中及错误状态。

余额接口契约来自 `network-api` 的 `HuiXinService`、`GuaGuaService` 及其响应模型。校园卡沿用 `Constant.HUI_XIN_URL` 的 `http://121.251.19.62/`，通过 `POST berserker-auth/oauth/token` 提交 `username`、`password`、`grant_type=password`、`logintype=sno`，携带与 Android 一致的 Basic 客户端认证；随后通过 `GET berserker-app/ykt/tsm/getCampusCards` 与 `synjones-auth: bearer <token>` 查询。此流程不经过 CAS，不使用信息门户密码。仅对这一 IP 添加 ATS HTTP 例外；iOS 17 及以上支持在 [Apple 官方 NSExceptionDomains 配置](https://developer.apple.com/documentation/bundleresources/information-property-list/nsapptransportsecurity/nsexceptiondomains) 中指定单个 IP，应用最低版本为 iOS 26。界面提示使用可信校园网或 VPN。

淋浴通过 `https://bathing.hfut.edu.cn/` 请求，密码按上游要求取 MD5 的最后十位大写十六进制字符后提交。余额详情中的临时登录仅保存令牌；在统一账号入口明确保存后，原始密码留在本机钥匙串，登录时按需计算摘要。校园卡查询密码也只在统一入口明确保存；学校接口仍为 HTTP，界面提示使用可信校园网或系统 VPN，不能将钥匙串保护等同于传输加密。登录令牌与最近一次余额存入另一个钥匙串条目，不进入 JSON 备份，退出、切换教务账号、进入演示或导入备份时清除；旧版信息门户校园卡令牌和对应余额会被移除，保留淋浴账号，避免向慧新易校发送其他服务的凭据。

本地真实接口验证使用已被 Git 忽略的 `local-accounts.json`：`huixin.student_number` 与 `huixin.query_password` 用于校园卡，`shower.phone_number` 与 `shower.password` 用于淋浴；`portal` 中的统一认证密码不会用于校园卡。按用户要求限制验证次数，失败不自动重试。2026-10-21 已使用同一份原生网络客户端分别完成一次慧新易校、一次呱呱淋浴真实登录，以及各一次余额查询，均成功；未重试。完整应用显示仍待实机验证。本次统一刷新改动没有使用真实账号重复验证。

冷启动和下拉刷新并发更新已连接或已配置密码的余额账号，即使教务会话失效也可独立查询。查询失败保留上次余额及其时间；明确过期时，使用相同账号、相同系统保存的密码自动重登一次并重查，密码拒绝后持久暂停自动尝试。未保存密码则提示重新连接。手动切换余额账号会移除旧账号保存的密码，避免过期后自动切回旧账号。未连接或缺少有效数据时显示占位符，零余额正常显示金额。演示模式不发起真实请求。

首页首次出现触发一次冷启动刷新，同一个 store 的多个窗口或重复进入首页不会重复启动。今天、课表、教务、成绩、考试、学期课程、培养方案、开课查询、校园服务、我的、个人信息和日程页面的下拉刷新，以及“同步全部校园数据”和培养方案按钮，都进入同一个调度器。重复刷新合并；若登录或账号配置正在进行，刷新等待完成后执行；若当前仅在查询课程，全量刷新会等待查询后再执行完整同步。切换 Tab 不取消由 store 持有的任务。所有数据请求忽略本地响应缓存。

统一刷新包含五项教务数据（课表与学期课程、全部成绩、考试、个人信息、培养方案），以及已连接或配置过凭据的校园卡、淋浴账号；完全未配置的服务不计入任务。曾提交开课查询后，全量刷新也重查该条件在当前同步学期的第一页并重置分页；未提交过查询时不遍历全校课程。查询和加载更多也使用同一调度器、身份验证和错误汇总，分页失败保留之前的结果。日程和偏好是本地数据，不会伪造网络更新；在系统浏览器打开的官方网页由站点自行刷新。

每轮刷新生成按数据项去重的 `RefreshReport`，顶部进度统计实际参与的数据项，不再固定为四项。余额详情的刷新或连接正在执行时，全量刷新会等待并复用同一任务。教务成功而余额仍未返回时，顶部继续显示更新中；所有任务完成且无错误才显示“已更新”。部分失败时保留成功项和各失败项的旧缓存，顶部汇总具体来源与错误。单独缺少教务登录时提供登录入口；余额成功、教务过期时显示部分更新；余额认证失败时提供统一账号配置入口，避免引导到无关的 CAS 登录。错误详情合并重复原因，钥匙串与缓存保存失败也纳入结果。

教务会话过期时，每轮最多续登一次；只重查因会话过期失败的数据项，不重复拉取已经成功的数据。退出、切换账号和导入备份会取消旧请求、清除查询上下文并丢弃迟到结果。首次绑定教务身份时保留同一轮已连接的余额，更新它们的账号归属。

参考 [Telegram iOS 的网络状态标题切换](https://github.com/TelegramMessenger/Telegram-iOS/blob/master/submodules/ChatListUI/Sources/ChatListController.swift)，用 SwiftUI 在导航标题位置显示小型活动指示器与“连接中…”、“更新中…”，并显示完成的接口数量。完成后短暂显示“已更新”，再恢复页面标题；网络错误、部分失败可点按顶栏查看详情并重试，过期状态可点按登录。刷新过程不使用模态错误弹窗，也不让下拉控件持续显示第二个等待指示器。

尚未登录且未保存凭据时不发送匿名教务请求、不强制弹出登录页面。断网保留会话供手动重试；服务端确认过期或账号不符时清除教务业务 Cookie，保留受域名限制的 CAS 会话供下次单点登录，并保留离线缓存。退出、恢复备份或切换演示数据会清理钥匙串会话和密码；退出还会取消刷新并丢弃其迟到结果。

本次会话与密码管理改动使用合成账号和 URLProtocol 假网络验证，没有读取 `local-accounts.json`，没有新增真实学校登录尝试。Core 测试可在 Linux 以 `swift test --package-path Packages/HFUTCore --build-system native` 执行，不运行 iOS 应用、模拟器或真机；钥匙串和生命周期测试由 macOS CI XCTest 宿主覆盖，设备交互仍需实机验证。

## 目录与依赖

```text
ios/
  Package.swift                     # xtool / SwiftPM 构建入口
  Package.resolved                  # 固定应用依赖版本
  xtool.yml                         # IPA、图标和顶层资源配置
  project.yml                       # XcodeGen 工程定义
  HFUTSchedule/                     # 两种构建入口共用的应用 target
    App/                            # @main 应用入口
    Features/                       # Today、Schedule、Academic、Services 等功能
    Shared/                         # 公共组件、应用状态与本地持久化
    Info.plist                      # 两种构建共用的版本与系统配置
    Resources/
      AppIcon.png
      Licenses/SwiftSoup-MIT.txt
  HFUTScheduleTests/                # 应用宿主单元测试（CI）
  HFUTScheduleUITests/              # iPhone / iPad UI 测试（CI）
  Packages/
    HFUTCore/                       # 独立 Foundation 数据与网络 Swift Package
      Package.swift
      Package.resolved
      Sources/HFUTCore/
      Tests/HFUTCoreTests/           # 合成 fixture 与契约测试
  scripts/                          # 版本、预发布、IPA 检查及 CI 测试脚本
```

在 `ios/` 下运行 `xcodegen generate` 可生成 `HFUTSchedule.xcodeproj`，在 macOS 上通过 Xcode 打开。生成的工程不纳入版本控制，修改 target、依赖或构建配置时编辑 `project.yml` 后重新生成。应用目录以 Xcode target 命名，SwiftPM 用显式 `path` 引用同一套源码；`Packages/HFUTCore` 保留标准 Swift Package 的 `Sources` / `Tests` 排布。Info.plist 和资源由各自的打包配置处理，不参与 Swift 源码编译；许可证仍复制到应用包顶层。

`.build/`、`xtool/`、`DerivedData/` 与 `.xcresult` 均为被 Git 忽略的本地产物，不属于源码结构。Android 模块和根目录 Gradle 入口保持原位。

唯一应用外部依赖为 [SwiftSoup 2.8.8](https://github.com/scinfu/SwiftSoup/tree/2.8.8)，固定版本并提交 `Package.resolved`，用于容错解析教务 HTML。应用与原项目沿用根目录 Apache-2.0 许可；SwiftSoup 使用 MIT 许可。应用无统计上报或第三方业务后端。
