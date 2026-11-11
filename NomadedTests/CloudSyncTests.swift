import CloudKit
import Foundation
import Testing
@testable import Nomaded

struct CloudSyncTests {
    /// A schema missing in production comes back as one record turned down inside a batch,
    /// inside Core Data's own error: the words that say what to fix are the record's.
    @Test func aRefusalDeepInsideSaysWhy() {
        let reason = "Cannot create or modify field 'CD_countryCode' in record 'CD_Visit' in production schema"
        let refused = NSError(domain: CKError.errorDomain, code: CKError.serverRejectedRequest.rawValue, userInfo: [NSLocalizedDescriptionKey: reason])
        let batch = NSError(domain: CKError.errorDomain, code: CKError.partialFailure.rawValue, userInfo: [
            CKPartialErrorsByItemIDKey: [CKRecord.ID(recordName: "visit"): refused],
        ])
        let wrapped = NSError(domain: NSCocoaErrorDomain, code: 134_400, userInfo: [NSUnderlyingErrorKey: batch])
        let said = CloudSync.describe(wrapped)
        #expect(said.contains(reason))
        #expect(said.contains("\(CKError.serverRejectedRequest.rawValue)"))
    }

    /// One record turned down sinks the whole batch: the rest come back as "Atomic failure"
    /// (what TestFlight 1.2 (6) showed), and the reason is only on the one that sank it.
    @Test func anAtomicFailurePointsAtTheRecordThatSankIt() {
        let reason = "Cannot create new type CD_VisitedCity in production schema"
        var partials: [CKRecord.ID: NSError] = [:]
        for index in 0..<5 {
            partials[CKRecord.ID(recordName: "fine-\(index)")] = NSError(domain: CKError.errorDomain, code: CKError.batchRequestFailed.rawValue, userInfo: [NSLocalizedDescriptionKey: "Atomic failure"])
        }
        partials[CKRecord.ID(recordName: "city")] = NSError(domain: CKError.errorDomain, code: CKError.serverRejectedRequest.rawValue, userInfo: [NSLocalizedDescriptionKey: reason])
        let batch = NSError(domain: CKError.errorDomain, code: CKError.partialFailure.rawValue, userInfo: [CKPartialErrorsByItemIDKey: partials])
        #expect(CloudSync.describe(batch).contains(reason))
    }

    @Test func aPlainErrorSaysItself() {
        let error = NSError(domain: CKError.errorDomain, code: CKError.networkUnavailable.rawValue, userInfo: [NSLocalizedDescriptionKey: "The Internet connection appears to be offline."])
        #expect(CloudSync.describe(error).hasPrefix("The Internet connection appears to be offline."))
    }

    @Test func aLongStoryIsCut() {
        let error = NSError(domain: "Test", code: 1, userInfo: [NSLocalizedDescriptionKey: String(repeating: "x", count: 1_000)])
        #expect(CloudSync.describe(error).count <= 300)
    }
}
