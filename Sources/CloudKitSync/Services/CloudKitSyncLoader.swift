//
//  CloudKitSyncLoader.swift
//  CloudKitSync
//
//  Created by Dmitry Matyushkin on 8/26/20.
//  Copyright © 2020 Dmitry Matyushkin. All rights reserved.
//

import Foundation
import CloudKit
import DependencyInjection
import CommonError

public protocol CloudKitSyncLoaderProtocol {

	func loadShare<T>(metadata: CKShare.Metadata, itemType: T.Type) async throws -> T where T: CloudKitSyncItemProtocol
	func fetchChanges<T>(localDb: Bool, itemType: T.Type) async throws -> [T] where T: CloudKitSyncItemProtocol
}

public final class CloudKitSyncLoader: CloudKitSyncLoaderProtocol, DIDependency {

	@Autowired
    private var cloudKitUtils: CloudKitSyncUtilsProtocol

	public init() { }

	public func loadShare<T>(metadata: CKShare.Metadata, itemType: T.Type) async throws -> T where T: CloudKitSyncItemProtocol {
        guard let rootRecordId = metadata.hierarchicalRootRecordID else { throw CommonError(description: "No root record ID for share") }
        _ = try await self.cloudKitUtils.acceptShare(metadata: metadata)
        guard let rootRecord = try await self.cloudKitUtils.fetchRecords(recordIds: [rootRecordId], localDb: false).first else {throw CommonError(description: "No root record")}
        let storedRecord = try await self.storeRecord(record: rootRecord, itemType: itemType, parent: nil)
        guard let result = storedRecord as? T else { throw CommonError(description: "Unable to map item") }
        return result
	}
    
    private func storeRecord(record: CKRecord, itemType: CloudKitSyncItemProtocol.Type, parent: CloudKitSyncItemProtocol?) async throws -> CloudKitSyncItemProtocol {
        let storeItem = try await itemType.store(record: record, isRemote: true)
        if let parent = parent {
            try await storeItem.setParent(item: parent)
        }
        if itemType.hasDependentItems {
            let dependentRecordIDs = (record[itemType.dependentItemsRecordAttribute] as? [CKRecord.Reference])?.map({ $0.recordID }) ?? []
            let dependentRecords = try await self.cloudKitUtils.fetchRecords(recordIds: dependentRecordIDs, localDb: false)
            for record in dependentRecords {
                _ = try await self.storeRecord(record: record, itemType: itemType.dependentItemsType.self, parent: storeItem)
            }
        }
        return storeItem
    }

	public func fetchChanges<T>(localDb: Bool, itemType: T.Type) async throws -> [T] where T: CloudKitSyncItemProtocol {
        let zoneIds = try await self.cloudKitUtils.fetchDatabaseChanges(localDb: localDb)
        let records = try await self.cloudKitUtils.fetchZoneChanges(zoneIds: zoneIds, localDb: localDb)
        let items = try await self.processChangesRecords(records: records, itemType: itemType, parent: nil, localDb: localDb)
        guard let result = items as? [T] else { throw CommonError(description: "Unable to map list") }
        return result
	}
    
    private func processChangesRecords(records: [CKRecord], itemType: CloudKitSyncItemProtocol.Type, parent: CloudKitSyncItemProtocol?, localDb: Bool) async throws -> [CloudKitSyncItemProtocol] {
        let itemRecords = records.filter({ $0.recordType == itemType.recordType && (parent == nil || $0.parent?.recordID.recordName == parent?.recordId) })
        guard !itemRecords.isEmpty else { return [] }
        return try await itemRecords.asyncMap({ record in
            let item = try await itemType.store(record: record, isRemote: !localDb)
            if let parent = parent {
                try await item.setParent(item: parent)
            }
            if itemType.hasDependentItems {
                _ = try await self.processChangesRecords(records: records, itemType: itemType.dependentItemsType.self, parent: item, localDb: localDb)
            }
            return item
        })
    }
}
