//
//  BlueGreenPublisherTests.swift
//  
//
//  Created by Joel Saltzman on 3/26/21.
//

import Foundation
import XCTest
import AWSDeployCore
import SotoLambda
import SotoS3
import LogKit
import Logging
@testable import SotoTestUtils

class BlueGreenPublisherTests: XCTestCase {
    
    func testParseFunctionName() throws {
        // Given a valid archive name
        let functionName = "my-function"
        let archiveName = "\(functionName)_yyyymmdd_HHMM.zip"
        
        // When calling parseFunctionName
        let result = try BlueGreenPublisher.parseFunctionName(from: URL(string: "/tmp/\(archiveName)")!)
        
        // Then we should receive the function prefix
        XCTAssertEqual(result, functionName)
    }
    func testParseFunctionNameThrowsWithInvalidArchivename() throws {
        // Given an invalid archive name
        let functionName = "my-function"
        let archiveName = "\(functionName).zip"
        
        // When calling parseFunctionName
        // Then an error should be thrown
        XCTAssertThrowsError(try BlueGreenPublisher.parseFunctionName(from: URL(string: "/tmp/\(archiveName)")!))
    }
    
    func testUpdateFunctionCode() throws {
        // Given an archive
        let functionName = UUID().uuidString
        let archiveURL = URL(string: "/tmp/\(functionName)_yyyymmdd_HHMM.zip")!
        FileManager.default.createFile(atPath: archiveURL.absoluteString, contents: "File".data(using: .utf8)!, attributes: nil)
        let publisher = BlueGreenPublisher()
        let testServices = TestServices()
        let sha256 = UUID().uuidString
        let resultReceived = expectation(description: "Result received")
        
        // When calling updateCode
        let future = publisher.updateFunctionCode(.init(functionName: functionName, revisionId: UUID().uuidString),
                                                  archiveURL: archiveURL,
                                                  services: testServices)
        
        // Then we should receive a codeSha256
        future.whenComplete({ (result: Result<Lambda.FunctionConfiguration, Error>) in
            do {
                let config = try result.get()
                XCTAssertEqual(config.codeSha256, sha256)
                resultReceived.fulfill()
            } catch {
                XCTFail(String(describing: error))
            }
        })
        
        try testServices.awsServer.processRaw { (request: AWSTestServer.Request) -> AWSTestServer.Result<AWSTestServer.Response> in
            let buffer: ByteBuffer = ByteBuffer(string: "{\"CodeSha256\": \"\(sha256)\"}")
            return .result(.init(httpStatus: .ok, body: buffer))
        }
        wait(for: [resultReceived], timeout: 2.0)
    }
    func testUpdateFunctionCodeThrowsWithInvalidArchive() throws {
        // Given an archive
        let functionName = UUID().uuidString
        let archiveURL = URL(string: "/tmp/\(functionName)_yyyymmdd_HHMM.zip")!
        FileManager.default.createFile(atPath: archiveURL.absoluteString, contents: "".data(using: .utf8)!, attributes: nil)
        let publisher = BlueGreenPublisher()
        let testServices = TestServices()
        let resultReceived = expectation(description: "Result received")
        
        // When calling updateCode
        publisher.updateFunctionCode(.init(functionName: functionName, revisionId: UUID().uuidString),
                                     archiveURL: archiveURL,
                                     services: testServices)
            .whenComplete { (result: Result<Lambda.FunctionConfiguration, Error>) in
                do {
                    let _ = try result.get()
                    XCTFail("An error should have been thrown.")
                } catch {
                    // Then an error should be thrown
                    XCTAssertEqual("\(error)", BlueGreenPublisherError.archiveDoesNotExist(archiveURL.absoluteString).description)
                }
                resultReceived.fulfill()
            }
        
        wait(for: [resultReceived], timeout: 2.0)
    }
    func testUpdateFunctionCodeThrowsWithMissingFunctionName() {
        // Given an invalid FunctionConfiguration
        let configuration: Lambda.FunctionConfiguration = .init()
        let publisher = BlueGreenPublisher()
        let archiveURL = URL(string: "/tmp/my-function_yyyymmdd_HHMM.zip")!
        let testServices = TestServices()
        let errorReceived = expectation(description: "Error received")
        
        // When calling updateFunctionCode
        publisher.updateFunctionCode(configuration, archiveURL: archiveURL, services: testServices)
            .whenFailure { (error: Error) in
                // Then an error should be thrown
                XCTAssertEqual("\(error)", BlueGreenPublisherError.invalidFunctionConfiguration("functionName", "updateFunctionCode").description)
                errorReceived.fulfill()
            }
        
        wait(for: [errorReceived], timeout: 2.0)
    }
    func testUpdateFunctionCodeThrowsWithMissingRevisionId() {
        // Given an invalid FunctionConfiguration
        let configuration: Lambda.FunctionConfiguration = .init(functionName: "my-function")
        let publisher = BlueGreenPublisher()
        let archiveURL = URL(string: "/tmp/my-function_yyyymmdd_HHMM.zip")!
        let testServices = TestServices()
        let errorReceived = expectation(description: "Error received")
        
        // When calling updateFunctionCode
        publisher.updateFunctionCode(configuration, archiveURL: archiveURL, services: testServices)
            .whenFailure { (error: Error) in
                // Then an error should be thrown
                XCTAssertEqual("\(error)", BlueGreenPublisherError.invalidFunctionConfiguration("revisionId", "updateFunctionCode").description)
                errorReceived.fulfill()
            }
        
        wait(for: [errorReceived], timeout: 2.0)
    }

    func testPublishLatestThrowsWithMissingFunctionName() {
        // Given an invalid FunctionConfiguration
        let configuration: Lambda.FunctionConfiguration = .init()
        let publisher = BlueGreenPublisher()
        let testServices = TestServices()
        let errorReceived = expectation(description: "Error received")
        
        // When calling publishLatest
        publisher.publishLatest(configuration, services: testServices)
            .whenFailure { (error: Error) in
                // Then an error should be thrown
                XCTAssertEqual("\(error)", BlueGreenPublisherError.invalidFunctionConfiguration("functionName", "publishLatest").description)
                errorReceived.fulfill()
            }
        
        wait(for: [errorReceived], timeout: 2.0)
    }
    func testPublishLatestThrowsWithMissingCodeSha256() {
        // Given an invalid FunctionConfiguration
        let configuration: Lambda.FunctionConfiguration = .init(functionName: "my-function")
        let publisher = BlueGreenPublisher()
        let testServices = TestServices()
        let errorReceived = expectation(description: "Error received")
        
        // When calling publishLatest
        publisher.publishLatest(configuration, services: testServices)
            .whenFailure { (error: Error) in
                // Then an error should be thrown
                XCTAssertEqual("\(error)", BlueGreenPublisherError.invalidFunctionConfiguration("codeSha256", "publishLatest").description)
                errorReceived.fulfill()
            }
        
        wait(for: [errorReceived], timeout: 2.0)
    }
    func testPublishLatest() throws {
        // Given an invalid FunctionConfiguration
        let configuration: Lambda.FunctionConfiguration = .init(codeSha256: "12345", functionName: "my-function")
        let publisher = BlueGreenPublisher()
        let testServices = TestServices()
        let resultReceived = expectation(description: "Result received")
        
        // When calling publishLatest
        publisher.publishLatest(configuration, services: testServices)
            .whenSuccess { (config: Lambda.FunctionConfiguration) in
                // Then a success result should be received
                resultReceived.fulfill()
            }
        
        try testServices.awsServer.processRaw { (request: AWSTestServer.Request) -> AWSTestServer.Result<AWSTestServer.Response> in
            let buffer: ByteBuffer = ByteBuffer(string: "{\"CodeSha256\": \"12345\"}")
            return .result(.init(httpStatus: .ok, body: buffer))
        }
        wait(for: [resultReceived], timeout: 2.0)
    }
    
    func testGetFunctionConfigurationThrowsWithMissingFunctionName() throws {
        // Given an invalid archive path
        let testServices = TestServices()
        let instance = BlueGreenPublisher()
        let archiveURL = URL(string: "invalid.zip")!
        let errorReceived = expectation(description: "Error received")
        
        // When calling publishArchive
        instance.getFunctionConfiguration(archiveURL: archiveURL, services: testServices)
            .whenFailure { (error: Error) in
                // Then an error should be thrown
                XCTAssertEqual("\(error)", BlueGreenPublisherError.invalidArchiveName(archiveURL.absoluteString).description)
                errorReceived.fulfill()
            }
        
        wait(for: [errorReceived], timeout: 2.0)
    }
    func testPublishArchiveErrorsAreLogged() throws {
        // Setup
        let testServices = TestServices()
        testServices.logger.logLevel = .info
        let instance = BlueGreenPublisher()
        let errorReceived = expectation(description: "Error received")
        // Given an error when publishing
        let archiveURL = URL(string: "/tmp/invalid.zip")!
        
        
        // When calling publishArchive
        instance.publishArchive(archiveURL, services: testServices)
            .whenFailure { (error: Error) in
                // Then an error should be thrown
                XCTAssertEqual("\(error)", BlueGreenPublisherError.invalidArchiveName(archiveURL.absoluteString).description)
                errorReceived.fulfill()
            }
        
        wait(for: [errorReceived], timeout: 2.0)
        XCTAssertTrue("\(testServices.logCollector.logs.allEntries)".contains("Error publishing"))
    }
    func testPublishArchive() throws {
        // Setup
        let testServices = TestServices()
        let instance = BlueGreenPublisher()
        let functionName = "my-function"
        let revisionId = Int.random(in: 1..<10)
        let aliasConfig: Lambda.AliasConfiguration = .init(revisionId: "\(revisionId)")
        let functionConfiguration = String(data: try JSONEncoder().encode(["FunctionName": functionName,
                                                                           "RevisionId": "\(revisionId)",
                                                                           "Version": "4",
                                                                           "CodeSha256": UUID().uuidString]),
                                           encoding: .utf8)!
        // getFunctionConfiguration, updateFunctionCode, publishLatest, verifyLambda, updateAlias
        var fixtureResults: [ByteBuffer] = .init(repeating: ByteBuffer(string: functionConfiguration), count: 5)
        // Given an archive
        let archiveURL = URL(string: "/tmp/\(functionName)_yyyymmdd_HHMM.zip")!
        FileManager.default.createFile(atPath: archiveURL.absoluteString, contents: "File".data(using: .utf8)!, attributes: nil)
        let resultReceived = expectation(description: "Result received")
        
        // When publishing
        instance.publishArchive(archiveURL, services: testServices)
            .whenComplete({ (publishResult: Result<Lambda.AliasConfiguration, Error>) in
                // Then a String that represents the revisionId should be returned
                do {
                    let result = try publishResult.get()
                    XCTAssertEqual(result.revisionId, aliasConfig.revisionId)
                } catch {
                    XCTFail(String(describing: error))
                }
                resultReceived.fulfill()
            })
        
        try testServices.awsServer.processRaw { (request: AWSTestServer.Request) -> AWSTestServer.Result<AWSTestServer.Response> in
            guard let result = fixtureResults.popLast() else {
                let error = AWSTestServer.ErrorType(status: 500, errorCode: "InternalFailure", message: "Unhandled request: \(request)")
                return .error(error, continueProcessing: false)
            }
            return .result(.init(httpStatus: .ok, body: result), continueProcessing: fixtureResults.count > 0)
        }
        XCTAssertEqual(fixtureResults.count, 0, "There were fixtureResults left over. Not all calls were performed.")
        wait(for: [resultReceived], timeout: 2.0)
    }
    func testPublishMultipleArchives() throws {
        // Setup
        let testServices = TestServices()
        let instance = BlueGreenPublisher()
        let functionNames = ["my-function", "my-function-2"]
        let revisionIds = [Int.random(in: 1..<10), Int.random(in: 1..<10)]
        let aliasConfigs: [Lambda.AliasConfiguration] = [.init(revisionId: "\(revisionIds[0])"), .init(revisionId: "\(revisionIds[1])")]
        let functionConfiguration1 = String(data: try JSONEncoder().encode(["FunctionName": functionNames[0],
                                                                           "RevisionId": "\(revisionIds[0])",
                                                                           "Version": "4",
                                                                           "CodeSha256": UUID().uuidString]),
                                           encoding: .utf8)!
        let functionConfiguration2 = String(data: try JSONEncoder().encode(["FunctionName": functionNames[1],
                                                                           "RevisionId": "\(revisionIds[1])",
                                                                           "Version": "4",
                                                                           "CodeSha256": UUID().uuidString]),
                                           encoding: .utf8)!
        var fixtureResults: [ByteBuffer] = .init(repeating: ByteBuffer(string: functionConfiguration1), count: 5) +
            .init(repeating: ByteBuffer(string: functionConfiguration2), count: 5)
        // Given an archive
        let archiveURLs = [URL(string: "/tmp/\(functionNames[0])_yyyymmdd_HHMM.zip")!, URL(string: "/tmp/\(functionNames[1])_yyyymmdd_HHMM.zip")!]
        FileManager.default.createFile(atPath: archiveURLs[0].absoluteString, contents: "File".data(using: .utf8)!, attributes: nil)
        FileManager.default.createFile(atPath: archiveURLs[1].absoluteString, contents: "File".data(using: .utf8)!, attributes: nil)
        
        // When publishing
        try instance.publishArchives(archiveURLs, services: testServices)
            .whenComplete({ (publishResult: Result<[Lambda.AliasConfiguration], Error>) in
                // Then a String that represents the revisionId should be returned
                do {
                    let result = try publishResult.get()
                    XCTAssertEqual(result.count, 2)
                    XCTAssertEqual(result[0].revisionId, aliasConfigs[0].revisionId)
                    XCTAssertEqual(result[1].revisionId, aliasConfigs[1].revisionId)
                } catch {
                    XCTFail(String(describing: error))
                }
            })
        
        try testServices.awsServer.processRaw { (request: AWSTestServer.Request) -> AWSTestServer.Result<AWSTestServer.Response> in
            guard let result = fixtureResults.popLast() else { return .error(.internal, continueProcessing: false)}
            return .result(.init(httpStatus: .ok, body: result), continueProcessing: fixtureResults.count > 0)
        }
        XCTAssertEqual(fixtureResults.count, 0, "There were fixtureResults left over. Not all calls were performed.")
    }
    
    
    func testVerifyLambdaThrowsWithMissingFunctionName() {
        // Given a missing functionName in a FunctionConfiguration
        let configuration: Lambda.FunctionConfiguration = .init()
        let publisher = BlueGreenPublisher()
        let testServices = TestServices()
        let errorReceived = expectation(description: "Error received")
        
        // When calling verifyLambda
        publisher.verifyLambda(configuration, services: testServices)
            .whenFailure { (error: Error) in
                // Then an error should be thrown
                XCTAssertEqual("\(error)", BlueGreenPublisherError.invalidFunctionConfiguration("functionName", "verifyLambda").description)
                errorReceived.fulfill()
            }
        
        wait(for: [errorReceived], timeout: 2.0)
    }
    func testVerifyLambdaThrowsWithMissingVersion() {
        // Given a missing version in a FunctionConfiguration
        let configuration: Lambda.FunctionConfiguration = .init(functionName: "my-function")
        let publisher = BlueGreenPublisher()
        let testServices = TestServices()
        let errorReceived = expectation(description: "Error received")
        
        // When calling verifyLambda
        publisher.verifyLambda(configuration, services: testServices)
            .whenFailure { (error: Error) in
                // Then an error should be thrown
                XCTAssertEqual("\(error)", BlueGreenPublisherError.invalidFunctionConfiguration("version", "verifyLambda").description)
                errorReceived.fulfill()
            }
        
        wait(for: [errorReceived], timeout: 2.0)
    }
    func testVerifyLambda() throws {
        // Given an invalid FunctionConfiguration
        let configuration: Lambda.FunctionConfiguration = .init(functionName: "my-function", version: "2")
        let publisher = BlueGreenPublisher()
        let testServices = TestServices()
        let resultReceived = expectation(description: "Result received")
        
        // When calling verifyLambda
        publisher.verifyLambda(configuration, services: testServices)
            .whenSuccess { (config: Lambda.FunctionConfiguration) in
                resultReceived.fulfill()
            }
        
        try testServices.awsServer.processRaw { (request: AWSTestServer.Request) -> AWSTestServer.Result<AWSTestServer.Response> in
            let buffer: ByteBuffer = ByteBuffer(string: "{\"CodeSha256\": \"12345\", \"Version\": \"1\"}")
            return .result(.init(httpStatus: .ok, body: buffer))
        }
        wait(for: [resultReceived], timeout: 2.0)
    }
    func testVerifyLambdaThrowsWhenReceivingErrorResults() throws {
        // Given an invalid FunctionConfiguration
        let functionName = "my-function"
        let configuration: Lambda.FunctionConfiguration = .init(functionName: functionName, version: "2")
        let publisher = BlueGreenPublisher()
        let testServices = TestServices()
        let errorReceived = expectation(description: "Error received")
        let payload = "{\"errorMessage\":\"RequestId: 590ec71e-14c1-4498-8edf-2bd808dc3c0e Error: Runtime exited without providing a reason\",\"errorType\":\"Runtime.ExitError\"}"
        
        // When calling verifyLambda
        publisher.verifyLambda(configuration, services: testServices)
            .whenFailure { (error: Error) in
                XCTAssertEqual("\(error)", BlueGreenPublisherError.invokeLambdaFailed(functionName, payload).description)
                errorReceived.fulfill()
            }
        
        try testServices.awsServer.processRaw { (request: AWSTestServer.Request) -> AWSTestServer.Result<AWSTestServer.Response> in
            let buffer: ByteBuffer = ByteBuffer(string: payload)
            return .result(.init(httpStatus: .ok, headers: ["X-Amz-Function-Error": "Unhandled"], body: buffer))
        }
        wait(for: [errorReceived], timeout: 3.0)
    }
    
    func testUpdateFunctionVersionThrowsWithMissingFunctionName() throws {
        // Given a missing FunctioName in the FunctionConfiguration
        let configuration: Lambda.FunctionConfiguration = .init()
        let publisher = BlueGreenPublisher()
        let testServices = TestServices()
        let errorReceived = expectation(description: "Error received")
        
        // When calling updateFunctionVersion
        publisher.updateFunctionVersion(configuration, alias: "production", services: testServices)
            .whenFailure { (error: Error) in
                // Then an error should be thrown
                XCTAssertEqual("\(error)", BlueGreenPublisherError.invalidFunctionConfiguration("functionName", "updateFunctionVersion").description)
                errorReceived.fulfill()
            }
        
        wait(for: [errorReceived], timeout: 2.0)
    }
    func testUpdateFunctionVersionThrowsWithMissingVersion() throws {
        // Given a missing FunctioName in the FunctionConfiguration
        let configuration: Lambda.FunctionConfiguration = .init(functionName: "my-function")
        let publisher = BlueGreenPublisher()
        let testServices = TestServices()
        let errorReceived = expectation(description: "Error received")
        
        // When calling updateFunctionVersion
        publisher.updateFunctionVersion(configuration, alias: "production", services: testServices)
            .whenFailure { (error: Error) in
                // Then an error should be thrown
                XCTAssertEqual("\(error)", BlueGreenPublisherError.invalidFunctionConfiguration("version", "updateFunctionVersion").description)
                errorReceived.fulfill()
            }
        
        wait(for: [errorReceived], timeout: 2.0)
    }
    
//    func testInvokeLambda() throws {
//        // Given a working Lambda
//        
//        // When calling verifyLambda
//        
//        // Then
//        let expectedResponse = expectation(description: "response")
//        let instance = BlueGreenPublisher()
//        //arn:aws:lambda:us-west-1:796145072238:function:login
//        //arn:aws:lambda:us-west-1:796145072238:function:error
//        instance.verifyLambda(Lambda.FunctionConfiguration.init(codeSha256: "", functionName: "login:13"), services: Services.shared)//TestServices()
//            .whenComplete({ (result: Result<Lambda.FunctionConfiguration, Error>) in
//                do {
//                    let response = try result.get()
//                    print("result: \(response)")
//                } catch {
//                    print("error: \(error)")
//                }
//                expectedResponse.fulfill()
//            })
//        wait(for: [expectedResponse], timeout: 5.0)
//    }
}
