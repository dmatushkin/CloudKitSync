//
//  CloudKitSyncShare.swift
//  CloudKitSync
//
//  Created by Dmitry Matyushkin on 8/26/20.
//  Copyright © 2020 Dmitry Matyushkin. All rights reserved.
//

import Foundation
import CloudKit
import DependencyInjection
import CommonError

extension CKRecordZone {
    
    convenience init(ownerName: String?, zoneName: String) {
        if let ownerName = ownerName {
            self.init(zoneID: CKRecordZone.ID(zoneName: zoneName, ownerName: ownerName))
        } else {
            self.init(zoneName: zoneName)
        }
    }
}

extension Collection {
    
    public func asyncCompactMap<ElementOfResult>(_ transform: @escaping (Element) async throws -> ElementOfResult?) async rethrows -> [ElementOfResult] {
        return try await withThrowingTaskGroup(of: ElementOfResult?.self, returning: [ElementOfResult].self, body: { group in
            var result: [ElementOfResult] = []
            for item in self {
                group.addTask {
                    try await transform(item)
                }
            }
            for try await item in group {
                if let item = item {
                    result.append(item)
                }
            }
            return result
        })
    }
    
    public func asyncMap<ElementOfResult>(_ transform: @escaping (Element) async throws -> ElementOfResult) async rethrows -> [ElementOfResult] {
        return try await withThrowingTaskGroup(of: ElementOfResult.self, returning: [ElementOfResult].self, body: { group in
            var result: [ElementOfResult] = []
            for item in self {
                group.addTask {
                    try await transform(item)
                }
            }
            for try await item in group {
                result.append(item)
            }
            return result
        })
    }
}

public protocol CloudKitSyncShareProtocol {
    func setupUserPermissions(itemType: CloudKitSyncItemProtocol.Type) async throws
    func shareItem(item: CloudKitSyncItemProtocol, shareTitle: String, shareType: String) async throws -> CKShare
    func updateItem(item: CloudKitSyncItemProtocol) async throws
}

public final class CloudKitSyncShare: CloudKitSyncShareProtocol, DIDependency {
    
    @Autowired private var cloudKitUtils: CloudKitSyncUtilsProtocol
    @Autowired private var operations: CloudKitSyncOperationsProtocol
    
    public init() { }
    
    private func processAccountStatus(status: CKAccountStatus) async throws -> CKContainer.ApplicationPermissionStatus {
        switch status {
        case .couldNotDetermine:
            throw CommonError(description: "CloudKit account status incorrect")
        case .available:
            return try await withCheckedThrowingContinuation {[weak self] continuation in
                self?.operations.permissionStatus(forApplicationPermission: .userDiscoverability, completionHandler: { (status, error) in
                    if let error = error {
                        continuation.resume(throwing: error)
                    } else {
                        continuation.resume(returning: status)
                    }
                })
            }
        case .restricted:
            throw CommonError(description: "CloudKit account is restricted")
        case .noAccount:
            throw CommonError(description: "CloudKit account does not exist")
        case .temporarilyUnavailable:
            throw CommonError(description: "CloudKit is temporarily unavailable")
        @unknown default:
            throw CommonError(description: "CloudKit account status unknown")
        }
    }
    
    private func processPermissionStatus(status: CKContainer.ApplicationPermissionStatus, itemType: CloudKitSyncItemProtocol.Type) async throws {
        switch status {
        case .initialState:
            let status: CKContainer.ApplicationPermissionStatus = try await withCheckedThrowingContinuation {[weak self] continuation in
                self?.operations.requestApplicationPermission(.userDiscoverability, completionHandler: { (status, error) in
                    if let error = error {
                        continuation.resume(throwing: error)
                    } else {
                        continuation.resume(returning: status)
                    }
                })
            }
            return try await self.processPermissionStatus(status: status, itemType: itemType)
        case .couldNotComplete:
            throw CommonError(description: "CloudKit permission status could not complete")
        case .denied:
            throw CommonError(description: "CloudKit permission status denied")
        case .granted:
            let recordZone = CKRecordZone(zoneName: itemType.zoneName)
            return try await withCheckedThrowingContinuation {[weak self] continuation in
                self?.operations.saveZone(recordZone) { (_, error) in
                    if let error = error {
                        continuation.resume(throwing: error)
                    } else {
                        continuation.resume(returning: ())
                    }
                }
            }
        @unknown default:
            throw CommonError(description: "CloudKit account status unknown")
        }
    }
    
    public func setupUserPermissions(itemType: CloudKitSyncItemProtocol.Type) async throws {
        let accountStatus: CKAccountStatus = try await withCheckedThrowingContinuation {[weak self] continuation in
            self?.operations.accountStatus { (status, error) in
                if let error = error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume(returning: status)
                }
            }
        }
        let permissionStatus = try await self.processAccountStatus(status: accountStatus)
        try await self.processPermissionStatus(status: permissionStatus, itemType: itemType)
    }
    
    private func setItemParents(item: CloudKitSyncItemProtocol) async throws {
        let items = item.dependentItems()
        for dependant in items {
            try await dependant.setParent(item: item)
            if type(of: dependant).hasDependentItems {
                try await self.setItemParents(item: dependant)
            }
        }
    }
    
    private func updateItemRecordId(item: CloudKitSyncItemProtocol) async throws -> CKRecord {
        let recordZoneID = CKRecordZone(ownerName: item.ownerName, zoneName: type(of: item).zoneName).zoneID
        if let recordName = item.recordId {
            let recordId = CKRecord.ID(recordName: recordName, zoneID: recordZoneID)
            if let record = try await cloudKitUtils.fetchRecords(recordIds: [recordId], localDb: !item.isRemote).first {
                try await item.populate(record: record)
                return record
            } else {
                throw CommonError(description: "No records received")
            }
        } else {
            let recordName = CKRecord.ID().recordName
            let recordId = CKRecord.ID(recordName: recordName, zoneID: recordZoneID)
            let record = CKRecord(recordType: type(of: item).recordType, recordID: recordId)
            try await item.setRecordId(recordName)
            try await item.populate(record: record)
            return record
        }
    }
    
    private func fetchRemoteRecords(rootItem: CloudKitSyncItemProtocol, rootRecord: CKRecord, recordZoneID: CKRecordZone.ID) async throws -> [(CloudKitSyncItemProtocol, CKRecord)] {
        let remoteRecordIds = rootItem.dependentItems().compactMap({ $0.recordId }).map({ CKRecord.ID(recordName: $0, zoneID: recordZoneID) })
        if remoteRecordIds.count == 0 {
            return []
        }
        let remoteItemsMap = rootItem.dependentItems().filter({ $0.recordId != nil }).reduce(into: [String: CloudKitSyncItemProtocol](), {result, item in
            if let recordId = item.recordId {
                result[recordId] = item
            }
        })
        let records = try await self.cloudKitUtils.fetchRecords(recordIds: remoteRecordIds, localDb: !rootItem.isRemote)
        return try await records.asyncMap({ record in
            if let item = remoteItemsMap[record.recordID.recordName] {
                record.setParent(rootRecord)
                try await item.populate(record: record)
                return (item, record)
            } else {
                throw CommonError(description: "Consistency error")
            }
        })
    }
    
    private func updateDependentRecords(rootItem: CloudKitSyncItemProtocol, rootRecord: CKRecord) async throws -> [CKRecord] {
        if !type(of: rootItem).hasDependentItems || rootItem.dependentItems().isEmpty {
            return []
        }
        let recordZoneID = CKRecordZone(ownerName: rootItem.ownerName, zoneName: type(of: rootItem).zoneName).zoneID
        let remoteItems = try await self.fetchRemoteRecords(rootItem: rootItem, rootRecord: rootRecord, recordZoneID: recordZoneID)
        let localItems = try await rootItem.dependentItems().filter({ $0.recordId == nil }).asyncMap({item -> (CloudKitSyncItemProtocol, CKRecord) in
            let recordName = CKRecord.ID().recordName
            let recordId = CKRecord.ID(recordName: recordName, zoneID: recordZoneID)
            let record = CKRecord(recordType: type(of: item).recordType, recordID: recordId)
            record.setParent(rootRecord)
            try await item.setRecordId(recordName)
            try await item.populate(record: record)
            return (item, record)
        })
        let allItems = remoteItems + localItems
        let records = allItems.map({ $0.1 })
        rootRecord[type(of: rootItem).dependentItemsRecordAttribute] = records.map({ CKRecord.Reference(record: $0, action: .deleteSelf) }) as CKRecordValue
        let dependentRecords = try await allItems.asyncMap({ item in try await self.updateDependentRecords(rootItem: item.0, rootRecord: item.1) }).flatMap({ $0 })
        return records + dependentRecords
    }
    
    public func shareItem(item: CloudKitSyncItemProtocol, shareTitle: String, shareType: String) async throws -> CKShare {
        try await self.setItemParents(item: item)
        let record = try await self.updateItemRecordId(item: item)
        let dependent = try await self.updateDependentRecords(rootItem: item, rootRecord: record)
        let share = CKShare(rootRecord: record)
        share[CKShare.SystemFieldKey.title] = shareTitle as CKRecordValue
        share[CKShare.SystemFieldKey.shareType] = shareType as CKRecordValue
        share.publicPermission = .readWrite
        try await self.cloudKitUtils.updateRecords(records: [record, share], localDb: !item.isRemote)
        try await self.cloudKitUtils.updateRecords(records: dependent, localDb: !item.isRemote)
        return share
    }
    
    private func appendShareRecordIfNeeded(record: CKRecord, item: CloudKitSyncItemProtocol) async throws -> [CKRecord] {
        if let share = record.share {
            return [record] + (try await self.cloudKitUtils.fetchRecords(recordIds: [share.recordID], localDb: !item.isRemote))
        } else {
            return [record]
        }
    }
    
    public func updateItem(item: CloudKitSyncItemProtocol) async throws {
        try await self.setItemParents(item: item)
        let record = try await self.updateItemRecordId(item: item)
        let records = try await appendShareRecordIfNeeded(record: record, item: item)
        let dependent = try await self.updateDependentRecords(rootItem: item, rootRecord: record)
        try await self.cloudKitUtils.updateRecords(records: records, localDb: !item.isRemote)
        try await self.cloudKitUtils.updateRecords(records: dependent, localDb: !item.isRemote)        
    }
}
