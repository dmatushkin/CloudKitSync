//
//  CloudKitSyncUtilsStub.swift
//  CloudKitSyncTests
//
//  Created by Dmitry Matyushkin on 8/26/20.
//  Copyright © 2020 Dmitry Matyushkin. All rights reserved.
//

import Foundation
import CloudKit
import SwiftyBeaver
import XCTest
import CommonError
@testable import CloudKitSync

//swiftlint:disable large_tuple

class CloudKitSyncUtilsStub: CloudKitSyncUtilsProtocol {

    static let operationsQueue = DispatchQueue(label: "CloudKitUtilsStub.operationsQueue", attributes: .concurrent)

    var onFetchRecords: (([CKRecord.ID], Bool) -> ([CKRecord], Error?))?
    var onUpdateRecords: (([CKRecord], Bool) -> Error?)?
    var onUpdateSubscriptions: (([CKSubscription], Bool) -> Error?)?
    var onFetchDatabaseChanges: ((Bool) -> ([CKRecordZone.ID], Error?))?
    var onFetchZoneChanges: (([CKRecordZone.ID]) -> ([CKRecord], Error?))?
	var onAcceptShare: ((CKShare.Metadata) -> (CKShare.Metadata, CKShare?, Error?))?

    func cleanup() {
        self.onFetchRecords = nil
        self.onUpdateRecords = nil
        self.onUpdateSubscriptions = nil
        self.onFetchDatabaseChanges = nil
        self.onFetchZoneChanges = nil
    }
    
    func fetchRecords(recordIds: [CKRecord.ID], localDb: Bool) async throws -> [CKRecord] {
        guard let onFetchRecords = self.onFetchRecords else { fatalError() }
        return try await withCheckedThrowingContinuation({ continuation in
            CloudKitSyncUtilsStub.operationsQueue.asyncAfter(deadline: .now() + 0.1) {
                SwiftyBeaver.debug("about to fetch records \(recordIds)")
                let result = onFetchRecords(recordIds, localDb)
                if let error = result.1 {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume(returning: result.0)
                }
            }
        })
    }
    
    func updateSubscriptions(subscriptions: [CKSubscription], localDb: Bool) async throws {
        guard let onUpdateSubscriptions = self.onUpdateSubscriptions else { fatalError() }
        return try await withCheckedThrowingContinuation({ continuation in
            CloudKitSyncUtilsStub.operationsQueue.asyncAfter(deadline: .now() + 0.1) {
                SwiftyBeaver.debug("about to update subscriptions \(subscriptions)")
                if let error = onUpdateSubscriptions(subscriptions, localDb) {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume(returning: ())
                }
            }
        })
    }
    
    func updateRecords(records: [CKRecord], localDb: Bool) async throws {
        guard let onUpdateRecords = self.onUpdateRecords else { fatalError() }
        return try await withCheckedThrowingContinuation({ continuation in
            CloudKitSyncUtilsStub.operationsQueue.asyncAfter(deadline: .now() + 0.1) {
                SwiftyBeaver.debug("about to update records \(records)")
                if let error = onUpdateRecords(records, localDb) {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume(returning: ())
                }
            }
        })
    }
    
    func fetchDatabaseChanges(localDb: Bool) async throws -> [CKRecordZone.ID] {
        guard let onFetchDatabaseChanges = self.onFetchDatabaseChanges else { fatalError() }
        return try await withCheckedThrowingContinuation({ continuation in
            CloudKitSyncUtilsStub.operationsQueue.asyncAfter(deadline: .now() + 0.1) {
                SwiftyBeaver.debug("about to fetch database changes")
                let result = onFetchDatabaseChanges(localDb)
                if let error = result.1 {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume(returning: result.0)
                }
            }
        })
    }

    func fetchZoneChanges(zoneIds: [CKRecordZone.ID], localDb: Bool) async throws -> [CKRecord] {
        guard let onFetchZoneChanges = self.onFetchZoneChanges else { fatalError() }
        return try await withCheckedThrowingContinuation({ continuation in
            CloudKitSyncUtilsStub.operationsQueue.asyncAfter(deadline: .now() + 0.1) {
                SwiftyBeaver.debug("about to fetch zone changes \(zoneIds)")
                let result = onFetchZoneChanges(zoneIds)
                if let error = result.1 {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume(returning: result.0)
                }
            }
        })
    }
    
    func acceptShare(metadata: CKShare.Metadata) async throws -> CKShare {
        guard let onAcceptShare = self.onAcceptShare else { fatalError() }
        return try await withCheckedThrowingContinuation({ continuation in
            CloudKitSyncUtilsStub.operationsQueue.asyncAfter(deadline: .now() + 0.1) {
                SwiftyBeaver.debug("about to accept share \(metadata)")
                let result = onAcceptShare(metadata)
                if let error = result.2 {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume(returning: result.1!)
                }
            }
        })
    }
}

class TokenTestArchiver: NSKeyedArchiver {

    override func decodeObject(forKey key: String) -> Any? {
        return nil
    }
}

class TestServerChangeToken: CKServerChangeToken {

    let key: String

    init?(key: String) {
        self.key = key
        let archiver = TokenTestArchiver()
        super.init(coder: archiver)
        archiver.finishEncoding()
    }

    required init?(coder: NSCoder) {
        self.key = "nothing"
        super.init(coder: coder)
    }
}
