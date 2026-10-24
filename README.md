# coola

面向合肥工业大学本科生的原生 iOS/iPadOS 校园服务应用，使用 Swift 和 SwiftUI 开发，支持 iOS/iPadOS 26 及以上的 iPhone 与 iPad。

本仓库维护 iOS 版本，已移除 Android 源码、Gradle 构建入口、Android Studio 工程配置及安卓发行配置。

## 功能

- 官方 CAS 登录、账号与密码管理。
- 今日概览、周课表、成绩、考试、学期课程、培养方案和开课查询。
- 校园卡与浴室水费余额、校园服务官方网页入口。
- 本地日程、ICS 日历导出、离线缓存、JSON 备份与恢复。
- iPad 宽屏布局、原生 Liquid Glass 导航和游客演示数据。

完整功能说明与实现范围见 [iOS 开发说明](ios/README.md)。

## 构建

需要 xtool 1.22.2 及匹配的 Swift/iOS 26+ SDK，环境要求见 [构建说明](ios/README.md#构建)。在仓库根目录执行：

```sh
cd ios
python3 scripts/prepare_version.py --local
xtool dev build --configuration release --ipa
python3 scripts/check_ipa.py xtool/HFUTSchedule.ipa
```

输出为 `ios/xtool/HFUTSchedule.ipa`。IPA 未签名，安装和分发需要 Apple 开发者签名与描述文件。本机构建不运行应用、真机或模拟器测试。

## 自动构建与发布

每次分支 push 由 [iOS CI](.github/workflows/ios.yml) 构建，核心测试及 iPhone/iPad 测试通过后自动发布预发布版本，附带未签名 IPA。版本使用 `YYYY.M.D.X`，发布说明采用触发提交的完整 commit message。详细规则及验证限制见 [iOS 开发说明](ios/README.md#版本与自动预发布)。

## 仓库内容

- [ios/](ios/)：应用、Swift Package、测试与构建脚本。
- [tools/](tools/)：培养方案爬取、校园网登录、WebVPN 和验证码等独立工具。
- [docs/](docs/README.md)：历史文档和接口参考。
- `src/`、`sql/`：保留的校园数据资源、历史素材和数据库定义。

## 许可与来源

本项目沿用 [Apache-2.0 许可证](LICENSE)。应用依赖 SwiftSoup 2.8.8，其 MIT 许可证随应用分发。

原项目为 [Chiu-xaH/HFUT-Schedule](https://github.com/Chiu-xaH/HFUT-Schedule)，原开发者联系方式：zsh0908@outlook.com。
