import XCTest

#if !canImport(ObjectiveC)
public func allTests() -> [XCTestCaseEntry] {
    return [
        testCase(CloudKitSyncLoaderTests.allTests),
		testCase(CloudKitSyncSharePermissionsTests.allTests),
		testCase(CloudKitSyncShareTests.allTests),
		testCase(CloudKitSyncUtilsTests.allTests)
    ]
}
#endif
