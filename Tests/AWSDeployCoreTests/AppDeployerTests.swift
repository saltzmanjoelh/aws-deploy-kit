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
        let packageDirectory = try createTempPackage()
        var instance = try AppDeployer.parseAsRoot(["-s", ExamplePackage.executableThree, "-p", packageDirectory.path]) as! AppDeployer

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
        testServices.mockShell.launchBash = { _ throws -> LogCollector.Logs in
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
        let packageDirectory = try createTempPackage()
        let instance = AppDeployer()

        // When calling getProducts
        let result = try instance.getProducts(from: packageDirectory, services: testServices)

        // Then all executables should be returned
        XCTAssertEqual(result.count, ExamplePackage.executables.count)
    }
    func testGetProductsThrowsWithInvalidShellOutput() throws {
        // Give a failed shell output
        testServices.mockShell.launchBash = { _ throws -> LogCollector.Logs in
            return .stubMessage(level: .trace, message: "")
        }
        let instance = AppDeployer()

        // When calling getProducts
        do {
            _ = try instance.getProducts(from: URL(fileURLWithPath: ""), services: testServices)
            
            XCTFail("An error should have been thrown.")
        } catch {
            // Then AppDeployerError.packageDumpFailure is thrown
            XCTAssertEqual("\(error)", AppDeployerError.packageDumpFailure.description)
        }
    }

    func testFullRunThrough() throws {
        // This is more of an integration test. We won't stub the services
        let packageDirectory = try createTempPackage()
        let collector = LogCollector()
        if isGitHubAction() {
            print("GITHUB Action")
            // Running in a github workflow, bandwidth is limited mock the results
            // instead of actually running in Docker
            try FileManager.default.createDirectory(atPath: ExamplePackage.tempDirectory,
                                                    withIntermediateDirectories: true,
                                                    attributes: nil)
            let archivePath = "\(ExamplePackage.tempDirectory)/archive.zip"
            try "contents".data(using: .utf8)?.write(to: URL(fileURLWithPath: archivePath))
            Services.shared = TestServices()
        }
        defer {
            if isGitHubAction() { // Restore regular services when the test is done
                Services.shared = Services()
            }
        }
        Services.shared.logger = CollectingLogger(label: #function, logCollector: collector)
        Services.shared.logger.logLevel = .trace

        // Given a valid configuation (not calling publish for the tests)
        var instance = try AppDeployer.parseAsRoot(["-d", packageDirectory.path, ExamplePackage.executableOne]) as! AppDeployer

        // When calling run
        // Then no errors should be thrown
        XCTAssertNoThrow(try instance.run())
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
