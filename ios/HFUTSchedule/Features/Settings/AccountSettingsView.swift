import SwiftUI

struct AccountSettingsView: View {
    @Environment(AppStore.self) private var store
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        Group {
            if store.snapshot.isDemo {
                ContentUnavailableView("演示模式", systemImage: "person.crop.circle", description: Text("退出演示后可配置系统账号。"))
            } else {
                AccountList(accounts: store.accounts)
            }
        }
        .navigationTitle("账号与密码")
        .privacySensitive()
        .overlay {
            if scenePhase != .active {
                Rectangle().fill(.background).overlay { Label("账号已保护", systemImage: "lock.shield") }
            }
        }
    }
}

private struct AccountList: View {
    @ObservedObject var accounts: AccountStore
    var body: some View {
        Form {
            Section {
                ForEach(AccountSystem.allCases) { system in
                    NavigationLink {
                        AccountEditor(system: system, accounts: accounts)
                    } label: {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(system.title)
                            if let summary = accounts.summaries[system] {
                                Text("\(summary.account) · \(summary.automaticLogin ? "已保存" : "自动登录已暂停")")
                                    .font(.footnote).foregroundStyle(.secondary)
                            } else {
                                Text("未配置").font(.footnote).foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            } footer: {
                Text("统一认证用于教务和信息门户。校园卡查询密码、呱呱淋浴密码各自独立，请分别配置。保存后用于连接与会话过期时自动登录；验证码仍需在学校页面完成。")
            }
            if let error = accounts.error { Section { Text(error).foregroundStyle(.red) } }
            Section("密码保护") {
                Text("密码仅保存在本机钥匙串，设备锁定时不可读取，不通过 iCloud 同步，也不进入导出备份。已有密码不回显，修改时留空可保留原密码。")
                Text("退出并清除本地数据、切换教务账号、进入演示或恢复备份时，会清除保存的账号密码。")
            }
        }
    }
}

private struct AccountEditor: View {
    let system: AccountSystem
    @ObservedObject var accounts: AccountStore
    @Environment(AppStore.self) private var store
    @Environment(\.scenePhase) private var scenePhase
    @State private var account = ""
    @State private var password = ""
    @State private var busy = false
    @State private var message: String?
    @State private var confirmRemoval = false
    @State private var confirmSwitch = false
    private var existing: AccountStore.Summary? { accounts.summaries[system] }
    private var valid: Bool {
        !account.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        (!password.isEmpty || existing?.account == account)
    }

    var body: some View {
        Form {
            Section {
                TextField(system.accountLabel, text: $account)
                    .textContentType(.username).keyboardType(.numberPad)
                    .textInputAutocapitalization(.never).autocorrectionDisabled()
                SecureField(existing == nil ? system.passwordLabel : "新密码（留空保留原密码）", text: $password)
                    .textContentType(.password).textInputAutocapitalization(.never).autocorrectionDisabled()
            } footer: {
                Text(system == .campusCard
                     ? "使用慧新易校校园卡查询密码。学校此接口使用 HTTP，请在可信校园网或系统 VPN 下连接。"
                     : "保存后启用此系统的自动登录。密码被拒绝或要求验证码后会暂停自动尝试，修改并保存可重新启用。")
            }
            Section {
                Button(busy ? "正在连接…" : "保存并连接") {
                    let previous = existing?.account ?? store.snapshot.profile.number
                    if system == .cas, !previous.isEmpty, previous != account.trimmingCharacters(in: .whitespacesAndNewlines) {
                        confirmSwitch = true
                    } else { save() }
                }.disabled(busy || store.isBusy || !valid)
            }
            if let message { Section { Text(message).font(.footnote) } }
            if existing != nil {
                Section {
                    Button("删除保存的账号与密码", role: .destructive) { confirmRemoval = true }
                        .disabled(busy || store.isBusy)
                }
            }
        }
        .navigationTitle(system.title)
        .privacySensitive()
        .disabled(store.snapshot.isDemo)
        .overlay {
            if store.snapshot.isDemo || scenePhase != .active {
                Rectangle().fill(.background).overlay { Label("账号已保护", systemImage: "lock.shield") }
            }
        }
        .onAppear { account = existing?.account ?? (system == .shower ? "" : store.snapshot.profile.number) }
        .onDisappear { password = "" }
        .onChange(of: scenePhase) { _, phase in if phase != .active { password = "" } }
        .confirmationDialog("删除保存的密码并断开此系统的连接？", isPresented: $confirmRemoval, titleVisibility: .visible) {
            Button("删除并断开", role: .destructive) {
                Task {
                    do { try await store.removeAccount(system); password = ""; message = "已删除保存的账号与密码。" }
                    catch { message = error.localizedDescription }
                }
            }
        }
        .confirmationDialog("切换统一认证账号将清除当前账号的缓存和其他系统凭据。", isPresented: $confirmSwitch, titleVisibility: .visible) {
            Button("切换账号", role: .destructive) { save() }
        }
    }

    private func save() {
        guard !store.snapshot.isDemo, scenePhase == .active else { return }
        busy = true; message = nil
        let enteredAccount = account, enteredPassword = password
        password = ""
        Task {
            defer { busy = false }
            do {
                try await store.configureAccount(system, account: enteredAccount, password: enteredPassword)
                if let kind = system.balanceKind {
                    await store.balances.refresh(kind)
                    message = store.balances.errors[kind] ?? "已安全保存并连接。"
                } else {
                    await store.refresh()
                    message = store.isAuthenticated ? "已安全保存并连接。" : "账号已保存。若学校要求验证码，请使用统一认证页面完成登录。"
                }
            } catch { message = error.localizedDescription }
        }
    }
}
