import SwiftUI
import HFUTCore

enum SyncStatus: Equatable {
    case idle
    case connecting
    case updating(completed: Int, total: Int)
    case updated
    case needsLogin
    case failed(message: String, partial: Bool)

    var isActive: Bool {
        switch self { case .connecting, .updating: true; default: false }
    }
    var text: String? {
        switch self {
        case .idle: nil
        case .connecting: "连接中…"
        case .updating: "更新中…"
        case .updated: "已更新"
        case .needsLogin: "请重新登录"
        case .failed(_, let partial): partial ? "部分数据未更新" : "更新失败"
        }
    }
    var detail: String? {
        switch self {
        case .connecting: "正在连接校园服务"
        case .updating(let completed, let total): "\(completed)/\(total) 项已完成"
        case .needsLogin: "点按登录 · 缓存仍可查看"
        case .failed: "点按查看详情或重试"
        default: nil
        }
    }
}

/// Recreates Telegram's network-state-in-title interaction with native SwiftUI views.
private struct SyncNavigationTitle: View {
    @Environment(AppStore.self) private var store
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let title: String
    @State private var showFailure = false
    @State private var showAccounts = false
    var body: some View {
        Group {
            switch store.syncStatus {
            case .needsLogin:
                Button { store.showLogin = true } label: { titleContent }
            case .failed:
                Button { showFailure = true } label: { titleContent }
            default:
                titleContent
            }
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(store.syncStatus.text ?? title)
        .accessibilityValue(store.syncStatus.detail ?? "")
        .accessibilityIdentifier("sync-navigation-title")
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.2), value: store.syncStatus)
        .confirmationDialog("同步未完成", isPresented: $showFailure, titleVisibility: .visible) {
            Button("重试") { Task { await store.refresh() } }
            if store.refreshReport?.requiresAcademicLogin == true { Button("登录教务系统") { store.showLogin = true } }
            if [SyncResource.campusCard, .shower].contains(where: { resource in
                if case .failure(_, true) = store.refreshReport?.outcomes[resource] { return true }; return false
            }) { Button("账号与密码") { showAccounts = true } }
            Button("取消", role: .cancel) {}
        } message: {
            if case .failed(let message, _) = store.syncStatus { Text(message) }
        }
        .sheet(isPresented: $showAccounts) { NavigationStack { AccountSettingsView() } }
    }

    private var titleContent: some View {
        VStack(spacing: 1) {
            HStack(spacing: 7) {
                if store.syncStatus.isActive { ProgressView().controlSize(.mini).accessibilityHidden(true) }
                if store.syncStatus == .updated { Image(systemName: "checkmark").font(.caption).foregroundStyle(.green).accessibilityHidden(true) }
                Text(store.syncStatus.text ?? title).font(.headline).lineLimit(1).contentTransition(.opacity)
            }
            if let detail = store.syncStatus.detail { Text(detail).font(.caption2).foregroundStyle(.secondary).lineLimit(1) }
        }.foregroundStyle(.primary).contentShape(Rectangle())
    }
}

extension View {
    func syncNavigationTitle(_ title: String) -> some View {
        self.navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .principal) { SyncNavigationTitle(title: title) } }
    }

    func topBarRefreshable() -> some View {
        modifier(TopBarRefreshModifier())
    }
}

private struct TopBarRefreshModifier: ViewModifier {
    @Environment(AppStore.self) private var store
    func body(content: Content) -> some View {
        content.scrollBounceBehavior(.always, axes: .vertical).refreshable {
            // Release the pull control immediately; long-running progress belongs to the title.
            Task { await store.refresh() }
        }
    }
}
