import Foundation

var checks = 0
func check(_ condition: @autoclosure () -> Bool, _ message: String) {
    checks += 1
    if !condition() { fatalError(message) }
}
var calendar = Calendar(identifier: .gregorian)
calendar.timeZone = TimeZone(identifier: "America/New_York")!
func date(_ year: Int, _ month: Int, _ day: Int, _ hour: Int, _ minute: Int = 0) -> Date {
    calendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour, minute: minute))!
}
let five = date(2026, 11, 1, 17)
check(UpdateSchedule.nextCheck(after: date(2026, 11, 1, 15), lastSuccessfulCheck: nil, calendar: calendar) == five, "Before five, check today")
check(UpdateSchedule.nextCheck(after: five, lastSuccessfulCheck: nil, calendar: calendar) == five, "At five, check immediately")
check(UpdateSchedule.nextCheck(after: date(2026, 11, 1, 18), lastSuccessfulCheck: nil, calendar: calendar) == date(2026, 11, 1, 18), "Missed check is due on wake or launch")
check(UpdateSchedule.nextCheck(after: date(2026, 11, 1, 18), lastSuccessfulCheck: five, calendar: calendar) == date(2026, 11, 2, 17), "Successful check schedules next local five")
check(UpdateSchedule.nextCheck(after: date(2026, 11, 1, 18), lastSuccessfulCheck: date(2026, 11, 1, 16), calendar: calendar) == date(2026, 11, 1, 18), "A manual check before five doesn't cancel the scheduled check")
let beforeDST = date(2026, 10, 31, 17)
check(UpdateSchedule.nextCheck(after: beforeDST, lastSuccessfulCheck: beforeDST, calendar: calendar) == five, "Daily checks follow wall time across DST")
let skipped = UpdateVisibility(availableVersion: "2", skippedVersion: "2")
check(!skipped.showsAutomaticBanner && skipped.showsManualResult, "Manual checks still find a skipped update")
check(UpdateVisibility(availableVersion: "3", skippedVersion: "2").showsAutomaticBanner, "A newer update is not suppressed")
check(!UpdateVisibility(availableVersion: nil, skippedVersion: "2").showsAutomaticBanner, "No update means no banner")
print("Passed \(checks) update schedule and visibility checks.")
