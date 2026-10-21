import SwiftUI
import HFUTCore

struct Card<Content: View>: View {
    @ViewBuilder var content: Content
    var body: some View {
        content.padding(18).frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 20))
    }
}

struct SessionBanner: View {
    @Environment(AppStore.self) private var store
    var body: some View {
        if store.snapshot.isDemo {
            Label("演示模式 · 所有数据均为示例", systemImage: "sparkles")
                .font(.footnote).foregroundStyle(.orange).frame(maxWidth: .infinity, alignment: .leading)
        } else if !store.isAuthenticated && !store.syncStatus.isActive {
            Button { store.showLogin = true } label: {
                Label(store.snapshot.updatedAt == nil ? "登录以同步校园数据" : "正在查看离线缓存 · 登录后可同步", systemImage: "lock.open")
                    .font(.footnote).frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }
}

struct CourseRow: View {
    let course: Course
    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(course.name).font(.headline)
            Text([course.kind, course.credits.map { "\($0.formatted()) 学分" } ?? "", course.teachers].filter { !$0.isEmpty }.joined(separator: " · "))
                .font(.subheadline).foregroundStyle(.secondary)
            if !course.code.isEmpty { Text(course.code).font(.caption.monospaced()).foregroundStyle(.secondary) }
            if !course.arrangement.isEmpty { Text(course.arrangement).font(.caption).foregroundStyle(.secondary) }
        }.padding(.vertical, 4).textSelection(.enabled)
    }
}

struct ScheduleRow: View {
    let entry: ScheduleEntry
    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            VStack(alignment: .leading, spacing: 4) {
                Text(SchoolDate.time(entry.startTime)).font(.headline.monospacedDigit())
                Text(SchoolDate.time(entry.endTime)).font(.caption.monospacedDigit()).foregroundStyle(.secondary)
            }.frame(width: 56, alignment: .leading)
            RoundedRectangle(cornerRadius: 2).fill(courseColor(entry.lessonID)).frame(width: 3)
            VStack(alignment: .leading, spacing: 5) {
                Text(entry.name).font(.headline)
                Label(entry.room.isEmpty ? "地点待定" : entry.room, systemImage: "mappin.and.ellipse")
                    .font(.subheadline).foregroundStyle(.secondary)
                if !entry.teacher.isEmpty { Text(entry.teacher).font(.caption).foregroundStyle(.secondary) }
            }.frame(maxWidth: .infinity, alignment: .leading)
        }.fixedSize(horizontal: false, vertical: true).padding(.vertical, 7)
    }
}

func courseColor(_ id: Int) -> Color {
    let palette: [Color] = [.indigo, .teal, .orange, .purple, .blue, .pink]
    return palette[Int(id.magnitude % UInt(palette.count))]
}

struct EntryDetail: View {
    let entry: ScheduleEntry
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        NavigationStack {
            Form {
                Section { Text(entry.name).font(.title2.bold()) }
                LabeledContent("日期", value: entry.date)
                LabeledContent("时间", value: entry.timeRange)
                LabeledContent("地点", value: entry.room.isEmpty ? "待定" : entry.room)
                LabeledContent("教师", value: entry.teacher.isEmpty ? "未提供" : entry.teacher)
                LabeledContent("教学周", value: "第 \(entry.week) 周")
            }.textSelection(.enabled)
                .navigationTitle("课程详情").navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .confirmationAction) { Button("完成") { dismiss() } } }
        }.presentationDetents([.medium, .large])
    }
}
