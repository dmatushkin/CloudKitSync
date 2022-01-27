//
//  PersistModels.swift
//  CloudKitSyncTests
//
//  Created by Dmitry Matyushkin on 8/26/20.
//  Copyright © 2020 Dmitry Matyushkin. All rights reserved.
//

import Foundation
import CloudKitSync
import Combine
import CloudKit
import CommonError

class TestShareMetadata: CKShare.Metadata {

    override var rootRecordID: CKRecord.ID {
        return CKRecord.ID(recordName: "testShareRecord", zoneID: CKRecordZone.ID(zoneName: "testRecordZone", ownerName: "testRecordOwner"))
    }
    
    override var hierarchicalRootRecordID: CKRecord.ID? {
        return rootRecordID
    }
}

class SharedRecord: CKRecord {

    override var share: CKRecord.Reference? {
        let recordId = CKRecord.ID(recordName: "shareTestRecord")
        let record = CKRecord(recordType: "cloudkit.share", recordID: recordId)
        return CKRecord.Reference(record: record, action: .none)
    }
}

let modelOperationsQueue = DispatchQueue(label: "CloudKitSyncItemProtocol.modelOperationsQueue")

class TestShoppingList: CloudKitSyncItemProtocol {

	var items = [TestShoppingItem]()
	var name: String?
	var ownerName: String?
	var date: TimeInterval = 0

	func appendItem(item: TestShoppingItem) {
		if !items.contains(item) {
			items.append(item)
			print("Setting \(item.recordId ?? "no record") as a dependent to \(self.recordId ?? "no record"), \(items.count) total")
		}
	}

	static var zoneName: String {
		return "testZone"
	}

	static var recordType: String {
		return "testListRecord"
	}

	static var hasDependentItems: Bool {
		return true
	}

	static var dependentItemsRecordAttribute: String {
		return "items"
	}

	static var dependentItemsType: CloudKitSyncItemProtocol.Type {
		return TestShoppingItem.self
	}

	var isRemote: Bool = false

	func dependentItems() -> [CloudKitSyncItemProtocol] {
		return items
	}

	var recordId: String?

	func setRecordId(_ recordId: String) async throws {
        try await withCheckedThrowingContinuation({[unowned self] (continuation: CheckedContinuation<Void, Error>) in
            modelOperationsQueue.asyncAfter(deadline: .now() + 0.1) {[unowned self] in
                self.recordId = recordId
                continuation.resume(returning: ())
            }
        })
	}

	func populate(record: CKRecord) async throws {
        try await withCheckedThrowingContinuation({[unowned self] (continuation: CheckedContinuation<Void, Error>) in
            modelOperationsQueue.asyncAfter(deadline: .now() + 0.1) {[unowned self] in
                record["name"] = self.name
                record["date"] = Date(timeIntervalSinceReferenceDate: self.date)
                continuation.resume(returning: ())
            }
        })
	}

	static func store(record: CKRecord, isRemote: Bool) async throws -> CloudKitSyncItemProtocol {
        return try await withCheckedThrowingContinuation({ continuation in
            modelOperationsQueue.asyncAfter(deadline: .now() + 0.1) {
                let list = TestShoppingList()
                list.recordId = record.recordID.recordName
                list.ownerName = record.recordID.zoneID.ownerName
                list.isRemote = isRemote
                list.name = record["name"] as? String
                let date = record["date"] as? Date ?? Date()
                list.date = date.timeIntervalSinceReferenceDate
                continuation.resume(returning: list)
            }
        })
	}

	func setParent(item: CloudKitSyncItemProtocol) async throws {
		fatalError()
	}
}

class TestShoppingItem: CloudKitSyncItemProtocol, Equatable {

	static func == (lhs: TestShoppingItem, rhs: TestShoppingItem) -> Bool {
		return lhs.recordId == rhs.recordId && lhs.ownerName == rhs.ownerName && lhs.goodName == rhs.goodName && lhs.storeName == rhs.storeName && lhs.isRemote == rhs.isRemote
	}

	var goodName: String?
	var storeName: String?
	var ownerName: String?

	static var zoneName: String {
		return "testZone"
	}

	static var recordType: String {
		return "testItemRecord"
	}

	static var hasDependentItems: Bool {
		return false
	}

	static var dependentItemsRecordAttribute: String {
		   return "items"
	}

	static var dependentItemsType: CloudKitSyncItemProtocol.Type {
		   return TestShoppingItem.self
	}

	var isRemote: Bool = false

	func dependentItems() -> [CloudKitSyncItemProtocol] {
		return []
	}

	var recordId: String?

	func setRecordId(_ recordId: String) async throws {
        try await withCheckedThrowingContinuation({[unowned self] (continuation: CheckedContinuation<Void, Error>) in
            modelOperationsQueue.asyncAfter(deadline: .now() + 0.1) {[unowned self] in
                self.recordId = recordId
                continuation.resume(returning: ())
            }
        })
	}

	func populate(record: CKRecord) async throws {
        try await withCheckedThrowingContinuation({[unowned self] (continuation: CheckedContinuation<Void, Error>) in
            modelOperationsQueue.asyncAfter(deadline: .now() + 0.1) {[unowned self] in
                record["goodName"] = self.goodName
                record["storeName"] = self.storeName
                continuation.resume(returning: ())
            }
        })
	}

	static func store(record: CKRecord, isRemote: Bool) async throws -> CloudKitSyncItemProtocol {
        return try await withCheckedThrowingContinuation({ continuation in
            modelOperationsQueue.asyncAfter(deadline: .now() + 0.1) {
                let item = TestShoppingItem()
                item.recordId = record.recordID.recordName
                item.ownerName = record.recordID.zoneID.ownerName
                item.isRemote = isRemote
                item.goodName = record["goodName"] as? String
                item.storeName = record["storeName"] as? String
                continuation.resume(returning: item)
            }
        })
	}

	func setParent(item: CloudKitSyncItemProtocol) async throws {
        try await withCheckedThrowingContinuation({[unowned self] (continuation: CheckedContinuation<Void, Error>) in
            modelOperationsQueue.asyncAfter(deadline: .now() + 0.1) {
                (item as? TestShoppingList)?.appendItem(item: self)
                continuation.resume(returning: ())
            }
        })
	}
}
