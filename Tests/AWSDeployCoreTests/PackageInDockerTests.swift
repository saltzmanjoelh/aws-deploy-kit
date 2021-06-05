//
//  PackageInDockerTests.swift
//  
//
//  Created by Joel Saltzman on 5/17/21.
//

import Foundation
import XCTest
import Mocking
import Logging
import LogKit
@testable import AWSDeployCore

class PackageInDockerTests: XCTestCase {
    
    var instance: PackageInDocker!
    var mockServices: MockServices!
    var packageDirectory: URL!
    
    override func setUp() {
        super.setUp()
        instance = PackageInDocker()
        mockServices = MockServices()
        packageDirectory = tempPackageDirectory()
    }
    override func tearDown() {
        super.tearDown()
        mockServices.cleanup()
    }
    
    func testCopyExecutable() throws {
        // Setup
        mockServices.mockFileManager.fileExists = { _ in true } // Simulate that it exists
        mockServices.mockFileManager.copyItem = { _ in } // Simulate a successful copy
        
        // Given a valid configuration
        let destinationDirectory = PackageInDocker.destinationDirectory
        
        // When calling copyExecutable
        try instance.copyExecutable(executable: ExamplePackage.executableOne,
                                    at: packageDirectory,
                                    destinationDirectory: destinationDirectory,
                                    services: mockServices)
        
        // Then no errors should be thrown
        // and copyItem should have been called with the destination
        let expectedSource = BuildInDocker.URLForBuiltExecutable(at: packageDirectory, for: ExamplePackage.executableOne, services: mockServices)
        let expectedDestination = URL(fileURLWithPath: destinationDirectory.appendingPathComponent(ExamplePackage.executableOne).path)
        let result = mockServices.mockFileManager.$copyItem.wasCalled(with: .init([expectedSource, expectedDestination]))
        XCTAssertTrue(result, "Source and/or destination were not used")
    }
    func testCopyExecutable_failsWhenExecutableDoesNotExist() throws {
        // Setup
        mockServices.mockFileManager.fileExists = { _ in false } // Simulate that does not exist
        
        // Given a valid configuration
        let destinationDirectory = PackageInDocker.destinationDirectory
        
        // When calling copyExecutable
        do {
            try instance.copyExecutable(executable: ExamplePackage.executableOne,
                                        at: packageDirectory,
                                        destinationDirectory: destinationDirectory,
                                        services: mockServices)
            
            XCTFail("An error should have been thrown")
        } catch PackageInDockerError.executableNotFound(let path){
            // Then PackageInDockerError.executableNotFound should be thrown
            XCTAssertEqual(path, BuildInDocker.URLForBuiltExecutable(at: packageDirectory, for: ExamplePackage.executableOne, services: mockServices).path)
        } catch {
            XCTFail(error)
        }
    }
    
    func testCopyEnvFile() throws {
        // Setup
        mockServices.mockFileManager.fileExists = { _ in true } // Simulate that it exists
        mockServices.mockFileManager.copyItem = { _ in } // Simulate a successful copy
        
        // Given a valid configuration
        let destinationDirectory = PackageInDocker.destinationDirectory
        
        // When calling copyEnvFile
        try instance.copyEnvFile(at: packageDirectory,
                                 executable: ExamplePackage.executableOne,
                                 destinationDirectory: destinationDirectory,
                                 services: mockServices)
        
        // Then no errors should be thrown
        // and copyItem should have been called with the destination
        let expectedSourceFile = instance.URLForEnvFile(packageDirectory: packageDirectory,
                                                    executable: ExamplePackage.executableOne)
        XCTAssertTrue(mockServices.mockFileManager.$copyItem.wasCalled(with: expectedSourceFile), "Source was not used. \(mockServices.mockFileManager.$copyItem.usage.history[0].context.inputs)")
        let expectedDestinationFile = destinationDirectory.appendingPathComponent(".env")
        XCTAssertTrue(mockServices.mockFileManager.$copyItem.wasCalled(with: expectedDestinationFile), "Destination were not used")
    }
    func testCopyEnvFile_continuesWhenFileDoesNotExist() throws {
        // Given a non-existent .env file
        mockServices.mockFileManager.fileExists = { _ in false } // Simulate that it does not exist
        
        // When calling copyEnvFile
        try instance.copyEnvFile(at: packageDirectory,
                                 executable: ExamplePackage.executableOne,
                                 destinationDirectory: PackageInDocker.destinationDirectory,
                                 services: mockServices)
        
        // Then the mock should not be called
        XCTAssertFalse(mockServices.mockFileManager.$copyItem.wasCalled, "copyItem should not have been called.")
    }
    
    func testGetLddDependencies() throws {
        // Given the logs from running ldd
        mockServices.mockShell.launchBash = { _ throws -> LogCollector.Logs in
            LogCollector.Logs.lddLogs()
        }
        let packageDirectory = try createTempPackage()

        // When calling getLddDependencies
        let result = try instance.getLddDependencies(for: ExamplePackage.executableOne,
                                                     at: packageDirectory,
                                                     services: mockServices)
        
        // Then the dependencies should be returend
        XCTAssertEqual(result.count, 2)
        XCTAssertTrue(result.description.contains("libswiftCore.so"), "\(result.description) should contain: libswiftCore.so")
        XCTAssertTrue(result.description.contains("libicudataswift.so.65"), "\(result.description) should contain: libicudataswift.so.65")
    }
    
    func testCopySwiftDependencies() throws {
        // Given some URLs to dependencies
        mockServices.mockShell.launchBash = { _ throws -> LogCollector.Logs in
            LogCollector.Logs.lddLogs()
        }
        mockServices.mockFileManager.copyItem = { _  in }
        let destinationDirectory = instance.destinationURLForExecutable(ExamplePackage.executableOne)
        
        // When calling copySwiftDependencies
        try instance.copySwiftDependencies(for: ExamplePackage.executableOne,
                                           at: packageDirectory,
                                           to: destinationDirectory,
                                           services: mockServices)
        
        // Then those URLs should be copied to the destination
        XCTAssertTrue(mockServices.mockFileManager.$copyItem.wasCalled)
        XCTAssertTrue(mockServices.mockFileManager.$copyItem.wasCalled(with: destinationDirectory))
        XCTAssertEqual(mockServices.mockFileManager.$copyItem.usage.history.count, 2)
    }
    
    func testAddBootstrap() throws {
        // Given a successful run
        mockServices.mockShell.launchBash = { _ throws -> LogCollector.Logs in
            return LogCollector.Logs() // No output, only outputs on error
        }
        
        // When calling addBootstrap
        let result: LogCollector.Logs = try instance.addBootstrap(for: ExamplePackage.executableOne,
                                                                  in: packageDirectory,
                                                                  services: mockServices)
        
        // Then empty logs should be received
        XCTAssertEqual(result.allEntries.count, 0)
    }
    func testAddBootstrap_throwsOnFailure() throws {
        // Given a failed symlink
        mockServices.mockShell.launchBash = { _ throws -> LogCollector.Logs in
            let logs = LogCollector.Logs()
            logs.append(level: .error, message: "ln: failed to create symbolic link 'bootstrap': File exists", metadata: nil)
            return logs
        }
        
        do {
            // When calling addBootstrap
            _ = try instance.addBootstrap(for: ExamplePackage.executableOne,
                                          in: packageDirectory,
                                          services: mockServices)
            
            XCTFail("An error should have been thrown.")
        } catch PackageInDockerError.bootstrapFailure(_) {
            // Then an error should be thrown
        }
    }
    
    func testArchiveName() {
        let archivePath = instance.archivePath(for: ExamplePackage.executableOne,
                                               in: instance.destinationURLForExecutable(ExamplePackage.executableOne))
        XCTAssertTrue(archivePath.description.contains(ExamplePackage.executableOne), "The archive path should contain the executable name")
        XCTAssertTrue(archivePath.description.contains("_"), "The archive path should contain an underscore to separate the executable name and timestamp.")
        XCTAssertTrue(archivePath.description.contains(":"), "The archive path should contain a colon in the timestamp.")
        XCTAssertTrue(archivePath.description.contains("Z"), "The timestamp portion of the archive path  should contain Z")
    }
    func testArchiveContents() throws {
        // Given a succesful zip
        mockServices.mockShell.launchBash = { _ throws -> LogCollector.Logs in
            let logs = LogCollector.Logs()
            logs.append(level: .trace, message: "adding: bootstrap (stored 0%)", metadata: nil)
            return logs
        }
        mockServices.mockFileManager.fileExists = { _ in return true }
        
        // When calling archiveContents
        let result = try instance.archiveContents(for: ExamplePackage.executableOne,
                                         in: packageDirectory,
                                         services: mockServices)
        
        // Then the archive path should be returned
        XCTAssertTrue(result.path.contains(".zip"))
    }
    func testArchiveContents_throwsOnFailure() throws {
        // Given a failed zip
        mockServices.mockShell.launchBash = { _ throws -> LogCollector.Logs in
            let logs = LogCollector.Logs()
            logs.append(level: .error, message: "error", metadata: nil)
            return logs
        }
        
        do {
            // When calling archiveContents
            _ = try instance.archiveContents(for: ExamplePackage.executableOne,
                                             in: packageDirectory,
                                             services: mockServices)
            
            XCTFail("An error should have been thrown.")
        } catch PackageInDockerError.archivingFailure(_) {
            // Then an error should be thrown
        } catch {
            XCTFail(error)
        }
    }
    func testArchiveContents_throwsWithMissingArchive() throws {
        // Given a successful zip where the archive gets deleted
        mockServices.mockShell.launchBash = { _ throws -> LogCollector.Logs in
            return LogCollector.Logs()
        }
        mockServices.mockFileManager.fileExists = { _ in return false }
        
        do {
            // When calling archiveContents
            _ = try instance.archiveContents(for: ExamplePackage.executableOne,
                                             in: packageDirectory,
                                             services: mockServices)
            
            XCTFail("An error should have been thrown.")
        } catch PackageInDockerError.archiveNotFound(_) {
            // Then an error should be thrown
        } catch {
            XCTFail(error)
        }
    }
    
    func testCreateDestinationDirectory() {
        // This is a control function that simply calls other functions.
        // We test those functions separately. This is more
        // for the code coverage. Note that we call the mockPackager
        // instead of the instance.
        mockServices.mockFileManager.removeItem = { _ in }
        mockServices.mockFileManager.createDirectory = { _ in }
        
        XCTAssertNoThrow(try mockServices.mockPackager.createDestinationDirectory(URL(fileURLWithPath: ""), services: mockServices))
        XCTAssertEqual(mockServices.mockFileManager.$removeItem.usage.history.count, 1, "removeItem should have been called.")
        XCTAssertEqual(mockServices.mockFileManager.$createDirectory.usage.history.count, 1, "createDirectory should have been called.")
    }
    
    func testPrepareDestinationDirectory() {
        // This is a control function that simply calls other functions.
        // We test those functions separately. This is more
        // for the code coverage. Note that we call the mockPackager
        // instead of the instance.
        mockServices.mockPackager.copyExecutable = { _ in }
        mockServices.mockPackager.copyEnvFile = { _ in }
        mockServices.mockPackager.copySwiftDependencies = { _ in }
        mockServices.mockPackager.addBootstrap = { _ in return .init() }
        
        XCTAssertNoThrow(try mockServices.mockPackager.prepareDestinationDirectory(executable: "",
                                                                                   packageDirectory: URL(fileURLWithPath: ""),
                                                                                   destinationDirectory: URL(fileURLWithPath: ""),
                                                                                   services: mockServices))
        XCTAssertEqual(mockServices.mockPackager.$copyExecutable.usage.history.count, 1, "copyExecutable should have been called.")
        XCTAssertEqual(mockServices.mockPackager.$copyEnvFile.usage.history.count, 1, "copyEnvFile should have been called.")
        XCTAssertEqual(mockServices.mockPackager.$copySwiftDependencies.usage.history.count, 1, "copySwiftDependencies should have been called.")
        XCTAssertEqual(mockServices.mockPackager.$addBootstrap.usage.history.count, 1, "addBootstrap should have been called.")
    }
    
    
    func testPackageExecutable() throws {
        // This is a control function that simply calls other functions.
        // We test those functions separately. This is more
        // for the code coverage. Note that we call the mockPackager
        // instead of the instance.
        mockServices.mockPackager.createDestinationDirectory = { _ in }
        mockServices.mockPackager.prepareDestinationDirectory = { _ in }
        mockServices.mockPackager.archiveContents = { _ throws in return URL(fileURLWithPath: "file.zip") }
        
        XCTAssertNoThrow(try mockServices.mockPackager.packageExecutable("", at: URL(fileURLWithPath: ""), services: mockServices))
        XCTAssertEqual(mockServices.mockPackager.$createDestinationDirectory.usage.history.count, 1, "createDestinationDirectory should have been called.")
        XCTAssertEqual(mockServices.mockPackager.$prepareDestinationDirectory.usage.history.count, 1, "prepareDestinationDirectory should have been called.")
        XCTAssertEqual(mockServices.mockPackager.$archiveContents.usage.history.count, 1, "archiveContents should have been called.")
    }
}
