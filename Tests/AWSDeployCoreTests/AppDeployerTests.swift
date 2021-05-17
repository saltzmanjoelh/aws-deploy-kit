//
//  AWSDeployTests.swift
//
//
//  Created by Joel Saltzman on 3/18/21.
//

@testable import AWSDeployCore
import Foundation
import Logging
import LogKit
import SotoS3
@testable import SotoTestUtils
import XCTest

class AppDeployerTests: XCTestCase {
    
    var testServices: TestServices!
    
    override func setUp() {
        continueAfterFailure = false
        testServices = TestServices()
    }
    override func tearDownWithError() throws {
        try super.tearDownWithError()
        testServices.cleanup()
        ShellExecutor.resetAction()
        try cleanupTestPackage()
    }

    func testVerifyConfiguration_directoryPathUpdateWithDot() throws {
        // Given a "." path
        var instance = try AppDeployer.parseAsRoot(["-d", ".", "my-function"]) as! AppDeployer

        // When calling verifyConfiguration
        try instance.verifyConfiguration(services: testServices)

        // Then the directoryPath should be updated
        XCTAssertNotEqual(instance.directoryPath, "./")
        XCTAssertNotEqual(instance.directoryPath, ".")
    }

    func testVerifyConfiguration_directoryPathUpdateWithDotSlash() throws {
        // Given a "." path
        var instance = try AppDeployer.parseAsRoot(["-d", "./", "my-function"]) as! AppDeployer

        // When calling verifyConfiguration
        try instance.verifyConfiguration(services: testServices)

        // Then the directoryPath should be updated
        XCTAssertNotEqual(instance.directoryPath, "./")
        XCTAssertNotEqual(instance.directoryPath, ".")
    }

    func testVerifyConfiguration_logsWhenSkippingProducts() throws {
        // Given a product to skip
        let path = try createTempPackage()
        var instance = try AppDeployer.parseAsRoot(["-s", ExamplePackage.executableThree, "-p", path]) as! AppDeployer

        // When calling verifyConfiguration
        try instance.verifyConfiguration(services: testServices)

        // Then a "Skipping $PRODUCT" log should be received
        let messages = testServices.logCollector.logs.allMessages()
        XCTAssertString(messages, contains: "Skipping: \(ExamplePackage.executableThree)")
    }
    func testVerifyConfiguration_throwsWithMissingProducts() throws {
        // Given a package without any executables
        var instance = AppDeployer()
        instance.directoryPath = "./"
        instance.products = []
        instance.skipProducts = ""
        instance.publishBlueGreen = false
        ShellExecutor.shellOutAction = { (_, _, _) throws -> LogCollector.Logs in
            let packageManifest = "{\"products\" : []}"
            return .stubMessage(level: .trace, message: packageManifest)
        }
        
        do {
            // When calling verifyConfiguration
            try instance.verifyConfiguration(services: testServices)
            
            XCTFail("An error should have been thrown and products should have been empty instead of: \(instance.products)")
        } catch AppDeployerError.missingProducts {
            // Then the AppDeployerError.missingProducts error should be thrown
        } catch {
            XCTFail(String(describing: error))
        }
    }

    func testGetProducts() throws {
        // Given a package with a library and multiple executables
        let path = try createTempPackage()
        let instance = AppDeployer()

        // When calling getProducts
        let result = try instance.getProducts(from: path, logger: testServices.logger)

        // Then all executables should be returned
        XCTAssertEqual(result.count, ExamplePackage.executables.count)
    }
    func testGetProductsThrowsWithInvalidShellOutput() throws {
        // Give a failed shell output
        ShellExecutor.shellOutAction = { (_, _, _) throws -> LogCollector.Logs in
            return .stubMessage(level: .trace, message: "{\"products\": []}")
        }
        let instance = AppDeployer()

        // When calling getProducts
        do {
            _ = try instance.getProducts(from: "", logger: testServices.logger)
            
        } catch {
            // Then AppDeployerError.packageDumpFailure is thrown
            XCTAssertEqual("\(error)", AppDeployerError.packageDumpFailure.description)
        }
    }
    
    func testRunDoesNotThrow() throws {
        // Setup
        let functionName = "my-function"
        let archivePath = "\(ExamplePackage.tempDirectory)/\(functionName)_yyyymmdd_HHMM.zip"
        print(archivePath)
        try? FileManager.default.createDirectory(atPath: ExamplePackage.tempDirectory,
                                                withIntermediateDirectories: false,
                                                attributes: nil)
        FileManager.default.createFile(atPath: archivePath, contents: "File".data(using: .utf8)!, attributes: nil)
        ShellExecutor.shellOutAction = { (_, _, _) throws -> LogCollector.Logs in
            return .stubMessage(level: .trace, message: archivePath)
        }
        let functionConfiguration = String(
            data: try JSONEncoder().encode([
                "FunctionName": functionName,
                "RevisionId": "1234",
                "Version": "4",
                "CodeSha256": UUID().uuidString,
            ]),
            encoding: .utf8
        )!
        // getFunctionConfiguration, updateFunctionCode, publishLatest, verifyLambda, updateAlias
        var fixtureResults: [ByteBuffer] = .init(repeating: ByteBuffer(string: functionConfiguration), count: 5)
        let resultReceived = expectation(description: "Result received")
        _ = testServices.awsServer // Start the server

        // run() uses wait() so do it in the background
        DispatchQueue.global().async {
            do {
                // Given a valid configuation
                var instance = try AppDeployer.parseAsRoot(["-p", "my-function"]) as! AppDeployer

                // When calling run
                try instance.run(services: self.testServices)
                print("done")
            } catch {
                // Then no errors should be thrown
                XCTFail(error)
            }
            resultReceived.fulfill()
        }

        do {
            try self.testServices.awsServer.processRaw { request in
                guard let result = fixtureResults.popLast() else {
                    let error = AWSTestServer.ErrorType(status: 500, errorCode: "InternalFailure", message: "Unhandled request: \(request)")
                    return .error(error, continueProcessing: false)
                }
                return .result(.init(httpStatus: .ok, body: result), continueProcessing: fixtureResults.count > 0)
            }
        } catch {
            XCTFail(error)
        }
        wait(for: [resultReceived], timeout: 2.0)
        XCTAssertEqual(fixtureResults.count, 0, "Not all calls were performed.")
    }

    func testFullRunThrough() throws {
        // This is more of an integration test. We won't stub the services
        let path = try createTempPackage()
        let collector = LogCollector()
        if isGitHubAction() {
            // Running in a github workflow, bandwidth is limited mock the results
            // instead of actually running in Docker
            try FileManager.default.createDirectory(atPath: ExamplePackage.tempDirectory,
                                                    withIntermediateDirectories: true,
                                                    attributes: nil)
            let archivePath = "\(ExamplePackage.tempDirectory)/archive.zip"
            try "contents".data(using: .utf8)?.write(to: URL(fileURLWithPath: archivePath))
            Services.shared = TestServices()
            ShellExecutor.shellOutAction = { (command: String, path: String, logger: Logger?) throws -> LogCollector.Logs in
                if command.contains("packageInDocker.sh") {
                    collector.log(level: .trace, message: "\(archivePath)")
                    return .stubMessage(level: .trace, message: archivePath)
                }
                return .stubMessage(level: .trace, message: "")
            }
        }
        defer {
            if isGitHubAction() { // Restore regular services when the test is done
                Services.shared = Services()
            }
        }
        Services.shared.logger = CollectingLogger(label: #function, logCollector: collector)
        Services.shared.logger.logLevel = .trace

        // Given a valid configuation (not calling publish for the tests)
        var instance = try AppDeployer.parseAsRoot(["-d", path, ExamplePackage.executableOne]) as! AppDeployer

        // When calling run
        // Then no errors should be thrown
        XCTAssertNoThrow(try instance.run())
        // and the zip should exist. The last line of the last log should contain the zip path
        let zipPath = collector.logs.allEntries.last?.message.trimmingCharacters(in: .whitespacesAndNewlines).components(separatedBy: "\n").last
        XCTAssertNotNil(zipPath)
        XCTAssertTrue(FileManager.default.fileExists(atPath: zipPath!), "File does not exist: \(zipPath!)")
    }
    
    func testRemoveSkippedProducts() {
        // Given a list of skipProducts for a process
        let skipProducts = ExamplePackage.executableThree
        let processName = ExamplePackage.executableTwo // Simulating that executableTwo is the executable that does the deployment
        
        // When calling removeSkippedProducts
        let result = AppDeployer.removeSkippedProducts(skipProducts,
                                                       from: ExamplePackage.executables,
                                                       logger: testServices.logger,
                                                       processName: processName)
        
        // Then the remaining products should not contain the skipProducts
        XCTAssertFalse(result.contains(skipProducts), "The \"skipProducts\": \(skipProducts) should have been removed.")
        // or a product with a matching processName
        XCTAssertFalse(result.contains(processName), "The \"processName\": \(processName) should have been removed.")
    }
}
