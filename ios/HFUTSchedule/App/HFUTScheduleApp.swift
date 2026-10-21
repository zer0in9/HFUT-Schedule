import SwiftUI

@main
struct HFUTScheduleApp: App {
    @State private var store = AppStore()
    @AppStorage("appearance") private var appearance = "system"
    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(store)
                .tint(.indigo)
                .preferredColorScheme(appearance == "system" ? nil : (appearance == "dark" ? .dark : .light))
        }
    }
}

struct RootView: View {
    @Environment(AppStore.self) private var store
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @State private var selectedTab: AppTab = .today

    var body: some View {
        @Bindable var store = store
        tabs
            .sheet(isPresented: $store.showLogin) { LoginView() }
            .alert("提示", isPresented: Binding(get: { store.errorMessage != nil }, set: { if !$0 { store.errorMessage = nil } })) {
                Button("知道了", role: .cancel) { store.errorMessage = nil }
            } message: { Text(store.errorMessage ?? "") }
    }

    private var tabs: some View {
        TabView(selection: $selectedTab) {
            ForEach(AppTab.allCases) { tab in
                Tab(tab.title, systemImage: tab.symbol, value: tab) {
                    page(tab)
                }
            }
        }
        .tabViewStyle(.sidebarAdaptable)
        .tabBarMinimizeBehavior(horizontalSizeClass == .compact ? .onScrollDown : .never)
    }

    private func page(_ tab: AppTab) -> some View {
        NavigationStack {
            switch tab {
            case .today: TodayView()
            case .schedule: ScheduleView()
            case .academic: AcademicView()
            case .campus: ServicesView()
            case .settings: SettingsView()
            }
        }
    }
}

private enum AppTab: String, CaseIterable, Identifiable {
    case today, schedule, academic, campus, settings

    var id: Self { self }
    var title: String {
        switch self {
        case .today: "今天"
        case .schedule: "课表"
        case .academic: "教务"
        case .campus: "校园"
        case .settings: "我的"
        }
    }
    var symbol: String {
        switch self {
        case .today: "sun.max"
        case .schedule: "calendar"
        case .academic: "graduationcap"
        case .campus: "square.grid.2x2"
        case .settings: "person.crop.circle"
        }
    }
}
