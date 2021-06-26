//
//  BuildCommandTests.swift
//
//
//  Created by Joel Saltzman on 3/18/21.
//

import Foundation
import XCTest
import Logging
import LogKit
import SotoS3
import SotoLambda
@testable import SotoTestUtils
@testable import AWSDeployCore

class BuildCommandTests: XCTestCase {
    
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
    
    func testVerifyConfiguration_directoryPathUpdateWithDot() throws {
        // Given a "." path
        var instance = try BuildCommand.parseAsRoot(["-d", ".", "my-function"]) as! BuildCommand

        // When calling verifyConfiguration
        try instance.verifyConfiguration(services: mockServices)

        // Then the directoryPath should be updated
        XCTAssertNotEqual(instance.options.directory.path, "./")
        XCTAssertNotEqual(instance.options.directory.path, ".")
    }

    func testVerifyConfiguration_directoryPathUpdateWithDotSlash() throws {
        // Given a "." path
        var instance = try BuildCommand.parseAsRoot(["-d", "./", "my-function"]) as! BuildCommand

        // When calling verifyConfiguration
        try instance.verifyConfiguration(services: mockServices)

        // Then the directoryPath should be updated
        XCTAssertNotEqual(instance.options.directory.path, "./")
        XCTAssertNotEqual(instance.options.directory.path, ".")
    }

    func testVerifyConfiguration_logsWhenSkippingProducts() throws {
        // Given a product to skip
        let packageDirectory = try createTempPackage()
        var instance = try BuildCommand.parseAsRoot(["-s", ExamplePackage.executableThree, "-d", packageDirectory.path]) as! BuildCommand

        // When calling verifyConfiguration
        try instance.verifyConfiguration(services: mockServices)

        // Then a "Skipping $PRODUCT" log should be received
        let messages = mockServices.logCollector.logs.allMessages()
        XCTAssertString(messages, contains: "Skipping: \(ExamplePackage.executableThree)")
    }
    func testVerifyConfiguration_throwsWithMissingProducts() throws {
        // Given a package without any executables
        var instance = try BuildCommand.parseAsRoot(["-d", "/invalid"]) as! BuildCommand
        instance.options.products = []
        instance.options.skipProducts = ""
        mockServices.mockShell.launchShell = { _ throws -> LogCollector.Logs in
            let packageManifest = "{\"products\" : []}"
            return .stubMessage(level: .trace, message: packageManifest)
        }
        
        do {
            // When calling verifyConfiguration
            try instance.verifyConfiguration(services: mockServices)
            
            XCTFail("An error should have been thrown and products should have been empty instead of: \(instance.options.products)")
        } catch AppDeployerError.missingProducts {
            // Then the AppDeployerError.missingProducts error should be thrown
        } catch {
            XCTFail(String(describing: error))
        }
    }

    func testGetProducts() throws {
        // Given a package with a library and multiple executables
        let packageDirectory = try createTempPackage()
        let instance = BuildCommand()

        // When calling getProducts
        let result = try instance.getProducts(from: packageDirectory, services: mockServices)

        // Then all executables should be returned
        XCTAssertEqual(result.count, ExamplePackage.executables.count)
    }
    func testGetProductsThrowsWithInvalidShellOutput() throws {
        // Give a failed shell output
        mockServices.mockShell.launchShell = { _ throws -> LogCollector.Logs in
            return .stubMessage(level: .trace, message: "")
        }
        let instance = BuildCommand()

        // When calling getProducts
        do {
            _ = try instance.getProducts(from: URL(fileURLWithPath: ""), services: mockServices)
            
            XCTFail("An error should have been thrown.")
        } catch {
            // Then AppDeployerError.packageDumpFailure is thrown
            XCTAssertEqual("\(error)", AppDeployerError.packageDumpFailure.description)
        }
    }
    
    func testRemoveSkippedProducts() {
        // Given a list of skipProducts for a process
        let skipProducts = ExamplePackage.executableThree
        let processName = ExamplePackage.executableTwo // Simulating that executableTwo is the executable that does the deployment
        
        // When calling removeSkippedProducts
        let result = BuildCommand.removeSkippedProducts(skipProducts,
                                                           from: ExamplePackage.executables,
                                                           logger: mockServices.logger,
                                                           processName: processName)
        
        // Then the remaining products should not contain the skipProducts
        XCTAssertFalse(result.contains(skipProducts), "The \"skipProducts\": \(skipProducts) should have been removed.")
        // or a product with a matching processName
        XCTAssertFalse(result.contains(processName), "The \"processName\": \(processName) should have been removed.")
    }
    
    func testRunWithMocks() throws {
        // Given a valid configuration
        let packageDirectory = tempPackageDirectory()
        var instance = try! BuildCommand.parseAsRoot([packageDirectory.path, ExamplePackage.executableOne]) as! BuildCommand
        Services.shared = mockServices
        mockServices.mockBuilder.buildProducts = { _ throws -> [URL] in
            return [DockerizedBuilder.URLForBuiltExecutable(at: packageDirectory, for: ExamplePackage.executableOne, services: self.mockServices)]
        }
        
        // When calling run()
        // Then no errors are thrown
        XCTAssertNoThrow(try instance.run())
        // And the product get's built and packaged
        XCTAssertTrue(mockServices.mockBuilder.$buildProducts.wasCalled)
    }
}
