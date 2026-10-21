import SwiftUI
import HFUTCore

struct ScheduleView: View {
    @Environment(AppStore.self) private var store
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @State private var week = 1
    @State private var layout = 0
    @State private var selected: ScheduleEntry?
    @State private var calendarURL: URL?
    @State private var initializedLayout = false
    private var entries: [ScheduleEntry] { store.snapshot.schedule.filter { $0.week == week } }
    private let weekdays = ["周一", "周二", "周三", "周四", "周五", "周六", "周日"]

    var body: some View {
        VStack(spacing: 0) {
            VStack(spacing: 14) {
                SessionBanner()
                HStack {
                    Button { week -= 1 } label: { Image(systemName: "chevron.left") }.disabled(week <= 1).accessibilityLabel("上一周")
                    Spacer()
                    Menu {
                        ForEach(1...max(30, store.weekNumbers.max() ?? 20), id: \.self) { value in Button("第 \(value) 周") { week = value } }
                    } label: { Text("第 \(week) 周").font(.headline) }
                    Spacer()
                    Button { week += 1 } label: { Image(systemName: "chevron.right") }
                        .disabled(week >= max(30, store.weekNumbers.max() ?? 20)).accessibilityLabel("下一周")
                    Button("本周") { week = max(1, store.week) }.font(.subheadline).padding(.leading, 14)
                }
                Text(Semester(id: store.snapshot.semesterID).title).font(.footnote).foregroundStyle(.secondary)
                Picker("课表布局", selection: $layout) { Text("日程").tag(0); Text("周视图").tag(1) }.pickerStyle(.segmented)
            }.padding()
            if entries.isEmpty {
                ScrollView {
                    ContentUnavailableView("本周没有课程", systemImage: "calendar", description: Text(store.snapshot.updatedAt == nil ? "登录后同步课表，或在“我的”中开启演示。" : "可切换周次，或下拉刷新课表。"))
                        .padding(.top, 40)
                }.scrollBounceBehavior(.always, axes: .vertical).topBarRefreshable()
            } else if layout == 0 {
                List {
                    ForEach(1...7, id: \.self) { day in
                        let rows = entries.filter { $0.weekday == day }
                        if !rows.isEmpty {
                            Section("\(weekdays[day - 1]) · \(rows.first?.date ?? "")") {
                                ForEach(rows) { entry in
                                    Button { selected = entry } label: { ScheduleRow(entry: entry) }.buttonStyle(.plain)
                                }
                            }
                        }
                    }
                }.listStyle(.insetGrouped).topBarRefreshable()
            } else {
                GeometryReader { geometry in
                    weeklyGrid(dayWidth: max(horizontalSizeClass == .regular ? 88 : 112, (geometry.size.width - 56) / 7))
                }
            }
        }
        .background(Color(uiColor: .systemGroupedBackground))
        .syncNavigationTitle("我的课表")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button { do { calendarURL = try store.exportCalendar() } catch { store.errorMessage = error.localizedDescription } }
                label: { Image(systemName: "square.and.arrow.up") }
                    .disabled(store.snapshot.schedule.isEmpty).accessibilityLabel("导出学期日历")
            }
        }
        .onAppear {
            week = max(1, store.week)
            if !initializedLayout {
                layout = horizontalSizeClass == .regular ? 1 : 0
                initializedLayout = true
            }
        }
        .sheet(item: $selected) { EntryDetail(entry: $0) }
        .sheet(isPresented: Binding(get: { calendarURL != nil }, set: { if !$0 { calendarURL = nil } })) {
            if let calendarURL { ShareSheet(url: calendarURL) }
        }
    }

    private func weeklyGrid(dayWidth: CGFloat) -> some View {
        return ScrollView([.horizontal, .vertical]) {
            VStack(spacing: 0) {
                HStack(spacing: 0) {
                    Text("时间").frame(width: 48)
                    ForEach(1...7, id: \.self) { day in
                        VStack(spacing: 4) {
                            Text(weekdays[day - 1]).font(.subheadline.bold())
                            Text(entries.first { $0.weekday == day }?.date.suffix(5) ?? "").font(.caption2).foregroundStyle(.secondary)
                        }.frame(width: dayWidth, height: 52)
                    }
                }
                ZStack(alignment: .topLeading) {
                    ForEach(6...23, id: \.self) { hour in
                        HStack(spacing: 0) {
                            Text("\(hour):00").font(.caption2.monospacedDigit()).foregroundStyle(.secondary).frame(width: 48)
                            Rectangle().fill(Color.secondary.opacity(0.13)).frame(width: dayWidth * 7, height: 0.5)
                        }.offset(y: CGFloat(hour - 6) * 60)
                    }
                    ForEach(ScheduleLayout.placements(entries)) { placement in
                        let entry = placement.entry
                        let width = (dayWidth - 4) / CGFloat(placement.columnCount)
                        Button { selected = entry } label: {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(entry.name).font(.caption.bold())
                                Text(entry.room).font(.caption2)
                                Text(entry.timeRange).font(.system(size: 10).monospacedDigit())
                            }
                            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading).padding(6)
                            .background(courseColor(entry.lessonID).opacity(0.17), in: RoundedRectangle(cornerRadius: 8))
                            .overlay(alignment: .leading) { Capsule().fill(courseColor(entry.lessonID)).frame(width: 3) }
                            .foregroundStyle(.primary).clipped()
                        }
                        .buttonStyle(.plain)
                        .frame(width: width - 2, height: max(30, CGFloat(minutes(entry.endTime) - minutes(entry.startTime)) - 3))
                        .offset(x: 50 + CGFloat(entry.weekday - 1) * dayWidth + CGFloat(placement.column) * width,
                                y: CGFloat(minutes(entry.startTime) - 360))
                        .accessibilityLabel("\(entry.name)，\(entry.date)，\(entry.timeRange)，\(entry.room)")
                    }
                }.frame(width: 48 + dayWidth * 7, height: 1080, alignment: .topLeading)
            }.padding(.trailing, 8)
        }.background(Color(uiColor: .secondarySystemGroupedBackground))
            .topBarRefreshable()
    }
    private func minutes(_ time: Int) -> Int { time / 100 * 60 + time % 100 }
}

struct ShareSheet: UIViewControllerRepresentable {
    let url: URL
    func makeUIViewController(context: Context) -> UIActivityViewController { UIActivityViewController(activityItems: [url], applicationActivities: nil) }
    func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}
}
