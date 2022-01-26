//
//  CloudKitSyncUtils.swift
//  CloudKitSync
//
//  Created by Dmitry Matyushkin on 8/14/20.
//  Copyright © 2020 Dmitry Matyushkin. All rights reserved.
//

import Foundation
import CloudKit
import SwiftyBeaver
import Combine
import DependencyInjection

public protocol CloudKitSyncUtilsProtocol {
	func fetchRecords(recordIds: [CKRecord.ID], localDb: Bool) -> AnyPublisher<CKRecord, Error>
    func fetchRecords(recordIds: [CKRecord.ID], localDb: Bool) async throws -> [CKRecord]
	func updateSubscriptions(subscriptions: [CKSubscription], localDb: Bool) -> AnyPublisher<Void, Error>
    func updateSubscriptions(subscriptions: [CKSubscription], localDb: Bool) async throws
	func updateRecords(records: [CKRecord], localDb: Bool) -> AnyPublisher<Void, Error>
    func updateRecords(records: [CKRecord], localDb: Bool) async throws
	func fetchDatabaseChanges(localDb: Bool) -> AnyPublisher<[CKRecordZone.ID], Error>
    func fetchDatabaseChanges(localDb: Bool) async throws -> [CKRecordZone.ID]
	func fetchZoneChanges(zoneIds: [CKRecordZone.ID], localDb: Bool) -> AnyPublisher<[CKRecord], Error>
    func fetchZoneChanges(zoneIds: [CKRecordZone.ID], localDb: Bool) async throws -> [CKRecord]
	func acceptShare(metadata: CKShare.Metadata) -> AnyPublisher<(CKShare.Metadata, CKShare?), Error>
    func acceptShare(metadata: CKShare.Metadata) async throws -> CKShare
}

extension Error {
    
    var isRetry: Bool {
        if case .retry = CloudKitSyncErrorType.errorType(forError: self) {
            return true
        } else {
            return false
        }
    }
}

public final class CloudKitSyncUtils: CloudKitSyncUtilsProtocol, DIDependency {

    static let retryQueue = DispatchQueue(label: "CloudKitUtils.retryQueue", attributes: .concurrent)
    @Autowired private var operations: CloudKitSyncOperationsProtocol
    @Autowired private var storage: CloudKitSyncTokenStorageProtocol
    
    private static func handleError<V, E: Error>(_ error: E, continuation: CheckedContinuation<V, E>, restartValue: V? = nil) {
        let cloudKitError = CloudKitSyncErrorType.errorType(forError: error)
        if case let .retry(timeout) = cloudKitError {
            CloudKitSyncUtils.retryQueue.asyncAfter(deadline: .now() + timeout) {
                continuation.resume(throwing: error)
            }
        } else if let restartValue = restartValue, case .tokenReset = cloudKitError {
            continuation.resume(returning: restartValue)
        } else {
            continuation.resume(throwing: error)
        }
    }

	public init() {}

	public func fetchRecords(recordIds: [CKRecord.ID], localDb: Bool) -> AnyPublisher<CKRecord, Error> {
		return CloudKitFetchRecordsPublisher(recordIds: recordIds, localDb: localDb).eraseToAnyPublisher()
	}
    
    public func fetchRecords(recordIds: [CKRecord.ID], localDb: Bool) async throws -> [CKRecord] {
        guard !recordIds.isEmpty else { return [] }
        do {
            return try await withCheckedThrowingContinuation({[weak self] continuation in
                var resultRecords: [CKRecord] = []
                let operation = CKFetchRecordsOperation(recordIDs: recordIds)
                operation.perRecordResultBlock = { _, result in
                    switch result {
                    case let .success(record):
                        resultRecords.append(record)
                    case .failure(_):
                        break
                    }
                }
                operation.fetchRecordsResultBlock = { result in
                    switch result {
                    case .success:
                        continuation.resume(returning: resultRecords)
                    case let .failure(error):
                        CloudKitSyncUtils.handleError(error, continuation: continuation)
                    }
                }
                operation.qualityOfService = .utility
                self?.operations.run(operation: operation, localDb: localDb)
            })
        } catch {
            if error.isRetry {
                return try await fetchRecords(recordIds: recordIds, localDb: localDb)
            } else {
                throw error
            }
        }
    }

	public func updateSubscriptions(subscriptions: [CKSubscription], localDb: Bool) -> AnyPublisher<Void, Error> {
		return CloudKitUpdateSubscriptionsPublisher(subscriptions: subscriptions, localDb: localDb).eraseToAnyPublisher()
	}
    
    public func updateSubscriptions(subscriptions: [CKSubscription], localDb: Bool) async throws {
        guard !subscriptions.isEmpty else { return }
        return try await withCheckedThrowingContinuation({[weak self] continuation in
            let operation = CKModifySubscriptionsOperation(subscriptionsToSave: subscriptions, subscriptionIDsToDelete: [])
            operation.modifySubscriptionsResultBlock = { result in
                switch result {
                case .success:
                    continuation.resume(returning: ())
                case let .failure(error):
                    continuation.resume(throwing: error)
                }
            }
            operation.qualityOfService = .utility
            self?.operations.run(operation: operation, localDb: localDb)
        })
    }

	public func updateRecords(records: [CKRecord], localDb: Bool) -> AnyPublisher<Void, Error> {
		return CloudKitUpdateRecordsPublisher(records: records, localDb: localDb).eraseToAnyPublisher()
	}
    
    public func updateRecords(records: [CKRecord], localDb: Bool) async throws {
        guard !records.isEmpty else { return }
        do {
            return try await withCheckedThrowingContinuation({[weak self] continuation in
                let operation = CKModifyRecordsOperation(recordsToSave: records, recordIDsToDelete: nil)
                operation.modifyRecordsResultBlock = { result in
                    switch result {
                    case .success:
                        continuation.resume(returning: ())
                    case let .failure(error):
                        CloudKitSyncUtils.handleError(error, continuation: continuation)
                    }
                }
                operation.qualityOfService = .utility
                operation.savePolicy = .allKeys
                self?.operations.run(operation: operation, localDb: localDb)
            })
        } catch {
            if error.isRetry {
                return try await updateRecords(records: records, localDb: localDb)
            } else {
                throw error
            }
        }
    }

	public func fetchDatabaseChanges(localDb: Bool) -> AnyPublisher<[CKRecordZone.ID], Error> {
		return CloudKitFetchDatabaseChangesPublisher(localDb: localDb).eraseToAnyPublisher()
	}
    
    public func fetchDatabaseChanges(localDb: Bool) async throws -> [CKRecordZone.ID] {
        return try await fetchDatabaseChangesContinuous(localDb: localDb).0
    }
    
    private func fetchDatabaseChangesContinuous(localDb: Bool) async throws -> ([CKRecordZone.ID], Bool) {
        do {
            let result: ([CKRecordZone.ID], Bool) = try await withCheckedThrowingContinuation({[weak self] continuation in
                guard let self = self else { return }
                var loadedZoneIds: [CKRecordZone.ID] = []
                let operation = CKFetchDatabaseChangesOperation(previousServerChangeToken: self.storage.getDbToken(localDb: localDb))
                operation.recordZoneWithIDChangedBlock = { zoneId in
                    loadedZoneIds.append(zoneId)
                }
                operation.changeTokenUpdatedBlock = {[weak self] token in
                    guard let self = self else { return }
                    self.storage.setDbToken(localDb: localDb, token: token)
                }
                operation.fetchDatabaseChangesResultBlock = {[weak self] result in
                    guard let self = self else { return }
                    switch result {
                    case let .success((token, moreComing)):
                        self.storage.setDbToken(localDb: localDb, token: token)
                        continuation.resume(returning: (loadedZoneIds, moreComing))
                    case let .failure(error):
                        self.storage.setDbToken(localDb: localDb, token: nil)
                        CloudKitSyncUtils.handleError(error, continuation: continuation, restartValue: (loadedZoneIds, true))
                    }
                }
                operation.qualityOfService = .utility
                operation.fetchAllChanges = true
                self.operations.run(operation: operation, localDb: localDb)
            })
            if result.1 {
                return (result.0 + (try await fetchDatabaseChangesContinuous(localDb: localDb)).0, false)
            } else {
                return (result.0, false)
            }
        } catch {
            if error.isRetry {
                return try await fetchDatabaseChangesContinuous(localDb: localDb)
            } else {
                throw error
            }
        }
    }

	public func fetchZoneChanges(zoneIds: [CKRecordZone.ID], localDb: Bool) -> AnyPublisher<[CKRecord], Error> {
		return CloudKitFetchZoneChangesPublisher(zoneIds: zoneIds, localDb: localDb).eraseToAnyPublisher()
	}
    
    public func fetchZoneChanges(zoneIds: [CKRecordZone.ID], localDb: Bool) async throws -> [CKRecord] {
        guard !zoneIds.isEmpty else { return [] }
        return try await fetchZoneChangesContinuous(zoneIds: zoneIds, localDb: localDb).0
    }
    
    private func zoneIdFetchOption(zoneId: CKRecordZone.ID, localDb: Bool) -> CKFetchRecordZoneChangesOperation.ZoneConfiguration {
        let options = CKFetchRecordZoneChangesOperation.ZoneConfiguration()
        options.previousServerChangeToken = self.storage.getZoneToken(zoneId: zoneId, localDb: localDb)
        return options
    }
    
    private func fetchZoneChangesContinuous(zoneIds: [CKRecordZone.ID], localDb: Bool) async throws -> ([CKRecord], Bool) {
        do {
            let result: ([CKRecord], Bool) = try await withCheckedThrowingContinuation({[weak self] continuation in
                guard let self = self else { return }
                var records: [CKRecord] = []
                var moreComingFlag: Bool = false
                let optionsByRecordZoneID = zoneIds.reduce(into: [CKRecordZone.ID: CKFetchRecordZoneChangesOperation.ZoneConfiguration](), { $0[$1] = zoneIdFetchOption(zoneId: $1, localDb: localDb) })
                let operation = CKFetchRecordZoneChangesOperation(recordZoneIDs: zoneIds, configurationsByRecordZoneID: optionsByRecordZoneID)
                operation.fetchAllChanges = true
                operation.recordWasChangedBlock = { _, result in
                    switch result {
                    case let .success(record):
                        records.append(record)
                    default:
                        break
                    }
                }
                operation.recordZoneChangeTokensUpdatedBlock = {[weak self] zoneId, token, data in
                    guard let self = self else { return }
                    self.storage.setZoneToken(zoneId: zoneId, localDb: localDb, token: token)
                }
                operation.recordZoneFetchResultBlock = {[weak self] zoneId, result in
                    guard let self = self else { return }
                    switch result {
                    case let .success((token, _, moreComing)):
                        self.storage.setZoneToken(zoneId: zoneId, localDb: localDb, token: token)
                        if moreComing {
                            moreComingFlag = true
                        }
                    case let .failure(error):
                        if case .tokenReset = CloudKitSyncErrorType.errorType(forError: error) {
                            self.storage.setZoneToken(zoneId: zoneId, localDb: localDb, token: nil)
                        }
                    }
                }
                operation.fetchRecordZoneChangesResultBlock = { result in
                    switch result {
                    case .success:
                        continuation.resume(returning: (records, moreComingFlag))
                    case let .failure(error):
                        CloudKitSyncUtils.handleError(error, continuation: continuation, restartValue: (records, true))
                    }
                }
                operation.qualityOfService = .utility
                operation.fetchAllChanges = true
                self.operations.run(operation: operation, localDb: localDb)
            })
            if result.1 {
                return (result.0 + (try await fetchZoneChangesContinuous(zoneIds: zoneIds, localDb: localDb)).0, false)
            } else {
                return (result.0, false)
            }
        } catch {
            if error.isRetry {
                return try await fetchZoneChangesContinuous(zoneIds: zoneIds, localDb: localDb)
            } else {
                throw error
            }
        }
    }

	public func acceptShare(metadata: CKShare.Metadata) -> AnyPublisher<(CKShare.Metadata, CKShare?), Error> {
		return CloudKitAcceptSharePublisher(metadata: metadata).eraseToAnyPublisher()
	}
    
    public func acceptShare(metadata: CKShare.Metadata) async throws -> CKShare {
        return try await withCheckedThrowingContinuation({[weak self] continuation in
            let operation = CKAcceptSharesOperation(shareMetadatas: [metadata])
            operation.qualityOfService = .userInteractive
            operation.perShareResultBlock = { metadata, result in
                switch result {
                case let .success(share):
                    continuation.resume(returning: share)
                case let .failure(error):
                    continuation.resume(throwing: error)
                }
            }
            self?.operations.run(operation: operation)
        })
    }
}
