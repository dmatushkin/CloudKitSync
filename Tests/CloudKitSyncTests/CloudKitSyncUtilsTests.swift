//
//  CloudKitSyncTests.swift
//  CloudKitSyncTests
//
//  Created by Dmitry Matyushkin on 8/14/20.
//  Copyright © 2020 Dmitry Matyushkin. All rights reserved.
//

import XCTest
import CommonError
import DependencyInjection
import CloudKit
@testable import CloudKitSync

//swiftlint:disable type_body_length file_length
class CloudKitSyncUtilsTests: XCTestCase {

	private let operations = CloudKitSyncTestOperations()
    private let storage = CloudKitSyncTestTokenStorage()
    private var utils: CloudKitSyncUtils!

	static var allTests = [
		("testFetchLocalRecordsCombineSuccess", testFetchLocalRecordsCombineSuccess),
		("testFetchLocalRecordsCombineSuccessNoRecords", testFetchLocalRecordsCombineSuccessNoRecords),
		("testFetchLocalRecordsCombineRetry", testFetchLocalRecordsCombineRetry),
		("testFetchLocalRecordsCombinneFail", testFetchLocalRecordsCombinneFail),
		("testUpdateRecordsCombineSuccess", testUpdateRecordsCombineSuccess),
		("testUpdateRecordsCombineSuccessNoRecords", testUpdateRecordsCombineSuccessNoRecords),
		("testUpdateRecordCombineRetry", testUpdateRecordCombineRetry),
		("testUpdateRecordsCombineFail", testUpdateRecordsCombineFail),
		("testFetchDatabaseChangesSuccessCombineNoTokenNoMoreComing", testFetchDatabaseChangesSuccessCombineNoTokenNoMoreComing),
		("testFetchDatabaseChangesSuccessCombineHasTokenNoMoreComing", testFetchDatabaseChangesSuccessCombineHasTokenNoMoreComing),
		("testFetchDatabaseChangesSuccessCombineNoTokenHasMoreComing", testFetchDatabaseChangesSuccessCombineNoTokenHasMoreComing),
		("testFetchDatabaseChangesCombineRetry", testFetchDatabaseChangesCombineRetry),
		("testFetchDatabaseChangesCombineTokenReset", testFetchDatabaseChangesCombineTokenReset),
		("testFetchDatabaseChangesCombineFail", testFetchDatabaseChangesCombineFail),
		("testFetchZoneChangesCombineSuccessNoTokenNoMore", testFetchZoneChangesCombineSuccessNoTokenNoMore),
		("testFetchZoneChangesCombineSuccessNoZones", testFetchZoneChangesCombineSuccessNoZones),
		("testFetchZoneChangesCombineSuccessHasTokenNoMore", testFetchZoneChangesCombineSuccessHasTokenNoMore),
		("testFetchZoneChangesCombineSuccessNoTokenHasMore", testFetchZoneChangesCombineSuccessNoTokenHasMore),
		("testFetchZoneChangesCombineSuccessResetToken", testFetchZoneChangesCombineSuccessResetToken),
		("testFetchZoneChangesCombineSuccessRetry", testFetchZoneChangesCombineSuccessRetry),
		("testFetchZoneChangesCombineFail", testFetchZoneChangesCombineFail)
	]

    override func setUp() {
        self.operations.cleanup()
        self.storage.cleanup()
		DIProvider.shared
			.register(forType: CloudKitSyncOperationsProtocol.self, object: self.operations)
			.register(forType: CloudKitSyncTokenStorageProtocol.self, object: self.storage)
        self.utils = CloudKitSyncUtils()
    }

    override func tearDown() {
		DIProvider.shared.clear()
        self.operations.cleanup()
        self.storage.cleanup()
        self.utils = nil
    }
    
    func testFetchLocalRecordsCombineSuccess() async throws {
        let recordIds = [CKRecord.ID(recordName: "aaaa"), CKRecord.ID(recordName: "bbbb"), CKRecord.ID(recordName: "cccc")]
        self.operations.onAddOperation = { operation, localOperations, sharedOperations in
            XCTAssertEqual((operation as? CKFetchRecordsOperation)?.recordIDs?.elementsEqual(recordIds), true)
            for recordId in recordIds {
                let record = CKRecord(recordType: CKRecord.RecordType("testDataRecord"), recordID: recordId)
                (operation as? CKFetchRecordsOperation)?.perRecordResultBlock?(recordId, .success(record))
            }
            (operation as? CKFetchRecordsOperation)?.fetchRecordsResultBlock?(.success(()))
        }
        let records = try await self.utils.fetchRecords(recordIds: recordIds, localDb: true)
        XCTAssertEqual(records.count, 3)
        XCTAssertEqual(records[0].recordID.recordName, "aaaa")
        XCTAssertEqual(records[1].recordID.recordName, "bbbb")
        XCTAssertEqual(records[2].recordID.recordName, "cccc")
    }
    
    func testFetchLocalRecordsCombineSuccessNoRecords() async throws {
        let records = try await self.utils.fetchRecords(recordIds: [], localDb: true)
        XCTAssertEqual(records.count, 0)
    }

    func testFetchLocalRecordsCombineRetry() async throws {
        let recordIds = [CKRecord.ID(recordName: "aaaa"), CKRecord.ID(recordName: "bbbb"), CKRecord.ID(recordName: "cccc")]
        self.operations.onAddOperation = { operation, localOperations, sharedOperations in
            XCTAssertEqual((operation as? CKFetchRecordsOperation)?.recordIDs?.elementsEqual(recordIds), true)
            if localOperations.count == 1 {
                (operation as? CKFetchRecordsOperation)?.fetchRecordsResultBlock?(.failure(CommonError(description: "retry")))
            } else {
                for recordId in recordIds {
                    let record = CKRecord(recordType: CKRecord.RecordType("testDataRecord"), recordID: recordId)
                    (operation as? CKFetchRecordsOperation)?.perRecordResultBlock?(recordId, .success(record))
                }
                (operation as? CKFetchRecordsOperation)?.fetchRecordsResultBlock?(.success(()))
            }
        }
        let records = try await self.utils.fetchRecords(recordIds: recordIds, localDb: true)
        XCTAssertEqual(self.operations.localOperations.count, 2)
        XCTAssertEqual(records.count, 3)
        XCTAssertEqual(records[0].recordID.recordName, "aaaa")
        XCTAssertEqual(records[1].recordID.recordName, "bbbb")
        XCTAssertEqual(records[2].recordID.recordName, "cccc")
    }
    
    func testFetchLocalRecordsCombinneFail() async {
        let recordIds = [CKRecord.ID(recordName: "aaaa"), CKRecord.ID(recordName: "bbbb"), CKRecord.ID(recordName: "cccc")]
        self.operations.onAddOperation = { operation, localOperations, sharedOperations in
            (operation as? CKFetchRecordsOperation)?.fetchRecordsResultBlock?(.failure(CommonError(description: "fail")))
        }
        do {
            _ = try await self.utils.fetchRecords(recordIds: recordIds, localDb: true)
            XCTAssertTrue(false)
        } catch {
            XCTAssertEqual(error.localizedDescription, "fail")
        }
        XCTAssertEqual(self.operations.localOperations.count, 1)
    }
    
    func testUpdateRecordsCombineSuccess() async throws {
        let records = [CKRecord.ID(recordName: "aaaa"), CKRecord.ID(recordName: "bbbb"), CKRecord.ID(recordName: "cccc")].map({CKRecord(recordType: CKRecord.RecordType("testDataRecord"), recordID: $0)})
        self.operations.onAddOperation = { operation, localOperations, sharedOperations in
            guard let operation = operation as? CKModifyRecordsOperation else { return }
            XCTAssertEqual(operation.recordsToSave?.elementsEqual(records), true)
            operation.modifyRecordsResultBlock?(.success(()))
        }
        try await self.utils.updateRecords(records: records, localDb: true)
        XCTAssertEqual(self.operations.localOperations.count, 1)
    }
    
    func testUpdateRecordsCombineSuccessNoRecords() async throws {
        try await self.utils.updateRecords(records: [], localDb: true)
        XCTAssertEqual(self.operations.localOperations.count, 0)
    }
    
    func testUpdateRecordCombineRetry() async throws {
        let records = [CKRecord.ID(recordName: "aaaa"), CKRecord.ID(recordName: "bbbb"), CKRecord.ID(recordName: "cccc")].map({CKRecord(recordType: CKRecord.RecordType("testDataRecord"), recordID: $0)})
        self.operations.onAddOperation = { operation, localOperations, sharedOperations in
            guard let operation = operation as? CKModifyRecordsOperation else { return }
            XCTAssertEqual(operation.recordsToSave?.elementsEqual(records), true)
            if localOperations.count == 1 {
                operation.modifyRecordsResultBlock?(.failure(CommonError(description: "retry")))
            } else {
                operation.modifyRecordsResultBlock?(.success(()))
            }
        }
        try await self.utils.updateRecords(records: records, localDb: true)
        XCTAssertEqual(self.operations.localOperations.count, 2)
    }
    
    func testUpdateRecordsCombineFail() async {
        let records = [CKRecord.ID(recordName: "aaaa"), CKRecord.ID(recordName: "bbbb"), CKRecord.ID(recordName: "cccc")].map({CKRecord(recordType: CKRecord.RecordType("testDataRecord"), recordID: $0)})
        self.operations.onAddOperation = { operation, localOperations, sharedOperations in
            guard let operation = operation as? CKModifyRecordsOperation else { return }
            XCTAssertEqual(operation.recordsToSave?.elementsEqual(records), true)
            operation.modifyRecordsResultBlock?(.failure(CommonError(description: "fail")))
        }
        do {
            try await self.utils.updateRecords(records: records, localDb: true)
            XCTAssertTrue(false)
        } catch {
            XCTAssertEqual(error.localizedDescription, "fail")
        }
        XCTAssertEqual(self.operations.localOperations.count, 1)
    }

	func testFetchDatabaseChangesSuccessCombineNoTokenNoMoreComing() async throws {
        let zoneIds = [CKRecordZone.ID(zoneName: "testZone1", ownerName: "testOwner"), CKRecordZone.ID(zoneName: "testZone2", ownerName: "testOwner"), CKRecordZone.ID(zoneName: "testZone3", ownerName: "testOwner")]
        let token = TestServerChangeToken(key: "test")
        self.operations.onAddOperation = { operation, localOperations, sharedOperations in
            guard let operation = operation as? CKFetchDatabaseChangesOperation else { return }
            XCTAssertEqual(operation.previousServerChangeToken, nil)
            for zoneId in zoneIds {
                operation.recordZoneWithIDChangedBlock?(zoneId)
            }
            operation.fetchDatabaseChangesResultBlock?(.success((token!, false)))
        }
        let zoneIdsResult = try await self.utils.fetchDatabaseChanges(localDb: true)
        XCTAssertEqual(self.operations.localOperations.count, 1)
        XCTAssertEqual(zoneIdsResult.elementsEqual(zoneIds), true)
        XCTAssertEqual((self.storage.getDbToken(localDb: true) as? TestServerChangeToken)?.key, "test")
    }

	func testFetchDatabaseChangesSuccessCombineHasTokenNoMoreComing() async throws {
        let zoneIds = [CKRecordZone.ID(zoneName: "testZone1", ownerName: "testOwner"), CKRecordZone.ID(zoneName: "testZone2", ownerName: "testOwner"), CKRecordZone.ID(zoneName: "testZone3", ownerName: "testOwner")]
        self.storage.setDbToken(localDb: true, token: TestServerChangeToken(key: "orig"))
        let token = TestServerChangeToken(key: "test")
        self.operations.onAddOperation = { operation, localOperations, sharedOperations in
            guard let operation = operation as? CKFetchDatabaseChangesOperation else { return }
            XCTAssertNotEqual((operation.previousServerChangeToken as? TestServerChangeToken), nil)
            for zoneId in zoneIds {
                operation.recordZoneWithIDChangedBlock?(zoneId)
            }
            operation.fetchDatabaseChangesResultBlock?(.success((token!, false)))
        }
        let zoneIdsResult = try await self.utils.fetchDatabaseChanges(localDb: true)
        XCTAssertEqual(self.operations.localOperations.count, 1)
        XCTAssertEqual(zoneIdsResult.elementsEqual(zoneIds), true)
        XCTAssertEqual((self.storage.getDbToken(localDb: true) as? TestServerChangeToken)?.key, "test")
    }

	func testFetchDatabaseChangesSuccessCombineNoTokenHasMoreComing() async throws {
        let zoneIds = [CKRecordZone.ID(zoneName: "testZone1", ownerName: "testOwner"), CKRecordZone.ID(zoneName: "testZone2", ownerName: "testOwner"), CKRecordZone.ID(zoneName: "testZone3", ownerName: "testOwner")]
        let zoneIds2 = [CKRecordZone.ID(zoneName: "testZone4", ownerName: "testOwner"), CKRecordZone.ID(zoneName: "testZone5", ownerName: "testOwner"), CKRecordZone.ID(zoneName: "testZone6", ownerName: "testOwner")]
        let token = TestServerChangeToken(key: "test")
        let token2 = TestServerChangeToken(key: "test2")
        self.operations.onAddOperation = { operation, localOperations, sharedOperations in
            guard let operation = operation as? CKFetchDatabaseChangesOperation else { return }
            if localOperations.count == 1 {
                XCTAssertEqual(operation.previousServerChangeToken, nil)
                for zoneId in zoneIds {
                    operation.recordZoneWithIDChangedBlock?(zoneId)
                }
                operation.fetchDatabaseChangesResultBlock?(.success((token!, true)))
            } else {
                XCTAssertNotEqual(operation.previousServerChangeToken, nil)
                for zoneId in zoneIds2 {
                    operation.recordZoneWithIDChangedBlock?(zoneId)
                }
                operation.fetchDatabaseChangesResultBlock?(.success((token2!, false)))
            }
        }
        let zoneIdsResult = try await self.utils.fetchDatabaseChanges(localDb: true)
        XCTAssertEqual(self.operations.localOperations.count, 2)
        XCTAssertEqual(zoneIdsResult.elementsEqual(zoneIds + zoneIds2), true)
        XCTAssertEqual((self.storage.getDbToken(localDb: true) as? TestServerChangeToken)?.key, "test2")
    }

	func testFetchDatabaseChangesCombineRetry() async throws {
        let zoneIds = [CKRecordZone.ID(zoneName: "testZone1", ownerName: "testOwner"), CKRecordZone.ID(zoneName: "testZone2", ownerName: "testOwner"), CKRecordZone.ID(zoneName: "testZone3", ownerName: "testOwner")]
        let token = TestServerChangeToken(key: "test")
        self.operations.onAddOperation = { operation, localOperations, sharedOperations in
            guard let operation = operation as? CKFetchDatabaseChangesOperation else { return }
            if localOperations.count == 1 {
                XCTAssertEqual(operation.previousServerChangeToken, nil)
                operation.fetchDatabaseChangesResultBlock?(.failure(CommonError(description: "retry")))
            } else {
                XCTAssertEqual(operation.previousServerChangeToken, nil)
                for zoneId in zoneIds {
                    operation.recordZoneWithIDChangedBlock?(zoneId)
                }
                operation.fetchDatabaseChangesResultBlock?(.success((token!, false)))
            }
        }
        let zoneIdsResult = try await self.utils.fetchDatabaseChanges(localDb: true)
        XCTAssertEqual(self.operations.localOperations.count, 2)
        XCTAssertEqual(zoneIdsResult.elementsEqual(zoneIds), true)
        XCTAssertEqual((self.storage.getDbToken(localDb: true) as? TestServerChangeToken)?.key, "test")
    }

	func testFetchDatabaseChangesCombineTokenReset() async throws {
        let zoneIds = [CKRecordZone.ID(zoneName: "testZone1", ownerName: "testOwner"), CKRecordZone.ID(zoneName: "testZone2", ownerName: "testOwner"), CKRecordZone.ID(zoneName: "testZone3", ownerName: "testOwner")]
        let token = TestServerChangeToken(key: "test")
        self.storage.setDbToken(localDb: true, token: TestServerChangeToken(key: "orig"))
        self.operations.onAddOperation = { operation, localOperations, sharedOperations in
            guard let operation = operation as? CKFetchDatabaseChangesOperation else { return }
            if localOperations.count == 1 {
                XCTAssertNotEqual(operation.previousServerChangeToken, nil)
                operation.fetchDatabaseChangesResultBlock?(.failure(CommonError(description: "token")))
            } else {
                XCTAssertEqual(operation.previousServerChangeToken, nil)
                for zoneId in zoneIds {
                    operation.recordZoneWithIDChangedBlock?(zoneId)
                }
                operation.fetchDatabaseChangesResultBlock?(.success((token!, false)))
            }
        }
        let zoneIdsResult = try await self.utils.fetchDatabaseChanges(localDb: true)
        XCTAssertEqual(self.operations.localOperations.count, 2)
        XCTAssertEqual(zoneIdsResult.elementsEqual(zoneIds), true)
        XCTAssertEqual((self.storage.getDbToken(localDb: true) as? TestServerChangeToken)?.key, "test")
    }

	func testFetchDatabaseChangesCombineFail() async {
        self.operations.onAddOperation = { operation, localOperations, sharedOperations in
            guard let operation = operation as? CKFetchDatabaseChangesOperation else { return }
            operation.fetchDatabaseChangesResultBlock?(.failure(CommonError(description: "fail")))
        }
        do {
            _ = try await self.utils.fetchDatabaseChanges(localDb: true)
            XCTAssertTrue(false)
        } catch {
            XCTAssertEqual(error.localizedDescription, "fail")
        }
        XCTAssertEqual(self.operations.localOperations.count, 1)
    }

	func testFetchZoneChangesCombineSuccessNoTokenNoMore() async throws {
        let zoneIds = [CKRecordZone.ID(zoneName: "testZone1", ownerName: "testOwner"), CKRecordZone.ID(zoneName: "testZone2", ownerName: "testOwner"), CKRecordZone.ID(zoneName: "testZone3", ownerName: "testOwner")]
        let tokensMap = zoneIds.reduce(into: [CKRecordZone.ID: TestServerChangeToken](), {result, currentZone in
            let token = TestServerChangeToken(key: currentZone.zoneName)!
            result[currentZone] = token
        })
        let records = [CKRecord.ID(recordName: "aaa"), CKRecord.ID(recordName: "bbb"), CKRecord.ID(recordName: "ccc"), CKRecord.ID(recordName: "ddd")].map({CKRecord(recordType: CKRecord.RecordType("testRecordType"), recordID: $0)})
        self.operations.onAddOperation = { operation, localOperations, sharedOperations in
            guard let operation = operation as? CKFetchRecordZoneChangesOperation else { return }
            for zoneId in zoneIds {
                let option = operation.configurationsByRecordZoneID?[zoneId]
                XCTAssertNotEqual(option, nil)
                XCTAssertEqual(option?.previousServerChangeToken, nil)
            }
            for record in records {
                operation.recordWasChangedBlock?(record.recordID, .success(record))
            }
            for zoneId in zoneIds {
                operation.recordZoneFetchResultBlock?(zoneId, .success((tokensMap[zoneId]!, nil, false)))
            }
            operation.fetchRecordZoneChangesResultBlock?(.success(()))
        }
		let resultRecords = try await self.utils.fetchZoneChanges(zoneIds: zoneIds, localDb: true)
        XCTAssertEqual(self.operations.localOperations.count, 1)
        XCTAssertTrue(resultRecords.elementsEqual(records))
        for zoneId in zoneIds {
            XCTAssertEqual((self.storage.getZoneToken(zoneId: zoneId, localDb: true) as? TestServerChangeToken)?.key, zoneId.zoneName)
        }
    }

	func testFetchZoneChangesCombineSuccessNoZones() async throws {
		let resultRecords = try await self.utils.fetchZoneChanges(zoneIds: [], localDb: true)
        XCTAssertEqual(self.operations.localOperations.count, 0)
        XCTAssertEqual(resultRecords.count, 0)
    }

	func testFetchZoneChangesCombineSuccessHasTokenNoMore() async throws {
        let zoneIds = [CKRecordZone.ID(zoneName: "testZone1", ownerName: "testOwner"), CKRecordZone.ID(zoneName: "testZone2", ownerName: "testOwner"), CKRecordZone.ID(zoneName: "testZone3", ownerName: "testOwner")]
        for zoneId in zoneIds {
            let token = TestServerChangeToken(key: zoneId.zoneName + "prev")!
            self.storage.setZoneToken(zoneId: zoneId, localDb: true, token: token)
        }
        let tokensMap = zoneIds.reduce(into: [CKRecordZone.ID: TestServerChangeToken](), {result, currentZone in
            let token = TestServerChangeToken(key: currentZone.zoneName)!
            result[currentZone] = token
        })
        let records = [CKRecord.ID(recordName: "aaa"), CKRecord.ID(recordName: "bbb"), CKRecord.ID(recordName: "ccc"), CKRecord.ID(recordName: "ddd")].map({CKRecord(recordType: CKRecord.RecordType("testRecordType"), recordID: $0)})
        self.operations.onAddOperation = { operation, localOperations, sharedOperations in
            guard let operation = operation as? CKFetchRecordZoneChangesOperation else { return }
            for zoneId in zoneIds {
                let option = operation.configurationsByRecordZoneID?[zoneId]
                XCTAssertNotEqual(option, nil)
                XCTAssertNotEqual(option?.previousServerChangeToken, nil)
            }
            for record in records {
                operation.recordWasChangedBlock?(record.recordID, .success(record))
            }
            for zoneId in zoneIds {
                operation.recordZoneFetchResultBlock?(zoneId, .success((tokensMap[zoneId]!, nil, false)))
            }
            operation.fetchRecordZoneChangesResultBlock?(.success(()))
        }
        let resultRecords = try await self.utils.fetchZoneChanges(zoneIds: zoneIds, localDb: true)
        XCTAssertEqual(self.operations.localOperations.count, 1)
        XCTAssertTrue(resultRecords.elementsEqual(records))
        for zoneId in zoneIds {
            XCTAssertEqual((self.storage.getZoneToken(zoneId: zoneId, localDb: true) as? TestServerChangeToken)?.key, zoneId.zoneName)
        }
    }

	func testFetchZoneChangesCombineSuccessNoTokenHasMore() async throws {
        let zoneIds = [CKRecordZone.ID(zoneName: "testZone1", ownerName: "testOwner"), CKRecordZone.ID(zoneName: "testZone2", ownerName: "testOwner"), CKRecordZone.ID(zoneName: "testZone3", ownerName: "testOwner")]
        let tokensMap = zoneIds.reduce(into: [CKRecordZone.ID: TestServerChangeToken](), {result, currentZone in
            let token = TestServerChangeToken(key: currentZone.zoneName)!
            result[currentZone] = token
        })
        let tokensMap2 = zoneIds.reduce(into: [CKRecordZone.ID: TestServerChangeToken](), {result, currentZone in
            let token = TestServerChangeToken(key: currentZone.zoneName + "2")!
            result[currentZone] = token
        })
        let records = [CKRecord.ID(recordName: "aaa"), CKRecord.ID(recordName: "bbb"), CKRecord.ID(recordName: "ccc"), CKRecord.ID(recordName: "ddd")].map({CKRecord(recordType: CKRecord.RecordType("testRecordType"), recordID: $0)})
        let records2 = [CKRecord.ID(recordName: "eee"), CKRecord.ID(recordName: "fff"), CKRecord.ID(recordName: "ggg"), CKRecord.ID(recordName: "hhh")].map({CKRecord(recordType: CKRecord.RecordType("testRecordType"), recordID: $0)})
        self.operations.onAddOperation = { operation, localOperations, sharedOperations in
            guard let operation = operation as? CKFetchRecordZoneChangesOperation else { return }
            if localOperations.count == 1 {
                for zoneId in zoneIds {
                    let option = operation.configurationsByRecordZoneID?[zoneId]
                    XCTAssertNotEqual(option, nil)
                    XCTAssertEqual(option?.previousServerChangeToken, nil)
                }
                for record in records {
                    operation.recordWasChangedBlock?(record.recordID, .success(record))
                }
                for zoneId in zoneIds {
                    operation.recordZoneFetchResultBlock?(zoneId, .success((tokensMap[zoneId]!, nil, true)))
                }
                operation.fetchRecordZoneChangesResultBlock?(.success(()))
            } else {
                for zoneId in zoneIds {
                    let option = operation.configurationsByRecordZoneID?[zoneId]
                    XCTAssertNotEqual(option, nil)
                    XCTAssertNotEqual(option?.previousServerChangeToken, nil)
                }
                for record in records2 {
                    operation.recordWasChangedBlock?(record.recordID, .success(record))
                }
                for zoneId in zoneIds {
                    operation.recordZoneFetchResultBlock?(zoneId, .success((tokensMap2[zoneId]!, nil, false)))
                }
                operation.fetchRecordZoneChangesResultBlock?(.success(()))
            }
        }
        let resultRecords = try await self.utils.fetchZoneChanges(zoneIds: zoneIds, localDb: true)
        XCTAssertEqual(self.operations.localOperations.count, 2)
        XCTAssertTrue(resultRecords.elementsEqual(records + records2))
        for zoneId in zoneIds {
            XCTAssertEqual((self.storage.getZoneToken(zoneId: zoneId, localDb: true) as? TestServerChangeToken)?.key, (zoneId.zoneName + "2"))
        }
    }

	func testFetchZoneChangesCombineSuccessResetToken() async throws {
        let zoneIds = [CKRecordZone.ID(zoneName: "testZone1", ownerName: "testOwner"), CKRecordZone.ID(zoneName: "testZone2", ownerName: "testOwner"), CKRecordZone.ID(zoneName: "testZone3", ownerName: "testOwner")]
        let tokensMap = zoneIds.reduce(into: [CKRecordZone.ID: TestServerChangeToken](), {result, currentZone in
            let token = TestServerChangeToken(key: currentZone.zoneName)!
            result[currentZone] = token
        })
        for zoneId in zoneIds {
            let token = TestServerChangeToken(key: zoneId.zoneName + "prev")!
            self.storage.setZoneToken(zoneId: zoneId, localDb: true, token: token)
        }
        let records = [CKRecord.ID(recordName: "aaa"), CKRecord.ID(recordName: "bbb"), CKRecord.ID(recordName: "ccc"), CKRecord.ID(recordName: "ddd")].map({CKRecord(recordType: CKRecord.RecordType("testRecordType"), recordID: $0)})
        self.operations.onAddOperation = { operation, localOperations, sharedOperations in
            guard let operation = operation as? CKFetchRecordZoneChangesOperation else { return }
            if localOperations.count == 1 {
                for zoneId in zoneIds {
                    let option = operation.configurationsByRecordZoneID?[zoneId]
                    XCTAssertNotEqual(option, nil)
                    XCTAssertNotEqual(option?.previousServerChangeToken, nil)
                }
                for zoneId in zoneIds {
                    operation.recordZoneFetchResultBlock?(zoneId, .failure(CommonError(description: "token")))
                }
                operation.fetchRecordZoneChangesResultBlock?(.failure(CommonError(description: "token")))
            } else {
                for zoneId in zoneIds {
                    let option = operation.configurationsByRecordZoneID?[zoneId]
                    XCTAssertNotEqual(option, nil)
                    XCTAssertEqual(option?.previousServerChangeToken, nil)
                }
                for record in records {
                    operation.recordWasChangedBlock?(record.recordID, .success(record))
                }
                for zoneId in zoneIds {
                    operation.recordZoneFetchResultBlock?(zoneId, .success((tokensMap[zoneId]!, nil, false)))
                }
                operation.fetchRecordZoneChangesResultBlock?(.success(()))
            }
        }
        let resultRecords = try await self.utils.fetchZoneChanges(zoneIds: zoneIds, localDb: true)
        XCTAssertEqual(self.operations.localOperations.count, 2)
        XCTAssertTrue(resultRecords.elementsEqual(records))
        for zoneId in zoneIds {
            XCTAssertEqual((self.storage.getZoneToken(zoneId: zoneId, localDb: true) as? TestServerChangeToken)?.key, (zoneId.zoneName))
        }
    }

	func testFetchZoneChangesCombineSuccessRetry() async throws {
        let zoneIds = [CKRecordZone.ID(zoneName: "testZone1", ownerName: "testOwner"), CKRecordZone.ID(zoneName: "testZone2", ownerName: "testOwner"), CKRecordZone.ID(zoneName: "testZone3", ownerName: "testOwner")]
        let tokensMap = zoneIds.reduce(into: [CKRecordZone.ID: TestServerChangeToken](), {result, currentZone in
            let token = TestServerChangeToken(key: currentZone.zoneName)!
            result[currentZone] = token
        })
        let records = [CKRecord.ID(recordName: "aaa"), CKRecord.ID(recordName: "bbb"), CKRecord.ID(recordName: "ccc"), CKRecord.ID(recordName: "ddd")].map({CKRecord(recordType: CKRecord.RecordType("testRecordType"), recordID: $0)})
        self.operations.onAddOperation = { operation, localOperations, sharedOperations in
            guard let operation = operation as? CKFetchRecordZoneChangesOperation else { return }
            if localOperations.count == 1 {
                for zoneId in zoneIds {
                    let option = operation.configurationsByRecordZoneID?[zoneId]
                    XCTAssertNotEqual(option, nil)
                    XCTAssertEqual(option?.previousServerChangeToken, nil)
                }
                for zoneId in zoneIds {
                    operation.recordZoneFetchResultBlock?(zoneId, .failure(CommonError(description: "retry")))
                }
                operation.fetchRecordZoneChangesResultBlock?(.failure(CommonError(description: "retry")))
            } else {
                for zoneId in zoneIds {
                    let option = operation.configurationsByRecordZoneID?[zoneId]
                    XCTAssertNotEqual(option, nil)
                    XCTAssertEqual(option?.previousServerChangeToken, nil)
                }
                for record in records {
                    operation.recordWasChangedBlock?(record.recordID, .success(record))
                }
                for zoneId in zoneIds {
                    operation.recordZoneFetchResultBlock?(zoneId, .success((tokensMap[zoneId]!, nil, false)))
                }
                operation.fetchRecordZoneChangesResultBlock?(.success(()))
            }
        }
        let resultRecords = try await self.utils.fetchZoneChanges(zoneIds: zoneIds, localDb: true)
        XCTAssertEqual(self.operations.localOperations.count, 2)
        XCTAssertTrue(resultRecords.elementsEqual(records))
        for zoneId in zoneIds {
            XCTAssertEqual((self.storage.getZoneToken(zoneId: zoneId, localDb: true) as? TestServerChangeToken)?.key, (zoneId.zoneName))
        }
    }

	func testFetchZoneChangesCombineFail() async {
        let zoneIds = [CKRecordZone.ID(zoneName: "testZone1", ownerName: "testOwner"), CKRecordZone.ID(zoneName: "testZone2", ownerName: "testOwner"), CKRecordZone.ID(zoneName: "testZone3", ownerName: "testOwner")]
        self.operations.onAddOperation = { operation, localOperations, sharedOperations in
            guard let operation = operation as? CKFetchRecordZoneChangesOperation else { return }
            operation.fetchRecordZoneChangesResultBlock?(.failure(CommonError(description: "fail")))
        }
        do {
			_ = try await self.utils.fetchZoneChanges(zoneIds: zoneIds, localDb: true)
            XCTAssertTrue(false)
        } catch {
            XCTAssertEqual(error.localizedDescription, "fail")
        }
        XCTAssertEqual(self.operations.localOperations.count, 1)
    }
}
