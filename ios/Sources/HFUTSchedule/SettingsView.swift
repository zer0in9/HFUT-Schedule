import SwiftUI
import UniformTypeIdentifiers
import HFUTCore

struct SettingsView: View {
    @EnvironmentObject private var store: AppStore
    @AppStorage("appearance") private var appearance = "system"
    @State private var showErase = false
    @State private var showDemo = false
    @State private var showImporter = false
    @State private var pendingImport: URL?
    @State private var showImportConfirmation = false
    @State private var shareURL: URL?
    private var semesters: [Int] {
        Array(Set((-8...2).map { Semester(date: Date()).id + $0 * 20 } + [store.selectedSemester])).sorted(by: >)
    }

    var body: some View {
        Form {
            Section {
                HStack(spacing: 16) {
                    Image(systemName: "person.crop.circle.fill").font(.system(size: 52)).foregroundStyle(.indigo.gradient)
                    VStack(alignment: .leading, spacing: 6) {
                        Text(store.snapshot.profile.name.isEmpty ? "尚未登录" : store.snapshot.profile.name).font(.title3.bold())
                        Text(store.snapshot.isDemo ? "演示模式" : (store.isAuthenticated ? "教务系统已连接" : "离线模式"))
                            .font(.subheadline).foregroundStyle(.secondary)
                    }
                }.padding(.vertical, 8)
                Button(store.isAuthenticated ? "重新登录" : "登录统一认证") { store.showLogin = true }.disabled(store.isBusy)
                NavigationLink("个人信息") { ProfileView() }
            }
            Section("偏好") {
                Picker("校区", selection: $store.campus) { ForEach(Campus.allCases) { Text($0.rawValue).tag($0) } }
                Picker("外观", selection: $appearance) { Text("跟随系统").tag("system"); Text("浅色").tag("light"); Text("深色").tag("dark") }
                Picker("同步学期", selection: $store.selectedSemester) {
                    ForEach(semesters, id: \.self) { Text(Semester(id: $0).title).tag($0) }
                }.disabled(store.isBusy)
                Button(store.isBusy ? "正在同步…" : "同步课表、成绩与考试") { Task { await store.refresh() } }.disabled(store.isBusy || store.snapshot.isDemo)
            }
            Section {
                NavigationLink("个人日程") { EventsView() }.accessibilityIdentifier("personal-events")
                Button("导出备份") { do { shareURL = try store.exportSnapshot() } catch { store.errorMessage = error.localizedDescription } }
                Button("从备份恢复") { showImporter = true }.disabled(store.isBusy)
                Button("体验演示数据") { showDemo = true }.disabled(store.isBusy)
                Button("退出并清除本地数据", role: .destructive) { showErase = true }.disabled(store.isBusy)
            } header: { Text("本地数据") }
            footer: { Text("备份包含个人课表和成绩，请妥善保存。恢复会替换现有数据，不包含登录凭据。") }
            Section("关于") {
                LabeledContent("聚在工大 iOS", value: Bundle.main.object(forInfoDictionaryKey: "HFUTDisplayVersion") as? String ?? "本地构建")
                NavigationLink("隐私与功能说明") { PrivacyView() }
                Link("项目源代码", destination: URL(string: "https://github.com/Chiu-xaH/HFUT-Schedule")!)
                Link("反馈问题", destination: URL(string: "https://github.com/Chiu-xaH/HFUT-Schedule/issues")!)
            }
        }
        .syncNavigationTitle("我的")
        .confirmationDialog("退出并删除缓存、课表、成绩和个人日程？", isPresented: $showErase, titleVisibility: .visible) {
            Button("退出并清除", role: .destructive) { Task { await store.signOut() } }
        }
        .confirmationDialog("使用演示数据会替换当前本地数据，请先导出备份。", isPresented: $showDemo, titleVisibility: .visible) {
            Button("使用演示数据", role: .destructive) { store.useDemo() }
        }
        .confirmationDialog("恢复备份将替换全部本地数据，并退出当前登录。", isPresented: $showImportConfirmation, titleVisibility: .visible) {
            Button("恢复备份", role: .destructive) {
                if let pendingImport {
                    do { try store.importSnapshot(from: pendingImport) } catch { store.errorMessage = error.localizedDescription }
                }
                pendingImport = nil
            }
            Button("取消", role: .cancel) { pendingImport = nil }
        }
        .fileImporter(isPresented: $showImporter, allowedContentTypes: [.json]) { result in
            switch result {
            case .success(let url): pendingImport = url; showImportConfirmation = true
            case .failure(let error): store.errorMessage = error.localizedDescription
            }
        }
        .sheet(isPresented: Binding(get: { shareURL != nil }, set: { if !$0 { shareURL = nil } })) {
            if let shareURL { ShareSheet(url: shareURL) }
        }
    }
}

struct ProfileView: View {
    @EnvironmentObject private var store: AppStore
    var body: some View {
        Form {
            SessionBanner()
            LabeledContent("姓名", value: store.snapshot.profile.name)
            LabeledContent("学号", value: store.snapshot.profile.number)
            LabeledContent("院系", value: store.snapshot.profile.department)
            LabeledContent("专业", value: store.snapshot.profile.major)
            LabeledContent("班级", value: store.snapshot.profile.className)
            LabeledContent("校区", value: store.snapshot.profile.campus)
        }.navigationTitle("个人信息").textSelection(.enabled)
    }
}

struct EventsView: View {
    @EnvironmentObject private var store: AppStore
    @State private var showEditor = false
    var body: some View {
        List {
            ForEach(store.snapshot.events.sorted { $0.date < $1.date }) { event in
                VStack(alignment: .leading, spacing: 6) {
                    Text(event.title).font(.headline)
                    Text(event.date.formatted(date: .abbreviated, time: .shortened)).font(.subheadline).foregroundStyle(.secondary)
                    if !event.location.isEmpty { Text(event.location).font(.subheadline) }
                    if !event.note.isEmpty { Text(event.note).font(.footnote).foregroundStyle(.secondary) }
                }.swipeActions { Button("删除", role: .destructive) { store.deleteEvent(event.id) } }
            }
        }
        .overlay { if store.snapshot.events.isEmpty { ContentUnavailableView("暂无个人日程", systemImage: "calendar.badge.plus") } }
        .navigationTitle("个人日程")
        .toolbar { Button { showEditor = true } label: { Image(systemName: "plus") }.accessibilityLabel("添加日程") }
        .sheet(isPresented: $showEditor) { EventEditor() }
    }
}

struct PrivacyView: View {
    var body: some View {
        List {
            Section("账号与数据") {
                Text("统一认证使用学校官方 HTTPS 页面，应用不读取或保存你的密码。教务会话保存在本机钥匙串中，仅设备解锁后可用，不迁移到其他设备。冷启动首页会恢复并校验会话后同步；过期后需重新登录。")
                Text("学校教务系统当前使用 HTTP，应用仅对 jxglstu.hfut.edu.cn 放开传输限制。请使用可信校园网或系统 VPN。")
                Text("课表、成绩、考试、培养方案和日程保存在本机，使用 iOS 文件保护并排除系统云备份。没有广告、统计上报或第三方数据服务器。")
                Text("退出会删除应用中的个人缓存及会话。已导出的文件不受此操作影响，请自行管理。")
            }
            Section("功能范围") {
                Text("原生页面提供今日概览、周课表、成绩、考试、课程汇总、培养方案、开课查询、个人日程、备份恢复与日历文件导出。")
                Text("校园卡、图书馆、校园网、第二课堂、选课、教评等服务从入口打开官方网页；尚未移植 Android 的原生交易流程、小组件、实况活动和验证码 OCR。")
                Text("演示模式使用本地生成的示例数据，不连接教务系统。教务接口可能变化，真实账号与网络的兼容性仍需 CI 或设备验证。")
            }
            Section("开源许可") {
                Text("HFUT-Schedule · Chiu-xaH · Apache License 2.0")
                Text("SwiftSoup · scinfu 及贡献者 · MIT License")
            }
        }.navigationTitle("隐私与说明")
    }
}
