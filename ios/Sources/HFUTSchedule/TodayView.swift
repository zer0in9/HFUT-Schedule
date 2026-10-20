import SwiftUI
import HFUTCore

struct TodayView: View {
    @EnvironmentObject private var store: AppStore
    @State private var selectedEntry: ScheduleEntry?
    @State private var showEvent = false
    private var today: [ScheduleEntry] { store.snapshot.schedule.filter { $0.date == SchoolDate.string(Date()) } }
    private var events: [PersonalEvent] {
        store.snapshot.events.filter { SchoolDate.calendar.isDate($0.date, inSameDayAs: Date()) }.sorted { $0.date < $1.date }
    }
    private var next: ScheduleEntry? {
        store.snapshot.schedule.first { ($0.endDate ?? .distantPast) > Date() }
    }

    var body: some View {
        GeometryReader { geometry in
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    SessionBanner()
                    if geometry.size.width >= 900 {
                        HStack(alignment: .top, spacing: 24) {
                            VStack(alignment: .leading, spacing: 20) {
                                hero
                                balanceOverview
                                if store.snapshot.updatedAt == nil { welcome }
                                else { todayCourses }
                            }.frame(maxWidth: .infinity)
                            VStack(alignment: .leading, spacing: 20) {
                                personalSchedule
                                favoriteServices
                            }.frame(width: min(380, geometry.size.width * 0.36))
                        }
                    } else {
                        hero
                        balanceOverview
                        if store.snapshot.updatedAt == nil { welcome }
                        else { todayCourses }
                        personalSchedule
                        favoriteServices
                    }
                    if let updated = store.snapshot.updatedAt {
                        Text("部分数据最近同步于 \(updated.formatted(date: .abbreviated, time: .shortened))")
                            .font(.caption).foregroundStyle(.secondary).frame(maxWidth: .infinity)
                    }
                }.padding(20).frame(maxWidth: 1200).frame(maxWidth: .infinity)
            }
            .topBarRefreshable()
        }
        .background(Color(uiColor: .systemGroupedBackground))
        .syncNavigationTitle("聚在工大")
        .task { await store.refreshOnLaunch() }
        .sheet(item: $selectedEntry) { EntryDetail(entry: $0) }
        .sheet(isPresented: $showEvent) { EventEditor() }
    }

    private var balanceOverview: some View {
        BalanceOverview(store: store.balances, isDemo: store.snapshot.isDemo, studentNumber: store.snapshot.profile.number)
    }

    private var todayCourses: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("今日课程").font(.title3.bold())
                Spacer()
                Text("\(today.count) 节安排").font(.subheadline).foregroundStyle(.secondary)
            }
            if today.isEmpty {
                Card { Label("今天没有课程安排，留点时间给自己。", systemImage: "cup.and.saucer").foregroundStyle(.secondary) }
            } else {
                Card {
                    VStack(spacing: 10) {
                        ForEach(today) { entry in
                            Button { selectedEntry = entry } label: { ScheduleRow(entry: entry) }.buttonStyle(.plain)
                            if entry.id != today.last?.id { Divider() }
                        }
                    }
                }
            }
        }
    }

    private var personalSchedule: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("个人日程").font(.title3.bold())
                Spacer()
                Button { showEvent = true } label: { Image(systemName: "plus.circle.fill") }.accessibilityLabel("添加日程")
            }
            Card {
                if events.isEmpty { Text("今天还没有个人日程").foregroundStyle(.secondary) }
                else {
                    VStack(alignment: .leading, spacing: 14) {
                        ForEach(events) { event in
                            HStack {
                                Text(event.date, style: .time).font(.subheadline.monospacedDigit())
                                VStack(alignment: .leading) {
                                    Text(event.title).font(.headline)
                                    if !event.location.isEmpty { Text(event.location).font(.caption).foregroundStyle(.secondary) }
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    private var favoriteServices: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("常用服务").font(.title3.bold())
                Spacer()
                NavigationLink("全部", destination: ServicesView()).font(.subheadline)
            }
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 140))], spacing: 12) {
                ForEach(CampusService.all.filter { store.favorites.contains($0.id) }) { service in
                    Link(destination: service.url(campus: store.campus)) {
                        Card {
                            Label(service.title, systemImage: service.symbol).font(.subheadline.weight(.medium))
                                .frame(minHeight: 30)
                        }
                    }
                }
            }
        }
    }

    private var hero: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                VStack(alignment: .leading, spacing: 6) {
                    Text(Date().formatted(.dateTime.month(.wide).day().weekday(.wide))).font(.subheadline)
                    Text(store.snapshot.profile.name.isEmpty ? "你好，工大同学" : "你好，\(store.snapshot.profile.name)").font(.title.bold())
                }
                Spacer()
                Image(systemName: "sun.horizon.fill").font(.system(size: 38)).symbolRenderingMode(.hierarchical)
            }
            Text("\(store.campus.rawValue)校区 · \(Semester(id: store.snapshot.semesterID).title)").font(.footnote).opacity(0.85)
            if store.snapshot.semesterStart != nil { Text(store.week > 0 ? "教学第 \(store.week) 周" : "学期尚未开始").font(.footnote) }
            if let next {
                Divider().overlay(.white.opacity(0.25))
                Text("下一项课程").font(.caption).opacity(0.8)
                Text(next.name).font(.title3.bold())
                Text("\(next.date)  \(next.timeRange) · \(next.room)").font(.footnote)
            }
        }
        .padding(24).frame(maxWidth: .infinity, alignment: .leading).foregroundStyle(.white)
        .background(LinearGradient(colors: [Color(red: 0.25, green: 0.29, blue: 0.67), Color(red: 0.37, green: 0.39, blue: 0.79)], startPoint: .topLeading, endPoint: .bottomTrailing), in: RoundedRectangle(cornerRadius: 26))
    }

    private var welcome: some View {
        Card {
            VStack(alignment: .leading, spacing: 16) {
                Label("把校园生活，装进口袋", systemImage: "graduationcap.fill").font(.title3.bold())
                Text("同步你的课表、成绩与考试安排。保存后，离线也能查看。").foregroundStyle(.secondary)
                Button("登录统一认证") { store.showLogin = true }.buttonStyle(.borderedProminent)
                Button("先体验演示数据") { store.useDemo() }.disabled(store.isBusy)
            }
        }
    }
}

struct EventEditor: View {
    @EnvironmentObject private var store: AppStore
    @Environment(\.dismiss) private var dismiss
    @State private var title = ""
    @State private var date = Date()
    @State private var location = ""
    @State private var note = ""
    var body: some View {
        NavigationStack {
            Form {
                TextField("日程标题", text: $title)
                DatePicker("时间", selection: $date)
                TextField("地点（可选）", text: $location)
                TextField("备注（可选）", text: $note, axis: .vertical)
            }
            .navigationTitle("添加日程").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") {
                        store.addEvent(PersonalEvent(title: title.trimmingCharacters(in: .whitespacesAndNewlines), date: date, location: location, note: note))
                        dismiss()
                    }.disabled(title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
    }
}
