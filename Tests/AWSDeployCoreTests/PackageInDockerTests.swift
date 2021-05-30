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
    var testServices: TestServices!
    var packageDirectory: URL!
    
    override func setUp() {
        super.setUp()
        instance = PackageInDocker()
        testServices = TestServices()
        packageDirectory = tempPackageDirectory()
    }
    override func tearDown() {
        super.tearDown()
        testServices.cleanup()
        ShellExecutor.resetAction()
    }
    
    func testCopyExecutable() throws {
        // Setup
        testServices.mockFileManager.fileExists = { _ in true } // Simulate that it exists
        testServices.mockFileManager.copyItem = { _ in } // Simulate a successful copy
        
        // Given a valid configuration
        let destinationDirectory = PackageInDocker.destinationDirectory
        
        // When calling copyExecutable
        try instance.copyExecutable(executable: ExamplePackage.executableOne,
                                    at: packageDirectory,
                                    destinationDirectory: destinationDirectory,
                                    services: testServices)
        
        // Then no errors should be thrown
        // and copyItem should have been called with the destination
        let expectedSource = instance.URLForBuiltExecutable(ExamplePackage.executableOne)
        let expectedDestination = URL(fileURLWithPath: destinationDirectory.appendingPathComponent(ExamplePackage.executableOne).path)
        let result = testServices.mockFileManager.$copyItem.wasCalled(with: .init([expectedSource, expectedDestination]))
        XCTAssertTrue(result, "Source and/or destination were not used")
    }
    func testCopyExecutable_failsWhenExecutableDoesNotExist() throws {
        // Setup
        testServices.mockFileManager.fileExists = { _ in false } // Simulate that does not exist
        
        // Given a valid configuration
        let destinationDirectory = PackageInDocker.destinationDirectory
        
        // When calling copyExecutable
        do {
            try instance.copyExecutable(executable: ExamplePackage.executableOne,
                                        at: packageDirectory,
                                        destinationDirectory: destinationDirectory,
                                        services: testServices)
            
            XCTFail("An error should have been thrown")
        } catch PackageInDockerError.executableNotFound(let path){
            // Then PackageInDockerError.executableNotFound should be thrown
            XCTAssertEqual(path, instance.URLForBuiltExecutable(ExamplePackage.executableOne).path)
        } catch {
            XCTFail(error)
        }
    }
    
    func testCopyEnvFile() throws {
        // Setup
        testServices.mockFileManager.fileExists = { _ in true } // Simulate that it exists
        testServices.mockFileManager.copyItem = { _ in } // Simulate a successful copy
        
        // Given a valid configuration
        let destinationDirectory = PackageInDocker.destinationDirectory
        
        // When calling copyEnvFile
        try instance.copyEnvFile(at: packageDirectory,
                                 executable: ExamplePackage.executableOne,
                                 destinationDirectory: destinationDirectory,
                                 services: testServices)
        
        // Then no errors should be thrown
        // and copyItem should have been called with the destination
        let expectedSourceFile = instance.URLForEnvFile(packageDirectory: packageDirectory,
                                                    executable: ExamplePackage.executableOne)
        XCTAssertTrue(testServices.mockFileManager.$copyItem.wasCalled(with: expectedSourceFile), "Source was not used. \(testServices.mockFileManager.$copyItem.usage.history[0].context.inputs)")
        let expectedDestinationFile = destinationDirectory.appendingPathComponent(".env")
        XCTAssertTrue(testServices.mockFileManager.$copyItem.wasCalled(with: expectedDestinationFile), "Destination were not used")
    }
    func testCopyEnvFile_continuesWhenFileDoesNotExist() throws {
        // Given a non-existent .env file
        testServices.mockFileManager.fileExists = { _ in false } // Simulate that it does not exist
        
        // When calling copyEnvFile
        try instance.copyEnvFile(at: packageDirectory,
                                 executable: ExamplePackage.executableOne,
                                 destinationDirectory: PackageInDocker.destinationDirectory,
                                 services: testServices)
        
        // Then the mock should not be called
        XCTAssertFalse(testServices.mockFileManager.$copyItem.wasCalled, "copyItem should not have been called.")
    }
    
    func testGetLddDependencies() throws {
        // Given the logs from running ldd
        ShellExecutor.shellOutAction = { (_, _, _) throws -> LogCollector.Logs in
            LogCollector.Logs.lddLogs()
        }
        let packageDirectory = try createTempPackage()

        // When calling getLddDependencies
        let result = try instance.getLddDependencies(for: ExamplePackage.executableOne,
                                                     at: packageDirectory,
                                                     services: testServices)
        
        // Then the dependencies should be returend
        XCTAssertEqual(result.count, 2)
        XCTAssertTrue(result.description.contains("libswiftCore.so"), "\(result.description) should contain: libswiftCore.so")
        XCTAssertTrue(result.description.contains("libicudataswift.so.65"), "\(result.description) should contain: libicudataswift.so.65")
    }
    
    func testCopySwiftDependencies() throws {
        // Given some URLs to dependencies
        ShellExecutor.shellOutAction = { (_, _, _) throws -> LogCollector.Logs in
            LogCollector.Logs.lddLogs()
        }
        testServices.mockFileManager.copyItem = { _  in }
        let destinationDirectory = instance.destinationURLForExecutable(ExamplePackage.executableOne)
        
        // When calling copySwiftDependencies
        try instance.copySwiftDependencies(for: ExamplePackage.executableOne,
                                           at: packageDirectory,
                                           to: destinationDirectory,
                                           services: testServices)
        
        // Then those URLs should be copied to the destination
        XCTAssertTrue(testServices.mockFileManager.$copyItem.wasCalled)
        XCTAssertTrue(testServices.mockFileManager.$copyItem.wasCalled(with: destinationDirectory))
        XCTAssertEqual(testServices.mockFileManager.$copyItem.usage.history.count, 2)
    }
    
    func testAddBootstrap() throws {
        // Given a successful run
        ShellExecutor.shellOutAction = { (_, _, _) throws -> LogCollector.Logs in
            return LogCollector.Logs() // No output, only outputs on error
        }
        
        // When calling addBootstrap
        let result: LogCollector.Logs = try instance.addBootstrap(for: ExamplePackage.executableOne,
                                                                  in: packageDirectory,
                                                                  services: testServices)
        
        // Then empty logs should be received
        XCTAssertEqual(result.allEntries.count, 0)
    }
    func testAddBootstrap_throwsOnFailure() throws {
        // Given a failed symlink
        ShellExecutor.shellOutAction = { (_, _, _) throws -> LogCollector.Logs in
            let logs = LogCollector.Logs()
            logs.append(level: .error, message: "ln: failed to create symbolic link 'bootstrap': File exists", metadata: nil)
            return logs
        }
        
        do {
            // When calling addBootstrap
            _ = try instance.addBootstrap(for: ExamplePackage.executableOne,
                                          in: packageDirectory,
                                          services: testServices)
            
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
        ShellExecutor.shellOutAction = { (_, _, _) throws -> LogCollector.Logs in
            let logs = LogCollector.Logs()
            logs.append(level: .trace, message: "adding: bootstrap (stored 0%)", metadata: nil)
            return logs
        }
        
        // When calling archiveContents
        let result = try instance.archiveContents(for: ExamplePackage.executableOne,
                                         in: packageDirectory,
                                         services: testServices)
        
        // Then the archive path should be returned
        XCTAssertTrue(result.path.contains(".zip"))
    }
    func testArchiveContents_throwsOnFailure() throws {
        // Given a failed zip
        ShellExecutor.shellOutAction = { (_, _, _) throws -> LogCollector.Logs in
            let logs = LogCollector.Logs()
            logs.append(level: .error, message: "error", metadata: nil)
            return logs
        }
        
        do {
            // When calling archiveContents
            _ = try instance.archiveContents(for: ExamplePackage.executableOne,
                                             in: packageDirectory,
                                             services: testServices)
            
            XCTFail("An error should have been thrown.")
        } catch PackageInDockerError.archivingFailure(_) {
            // Then an error should be thrown
        } catch {
            XCTFail(error)
        }
    }
//    func testGetArchivePath() throws {
//        // Given the output from building a package
//        let path = "/tmp/package/.build/release/lambda/executable/archive_date.zip"
//        let logs = LogCollector.Logs.init()
//        logs.append(level: .trace, message: "first", metadata: nil)
//        logs.append(level: .trace, message: "\(path)", metadata: nil)
//        testServices.mockFileManager.fileExists = { _ in return true }
//        
//        // When calling getArchivePath
//        let result = try instance.getArchivePath(from: logs, for: "executable", services: testServices)
//        
//        // Then the archive path is returned
//        XCTAssertEqual(result.path, path)
//    }
//    func testGetArchivePath_handlesMissingPath() throws {
//        // Given logs without a path
//        let logs = LogCollector.Logs.init()
//        
//        // When calling getArchivePath
//        do {
//            _ = try instance.getArchivePath(from: logs, for: "executable", services: testServices)
//            
//            XCTFail("An error should have been thrown")
//        } catch BuildInDockerError.archivePathNotReceived(_) {
//            // Then BuildInDockerError.archivePathNotReceived should be thrown
//        } catch {
//            XCTFail(error)
//        }
//    }
//    func testGetArchivePath_handlesInvalidPath() throws {
//        // Given logs with a bad path
//        let logs = LogCollector.Logs.init()
//        logs.append(level: .trace, message: "first", metadata: nil)
//        
//        // When calling getArchivePath
//        do {
//            _ = try instance.getArchivePath(from: logs, for: "executable", services: testServices)
//            
//            XCTFail("An error should have been thrown")
//        } catch BuildInDockerError.archiveNotFound(_) {
//            // Then BuildInDockerError.archiveNotFound should be thrown
//        } catch {
//            XCTFail(error)
//        }
//    }
}
