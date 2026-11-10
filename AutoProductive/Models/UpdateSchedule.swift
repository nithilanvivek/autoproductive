import Foundation

/// Calendar-based checks use local wall time rather than fixed 24-hour intervals,
/// which would drift when daylight saving time or the time zone changes.
enum UpdateSchedule {
    static func nextCheck(after now: Date, lastSuccessfulCheck: Date?, calendar: Calendar = .current) -> Date {
        let today = calendar.startOfDay(for: now)
        guard let todayAtFive = calendar.date(bySettingHour: 17, minute: 0, second: 0, of: today) else {
            return now
        }
        if now < todayAtFive { return todayAtFive }
        if now >= todayAtFive, lastSuccessfulCheck.map({ $0 >= todayAtFive }) != true {
            return now
        }
        return calendar.nextDate(after: max(now, todayAtFive), matching: DateComponents(hour: 17, minute: 0, second: 0), matchingPolicy: .nextTime) ?? now
    }
}

/// A skipped update is suppressed only in automatic checks. An explicit check
/// still presents it; a newer version also becomes visible automatically.
struct UpdateVisibility: Equatable {
    var availableVersion: String?
    var skippedVersion: String?

    var showsAutomaticBanner: Bool {
        guard let availableVersion else { return false }
        return availableVersion != skippedVersion
    }

    var showsManualResult: Bool { availableVersion != nil }
}
