//
//  InvokeCommandTests.swift
//
//
//  Created by Joel Saltzman on 6/21/21.
//

import Foundation
import XCTest
import NIO
import SotoLambda
@testable import AWSDeployCore

class InvokeCommandTests: XCTestCase {
    
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
    
    func testRunLogsResponse() throws {
        // Setup
        let payload = "{\"key\":\"value\"}"
        let expectedResponse = "success"
        var instance = try InvokeCommand.parseAsRoot(["my-function", "-l", payload])
        Services.shared = mockServices
        defer { Services.shared = Services() }
        // Given a successful invocation
        mockServices.mockInvoker.invoke = { _ in
            let promise = self.mockServices.lambda.eventLoopGroup.next().makePromise(of: Optional<Data>.self)
            promise.succeed(expectedResponse.data(using: .utf8))
            return promise.futureResult
        }
        
        // When calling run
        try instance.run()
        
        // Then the response should be logged
        XCTAssertEqual(mockServices.logCollector.logs.debugDescription, expectedResponse)
    }
    func testRunHandlesEmptyResponse() throws {
        // Setup
        let payload = "{\"key\":\"value\"}"
        var instance = try InvokeCommand.parseAsRoot(["my-function", "-l", payload])
        Services.shared = mockServices
        defer { Services.shared = Services() }
        // Given a successful invocation
        mockServices.mockInvoker.invoke = { _ in
            let promise = self.mockServices.lambda.eventLoopGroup.next().makePromise(of: Optional<Data>.self)
            promise.succeed(nil)
            return promise.futureResult
        }
        
        // When calling run
        try instance.run()
        
        // Then the response should be logged
        XCTAssertTrue(mockServices.logCollector.logs.debugDescription.contains("Invoke completed"))
    }
}
