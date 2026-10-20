import SwiftUI
import HFUTCore

struct ServicesView: View {
    @EnvironmentObject private var store: AppStore
    @State private var query = ""
    var body: some View {
        List {
            Section {
                Picker("校区", selection: $store.campus) { ForEach(Campus.allCases) { Text($0.rawValue).tag($0) } }.pickerStyle(.segmented)
            } footer: { Text("以下入口在系统浏览器打开学校官方站点。标注“校园网”的服务可能需要连接校园网或系统 VPN。") }
            ForEach(["学习", "生活", "校园"], id: \.self) { category in
                let services = CampusService.all.filter { $0.category == category && (query.isEmpty || $0.title.localizedCaseInsensitiveContains(query)) }
                if !services.isEmpty {
                    Section(category) {
                        ForEach(services) { service in
                            HStack(spacing: 16) {
                                Link(destination: service.url(campus: store.campus)) {
                                    HStack {
                                        Image(systemName: service.symbol).font(.title3).foregroundStyle(.indigo).frame(width: 30)
                                        VStack(alignment: .leading, spacing: 4) {
                                            Text(service.title).foregroundStyle(.primary)
                                            if service.requiresCampusNetwork { Text("校园网").font(.caption).foregroundStyle(.secondary) }
                                        }
                                        Spacer()
                                        Image(systemName: "arrow.up.right").font(.caption).foregroundStyle(.secondary)
                                    }.padding(.vertical, 5)
                                }
                                Button { store.toggleFavorite(service) } label: {
                                    Image(systemName: store.favorites.contains(service.id) ? "star.fill" : "star")
                                        .foregroundStyle(store.favorites.contains(service.id) ? .orange : .secondary)
                                }.buttonStyle(.borderless).accessibilityLabel("\(store.favorites.contains(service.id) ? "取消常用" : "设为常用")\(service.title)")
                            }
                        }
                    }
                }
            }
        }.navigationTitle("校园服务").searchable(text: $query, prompt: "搜索校园服务")
    }
}
