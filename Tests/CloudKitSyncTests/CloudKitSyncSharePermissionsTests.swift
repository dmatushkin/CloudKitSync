//
//  CloudKitSyncSharePermissionsTests.swift
//  CloudKitSyncTests
//
//  Created by Dmitry Matyushkin on 8/28/20.
//  Copyright © 2020 Dmitry Matyushkin. All rights reserved.
//

import XCTest
import CloudKit
import Combine
import DependencyInjection
import CommonError
@testable import CloudKitSync

//swiftlint:disable type_body_length

class CloudKitSyncSharePermissionsTests: XCTestCase {

	private let operations = CloudKitSyncTestOperations()
	private let utilsStub = CloudKitSyncUtilsStub()
	private var cloudShare: CloudKitSyncShare!

	static var allTests = [
		("testShareSetupPermissionsGrantedSuccess", testShareSetupPermissionsGrantedSuccess),
		("testShareSetupPermissionsInitialStateSuccess", testShareSetupPermissionsInitialStateSuccess),
		("testShareSetupPermissionsAccountStatusCouldNotDetermine", testShareSetupPermissionsAccountStatusCouldNotDetermine),
		("testShareSetupPermissionsAccountStatusRestricted", testShareSetupPermissionsAccountStatusRestricted),
		("testShareSetupPermissionsAccountStatusNoAccount", testShareSetupPermissionsAccountStatusNoAccount),
		("testShareSetupPermissionsAccountStatusCustomError", testShareSetupPermissionsAccountStatusCustomError),
		("testShareSetupPermissionsPermissionStatusCouldNotComplete", testShareSetupPermissionsPermissionStatusCouldNotComplete),
		("testShareSetupPermissionsPermissionStatusDenied", testShareSetupPermissionsPermissionStatusDenied),
		("testShareSetupPermissionsPermissionStatusCustomError", testShareSetupPermissionsPermissionStatusCustomError),
		("testShareSetupPermissionsRequestPermissionStatusCouldNotComplete", testShareSetupPermissionsRequestPermissionStatusCouldNotComplete),
		("testShareSetupPermissionsRequestPermissionStatusDenied", testShareSetupPermissionsRequestPermissionStatusDenied),
		("testShareSetupPermissionsRequestPermissionStatusCustomError", testShareSetupPermissionsRequestPermissionStatusCustomError),
		("testShareSetupPermissionsSaveZoneCustomError", testShareSetupPermissionsSaveZoneCustomError)
	]

	override func setUp() {
        self.operations.cleanup()
		DIProvider.shared
			.register(forType: CloudKitSyncOperationsProtocol.self, object: self.operations)
			.register(forType: CloudKitSyncUtilsProtocol.self, lambda: { self.utilsStub })
        self.cloudShare = CloudKitSyncShare()
    }

	override func tearDown() {
		DIProvider.shared.clear()
        self.cloudShare = nil
		self.utilsStub.cleanup()
    }

	func testShareSetupPermissionsGrantedSuccess() async {
		var operationsCount: Int = 0
		self.operations.onAccountStatus = {
			operationsCount += 1
			return (CKAccountStatus.available, nil)
		}
		self.operations.onPermissionStatus = {permission in
			operationsCount += 1
			XCTAssertEqual(permission, .userDiscoverability)
			return (CKContainer.ApplicationPermissionStatus.granted, nil)
		}
		self.operations.onSaveZone = { zone in
			operationsCount += 1
			XCTAssertEqual(zone.zoneID.zoneName, TestShoppingList.zoneName)
			return (zone, nil)
		}
		do {
			_ = try await cloudShare.setupUserPermissions(itemType: TestShoppingList.self)
		} catch {
			XCTAssert(false, "Should not be any errors here")
		}
		XCTAssertEqual(operationsCount, 3)
	}

	func testShareSetupPermissionsInitialStateSuccess() async {
		var operationsCount: Int = 0
		self.operations.onAccountStatus = {
			operationsCount += 1
			return (CKAccountStatus.available, nil)
		}
		self.operations.onPermissionStatus = {permission in
			operationsCount += 1
			XCTAssertEqual(permission, .userDiscoverability)
			return (CKContainer.ApplicationPermissionStatus.initialState, nil)
		}
		self.operations.onRequestAppPermission = { permission in
			operationsCount += 1
			XCTAssertEqual(permission, .userDiscoverability)
			return (CKContainer.ApplicationPermissionStatus.granted, nil)
		}
		self.operations.onSaveZone = { zone in
			operationsCount += 1
			XCTAssertEqual(zone.zoneID.zoneName, TestShoppingList.zoneName)
			return (zone, nil)
		}
		do {
			_ = try await cloudShare.setupUserPermissions(itemType: TestShoppingList.self)
		} catch {
			XCTAssert(false, "Should not be any errors here")
		}
		XCTAssertEqual(operationsCount, 4)
	}

	func testShareSetupPermissionsAccountStatusCouldNotDetermine() async {
		var operationsCount: Int = 0
		self.operations.onAccountStatus = {
			operationsCount += 1
			return (CKAccountStatus.couldNotDetermine, nil)
		}
		do {
			_ = try await cloudShare.setupUserPermissions(itemType: TestShoppingList.self)
			XCTAssert(false, "Error should happened")
		} catch {
			XCTAssertEqual(error.localizedDescription, "CloudKit account status incorrect")
		}
		XCTAssertEqual(operationsCount, 1)
	}

	func testShareSetupPermissionsAccountStatusRestricted() async {
		var operationsCount: Int = 0
		self.operations.onAccountStatus = {
			operationsCount += 1
			return (CKAccountStatus.restricted, nil)
		}
		do {
			_ = try await cloudShare.setupUserPermissions(itemType: TestShoppingList.self)
			XCTAssert(false, "Error should happened")
		} catch {
			XCTAssertEqual(error.localizedDescription, "CloudKit account is restricted")
		}
		XCTAssertEqual(operationsCount, 1)
	}

	func testShareSetupPermissionsAccountStatusNoAccount() async {
		var operationsCount: Int = 0
		self.operations.onAccountStatus = {
			operationsCount += 1
			return (CKAccountStatus.noAccount, nil)
		}
		do {
			_ = try await cloudShare.setupUserPermissions(itemType: TestShoppingList.self)
			XCTAssert(false, "Error should happened")
		} catch {
			XCTAssertEqual(error.localizedDescription, "CloudKit account does not exist")
		}
		XCTAssertEqual(operationsCount, 1)
	}

	func testShareSetupPermissionsAccountStatusCustomError() async {
		var operationsCount: Int = 0
		self.operations.onAccountStatus = {
			operationsCount += 1
			return (CKAccountStatus.noAccount, CommonError(description: "test error") as Error)
		}
		do {
			_ = try await cloudShare.setupUserPermissions(itemType: TestShoppingList.self)
			XCTAssert(false, "Error should happened")
		} catch {
			XCTAssertEqual(error.localizedDescription, "test error")
		}
		XCTAssertEqual(operationsCount, 1)
	}

	func testShareSetupPermissionsPermissionStatusCouldNotComplete() async {
		var operationsCount: Int = 0
		self.operations.onAccountStatus = {
			operationsCount += 1
			return (CKAccountStatus.available, nil)
		}
		self.operations.onPermissionStatus = {permission in
			operationsCount += 1
			XCTAssertEqual(permission, .userDiscoverability)
			return (CKContainer.ApplicationPermissionStatus.couldNotComplete, nil)
		}
		do {
			_ = try await cloudShare.setupUserPermissions(itemType: TestShoppingList.self)
			XCTAssert(false, "Error should happened")
		} catch {
			XCTAssertEqual(error.localizedDescription, "CloudKit permission status could not complete")
		}
		XCTAssertEqual(operationsCount, 2)
	}

	func testShareSetupPermissionsPermissionStatusDenied() async {
		var operationsCount: Int = 0
		self.operations.onAccountStatus = {
			operationsCount += 1
			return (CKAccountStatus.available, nil)
		}
		self.operations.onPermissionStatus = {permission in
			operationsCount += 1
			XCTAssertEqual(permission, .userDiscoverability)
			return (CKContainer.ApplicationPermissionStatus.denied, nil)
		}
		do {
			_ = try await cloudShare.setupUserPermissions(itemType: TestShoppingList.self)
			XCTAssert(false, "Error should happened")
		} catch {
			XCTAssertEqual(error.localizedDescription, "CloudKit permission status denied")
		}
		XCTAssertEqual(operationsCount, 2)
	}

	func testShareSetupPermissionsPermissionStatusCustomError() async {
		var operationsCount: Int = 0
		self.operations.onAccountStatus = {
			operationsCount += 1
			return (CKAccountStatus.available, nil)
		}
		self.operations.onPermissionStatus = {permission in
			operationsCount += 1
			XCTAssertEqual(permission, .userDiscoverability)
			return (CKContainer.ApplicationPermissionStatus.denied, CommonError(description: "test error") as Error)
		}
		do {
			_ = try await cloudShare.setupUserPermissions(itemType: TestShoppingList.self)
			XCTAssert(false, "Error should happened")
		} catch {
			XCTAssertEqual(error.localizedDescription, "test error")
		}
		XCTAssertEqual(operationsCount, 2)
	}

	func testShareSetupPermissionsRequestPermissionStatusCouldNotComplete() async {
		var operationsCount: Int = 0
		self.operations.onAccountStatus = {
			operationsCount += 1
			return (CKAccountStatus.available, nil)
		}
		self.operations.onPermissionStatus = {permission in
			operationsCount += 1
			XCTAssertEqual(permission, .userDiscoverability)
			return (CKContainer.ApplicationPermissionStatus.initialState, nil)
		}
		self.operations.onRequestAppPermission = { permission in
			operationsCount += 1
			XCTAssertEqual(permission, .userDiscoverability)
			return (CKContainer.ApplicationPermissionStatus.couldNotComplete, nil)
		}
		do {
			_ = try await cloudShare.setupUserPermissions(itemType: TestShoppingList.self)
			XCTAssert(false, "Error should happened")
		} catch {
			XCTAssertEqual(error.localizedDescription, "CloudKit permission status could not complete")
		}
		XCTAssertEqual(operationsCount, 3)
	}

	func testShareSetupPermissionsRequestPermissionStatusDenied() async {
		var operationsCount: Int = 0
		self.operations.onAccountStatus = {
			operationsCount += 1
			return (CKAccountStatus.available, nil)
		}
		self.operations.onPermissionStatus = {permission in
			operationsCount += 1
			XCTAssertEqual(permission, .userDiscoverability)
			return (CKContainer.ApplicationPermissionStatus.initialState, nil)
		}
		self.operations.onRequestAppPermission = { permission in
			operationsCount += 1
			XCTAssertEqual(permission, .userDiscoverability)
			return (CKContainer.ApplicationPermissionStatus.denied, nil)
		}
		do {
			_ = try await cloudShare.setupUserPermissions(itemType: TestShoppingList.self)
			XCTAssert(false, "Error should happened")
		} catch {
			XCTAssertEqual(error.localizedDescription, "CloudKit permission status denied")
		}
		XCTAssertEqual(operationsCount, 3)
	}

	func testShareSetupPermissionsRequestPermissionStatusCustomError() async {
		var operationsCount: Int = 0
		self.operations.onAccountStatus = {
			operationsCount += 1
			return (CKAccountStatus.available, nil)
		}
		self.operations.onPermissionStatus = {permission in
			operationsCount += 1
			XCTAssertEqual(permission, .userDiscoverability)
			return (CKContainer.ApplicationPermissionStatus.initialState, nil)
		}
		self.operations.onRequestAppPermission = { permission in
			operationsCount += 1
			XCTAssertEqual(permission, .userDiscoverability)
			return (CKContainer.ApplicationPermissionStatus.denied, CommonError(description: "test error") as Error)
		}
		do {
			_ = try await cloudShare.setupUserPermissions(itemType: TestShoppingList.self)
			XCTAssert(false, "Error should happened")
		} catch {
			XCTAssertEqual(error.localizedDescription, "test error")
		}
		XCTAssertEqual(operationsCount, 3)
	}

	func testShareSetupPermissionsSaveZoneCustomError() async {
		var operationsCount: Int = 0
		self.operations.onAccountStatus = {
			operationsCount += 1
			return (CKAccountStatus.available, nil)
		}
		self.operations.onPermissionStatus = {permission in
			operationsCount += 1
			XCTAssertEqual(permission, .userDiscoverability)
			return (CKContainer.ApplicationPermissionStatus.initialState, nil)
		}
		self.operations.onRequestAppPermission = { permission in
			operationsCount += 1
			XCTAssertEqual(permission, .userDiscoverability)
			return (CKContainer.ApplicationPermissionStatus.granted, nil)
		}
		self.operations.onSaveZone = { zone in
			operationsCount += 1
			XCTAssertEqual(zone.zoneID.zoneName, TestShoppingList.zoneName)
			return (zone, CommonError(description: "test error") as Error)
		}
		do {
			_ = try await cloudShare.setupUserPermissions(itemType: TestShoppingList.self)
			XCTAssert(false, "Error should happened")
		} catch {
			XCTAssertEqual(error.localizedDescription, "test error")
		}
		XCTAssertEqual(operationsCount, 4)
	}
}
