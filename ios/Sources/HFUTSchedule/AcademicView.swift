import SwiftUI
import HFUTCore

struct AcademicView: View {
    @EnvironmentObject private var store: AppStore
    var body: some View {
        List {
            Section { SessionBanner() }
            Section("学业概览") {
                NavigationLink { GradesView() } label: {
                    Label { HStack { Text("成绩查询"); Spacer(); Text("\(store.snapshot.grades.count) 门").foregroundStyle(.secondary) } } icon: { Image(systemName: "chart.bar.xaxis") }
                }.accessibilityIdentifier("grades-link")
                NavigationLink { ExamsView() } label: { Label("考试安排", systemImage: "pencil.and.list.clipboard") }
                NavigationLink { CourseListView() } label: { Label("学期课程", systemImage: "books.vertical") }
                NavigationLink { ProgramView() } label: { Label("培养方案", systemImage: "list.bullet.indent") }
                NavigationLink { CourseSearchView() } label: { Label("开课查询", systemImage: "magnifyingglass") }
            }
            Section {
                Link(destination: URL(string: "http://jxglstu.hfut.edu.cn/eams5-student/")!) { Label("选课、教评及其他教务操作", systemImage: "safari") }
            } footer: { Text("选退课、教学评价等操作请在官方教务系统完成。原生页面提供只读查询。") }
        }.navigationTitle("教务")
            .refreshable { await store.refresh() }
    }
}

struct GradesView: View {
    @EnvironmentObject private var store: AppStore
    @State private var term = "全部学期"
    @State private var search = ""
    private var terms: [String] { ["全部学期"] + Set(store.snapshot.grades.map(\.term)).sorted(by: >) }
    private var grades: [Grade] {
        store.snapshot.grades.filter { (term == "全部学期" || $0.term == term) && (search.isEmpty || $0.name.localizedCaseInsensitiveContains(search)) }
    }
    var body: some View {
        List {
            Section {
                SessionBanner()
                Picker("学期", selection: $term) { ForEach(terms, id: \.self) { Text($0).tag($0) } }
                HStack {
                    metric("加权绩点", value: Grade.weightedGPA(grades).map { String(format: "%.2f", $0) } ?? "—")
                    Spacer()
                    metric("已查询学分", value: grades.reduce(0) { $0 + ($1.credits ?? 0) }.formatted())
                    Spacer()
                    metric("课程数", value: "\(grades.count)")
                }.padding(.vertical, 10)
            } footer: { Text("绩点按当前筛选结果中有绩点的课程及学分加权计算；包含重修等所有返回记录，仅供参考，以学校官方认定为准。") }
            if grades.isEmpty {
                ContentUnavailableView("暂无成绩", systemImage: "chart.bar.xaxis", description: Text("同步后可查询；也可以调整学期或搜索条件。"))
            }
            ForEach(grades) { grade in
                Section {
                    HStack(alignment: .top) {
                        VStack(alignment: .leading, spacing: 6) {
                            Text(grade.name).font(.headline)
                            Text("\(grade.credits?.formatted() ?? "—") 学分 · 绩点 \(grade.gradePoint?.formatted() ?? "—")").font(.footnote).foregroundStyle(.secondary)
                            Text(grade.term).font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Text(grade.score).font(.title2.bold()).foregroundStyle((Double(grade.score) ?? 100) < 60 ? .red : .indigo)
                    }
                    if !grade.detail.isEmpty { Text(grade.detail).font(.footnote).foregroundStyle(.secondary) }
                }.textSelection(.enabled)
            }
        }.navigationTitle("成绩查询").searchable(text: $search, prompt: "搜索课程")
            .refreshable { await store.refresh() }
    }
    private func metric(_ title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 6) { Text(value).font(.title2.bold()); Text(title).font(.caption).foregroundStyle(.secondary) }
    }
}

struct ExamsView: View {
    @EnvironmentObject private var store: AppStore
    var body: some View {
        List {
            Section { SessionBanner() }
            if store.snapshot.exams.isEmpty {
                ContentUnavailableView("暂无考试安排", systemImage: "pencil.and.list.clipboard", description: Text("请先同步数据，具体安排以教务系统通知为准。"))
            }
            ForEach(store.snapshot.exams) { exam in
                VStack(alignment: .leading, spacing: 10) {
                    Text(exam.name).font(.headline)
                    Label(exam.dateTime, systemImage: "clock").font(.subheadline)
                    Label(exam.place.isEmpty ? "考场待定" : exam.place, systemImage: "mappin.and.ellipse").font(.subheadline).foregroundStyle(.secondary)
                    if let date = SchoolDate.parse(String(exam.dateTime.prefix(10))) {
                        let days = SchoolDate.calendar.dateComponents([.day], from: SchoolDate.calendar.startOfDay(for: Date()), to: date).day ?? 0
                        Text(days > 0 ? "还有 \(days) 天" : days == 0 ? "今天考试" : "已结束")
                            .font(.caption.bold()).foregroundStyle(days >= 0 ? .orange : .secondary)
                    }
                }.padding(.vertical, 8).textSelection(.enabled)
            }
        }.navigationTitle("考试安排").refreshable { await store.refresh() }
    }
}

struct CourseListView: View {
    @EnvironmentObject private var store: AppStore
    @State private var query = ""
    var body: some View {
        List {
            Section { SessionBanner(); Text(Semester(id: store.snapshot.semesterID).title).foregroundStyle(.secondary) }
            ForEach(store.snapshot.courses.filter { query.isEmpty || $0.name.localizedCaseInsensitiveContains(query) }) { CourseRow(course: $0) }
        }.navigationTitle("学期课程").searchable(text: $query, prompt: "搜索课程")
            .overlay { if store.snapshot.courses.isEmpty { ContentUnavailableView("暂无学期课程", systemImage: "books.vertical") } }
    }
}

struct ProgramView: View {
    @EnvironmentObject private var store: AppStore
    var body: some View {
        List {
            Section { SessionBanner() }
            if let program = store.snapshot.program {
                module(program)
                OutlineGroup(program.children, children: \.optionalChildren) { item in module(item) }
            } else {
                ContentUnavailableView("尚未加载培养方案", systemImage: "list.bullet.indent", description: Text("登录后加载个人培养方案，之后可离线查看。"))
            }
            Button(store.isBusy ? "正在加载…" : "加载 / 刷新培养方案") { Task { await store.loadProgram() } }
                .disabled(!store.isAuthenticated || store.isBusy)
        }.navigationTitle("培养方案")
    }
    private func module(_ item: ProgramModule) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(item.title).font(.headline)
            if let credits = item.requiredCredits { Text("要求 \(credits.formatted()) 学分").font(.footnote).foregroundStyle(.secondary) }
            ForEach(item.courses) { CourseRow(course: $0) }
        }.padding(.vertical, 6)
    }
}

extension ProgramModule {
    var optionalChildren: [ProgramModule]? { children.isEmpty ? nil : children }
}

struct CourseSearchView: View {
    @EnvironmentObject private var store: AppStore
    @State private var query = ""
    @State private var submittedQuery = ""
    @State private var results: [Course] = []
    @State private var page = 1
    @State private var loading = false
    @State private var hasMore = true
    @State private var task: Task<Void, Never>?
    @State private var searched = false
    var body: some View {
        List {
            Section {
                SessionBanner()
                Text(Semester(id: store.selectedSemester).title).font(.footnote).foregroundStyle(.secondary)
                TextField("课程名称", text: $query).submitLabel(.search).onSubmit { search(reset: true) }
                Button("查询") { search(reset: true) }.disabled(!store.isAuthenticated || loading)
            }
            ForEach(results) { CourseRow(course: $0) }
            if loading { ProgressView("正在查询…") }
            if searched && !loading && results.isEmpty { ContentUnavailableView("未找到课程", systemImage: "magnifyingglass") }
            if !results.isEmpty && hasMore { Button("加载下一页") { search(reset: false) }.disabled(loading) }
        }.navigationTitle("开课查询")
            .onDisappear { task?.cancel() }
    }

    private func search(reset: Bool) {
        guard store.isAuthenticated, !loading else { return }
        if reset { page = 1; results = []; submittedQuery = query; hasMore = true }
        loading = true
        let studentID = store.snapshot.studentID
        let semester = store.selectedSemester
        let requestedPage = page
        task = Task {
            defer { loading = false }
            do {
                let rows = try await store.client.search(studentID: studentID, semesterID: semester, name: submittedQuery, page: requestedPage)
                try Task.checkCancellation()
                guard store.isAuthenticated, store.snapshot.studentID == studentID, store.selectedSemester == semester else { return }
                let existing = Set(results.map(\.id))
                let added = rows.filter { !existing.contains($0.id) }
                results += added
                hasMore = !rows.isEmpty && !added.isEmpty
                searched = true
                page += 1
            } catch {
                if !Task.isCancelled { store.errorMessage = error.localizedDescription }
            }
        }
    }
}
