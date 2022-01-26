//
//  CloudKitSyncOperationsProtocol.swift
//  CloudKitSync
//
//  Created by Dmitry Matyushkin on 8/14/20.
//  Copyright © 2020 Dmitry Matyushkin. All rights reserved.
//

import Foundation
import CloudKit

public protocol CloudKitSyncOperationsProtocol {
    func run(operation: CKDatabaseOperation, localDb: Bool)
	func run(operation: CKOperation)
	func accountStatus(completionHandler: @escaping (CKAccountStatus, Error?) -> Void)
    func permissionStatus(forApplicationPermission applicationPermission: CKContainer.ApplicationPermissions, completionHandler: @escaping CKContainer.ApplicationPermissionBlock)
	func requestApplicationPermission(_ applicationPermission: CKContainer.ApplicationPermissions, completionHandler: @escaping CKContainer.ApplicationPermissionBlock)
	func saveZone(_ zone: CKRecordZone, completionHandler: @escaping (CKRecordZone?, Error?) -> Void)
}
