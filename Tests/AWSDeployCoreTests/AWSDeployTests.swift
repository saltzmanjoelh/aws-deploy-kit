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
import SotoLambda
@testable import SotoTestUtils
import XCTest

class AWSDeployTests: XCTestCase {
    
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
        mockServices.mockPublisher.publishArchives = { _ in
            return self.mockServices.awsServer.eventLoopGroup.next().makeSucceededFuture([.init(name: "my-function")])
        }
        // Given a functionRole provided in cli
        let role = "example-role"
        var instance = try AWSDeploy.Build.parseAsRoot(["my-function", "--function-role", role]) as! AWSDeploy.Build
        
        // When running
        try instance.run()
        
        // Then the publisher should receive the value
        XCTAssertEqual(mockServices.publisher.functionRole, role)
    }
    
    func testVerifyConfiguration_directoryPathUpdateWithDot() throws {
        // Given a "." path
        var instance = try AWSDeploy.Build.parseAsRoot(["-d", ".", "my-function"]) as! AWSDeploy.Build

        // When calling verifyConfiguration
        try instance.verifyConfiguration(services: mockServices)

        // Then the directoryPath should be updated
        XCTAssertNotEqual(instance.directory.path, "./")
        XCTAssertNotEqual(instance.directory.path, ".")
    }

    func testVerifyConfiguration_directoryPathUpdateWithDotSlash() throws {
        // Given a "." path
        var instance = try AWSDeploy.Build.parseAsRoot(["-d", "./", "my-function"]) as! AWSDeploy.Build

        // When calling verifyConfiguration
        try instance.verifyConfiguration(services: mockServices)

        // Then the directoryPath should be updated
        XCTAssertNotEqual(instance.directory.path, "./")
        XCTAssertNotEqual(instance.directory.path, ".")
    }

    func testVerifyConfiguration_logsWhenSkippingProducts() throws {
        // Given a product to skip
        let packageDirectory = try createTempPackage()
        var instance = try AWSDeploy.Build.parseAsRoot(["-s", ExamplePackage.executableThree, "-d", packageDirectory.path]) as! AWSDeploy.Build

        // When calling verifyConfiguration
        try instance.verifyConfiguration(services: mockServices)

        // Then a "Skipping $PRODUCT" log should be received
        let messages = mockServices.logCollector.logs.allMessages()
        XCTAssertString(messages, contains: "Skipping: \(ExamplePackage.executableThree)")
    }
    func testVerifyConfiguration_throwsWithMissingProducts() throws {
        // Given a package without any executables
        var instance = try AWSDeploy.Build.parseAsRoot(["-d", "/invalid"]) as! AWSDeploy.Build
        instance.products = []
        instance.skipProducts = ""
        instance.publish = false
        mockServices.mockShell.launchShell = { _ throws -> LogCollector.Logs in
            let packageManifest = "{\"products\" : []}"
            return .stubMessage(level: .trace, message: packageManifest)
        }
        
        do {
            // When calling verifyConfiguration
            try instance.verifyConfiguration(services: mockServices)
            
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
        let instance = AWSDeploy.Build()

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
        let instance = AWSDeploy.Build()

        // When calling getProducts
        do {
            _ = try instance.getProducts(from: URL(fileURLWithPath: ""), services: mockServices)
            
            XCTFail("An error should have been thrown.")
        } catch {
            // Then AppDeployerError.packageDumpFailure is thrown
            XCTAssertEqual("\(error)", AppDeployerError.packageDumpFailure.description)
        }
    }
    
    func testRunWithMocks() throws {
        // Given a valid configuration
        let packageDirectory = tempPackageDirectory()
        var instance = try! AWSDeploy.Build.parseAsRoot(["-p", packageDirectory.path, ExamplePackage.executableOne]) as! AWSDeploy.Build
        Services.shared = mockServices
        mockServices.mockBuilder.buildProducts = { _ throws -> [URL] in
            return [DockerizedBuilder.URLForBuiltExecutable(at: packageDirectory, for: ExamplePackage.executableOne, services: self.mockServices)]
        }
        mockServices.mockPackager.packageExecutable = { _ throws -> URL in
            return self.mockServices.packager.archivePath(for: ExamplePackage.executableOne, in: packageDirectory)
        }
        mockServices.mockPublisher.publishArchives = { _ throws -> EventLoopFuture<[Lambda.AliasConfiguration]> in
            return self.mockServices.stubAliasConfiguration()
                .map({ [$0] })
        }
        
        // When calling run()
        // Then no errors are thrown
        XCTAssertNoThrow(try instance.run())
        XCTAssertTrue(mockServices.mockPackager.$packageExecutable.wasCalled)
    }

    func testFullRunThrough() throws {
        // This is a live run. Only do it if we explicitly say we want to.
        guard shouldDoFullRunThrough() else { return }
        // This is more of an integration test. We won't stub the services
        let packageDirectory = try createTempPackage()
        let collector = LogCollector()
        Services.shared.logger = CollectingLogger(label: #function, logCollector: collector)
        Services.shared.logger.logLevel = .trace
        Services.shared.publisher = MockPublisher()

        // Given a valid configuation (not calling publish for the tests)
        var instance = try AWSDeploy.parseAsRoot(["-d", packageDirectory.path, "-p", ExamplePackage.executableOne]) as! AWSDeploy

        // When calling run
        // Then no errors should be thrown
        XCTAssertNoThrow(try instance.run())
    }
    
    func testRemoveSkippedProducts() {
        // Given a list of skipProducts for a process
        let skipProducts = ExamplePackage.executableThree
        let processName = ExamplePackage.executableTwo // Simulating that executableTwo is the executable that does the deployment
        
        // When calling removeSkippedProducts
        let result = AWSDeploy.Build.removeSkippedProducts(skipProducts,
                                                           from: ExamplePackage.executables,
                                                           logger: mockServices.logger,
                                                           processName: processName)
        
        // Then the remaining products should not contain the skipProducts
        XCTAssertFalse(result.contains(skipProducts), "The \"skipProducts\": \(skipProducts) should have been removed.")
        // or a product with a matching processName
        XCTAssertFalse(result.contains(processName), "The \"processName\": \(processName) should have been removed.")
    }
}
