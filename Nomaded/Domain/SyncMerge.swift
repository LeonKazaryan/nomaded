import Foundation

/// Two devices that mark the same country before they've synced each save a record of it,
/// and iCloud then hands both records to both devices. These rules pick the copies to delete.
///
/// Every device has to delete the same copies: if each kept the one the other deleted, the
/// country would vanish everywhere. So the oldest record of a group is always the one kept
/// (made first; at the same moment, the smaller id), and nobody ever deletes it. A device
/// that hasn't received it yet keeps the oldest one it has, and lets that go once the real
/// oldest arrives.
enum SyncMerge {
    /// When a record was made, and its id: the order every device agrees on.
    struct Age: Comparable {
        let made: Date
        let id: String

        static func < (lhs: Age, rhs: Age) -> Bool {
            (lhs.made, lhs.id) < (rhs.made, rhs.id)
        }
    }

    /// Every record that repeats an older one.
    static func copies<Record>(
        in records: [Record],
        age: (Record) -> Age,
        isSame: (Record, Record) -> Bool
    ) -> [Record] {
        var kept: [Record] = []
        var copies: [Record] = []
        for record in records.sorted(by: { age($0) < age($1) }) {
            if kept.contains(where: { isSame($0, record) }) {
                copies.append(record)
            } else {
                kept.append(record)
            }
        }
        return copies
    }
}
