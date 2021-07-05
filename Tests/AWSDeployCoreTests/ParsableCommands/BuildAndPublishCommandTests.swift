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
        mockServices.mockBuilder.buildProducts = { _ throws -> [URL] in
            return [Builder.URLForBuiltExecutable(at: packageDirectory, for: ExamplePackage.executableOne, services: self.mockServices)]
        }
        mockServices.mockPublisher.publishArchives = { _ throws -> EventLoopFuture<[Lambda.AliasConfiguration]> in
            return self.mockServices.stubAliasConfiguration()
                .map({ [$0] })
        }
        
        // When calling run()
        // Then no errors are thrown
        XCTAssertNoThrow(try instance.run())
        XCTAssertTrue(mockServices.mockBuilder.$buildProducts.wasCalled)
        XCTAssertTrue(mockServices.mockPublisher.$publishArchives.wasCalled)
    }
}
