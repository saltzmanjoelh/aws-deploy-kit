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
        var instance = try InvokeCommand.parseAsRoot(["my-function", "-p", payload])
        Services.shared = mockServices
        defer { Services.shared = Services() }
        // Given a successful invocation
        mockServices.mockInvoker.invoke = { _ in
            let promise = self.mockServices.lambda.eventLoopGroup.next().makePromise(of: Data.self)
            promise.succeed(expectedResponse.data(using: .utf8)!)
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
        var instance = try InvokeCommand.parseAsRoot(["my-function", "-p", payload])
        Services.shared = mockServices
        defer { Services.shared = Services() }
        // Given a successful invocation
        mockServices.mockInvoker.verifyLambda = { _ in
            let promise = self.mockServices.lambda.eventLoopGroup.next().makePromise(of: Data.self)
            promise.succeed(Data())
            return promise.futureResult
        }
        
        // When calling run
        try instance.run()
        
        // Then the response should be logged
        let message = mockServices.logCollector.logs.debugDescription
        XCTAssertTrue(message.contains("Invoke my-function completed"), "Response was not logged: \(message)")
    }
    
    func testJSONFileIsHandled() throws {
        // Given a path to a json file
        let payload = "{\"key\":\"value\"}"
        mockServices.mockFileManager.contentsAtPathMock = { _ in return payload.data(using: .utf8)! }
        var instance = try InvokeCommand.parseAsRoot([ExamplePackage.executableOne, "-p", "file://payload.json", "-d", tempPackageDirectory().path]) as! InvokeCommand
        let resultProcessed = expectation(description: "Result processed")
        _ = mockServices.awsServer // start the server
        DispatchQueue.global().async {
            do {
                try self.waitToProcess([.init(data: "Hello".data(using: .utf8)!)], mockServices: self.mockServices)
            } catch {
                XCTFail(error)
            }
            resultProcessed.fulfill()
        }

        // When calling run
        try instance.run(services: mockServices)
        
        
        // Then the file should be loaded
        wait(for: [resultProcessed], timeout: 2.0)
        XCTAssertTrue(mockServices.mockFileManager.$contentsAtPathMock.wasCalled)
        XCTAssertTrue(mockServices.mockFileManager.$contentsAtPathMock.wasCalled(with: "/tmp/\(ExamplePackage.name)/Sources/\(ExamplePackage.executableOne)/payload.json"))
    }
    
    func testEndpointOption() throws {
        Services.shared = mockServices
        defer { Services.shared = Services() }
        mockServices.mockInvoker.verifyLambda = { _ -> EventLoopFuture<Data> in
            return self.mockServices.lambda.eventLoopGroup.next().makeSucceededFuture(Data())
        }
        // Given a custom endpoint provided as an option
        let endpoint = "localhost:5000"
        var instance = try InvokeCommand.parseAsRoot(["my-function", "-e", endpoint]) as! InvokeCommand
        
        // When calling run
        try instance.run()
        
        // Then the lambda's endpoint should be updated
        XCTAssertEqual(Services.shared.lambda.endpoint, endpoint)
    }
}
