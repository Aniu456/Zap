import Foundation

enum RelativeTime {
    private static let dayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh-Hans-SG")
        formatter.setLocalizedDateFormatFromTemplate("MMMd")
        return formatter
    }()

    static func string(from date: Date, now: Date = Date()) -> String {
        let seconds = Int(now.timeIntervalSince(date))
        if seconds < 10 { return "刚刚" }
        if seconds < 60 { return "\(seconds) 秒前" }
        let minutes = seconds / 60
        if minutes < 60 { return "\(minutes) 分钟前" }
        let hours = minutes / 60
        if hours < 24 { return "\(hours) 小时前" }
        let days = hours / 24
        if days < 7 { return "\(days) 天前" }
        return dayFormatter.string(from: date)
    }
}
