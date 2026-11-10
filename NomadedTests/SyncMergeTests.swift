import Foundation
import Testing
@testable import Nomaded

struct SyncMergeTests {
    /// A mark as two devices might each have saved it.
    private struct Mark: Equatable {
        let country: String
        let made: Double
        let id: String
    }

    private static func copies(_ marks: [Mark]) -> [Mark] {
        SyncMerge.copies(
            in: marks,
            age: { SyncMerge.Age(made: Date(timeIntervalSince1970: $0.made), id: $0.id) },
            isSame: { $0.country == $1.country }
        )
    }

    private static let iPhone = Mark(country: "IT", made: 100, id: "B")
    private static let iPad = Mark(country: "IT", made: 200, id: "A")
    private static let france = Mark(country: "FR", made: 300, id: "C")

    @Test func theOldestOfEachPlaceIsKept() {
        #expect(Self.copies([Self.iPad, Self.france, Self.iPhone]) == [Self.iPad])
    }

    @Test func differentPlacesAreNotCopies() {
        #expect(Self.copies([Self.iPhone, Self.france]).isEmpty)
    }

    /// Made at the same moment, the smaller id is kept.
    @Test func aTieGoesToTheSmallerID() {
        let one = Mark(country: "IT", made: 100, id: "1")
        let two = Mark(country: "IT", made: 100, id: "2")
        #expect(Self.copies([two, one]) == [two])
        #expect(Self.copies([one, two]) == [two])
    }

    /// Every device, whatever order its records come in, deletes the same ones.
    @Test func everyDeviceAgrees() {
        let marks = [Self.iPhone, Self.iPad, Self.france, Mark(country: "IT", made: 150, id: "D")]
        let expected = Self.copies(marks)
        for order in [marks.reversed(), [marks[2], marks[0], marks[3], marks[1]], [marks[1], marks[3], marks[0], marks[2]]] {
            #expect(Self.copies(Array(order)) == expected)
        }
    }

    /// A device that hasn't got every record yet never deletes the one everyone keeps.
    @Test func theRecordEveryoneKeepsIsNeverDeleted() {
        let later = Mark(country: "IT", made: 300, id: "E")
        let all = [Self.iPhone, Self.iPad, later]
        for partial in [[Self.iPhone, later], [Self.iPad, later], [Self.iPhone, Self.iPad], [Self.iPhone]] {
            #expect(!Self.copies(partial).contains(Self.iPhone))
        }
        #expect(Self.copies(all) == [Self.iPad, later])
    }
}
