import Foundation

public struct SchedulePlacement: Identifiable, Sendable {
    public let entry: ScheduleEntry
    public let column: Int
    public let columnCount: Int
    public var id: String { entry.id }
}

public enum ScheduleLayout {
    /// Partition each connected group of overlapping intervals into stable columns.
    /// Using only a class's immediate overlaps gives inconsistent widths for chained overlaps.
    public static func placements(_ entries: [ScheduleEntry]) -> [SchedulePlacement] {
        var result: [SchedulePlacement] = []
        for day in Dictionary(grouping: entries, by: \.date).values {
            let sorted = day.sorted { ($0.startTime, $0.endTime, $0.id) < ($1.startTime, $1.endTime, $1.id) }
            var group: [ScheduleEntry] = []
            var groupEnd = 0
            func appendGroup() {
                var ends: [Int] = []
                var assigned: [(ScheduleEntry, Int)] = []
                for entry in group {
                    let lane = ends.firstIndex { $0 <= entry.startTime } ?? ends.count
                    if lane == ends.count { ends.append(entry.endTime) } else { ends[lane] = entry.endTime }
                    assigned.append((entry, lane))
                }
                result += assigned.map { SchedulePlacement(entry: $0.0, column: $0.1, columnCount: ends.count) }
            }
            for entry in sorted {
                if !group.isEmpty && entry.startTime >= groupEnd {
                    appendGroup()
                    group = []
                    groupEnd = 0
                }
                group.append(entry)
                groupEnd = max(groupEnd, entry.endTime)
            }
            appendGroup()
        }
        return result.sorted { ($0.entry.date, $0.entry.startTime, $0.id) < ($1.entry.date, $1.entry.startTime, $1.id) }
    }
}
