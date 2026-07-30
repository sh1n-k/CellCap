import Core
import Foundation
import SystemSupport

/// Shared test doubles for CoreTests. Intentionally non-private so files in this target can reuse them.
struct MockSystemEnvironmentProvider: SystemEnvironmentProviding {
    let operatingSystemVersion: OperatingSystemVersion
    let isAppleSiliconValue: Bool

    init(operatingSystemVersion: OperatingSystemVersion, isAppleSilicon: Bool) {
        self.operatingSystemVersion = operatingSystemVersion
        self.isAppleSiliconValue = isAppleSilicon
    }

    func isAppleSilicon() -> Bool {
        isAppleSiliconValue
    }
}

struct FixedDateProvider: DateProviding {
    let now: Date
}

final class SequenceDateProvider: @unchecked Sendable, DateProviding {
    private let lock = NSLock()
    private var dates: [Date]

    init(dates: [Date]) {
        self.dates = dates
    }

    var now: Date {
        lock.lock()
        defer { lock.unlock() }
        return dates.isEmpty ? .distantPast : dates.removeFirst()
    }
}
