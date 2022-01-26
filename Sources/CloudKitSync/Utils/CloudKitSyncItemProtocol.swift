//
//  CloudKitSyncItemProtocol.swift
//  CloudKitSync
//
//  Created by Dmitry Matyushkin on 8/14/20.
//  Copyright © 2020 Dmitry Matyushkin. All rights reserved.
//

import Foundation
import CloudKit
import CommonError

public protocol CloudKitSyncItemProtocol: AnyObject {
	static var zoneName: String { get } // Name of the record zone
	static var recordType: String { get } // Type of the record
	static var hasDependentItems: Bool { get } // If this item has dependable items
	static var dependentItemsRecordAttribute: String { get } // Attribute name in record to store dependent items records
	static var dependentItemsType: CloudKitSyncItemProtocol.Type { get } // Class for depentent items
	var isRemote: Bool { get } // Is this item local or remote
	func dependentItems() -> [CloudKitSyncItemProtocol] // List of dependent items
	var recordId: String? { get } // Id of the record, if exists
	var ownerName: String? { get } // Name of record zone owner, if exists
	func setRecordId(_ recordId: String) async throws // Set id of the record
	func populate(record: CKRecord) async throws // Populate record with data from item
	static func store(record: CKRecord, isRemote: Bool) async throws -> CloudKitSyncItemProtocol // Store record data locally in item
	func setParent(item: CloudKitSyncItemProtocol) async throws // Set parent item
}
