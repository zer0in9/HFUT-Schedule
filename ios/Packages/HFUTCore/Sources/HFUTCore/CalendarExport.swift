import Foundation

public enum CalendarExport {
    public static func render(_ entries: [ScheduleEntry], generatedAt: Date = Date()) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyyMMdd'T'HHmmss'Z'"
        let stamp = formatter.string(from: generatedAt)
        func escape(_ text: String) -> String {
            text.replacingOccurrences(of: "\\", with: "\\\\")
                .replacingOccurrences(of: "\r\n", with: "\n").replacingOccurrences(of: "\r", with: "\n")
                .replacingOccurrences(of: "\n", with: "\\n")
                .replacingOccurrences(of: ";", with: "\\;").replacingOccurrences(of: ",", with: "\\,")
        }
        var lines = ["BEGIN:VCALENDAR", "VERSION:2.0", "PRODID:-//HFUT Schedule//iOS//ZH", "CALSCALE:GREGORIAN", "METHOD:PUBLISH"]
        for entry in entries {
            guard let start = entry.startDate, let end = entry.endDate else { continue }
            lines += ["BEGIN:VEVENT", "UID:\(escape(entry.id))@hfut-schedule", "DTSTAMP:\(stamp)",
                      "DTSTART:\(formatter.string(from: start))", "DTEND:\(formatter.string(from: end))",
                      "SUMMARY:\(escape(entry.name))", "LOCATION:\(escape(entry.room))",
                      "DESCRIPTION:\(escape(entry.teacher))", "END:VEVENT"]
        }
        lines.append("END:VCALENDAR")
        // RFC 5545: fold at 75 octets without splitting a UTF-8 code point.
        return lines.map { line in
            var folded = "", count = 0
            for scalar in line.unicodeScalars {
                let size = String(scalar).utf8.count
                if count + size > 75 { folded += "\r\n "; count = 1 }
                folded.unicodeScalars.append(scalar)
                count += size
            }
            return folded
        }.joined(separator: "\r\n") + "\r\n"
    }
}
