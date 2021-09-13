//
//  LambdaInvokerTests.swift
//  
//
//  Created by Joel Saltzman on 6/24/21.
//

import Foundation
import XCTest
import NIO
import SotoLambda
@testable import AWSDeployCore

class InvokerTests: XCTestCase {
    
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
    
    func testParsePayloadHandlesFilePath() throws {
        // Given a file path to a JSON file
        let file = "file:///tmp/payload.json"
        let contents = UUID().uuidString
        mockServices.mockFileManager.contentsAtPathMock = { _ in return contents.data(using: .utf8)! }
        
        // When calling parsePayload
        let result = try mockServices.invoker.parsePayload(file, services: mockServices).wait()
        
        // Then the contents of the file should be returned
        XCTAssertEqual(result.getString(at: 0, length: result.readableBytes), contents)
        XCTAssertTrue(mockServices.mockInvoker.$loadPayloadFile.wasCalled)
    }
    func testParsePayloadHandlesRawJSON() throws {
        // Given a JSON String
        let payload = "{\"key\":\"value\"}"
        
        // When calling parsePayload
        let result = try mockServices.invoker.parsePayload(payload, services: mockServices).wait()
        
        // Then the contents of the file should be returned
        let b = ByteBuffer(string: payload)
        XCTAssertEqual(result, b)
        XCTAssertFalse(mockServices.mockInvoker.$loadPayloadFile.wasCalled)
    }
    
    func testLoadPayloadFromFile() throws {
        // Given a JSON file
        let file = URL(fileURLWithPath: "/tmp/payload.json")
        let contents = UUID().uuidString
        mockServices.mockFileManager.contentsAtPathMock = { _ in return contents.data(using: .utf8)! }
        
        // When calling loadPayloadFromFile
        let result = try mockServices.invoker.loadPayloadFile(at: file, services: mockServices).wait()
        
        // Then the contents should be returned
        XCTAssertEqual(result.getString(at: 0, length: result.readableBytes), contents)
    }
    func testLoadPayloadFromFileHandlesMissingFiles() throws {
        // Given a file that doesn't exist
        let file = URL(fileURLWithPath: "/tmp/payload.json")
        mockServices.mockFileManager.contentsAtPathMock = { _ in return nil }
        
        do {
            // When calling loadPayloadFromFile
            _ = try mockServices.invoker.loadPayloadFile(at: file, services: mockServices).wait()
            
            // Then an error should be thrown
            XCTFail("An error should have been thrown.")
        } catch {
            XCTAssertEqual("\(error)", LambdaInvokerError.emptyPayloadFile(file.path).description)
        }
    }
    
    func testInvoke() throws {
        // Given a payload
        let payload = "{\"key\":\"value\"}"
        let expectedResponse = "{\"success\":true}"
        let responseReceived = expectation(description: "Response received")
        
        // When calling invoke
        mockServices.invoker.invoke(function: "function", with: payload, services: mockServices)
            .whenComplete({ (result: Result<Data, Error>) in
                // Then a response should be received
                do {
                    let data = try result.get()
                    XCTAssertNotNil(data)
                    let response = String(data: data, encoding: .utf8)
                    XCTAssertEqual(response, expectedResponse)
                } catch {
                    XCTFail(error)
                }
                responseReceived.fulfill()
            })
        
        
        try waitToProcess([.init(string: expectedResponse)], mockServices: mockServices)
        wait(for: [responseReceived], timeout: 2.0)
    }
    func testVerifyLambdaThrowsWhenVerifyResponseFails() throws {
        // Given a verify action that fails
        let functionName = "my-function"
        let verifyResponse: (Data) throws -> Void = { _ in throw LambdaInvokerError.verificationFailed(functionName) }
        let responseReceived = expectation(description: "Response received")
        
        // When calling invoke
        mockServices.invoker.verifyLambda(function: functionName, with: "", verifyResponse: verifyResponse, services: mockServices)
            .whenComplete({ (result: Result<Data, Error>) in
                // Then an error should be received
                do {
                    _ = try result.get()
                    
                    XCTFail("An error should have been thrown.")
                } catch {
                    XCTAssertEqual("\(error)", LambdaInvokerError.verificationFailed(functionName).description)
                }
                responseReceived.fulfill()
            })
        
        
        try waitToProcess([.init(string: "")], mockServices: mockServices)
        wait(for: [responseReceived], timeout: 2.0)
    }
}
