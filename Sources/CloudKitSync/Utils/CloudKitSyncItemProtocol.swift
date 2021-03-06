//
//  CloudKitSyncItemProtocol.swift
//  CloudKitSync
//
//  Created by Dmitry Matyushkin on 8/14/20.
//  Copyright © 2020 Dmitry Matyushkin. All rights reserved.
//

import Foundation
import CloudKit
import Combine
import CommonError

public protocol CloudKitSyncItemProtocol: class {
	static var zoneName: String { get } // Name of the record zone
	static var recordType: String { get } // Type of the record
	static var hasDependentItems: Bool { get } // If this item has dependable items
	static var dependentItemsRecordAttribute: String { get } // Attribute name in record to store dependent items records
	static var dependentItemsType: CloudKitSyncItemProtocol.Type { get } // Class for depentent items
	var isRemote: Bool { get } // Is this item local or remote
	func dependentItems() -> [CloudKitSyncItemProtocol] // List of dependent items
	var recordId: String? { get } // Id of the record, if exists
	var ownerName: String? { get } // Name of record zone owner, if exists
	func setRecordId(_ recordId: String) -> AnyPublisher<CloudKitSyncItemProtocol, Error> // Set id of the record
	func populate(record: CKRecord) -> AnyPublisher<CKRecord, Error> // Populate record with data from item
	static func store(record: CKRecord, isRemote: Bool) -> AnyPublisher<CloudKitSyncItemProtocol, Error> // Store record data locally in item
	func setParent(item: CloudKitSyncItemProtocol) -> AnyPublisher<CloudKitSyncItemProtocol, Error> // Set parent item
}

extension CloudKitSyncItemProtocol {

	func setParent(item: CloudKitSyncItemProtocol?) -> AnyPublisher<CloudKitSyncItemProtocol, Error> {
		if let parent = item {
			return self.setParent(item: parent)
		} else {
			return Future {[weak self] promise in
				if let value = self {
					return promise(.success(value))
				} else {
					return promise(.failure(CommonError(description: "Unable to set parent") as Error))
				}
			}.eraseToAnyPublisher()
		}
	}
}
