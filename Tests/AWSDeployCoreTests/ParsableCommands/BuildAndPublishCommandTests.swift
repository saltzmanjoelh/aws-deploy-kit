//
//  BuildAndPublishCommandTests.swift
//
//
//  Created by Joel Saltzman on 6/21/21.
//

import Foundation
import XCTest
import Logging
import LogKit
import NIO
import SotoLambda
@testable import AWSDeployCore
@testable import SotoTestUtils

class BuildAndPublishCommandTests: XCTestCase {
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
    func testRunWithMocks() throws {
        // Given a valid configuration
        let packageDirectory = tempPackageDirectory()
        var instance = try! AWSDeployCommand.parseAsRoot(["build-and-publish", ExamplePackage.executableOne, "-d", packageDirectory.path]) as! BuildAndPublishCommand
        Services.shared = mockServices
        mockServices.mockFileManager.fileExists = { _ in return true }
        mockServices.mockBuilder.buildProducts = { _ throws -> [URL] in
            return [Builder.URLForBuiltExecutable(ExamplePackage.executableOne, at: packageDirectory, services: self.mockServices)]
        }
        mockServices.mockPublisher.publishArchive = { _ -> EventLoopFuture<Lambda.AliasConfiguration> in
            return self.mockServices.stubAliasConfiguration()
        }
        
        // When calling run()
        // Then no errors are thrown
        XCTAssertNoThrow(try instance.run())
        XCTAssertTrue(mockServices.mockBuilder.$buildProducts.wasCalled)
        XCTAssertTrue(mockServices.mockPublisher.$publishArchive.wasCalled)
    }
    func testSSHKeyIsApplied() throws {
        // Given a valid configuration
        let packageDirectory = tempPackageDirectory()
        let sshKey = URL(fileURLWithPath: "/path/to/key")
        var instance = try! AWSDeployCommand.parseAsRoot(["build-and-publish", ExamplePackage.executableOne, "-d", packageDirectory.path, "-k", sshKey.path]) as! BuildAndPublishCommand
        Services.shared = mockServices
        mockServices.mockFileManager.fileExists = { _ in return true }
        mockServices.mockBuilder.buildProducts = { _ throws -> [URL] in
            return [Builder.URLForBuiltExecutable(ExamplePackage.executableOne, at: packageDirectory, services: self.mockServices)]
        }
        mockServices.mockPublisher.publishArchive = { _ -> EventLoopFuture<Lambda.AliasConfiguration> in
            return self.mockServices.stubAliasConfiguration()
        }
        
        // When calling run()
        // Then no errors are thrown
        XCTAssertNoThrow(try instance.run())
        XCTAssertTrue(mockServices.mockBuilder.$buildProducts.wasCalled)
        XCTAssertEqual(mockServices.mockBuilder.$buildProducts.usage.history[0].context.2, sshKey)
    }
}
