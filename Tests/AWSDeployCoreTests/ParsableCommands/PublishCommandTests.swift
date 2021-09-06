//
//  PublishCommandTests.swift
//
//
//  Created by Joel Saltzman on 6/21/21.
//

import Foundation
import XCTest
import NIO
import SotoLambda
@testable import AWSDeployCore
@testable import SotoTestUtils

class PublishCommandTests: XCTestCase {
        
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
    
    func testFunctionRoleGetsApplied() throws {
        // Setup
        Services.shared = mockServices
        defer { Services.shared = Services() }
        mockServices.mockBuilder.buildProducts = { _ in return [] }
        mockServices.mockPublisher.publishArchive = { _ in
            return self.mockServices.awsServer.eventLoopGroup.next().makeSucceededFuture(.init(name: "my-function"))
        }
        // Given a functionRole provided in cli
        let role = "example-role"
        var instance = try PublishCommand.parseAsRoot(["my-function.zip", "--function-role", role]) as! PublishCommand
        
        // When running
        try instance.run()
        
        // Then the publisher should receive the value
        XCTAssertEqual(mockServices.publisher.functionRole, role)
    }
    
    func testRunWithMocks() throws {
        // Given an archive
        let payload = "{\"hello\": \"world\"}"
        let packageURL = tempPackageDirectory()
        let archiveURL = packageURL.appendingPathComponent("\(ExamplePackage.executableOne.name).zip")
        var instance = try! PublishCommand.parseAsRoot([archiveURL.path, "-p", payload]) as! PublishCommand
        Services.shared = mockServices
        mockServices.mockPublisher.publishArchive = { _ -> EventLoopFuture<Lambda.AliasConfiguration> in
            return self.mockServices.stubAliasConfiguration()
        }
        
        // When calling run()
        // Then no errors are thrown
        XCTAssertNoThrow(try instance.run())
        // And the product get's published
        XCTAssertTrue(mockServices.mockPublisher.$publishArchive.wasCalled)
    }
    func testInvocationTaskIsCreated() throws {
        // Given an payload to test with
        let payload = "{\"hello\": \"world\"}"
        let packageURL = tempPackageDirectory()
        let archiveURL = packageURL.appendingPathComponent("\(ExamplePackage.executableOne.name).zip")
        var instance = try! PublishCommand.parseAsRoot([archiveURL.path, "-p", payload]) as! PublishCommand
        Services.shared = mockServices
        mockServices.mockPublisher.publishArchive = { _ -> EventLoopFuture<Lambda.AliasConfiguration> in
            return self.mockServices.stubAliasConfiguration()
        }
        
        // When calling run()
        XCTAssertNoThrow(try instance.run())
        
        // Then publishArchive is called with an InvocationTask
        XCTAssertTrue(mockServices.mockPublisher.$publishArchive.wasCalled)
        XCTAssertEqual(mockServices.mockPublisher.$publishArchive.usage.history.count, 1, "publishArchive should have been called once.")
        XCTAssertNotNil(mockServices.mockPublisher.$publishArchive.usage.history.first?.context.2, "The invocationTask should not be nil.")
    }
}
