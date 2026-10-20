import SwiftUI
import CryptoKit
import HFUTCore

struct BalanceOverview: View {
    @ObservedObject var store: BalanceStore
    let isDemo: Bool
    let studentNumber: String
    @State private var selected: BalanceKind?

    var body: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 140), spacing: 12)], spacing: 12) {
            ForEach(BalanceKind.allCases) { kind in
                let value = isDemo ? CampusBalance(amount: kind == .campusCard ? Decimal(string: "128.60")! : Decimal(string: "23.85")!) : store.saved.values[kind]
                Button { selected = kind } label: {
                    Card {
                        VStack(alignment: .leading, spacing: 10) {
                            HStack(spacing: 6) {
                                Label(kind.title, systemImage: kind.symbol)
                                    .font(.subheadline.weight(.medium)).foregroundStyle(.secondary)
                                Spacer(minLength: 0)
                                if store.loading.contains(kind) { ProgressView().controlSize(.mini) }
                            }
                            Text(value?.formatted ?? "—")
                                .font(.title2.bold()).monospacedDigit().foregroundStyle(.primary)
                                .lineLimit(1).minimumScaleFactor(0.7)
                            Text(status(kind, value: value)).font(.caption).foregroundStyle(.secondary)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }.frame(maxHeight: .infinity)
                }
                .buttonStyle(.plain)
                .disabled(isDemo)
                .accessibilityIdentifier("balance-\(kind.rawValue)")
            }
        }
        .sheet(item: $selected) { kind in
            BalanceAccountView(store: store, kind: kind, studentNumber: studentNumber)
        }
    }

    private func status(_ kind: BalanceKind, value: CampusBalance?) -> String {
        if isDemo { return "演示余额" }
        if store.loading.contains(kind) { return "更新中…" }
        if !store.isConnected(kind) { return value == nil ? "未连接 · 点按登录" : "上次余额 · 请重新登录" }
        if store.errors[kind] != nil { return "更新失败 · 点按查看" }
        if let value { return "更新于 \(value.updatedAt.formatted(date: .abbreviated, time: .shortened))" }
        return "点按查看"
    }
}

private struct BalanceAccountView: View {
    @ObservedObject var store: BalanceStore
    let kind: BalanceKind
    let studentNumber: String
    @Environment(\.dismiss) private var dismiss
    @State private var account = ""
    @State private var password = ""
    @State private var changingAccount = false
    private var loading: Bool { store.loading.contains(kind) }

    var body: some View {
        NavigationStack {
            Form {
                if let value = store.saved.values[kind] {
                    Section {
                        Text(value.formatted).font(.largeTitle.bold()).monospacedDigit()
                        LabeledContent("最近更新", value: value.updatedAt.formatted(date: .abbreviated, time: .shortened))
                    } footer: {
                        Text("余额以学校服务查询结果为准。\(kind == .shower ? "此处显示呱呱淋浴账户余额。" : "含未结算金额，与 Android 端口径一致。")")
                    }
                }
                if let error = store.errors[kind] {
                    Section { Text(error).font(.footnote).foregroundStyle(.red) }
                }
                if !store.isConnected(kind) || changingAccount {
                    Section {
                        TextField(kind == .campusCard ? "学号" : "呱呱淋浴手机号", text: $account)
                            .keyboardType(.numberPad).textContentType(.username)
                            .textInputAutocapitalization(.never).autocorrectionDisabled()
                        SecureField(kind == .campusCard ? "校园卡查询密码" : "呱呱淋浴密码", text: $password)
                            .textContentType(.password)
                        Button {
                            let enteredAccount = account.trimmingCharacters(in: .whitespacesAndNewlines)
                            let proof = kind == .shower ? Self.showerPassword(password) : password
                            Task {
                                let connected: Bool
                                if kind == .campusCard {
                                    connected = await store.connectCard(account: enteredAccount, queryPassword: proof)
                                } else {
                                    connected = await store.connectShower(account: enteredAccount, password: proof)
                                }
                                password = ""
                                if connected { changingAccount = false }
                            }
                        } label: {
                            HStack {
                                Text(loading ? "连接中…" : "连接并查询余额")
                                if loading { Spacer(); ProgressView() }
                            }
                        }
                        .disabled(loading || account.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || password.isEmpty)
                    } footer: {
                        Text(kind == .campusCard
                             ? "使用慧新易校的校园卡查询密码。服务使用 HTTP，请在可信校园网或 VPN 下连接。应用仅保存登录令牌，不保存查询密码。"
                             : "使用呱呱淋浴账号登录。应用仅保存登录凭据，不保存密码。")
                    }
                } else {
                    Section {
                        LabeledContent("账号", value: store.saved.credentials[kind]?.account ?? "")
                        Button(loading ? "更新中…" : "刷新余额") { Task { await store.refresh(kind) } }.disabled(loading)
                        Button("更换账号") { changingAccount = true; password = "" }.disabled(loading)
                        Button("断开连接", role: .destructive) { store.disconnect(kind); password = "" }.disabled(loading)
                    }
                }
                Section {
                    Link("打开\(kind == .campusCard ? "校园卡" : "呱呱淋浴")官方服务",
                         destination: kind == .campusCard ? CampusBalanceClient.cardURL : CampusBalanceClient.showerURL)
                }
            }
            .navigationTitle(kind.title).navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("完成") { dismiss() } } }
            .onAppear { account = store.saved.credentials[kind]?.account ?? (kind == .campusCard ? studentNumber : "") }
        }
        .interactiveDismissDisabled(loading)
    }

    /// Matches CryptoUtil.md5HashForGuaGua in the Android client; this is an upstream protocol requirement.
    private static func showerPassword(_ password: String) -> String {
        String(Insecure.MD5.hash(data: Data(password.utf8)).map { String(format: "%02X", $0) }.joined().suffix(10))
    }
}
