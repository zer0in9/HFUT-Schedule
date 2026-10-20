import Foundation

public enum SnapshotCodec {
    /// Validate imported/cached data before it reaches SwiftUI identity and layout calculations.
    public static func decode(_ data: Data) throws -> AcademicSnapshot {
        guard data.count <= 20_000_000 else { throw AcademicError.invalidResponse("备份文件大小") }
        let value = try JSONDecoder().decode(AcademicSnapshot.self, from: data)
        guard value.schemaVersion == 1, (34...4034).contains(value.semesterID), (value.semesterID - 34) % 20 == 0,
              value.studentID >= 0, value.courses.count <= 10_000, value.schedule.count <= 50_000,
              value.events.count <= 10_000 else { throw AcademicError.invalidResponse("备份版本或范围") }
        func unique<T: Hashable>(_ ids: [T]) -> Bool { Set(ids).count == ids.count }
        guard unique(value.courses.map(\.id)), unique(value.schedule.map(\.id)), unique(value.grades.map(\.id)),
              unique(value.exams.map(\.id)), unique(value.events.map(\.id)) else { throw AcademicError.invalidResponse("备份中的重复记录") }
        for entry in value.schedule {
            guard (1...60).contains(entry.week), (1...7).contains(entry.weekday), SchoolDate.parse(entry.date) != nil,
                  (0...2359).contains(entry.startTime), (0...2359).contains(entry.endTime), entry.endTime > entry.startTime,
                  entry.startTime % 100 < 60, entry.endTime % 100 < 60 else { throw AcademicError.invalidResponse("备份课程时间") }
        }
        func validProgram(_ module: ProgramModule, depth: Int) -> Bool {
            depth < 30 && unique(module.children.map(\.id)) && unique(module.courses.map(\.id)) &&
            module.children.allSatisfy { validProgram($0, depth: depth + 1) }
        }
        if let program = value.program, !validProgram(program, depth: 0) { throw AcademicError.invalidResponse("备份培养方案") }
        return value
    }
}
