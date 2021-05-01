//
//  AWSDeployTests.swift
//  
//
//  Created by Joel Saltzman on 3/18/21.
//

import Foundation
import XCTest
import ShellOut
import SotoS3
import Logging
import LogKit
@testable import SotoTestUtils
@testable import AWSDeployCore

class AppDeployerTests: XCTestCase {
    
    override func setUp() {
        continueAfterFailure = false
    }
    
    func testVerifyConfiguration_directoryPathUpdateWithDot() throws {
        // Given a "." path
        var instance = try AppDeployer.parseAsRoot(["-d", ".", "my-function"]) as! AppDeployer
        
        // When calling verifyConfiguration
        try instance.verifyConfiguration(services: TestServices())

        // Then the directoryPath should be updated
        XCTAssertNotEqual(instance.directoryPath, "./")
        XCTAssertNotEqual(instance.directoryPath, ".")
    }
    func testVerifyConfiguration_directoryPathUpdateWithDotSlash() throws {
        // Given a "." path
        var instance = try AppDeployer.parseAsRoot(["-d", "./", "my-function"]) as! AppDeployer
        
        // When calling verifyConfiguration
        try instance.verifyConfiguration(services: TestServices())

        // Then the directoryPath should be updated
        XCTAssertNotEqual(instance.directoryPath, "./")
        XCTAssertNotEqual(instance.directoryPath, ".")
    }
//    func testVerifyConfiguration_throwsWithInvalidBucketOption() throws {
//        // Given an invalid bucket option
//        var instance = try AppDeployer.parseAsRoot(["-b", ""]) as! AWSDeploy
//
//        do {
//            // When calling verifyConfiguration
//            try instance.verifyConfiguration(services: TestServices())
//
//            XCTFail("An error should have been thrown.")
//        } catch {
//            XCTAssertEqual("\(error)", AWSDeployError.invalidBucket.description)
//        }
//    }
    func testVerifyConfiguration_logsWhenSkippingProducts() throws {
        // This test is mostly for coverage until we create a logger that can store messages
        // Given a product to skip
        let product = UUID().uuidString
        var instance = try AppDeployer.parseAsRoot(["-s", product]) as! AppDeployer
        let testServices = TestServices()
        
        // When calling verifyConfiguration
        try instance.verifyConfiguration(services: testServices)

        // Then a "Skipping $PRODUCT" log should be received
        XCTAssertTrue("\(testServices.logCollector.logs.allEntries)".contains("Skipping: \(product)"))
    }
    
    func testGetProducts() throws {
        // Given a package with a library and multiple executables
        ShellExecutor.shellOutAction = shellOut(to:arguments:at:process:outputHandle:errorHandle:)
        let path = try createTempPackage()
        let instance = AppDeployer()
        
        // When calling getProducts with a skipProducts list
        let result = try instance.getProducts(from: path, skipProducts: "SkipMe", logger: Logger.CollectingLogger(label: "Test"))
        
        // Then only one executable should be returned
        XCTAssertEqual(result, ["TestExecutable"])
    }
    
    func testRunDoesNotThrow() throws {
        // Setup
        let testServices = TestServices()
        Services.shared = testServices
        defer {
            Services.shared = Services()
        }
        let functionName = "my-function"
        let archivePath = "/tmp/\(functionName)_yyyymmdd_HHMM.zip"
        FileManager.default.createFile(atPath: archivePath, contents: "File".data(using: .utf8)!, attributes: nil)
        ShellExecutor.shellOutAction = { (to: String,
                    arguments: [String],
                    at: String,
                    process: Process,
                    outputHandle: FileHandle?,
                    errorHandle: FileHandle?) throws -> String in
            return archivePath
        }
        let functionConfiguration = String(data: try JSONEncoder().encode(["FunctionName": functionName,
                                                                           "RevisionId": "1234",
                                                                           "Version": "4",
                                                                           "CodeSha256": UUID().uuidString]),
                                           encoding: .utf8)!
        // getFunctionConfiguration, updateFunctionCode, publishLatest, verifyLambda, updateAlias
        var fixtureResults: [ByteBuffer] = .init(repeating: ByteBuffer(string: functionConfiguration), count: 5)
        let resultReceived = expectation(description: "Result received")
        
        
        // run() uses wait() so do it in the background
        DispatchQueue.global().async {
            do {
                // Given a valid configuation
                var instance = try AppDeployer.parseAsRoot(["-p", "my-function"]) as! AppDeployer // "-b", "bucket-name"
                
                // When calling run
                try instance.run()
                
            } catch {
                // Then no errors should be thrown
                XCTFail(String(describing: error))
            }
            resultReceived.fulfill()
        }
        
        // Wait for the server to process
        try testServices.awsServer.processRaw { request in
            guard let result = fixtureResults.popLast() else {
                let error = AWSTestServer.ErrorType(status: 500, errorCode: "InternalFailure", message: "Unhandled request: \(request)")
                return .error(error, continueProcessing: false)
            }
            return .result(.init(httpStatus: .ok, body: result), continueProcessing: fixtureResults.count > 0)
        }
        XCTAssertEqual(fixtureResults.count, 0, "Not all calls were performed.")
        wait(for: [resultReceived], timeout: 2.0)
    }
//    func testRunDoesNotThrowWhenNotSpecifyingProducts() throws {
//        // Setup
//        let testServices = TestServices()
//        Services.shared = testServices
//        defer {
//            Services.shared = Services()
//        }
//        let functionName = "my-function"
//        let archivePath = "/tmp/\(functionName)_yyyymmdd_HHMM.zip"
//        FileManager.default.createFile(atPath: archivePath, contents: "File".data(using: .utf8)!, attributes: nil)
//        ShellExecutor.shellOutAction = { (to: String,
//                    arguments: [String],
//                    at: String,
//                    process: Process,
//                    outputHandle: FileHandle?,
//                    errorHandle: FileHandle?) throws -> String in
//            return archivePath
//        }
//        let functionConfiguration = String(data: try JSONEncoder().encode(["FunctionName": functionName,
//                                                                           "RevisionId": "1234",
//                                                                           "CodeSha256": UUID().uuidString]),
//                                           encoding: .utf8)!
//        // getFunctionConfiguration, updateFunctionCode, publishLatest, verifyLambda, updateAlias
//        var fixtureResults: [ByteBuffer] = .init(repeating: ByteBuffer(string: functionConfiguration), count: 5)
//        let resultReceived = expectation(description: "Result received")
//        
//        
//        // run() uses wait() so do it in the background
//        DispatchQueue.global().async {
//            do {
//                // Given a valid configuation
//                var instance = try AppDeployer.parseAsRoot([]) as! AWSDeploy // "-b", "bucket-name"
//                
//                // When calling run
//                try instance.run()
//                
//            } catch {
//                // Then no errors should be thrown
//                XCTFail(String(describing: error))
//            }
//            resultReceived.fulfill()
//        }
//        
//        // Wait for the server to process
//        try testServices.awsServer.processRaw { request in
//            guard let result = fixtureResults.popLast() else {
//                let error = AWSTestServer.ErrorType(status: 500, errorCode: "InternalFailure", message: "Unhandled request: \(request)")
//                return .error(error, continueProcessing: false)
//            }
//            return .result(.init(httpStatus: .ok, body: result), continueProcessing: fixtureResults.count > 0)
//        }
//        XCTAssertEqual(fixtureResults.count, 0, "Not all calls were performed.")
//        wait(for: [resultReceived], timeout: 2.0)
//    }
    func testRunWithRealPackage() throws {
        // This is more of an integration test. We won't stub the services
        let path = try createTempPackage(includeSource: true)
        // Create the Dockerfile
        let dockerFile = "FROM swift:5.3-amazonlinux2\nRUN yum -y install zip"
        try (dockerFile as NSString).write(toFile: URL(string: path)!.appendingPathComponent("Dockerfile").absoluteString,
                                           atomically: true,
                                           encoding: String.Encoding.utf8.rawValue)
        
        // Given a valid configuation (not calling publish for the tests)
        var instance = try AppDeployer.parseAsRoot(["-d", path, "TestPackage"]) as! AppDeployer // "-b", "bucket-name"

        // When calling run
        // Then no errors should be thrown
        XCTAssertNoThrow(try instance.run())
        // and the zip should exist
        let zipPath = URL(string: path)!.appendingPathComponent(".build")
        XCTAssertTrue(FileManager.default.fileExists(atPath: zipPath.absoluteString), "File does not exist: \(zipPath.absoluteString)")
    }
}
