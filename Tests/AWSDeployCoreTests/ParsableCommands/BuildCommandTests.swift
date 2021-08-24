//
//  BuildCommandTests.swift
//
//
//  Created by Joel Saltzman on 3/18/21.
//

import Foundation
import XCTest
import Logging
import LogKit
import SotoS3
import SotoLambda
@testable import SotoTestUtils
@testable import AWSDeployCore

class BuildCommandTests: XCTestCase {
    
    var mockServices: MockServices!
    
    override func setUp() {
        continueAfterFailure = false
        mockServices = MockServices()
    }
    override func tearDownWithError() throws {
        try super.tearDownWithError()
        mockServices.cleanup()
        try cleanupTestPackage()
    }
    
    func testURLForBuiltProductForExecutable() {
        let packageDirectory = tempPackageDirectory()
        mockServices.mockFileManager.fileExistsMock = { _ in return true }
        let result = Builder.URLForBuiltProduct(ExamplePackage.executableOne, at: packageDirectory, services: self.mockServices)
        XCTAssertFalse(result.path.contains(".swiftmodule"), "Executables should not get .swiftmodule appended to the path.")
    }
    func testURLForBuiltProductForLibrary() {
        let packageDirectory = tempPackageDirectory()
        mockServices.mockFileManager.fileExistsMock = { _ in return false }
        let result = Builder.URLForBuiltProduct(ExamplePackage.library, at: packageDirectory, services: self.mockServices)
        XCTAssertTrue(result.path.contains(".swiftmodule"), "Executables should get .swiftmodule appended to the path.")
    }
    
    func testRunWithMocks() throws {
        // Given a valid configuration
        let packageDirectory = tempPackageDirectory()
        var instance = try! BuildCommand.parseAsRoot(["build", "-d", packageDirectory.path, ExamplePackage.executableOne.name]) as! BuildCommand
        Services.shared = mockServices
        mockServices.mockBuilder.loadProducts = { _ in return ExamplePackage.products }
        mockServices.mockBuilder.buildProducts = { _ throws -> [URL] in
            return [Builder.URLForBuiltProduct(ExamplePackage.executableOne, at: packageDirectory, services: self.mockServices)]
        }
        
        // When calling run()
        // Then no errors are thrown
        XCTAssertNoThrow(try instance.run())
        // And the product get's built and packaged
        XCTAssertTrue(mockServices.mockBuilder.$buildProducts.wasCalled)
    }
    
    func testSSHKey() throws {
        // Given an ssh key
        let key = URL(fileURLWithPath: "/path/to/key")
        let packageDirectory = tempPackageDirectory()
        var instance = try! BuildCommand.parseAsRoot(["build", "-d", packageDirectory.path, ExamplePackage.executableOne.name, "-k", key.path]) as! BuildCommand
        Services.shared = mockServices
        mockServices.mockFileManager.fileExistsMock = { _ in return true }
        mockServices.mockBuilder.loadProducts = { _ in return ExamplePackage.products }
        mockServices.mockBuilder.buildProducts = { _ throws -> [URL] in
            return [Builder.URLForBuiltProduct(ExamplePackage.executableOne, at: packageDirectory, services: self.mockServices)]
        }
        
        // When calling run()
        // Then no errors are thrown
        XCTAssertNoThrow(try instance.run())
        // And the ssh key is provided
        XCTAssertTrue(mockServices.mockBuilder.$buildProducts.wasCalled)
        XCTAssertEqual(mockServices.mockBuilder.$buildProducts.usage.history[0].context.2, key)
    }
}
