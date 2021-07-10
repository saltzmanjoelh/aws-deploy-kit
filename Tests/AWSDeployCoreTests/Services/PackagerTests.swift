//
//  PackagerTests.swift
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

class PackagerTests: XCTestCase {
    
    var mockServices: MockServices!
    var packageDirectory: URL!
    
    override func setUp() {
        super.setUp()
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
        let destinationDirectory = mockServices.mockPackager.destinationURLForExecutable(ExamplePackage.executableOne, in: packageDirectory)
        
        // When calling copyExecutable
        try mockServices.mockPackager.copyExecutable(executable: ExamplePackage.executableOne,
                                    at: packageDirectory,
                                    destinationDirectory: destinationDirectory,
                                    services: mockServices)
        
        // Then no errors should be thrown
        // and copyItem should have been called with the destination
        let expectedSource = Builder.URLForBuiltExecutable(ExamplePackage.executableOne, at: packageDirectory, services: mockServices)
        let expectedDestination = destinationDirectory.appendingPathComponent(ExamplePackage.executableOne, isDirectory: false)
        let result = mockServices.mockFileManager.$copyItem.wasCalled(with: .init([expectedSource, expectedDestination]))
        XCTAssertTrue(result, "Source and/or destination were not used")
    }
    func testCopyExecutable_failsWhenExecutableDoesNotExist() throws {
        // Setup
        mockServices.mockFileManager.fileExists = { _ in false } // Simulate that does not exist
        
        // Given a valid configuration
        let destinationDirectory = mockServices.mockPackager.destinationURLForExecutable(ExamplePackage.executableOne, in: packageDirectory)
        
        // When calling copyExecutable
        do {
            try mockServices.mockPackager.copyExecutable(executable: ExamplePackage.executableOne,
                                        at: packageDirectory,
                                        destinationDirectory: destinationDirectory,
                                        services: mockServices)
            
            XCTFail("An error should have been thrown")
        } catch PackagerError.executableNotFound(let path){
            // Then PackageInDockerError.executableNotFound should be thrown
            XCTAssertEqual(path, Builder.URLForBuiltExecutable(ExamplePackage.executableOne, at: packageDirectory, services: mockServices).path)
        } catch {
            XCTFail(error)
        }
    }
    
    func testCopyEnvFile() throws {
        // Setup
        mockServices.mockFileManager.fileExists = { _ in true } // Simulate that it exists
        mockServices.mockFileManager.copyItem = { _ in } // Simulate a successful copy
        
        // Given a valid configuration
        let destinationDirectory = mockServices.mockPackager.destinationURLForExecutable(ExamplePackage.executableOne, in: packageDirectory)
        
        // When calling copyEnvFile
        try mockServices.mockPackager.copyEnvFile(at: packageDirectory,
                                 executable: ExamplePackage.executableOne,
                                 destinationDirectory: destinationDirectory,
                                 services: mockServices)
        
        // Then no errors should be thrown
        // and copyItem should have been called with the destination
        let expectedSourceFile = mockServices.mockPackager.URLForEnvFile(packageDirectory: packageDirectory,
                                                    executable: ExamplePackage.executableOne)
        XCTAssertTrue(mockServices.mockFileManager.$copyItem.wasCalled(with: expectedSourceFile), "Source was not used. \(mockServices.mockFileManager.$copyItem.usage.history[0].context.inputs)")
        let expectedDestinationFile = destinationDirectory.appendingPathComponent(".env")
        XCTAssertTrue(mockServices.mockFileManager.$copyItem.wasCalled(with: expectedDestinationFile), "Destination were not used")
    }
    func testCopyEnvFile_continuesWhenFileDoesNotExist() throws {
        // Given a non-existent .env file
        mockServices.mockFileManager.fileExists = { _ in false } // Simulate that it does not exist
        
        // When calling copyEnvFile
        try mockServices.mockPackager.copyEnvFile(at: packageDirectory,
                                 executable: ExamplePackage.executableOne,
                                 destinationDirectory: mockServices.mockPackager.destinationURLForExecutable(ExamplePackage.executableOne, in: packageDirectory),
                                 services: mockServices)
        
        // Then the mock should not be called
        XCTAssertFalse(mockServices.mockFileManager.$copyItem.wasCalled, "copyItem should not have been called.")
    }
    
    func testGetLddDependencies() throws {
        // Given the logs from running ldd
        mockServices.mockShell.launchShell = { _ throws -> LogCollector.Logs in
            LogCollector.Logs.lddLogs()
        }
        let packageDirectory = try createTempPackage()

        // When calling getLddDependencies
        let result = try mockServices.mockPackager.getLddDependencies(for: ExamplePackage.executableOne,
                                                     at: packageDirectory,
                                                     services: mockServices)
        
        // Then the dependencies should be returend
        XCTAssertEqual(result.count, 2)
        XCTAssertTrue(result.description.contains("/usr/lib/swift/linux/libswiftCore.so"), "\(result.description) should contain: libswiftCore.so")
        XCTAssertTrue(result.description.contains("/usr/lib/swift/linux/libicudataswift.so.65"), "\(result.description) should contain: libicudataswift.so.65")
    }
    func testParseLddLineHandlesInvalidInput() {
        // Given a invalid input
        let line = "nothing"
        
        // When calling parseLddLine
        let result = Packager.parseLddLine(line)
        
        // Then nil should be returned
        XCTAssertNil(result)
    }
    func testCopyDependency() throws {
        // Given a valid URL to a dependency
        let dependency = URL(fileURLWithPath: "/usr/lib/swift/linux/libswiftCore.so")
        let packageDirectory = tempPackageDirectory()
        let destinationDirectory = mockServices.mockPackager.destinationURLForExecutable(ExamplePackage.executableOne, in: packageDirectory)
        mockServices.mockShell.launchShell = { _ in return .init() }// Call doesn't return an errors
        
        // When calling copyDependency
        try mockServices.mockPackager.copyDependency(dependency, in: packageDirectory, to: destinationDirectory, services: mockServices)
        
        // Then the shell should be called
        XCTAssertTrue(mockServices.mockShell.$launchShell.wasCalled, "Shell command was not executed.")
        let expectedCommand = Docker.createShellCommand("cp \(dependency.path) \(destinationDirectory.path)", at: packageDirectory)
        let expectedInput = EquatableTuple([try CodableInput(expectedCommand), try CodableInput(packageDirectory)])
        XCTAssertTrue(mockServices.mockShell.$launchShell.wasCalled(with: expectedInput), "Unexpected shell command. History: \(mockServices.mockShell.$launchShell.usage.inputDescriptions.last!)")
    }
    func testCopyDependencyThrowsWithErrors() throws {
        // Given an invalid URL to a dependency
        let dependency = URL(fileURLWithPath: "/usr/lib/swift/linux/libswiftCore.so")
        let packageDirectory = tempPackageDirectory()
        let destinationDirectory = mockServices.mockPackager.destinationURLForExecutable(ExamplePackage.executableOne, in: packageDirectory)
        mockServices.mockShell.launchShell = { _ in
            let logs = LogCollector.Logs.init()
            logs.append(level: .error, message: "File not found.", metadata: nil)
            return logs
        }
        
        do {
            // When calling copyDependency
            try mockServices.mockPackager.copyDependency(dependency, in: packageDirectory, to: destinationDirectory, services: mockServices)
        } catch {
            XCTAssertEqual("\(error)", PackagerError.dependencyFailure(dependency, "File not found.").description, "Unexpected error: \(error)")
        }
        
        // Then the shell should be called
        XCTAssertTrue(mockServices.mockShell.$launchShell.wasCalled, "Shell command was not executed.")
        let expectedCommand = Docker.createShellCommand("cp \(dependency.path) \(destinationDirectory.path)", at: packageDirectory)
        let expectedInput = EquatableTuple([try CodableInput(expectedCommand), try CodableInput(packageDirectory)])
        XCTAssertTrue(mockServices.mockShell.$launchShell.wasCalled(with: expectedInput), "Unexpected shell command.")
    }
    
    func testCopySwiftDependencies() throws {
        // Given a successful run
        mockServices.mockShell.launchShell = { (tuple: EquatableTuple<CodableInput>) throws -> LogCollector.Logs in
            let command: String = try! tuple.inputs[0].decode()
            if command.contains("ldd") { // getLddDependencies
                return LogCollector.Logs.lddLogs()
            } else { // copyDependency
                return .init() // no errors
            }
        }
        mockServices.mockFileManager.copyItem = { _  in }
        let destinationDirectory = mockServices.mockPackager.destinationURLForExecutable(ExamplePackage.executableOne, in: packageDirectory)
        
        // When calling copySwiftDependencies
        try mockServices.mockPackager.copySwiftDependencies(for: ExamplePackage.executableOne,
                                           at: packageDirectory,
                                           to: destinationDirectory,
                                           services: mockServices)
        
        // Then those URLs should be copied to the destination
        XCTAssertTrue(mockServices.mockShell.$launchShell.wasCalled)
        XCTAssertEqual(mockServices.mockShell.$launchShell.usage.history.count, 3, "At least 2 shell commands should have been called. One for getting the dependencies and 1 for each dependency.")
    }
    
    func testAddBootstrap() throws {
        // Given a successful run
        mockServices.mockShell.launchShell = { _ throws -> LogCollector.Logs in
            return LogCollector.Logs() // No output, only outputs on error
        }
        
        // When calling addBootstrap
        let result: LogCollector.Logs = try mockServices.mockPackager.addBootstrap(for: ExamplePackage.executableOne,
                                                                  in: packageDirectory,
                                                                  services: mockServices)
        
        // Then empty logs should be received
        XCTAssertEqual(result.allEntries.count, 0)
    }
    func testAddBootstrap_throwsOnFailure() throws {
        // Given a failed symlink
        mockServices.mockShell.launchShell = { _ throws -> LogCollector.Logs in
            let logs = LogCollector.Logs()
            logs.append(level: .error, message: "ln: failed to create symbolic link 'bootstrap': File exists", metadata: nil)
            return logs
        }
        
        do {
            // When calling addBootstrap
            _ = try mockServices.mockPackager.addBootstrap(for: ExamplePackage.executableOne,
                                          in: packageDirectory,
                                          services: mockServices)
            
            XCTFail("An error should have been thrown.")
        } catch PackagerError.bootstrapFailure(_) {
            // Then an error should be thrown
        }
    }
    
    func testArchiveName() {
        let archivePath = mockServices.mockPackager.archivePath(for: ExamplePackage.executableOne,
                                               in: mockServices.mockPackager.destinationURLForExecutable(ExamplePackage.executableOne, in: packageDirectory))
        XCTAssertTrue(archivePath.description.contains(ExamplePackage.executableOne), "The archive path should contain the executable name")
    }
    func testArchiveContents() throws {
        // Given a succesful zip
        let destinationDirectory = mockServices.mockPackager.destinationURLForExecutable(ExamplePackage.executableOne, in: packageDirectory)
        mockServices.mockShell.launchShell = { _ throws -> LogCollector.Logs in
            let logs = LogCollector.Logs()
            logs.append(level: .trace, message: "adding: bootstrap (stored 0%)", metadata: nil)
            return logs
        }
        mockServices.mockFileManager.fileExists = { _ in return true }
        
        // When calling archiveContents
        let result = try mockServices.mockPackager.archiveContents(for: ExamplePackage.executableOne,
                                         in: destinationDirectory,
                                         services: mockServices)
        
        // Then the archive path should be returned
        XCTAssertTrue(result.path.contains(".zip"))
    }
    func testArchiveContents_throwsOnFailure() throws {
        // Given a failed zip
        mockServices.mockShell.launchShell = { _ throws -> LogCollector.Logs in
            let logs = LogCollector.Logs()
            logs.append(level: .error, message: "error", metadata: nil)
            return logs
        }
        
        do {
            // When calling archiveContents
            _ = try mockServices.mockPackager.archiveContents(for: ExamplePackage.executableOne,
                                             in: packageDirectory,
                                             services: mockServices)
            
            XCTFail("An error should have been thrown.")
        } catch PackagerError.archivingFailure(_) {
            // Then an error should be thrown
        } catch {
            XCTFail(error)
        }
    }
    func testArchiveContents_throwsWithMissingArchive() throws {
        // Given a successful zip where the archive gets deleted
        mockServices.mockShell.launchShell = { _ throws -> LogCollector.Logs in
            return LogCollector.Logs()
        }
        mockServices.mockFileManager.fileExists = { _ in return false }
        
        do {
            // When calling archiveContents
            _ = try mockServices.mockPackager.archiveContents(for: ExamplePackage.executableOne,
                                             in: packageDirectory,
                                             services: mockServices)
            
            XCTFail("An error should have been thrown.")
        } catch PackagerError.archiveNotFound(_) {
            // Then an error should be thrown
        } catch {
            XCTFail(error)
        }
    }
    
    func testCreateDestinationDirectory() {
        // This is a control function that simply calls other functions.
        // We test those functions separately. This is more for the code coverage.
        mockServices.mockFileManager.removeItem = { _ in }
        mockServices.mockFileManager.createDirectory = { _ in }
        
        XCTAssertNoThrow(try mockServices.mockPackager.createDestinationDirectory(URL(fileURLWithPath: ""), services: mockServices))
        XCTAssertEqual(mockServices.mockFileManager.$removeItem.usage.history.count, 1, "removeItem should have been called.")
        XCTAssertEqual(mockServices.mockFileManager.$createDirectory.usage.history.count, 1, "createDirectory should have been called.")
    }
    
    func testPrepareDestinationDirectory() {
        // This is a control function that simply calls other functions.
        // We test those functions separately. This is more for the code coverage.
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
        // We test those functions separately. This is more for the code coverage.
        mockServices.mockPackager.createDestinationDirectory = { _ in }
        mockServices.mockPackager.prepareDestinationDirectory = { _ in }
        mockServices.mockPackager.archiveContents = { _ throws in return URL(fileURLWithPath: "file.zip") }
        
        XCTAssertNoThrow(try mockServices.mockPackager.packageExecutable("", at: URL(fileURLWithPath: ""), services: mockServices))
        XCTAssertEqual(mockServices.mockPackager.$createDestinationDirectory.usage.history.count, 1, "createDestinationDirectory should have been called.")
        XCTAssertEqual(mockServices.mockPackager.$prepareDestinationDirectory.usage.history.count, 1, "prepareDestinationDirectory should have been called.")
        XCTAssertEqual(mockServices.mockPackager.$archiveContents.usage.history.count, 1, "archiveContents should have been called.")
    }
}