//
//  BlueGreenPublisherTests.swift
//
//
//  Created by Joel Saltzman on 3/26/21.
//

import AWSDeployCore
import Foundation
import Logging
import LogKit
import SotoLambda
import SotoS3
@testable import SotoTestUtils
import XCTest

class BlueGreenPublisherTests: XCTestCase {
    
    var testServices: TestServices!
    var publisher = BlueGreenPublisher()
    
    override func setUp() {
        super.setUp()
        testServices = TestServices()
        publisher = BlueGreenPublisher()
    }
    
    override func tearDownWithError() throws {
        try super.tearDownWithError()
        testServices.cleanup()
        ShellExecutor.resetAction()
        try cleanupTestPackage()
    }
    
    func testParseFunctionName() throws {
        // Given a valid archive name
        let functionName = "my-function"
        let archiveName = "\(functionName)_yyyymmdd_HHMM.zip"

        // When calling parseFunctionName
        let result = try BlueGreenPublisher.parseFunctionName(from: URL(string: "\(ExamplePackage.tempDirectory)/\(archiveName)")!)

        // Then we should receive the function prefix
        XCTAssertEqual(result, functionName)
    }

    func testParseFunctionNameThrowsWithInvalidArchiveName() throws {
        // Given an invalid archive name
        let functionName = "my-function"
        let archiveName = "\(functionName).zip"

        // When calling parseFunctionName
        // Then an error should be thrown
        XCTAssertThrowsError(try BlueGreenPublisher.parseFunctionName(from: URL(string: "\(ExamplePackage.tempDirectory)/\(archiveName)")!))
    }

    func testUpdateFunctionCode() throws {
        // Given an archive
        let functionName = UUID().uuidString
        let archiveURL = URL(string: "\(ExamplePackage.tempDirectory)/\(functionName)_yyyymmdd_HHMM.zip")!
        try? FileManager.default.createDirectory(atPath: ExamplePackage.tempDirectory,
                                                 withIntermediateDirectories: true,
                                                 attributes: nil)
        FileManager.default.createFile(atPath: archiveURL.absoluteString, contents: "File".data(using: .utf8)!, attributes: nil)
        let sha256 = UUID().uuidString

        // When calling updateFunctionCode
        publisher.updateFunctionCode(
            .init(functionName: functionName, revisionId: UUID().uuidString),
            archiveURL: archiveURL,
            services: testServices
        )
        .whenComplete { (result: Result<Lambda.FunctionConfiguration, Error>) in
            // Then we should receive a codeSha256
            do {
                let config = try result.get()
                XCTAssertEqual(config.codeSha256, sha256)
            } catch {
                XCTFail(String(describing: error))
            }
        }

        try testServices.awsServer.processRaw { (_: AWSTestServer.Request) -> AWSTestServer.Result<AWSTestServer.Response> in
            let buffer = ByteBuffer(string: "{\"CodeSha256\": \"\(sha256)\"}")
            return .result(.init(httpStatus: .ok, body: buffer))
        }
    }

    func testUpdateFunctionCodeThrowsWithInvalidArchive() throws {
        // Given an archive
        let functionName = UUID().uuidString
        let archiveURL = URL(string: "\(ExamplePackage.tempDirectory)/\(functionName)_yyyymmdd_HHMM.zip")!
        try? FileManager.default.createDirectory(atPath: archiveURL.path,
                                                 withIntermediateDirectories: true,
                                                 attributes: nil)
        FileManager.default.createFile(atPath: archiveURL.absoluteString, contents: "contents".data(using: .utf8)!, attributes: nil)
        let resultReceived = expectation(description: "Result received")

        // When calling updateCode
        publisher.updateFunctionCode(
            .init(functionName: functionName, revisionId: UUID().uuidString),
            archiveURL: archiveURL,
            services: testServices
        )
        .whenComplete { (result: Result<Lambda.FunctionConfiguration, Error>) in
            do {
                _ = try result.get()
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
        let archiveURL = URL(string: "\(ExamplePackage.tempDirectory)/my-function_yyyymmdd_HHMM.zip")!
        try? FileManager.default.createDirectory(atPath: ExamplePackage.tempDirectory,
                                                 withIntermediateDirectories: false,
                                                 attributes: nil)
        FileManager.default.createFile(atPath: archiveURL.path,
                                       contents: "contents".data(using: .utf8),
                                       attributes: nil)
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
        let archiveURL = URL(string: "\(ExamplePackage.tempDirectory)/my-function_yyyymmdd_HHMM.zip")!
        try? FileManager.default.createDirectory(atPath: ExamplePackage.tempDirectory,
                                                 withIntermediateDirectories: true,
                                                 attributes: nil)
        FileManager.default.createFile(atPath: archiveURL.path,
                                       contents: "contents".data(using: .utf8),
                                       attributes: nil)
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
        let resultReceived = expectation(description: "Result received")

        // When calling publishLatest
        publisher.publishLatest(configuration, services: testServices)
            .whenSuccess { (_: Lambda.FunctionConfiguration) in
                // Then a success result should be received
                resultReceived.fulfill()
            }

        try testServices.awsServer.processRaw { (_: AWSTestServer.Request) -> AWSTestServer.Result<AWSTestServer.Response> in
            let buffer = ByteBuffer(string: "{\"CodeSha256\": \"12345\"}")
            return .result(.init(httpStatus: .ok, body: buffer))
        }
        wait(for: [resultReceived], timeout: 2.0)
    }

    func testGetFunctionConfigurationThrowsWithMissingFunctionName() throws {
        // Given an invalid archive path
        let archiveURL = URL(string: "invalid.zip")!
        let errorReceived = expectation(description: "Error received")

        // When calling publishArchive
        publisher.getFunctionConfiguration(archiveURL: archiveURL, services: testServices)
            .whenFailure { (error: Error) in
                // Then an error should be thrown
                XCTAssertEqual("\(error)", BlueGreenPublisherError.invalidArchiveName(archiveURL.absoluteString).description)
                errorReceived.fulfill()
            }

        wait(for: [errorReceived], timeout: 2.0)
    }

    func testPublishArchiveErrorsAreLogged() throws {
        // Setup
        let errorReceived = expectation(description: "Error received")
        // Given an invalid zip path
        let archiveURL = URL(string: "\(ExamplePackage.tempDirectory)/invalid.zip")!

        // When calling publishArchive
        publisher.publishArchive(archiveURL, services: testServices)
            .whenFailure { (error: Error) in
                // Then an error should be thrown
                XCTAssertEqual("\(error)", BlueGreenPublisherError.invalidArchiveName(archiveURL.absoluteString).description)
                errorReceived.fulfill()
            }

        wait(for: [errorReceived], timeout: 2.0)
        // Then an error should b received
        XCTAssertTrue("\(testServices.logCollector.logs.allEntries)".contains("Error publishing"), "\"Error publishing\" was not found in the logs: \(testServices.logCollector.logs.allEntries)")
    }

    func testPublishArchive() throws {
        // Setup
        let functionName = "my-function"
        let revisionId = Int.random(in: 1..<10)
        let aliasConfig: Lambda.AliasConfiguration = .init(revisionId: "\(revisionId)")
        let functionConfiguration = String(
            data: try JSONEncoder().encode([
                "FunctionName": functionName,
                "RevisionId": "\(revisionId)",
                "Version": "4",
                "CodeSha256": UUID().uuidString,
            ]),
            encoding: .utf8
        )!
        // getFunctionConfiguration, updateFunctionCode, publishLatest, verifyLambda, updateAlias
        var fixtureResults: [ByteBuffer] = .init(repeating: ByteBuffer(string: functionConfiguration), count: 5)
        // Given an archive
        let archiveURL = URL(string: "\(ExamplePackage.tempDirectory)/\(functionName)_yyyymmdd_HHMM.zip")!
        try FileManager.default.createDirectory(atPath: ExamplePackage.tempDirectory,
                                                withIntermediateDirectories: false,
                                                attributes: nil)
        FileManager.default.createFile(atPath: archiveURL.absoluteString, contents: "File".data(using: .utf8)!, attributes: nil)
        let resultReceived = expectation(description: "Result received")

        // When publishing
        publisher.publishArchive(archiveURL, services: testServices)
            .whenComplete { (publishResult: Result<Lambda.AliasConfiguration, Error>) in
                // Then a String that represents the revisionId should be returned
                do {
                    let result = try publishResult.get()
                    XCTAssertEqual(result.revisionId, aliasConfig.revisionId)
                } catch {
                    XCTFail(String(describing: error))
                }
                resultReceived.fulfill()
            }

        try testServices.awsServer.processRaw { (request: AWSTestServer.Request) -> AWSTestServer.Result<AWSTestServer.Response> in
            guard let result = fixtureResults.popLast() else {
                let error = AWSTestServer.ErrorType(status: 500, errorCode: "InternalFailure", message: "Unhandled request: \(request)")
                return .error(error, continueProcessing: false)
            }
            return .result(.init(httpStatus: .ok, body: result), continueProcessing: fixtureResults.count > 0)
        }
        wait(for: [resultReceived], timeout: 2.0)
        XCTAssertEqual(fixtureResults.count, 0, "There were fixtureResults left over. Not all calls were performed.")
    }

    func testPublishMultipleArchives() throws {
        // Setup
        let functionName = "my-function"
        let version = Int.random(in: 1..<10)
        let aliasConfig: Lambda.AliasConfiguration = .init(functionVersion: "\(version)", revisionId: "\(version)")
        let functionConfiguration = String(
            data: try JSONEncoder().encode([
                "FunctionName": functionName,
                "RevisionId": "\(version)",
                "Version": "\(version)",
                "CodeSha256": UUID().uuidString,
            ]),
            encoding: .utf8
        )!
        // getFunctionConfiguration, updateFunctionCode, publishLatest, verifyLambda, updateAlias
        var fixtureResults: [ByteBuffer] = .init(repeating: ByteBuffer(string: functionConfiguration), count: 5)
        // Given an archive
        let archiveURL = URL(string: "\(ExamplePackage.tempDirectory)/\(functionName)_yyyymmdd_HHMM.zip")!
        try FileManager.default.createDirectory(atPath: ExamplePackage.tempDirectory,
                                                withIntermediateDirectories: false,
                                                attributes: nil)
        FileManager.default.createFile(atPath: archiveURL.absoluteString, contents: "File".data(using: .utf8)!, attributes: nil)
        let resultReceived = expectation(description: "Result received")

        // When publishing
        try publisher.publishArchives([archiveURL], services: testServices)
            .whenComplete { (publishResult: Result<[Lambda.AliasConfiguration], Error>) in
                // Then the updated version number should be included in the results
                do {
                    let result = try publishResult.get()
                    XCTAssertEqual(result[0].revisionId, aliasConfig.revisionId)
                    //XCTAssertEqual(result[0].functionVersion, aliasConfig.functionVersion)
                } catch {
                    XCTFail(String(describing: error))
                }
                resultReceived.fulfill()
            }

        try testServices.awsServer.processRaw { (request: AWSTestServer.Request) -> AWSTestServer.Result<AWSTestServer.Response> in
            guard let result = fixtureResults.popLast() else {
                let error = AWSTestServer.ErrorType(status: 500, errorCode: "InternalFailure", message: "Unhandled request: \(request)")
                return .error(error, continueProcessing: false)
            }
            return .result(.init(httpStatus: .ok, body: result), continueProcessing: fixtureResults.count > 0)
        }
        wait(for: [resultReceived], timeout: 2.0)
        XCTAssertEqual(fixtureResults.count, 0, "There were fixtureResults left over. Not all calls were performed.")
    }

    func testVerifyLambdaThrowsWithMissingFunctionName() {
        // Given a missing functionName in a FunctionConfiguration
        let configuration: Lambda.FunctionConfiguration = .init()
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
        let resultReceived = expectation(description: "Result received")

        // When calling verifyLambda
        publisher.verifyLambda(configuration, services: testServices)
            .whenSuccess { (_: Lambda.FunctionConfiguration) in
                resultReceived.fulfill()
            }

        try testServices.awsServer.processRaw { (_: AWSTestServer.Request) -> AWSTestServer.Result<AWSTestServer.Response> in
            let buffer = ByteBuffer(string: "{\"CodeSha256\": \"12345\", \"Version\": \"1\"}")
            return .result(.init(httpStatus: .ok, body: buffer))
        }
        wait(for: [resultReceived], timeout: 2.0)
    }

    func testVerifyLambdaThrowsWhenReceivingErrorResults() throws {
        // Given an invalid FunctionConfiguration
        let functionName = "my-function"
        let configuration: Lambda.FunctionConfiguration = .init(functionName: functionName, version: "2")
        let errorReceived = expectation(description: "Error received")
        let payload = "{\"errorMessage\":\"RequestId: 590ec71e-14c1-4498-8edf-2bd808dc3c0e Error: Runtime exited without providing a reason\",\"errorType\":\"Runtime.ExitError\"}"

        // When calling verifyLambda
        publisher.verifyLambda(configuration, services: testServices)
            .whenFailure { (error: Error) in
                XCTAssertEqual("\(error)", BlueGreenPublisherError.invokeLambdaFailed(functionName, payload).description)
                errorReceived.fulfill()
            }

        try testServices.awsServer.processRaw { (_: AWSTestServer.Request) -> AWSTestServer.Result<AWSTestServer.Response> in
            let buffer = ByteBuffer(string: payload)
            return .result(.init(httpStatus: .ok, headers: ["X-Amz-Function-Error": "Unhandled"], body: buffer))
        }
        wait(for: [errorReceived], timeout: 3.0)
    }

    func testUpdateFunctionVersionThrowsWithMissingFunctionName() throws {
        // Given a missing FunctioName in the FunctionConfiguration
        let configuration: Lambda.FunctionConfiguration = .init()
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
