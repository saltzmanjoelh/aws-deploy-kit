//
//  BuildInDockerTests.swift
//
//
//  Created by Joel Saltzman on 3/25/21.
//

@testable import AWSDeployCore
import Foundation
import Logging
import LogKit
import SotoCore
import XCTest
import Mocking

class BuildInDockerTests: XCTestCase {
    
    var instance: BuildInDocker!
    var mockServices: MockServices!
    
    override func setUp() {
        instance = BuildInDocker()
        mockServices = MockServices()
        mockServices.mockShell.launchShell = { _ throws -> LogCollector.Logs in
            return .stubMessage(level: .trace, message: "/path/to/app.zip")
        }
    }
    override func tearDownWithError() throws {
        try super.tearDownWithError()
        mockServices.cleanup()
        try cleanupTestPackage()
    }
    
    func testPrepareDockerImage() throws {
        // Given an a valid package with a Dockerfile
        let packageDirectory = tempPackageDirectory()
        let dockerFile = packageDirectory.appendingPathComponent("Dockerfile")

        // When calling prepareDockerImage
        _ = try instance.prepareDockerImage(at: dockerFile, services: mockServices)

        // Then the correct command should be issued
        XCTAssertTrue(mockServices.mockShell.$launchShell.wasCalled)
//        let message = testServices.mockShell.$launchBash.wasCalled
//        XCTAssertString(message, contains: "/usr/local/bin/docker build --file \(dockerFile.path) . -t \(Docker.Config.containerName)")
//        XCTAssertString(message, contains: "--no-cache")
    }
    func testPrepareDockerImageHandlesInvalidDockerfilePath() throws {
        // Given an invalid path to a dockerfile
        let packageDirectory = "/invalid"

        do {
            // When calling prepareDockerImage
            _ = try instance.prepareDockerImage(at: URL(fileURLWithPath: packageDirectory), services: mockServices)
        
            XCTFail("An error should have been thrown")
        } catch {
            // Then BuildInDockerError.invalidDockerfilePath should be thrown
            XCTAssertEqual("\(error)", BuildInDockerError.invalidDockerfilePath(URL(fileURLWithPath: packageDirectory).path).description)
        }
    }
    func testGetDefaultDockerfilePath() throws {
        // Given a package without a Dockerfile
        let path = try createTempPackage(includeSource: true, includeDockerfile: false)

        // When calling prepareDockerImage
        let result = try instance.getDockerfilePath(from: path, services: mockServices)

        // Then a default Dockerfile should be used
        XCTAssertString(result.path, contains: "/tmp/")
        XCTAssertString(result.path, contains: "Dockerfile")
        let message = mockServices.logCollector.logs.allMessages()
        XCTAssertString(message, contains: "Creating temporary Dockerfile")
    }
    func testGetProjectDockerfilePath() throws {
        // Given a package with a Dockerfile
        let packageDirectory = try createTempPackage(includeSource: true, includeDockerfile: true)

        // When calling prepareDockerImage
        let result = try instance.getDockerfilePath(from: packageDirectory, services: mockServices)

        // Then the Dockerfile from the project should be used
        XCTAssertEqual(result, packageDirectory.appendingPathComponent("Dockerfile"))
    }

    func testGetBuiltProductPath() throws {
        // Given a package
        let packageDirectory = URL(fileURLWithPath: "/tmp/package/")
        mockServices.mockFileManager.fileExists = { _ in return true }
        
        // When calling getBuiltProduct
        let result = try instance.getBuiltProductPath(at: packageDirectory, for: "executable", services: mockServices)
        
        // Then the archive path is returned
        XCTAssertEqual(result, packageDirectory
                        .appendingPathComponent(".build")
                        .appendingPathComponent("release")
                        .appendingPathComponent("executable"))
    }
    func testGetBuiltProductPath_handlesMissingFile() throws {
        // Given the path to a built product that doesn't exist
        mockServices.mockFileManager.fileExists = { _ in return false }
        
        // When calling getBuiltProduct
        do {
            _ = try instance.getBuiltProductPath(at: URL(fileURLWithPath: "/tmp"), for: "executable", services: mockServices)
            
            XCTFail("An error should have been thrown")
        } catch BuildInDockerError.builtProductNotFound(_) {
            // Then BuildInDockerError.builtProductNotFound should be thrown
        } catch {
            XCTFail(error)
        }
    }

    func testBuildProducts() throws {
        // This is a control function that simply calls other functions.
        // We test those functions separately. This is more for the code coverage.
        // Given a successful build
        let archiveURL = URL(fileURLWithPath: "archive.zip")
        mockServices.mockBuilder.preBuildCommand = "ls -al"
        mockServices.mockBuilder.postBuildCommand = "ls -al"
        mockServices.mockBuilder.getDockerfilePath = { _ in return URL(fileURLWithPath: "/tmp").appendingPathComponent("Dockerfile") }
        mockServices.mockBuilder.prepareDockerImage = { _ in return .init() }
        mockServices.mockBuilder.executeShellCommand = { _ in }
        mockServices.mockBuilder.buildProduct = { _ in return .init() }
        mockServices.mockBuilder.getBuiltProductPath = { _ in return archiveURL }
        
        XCTAssertNoThrow(try instance.buildProducts([ExamplePackage.executableOne], at: tempPackageDirectory(), services: mockServices))
        XCTAssertTrue(mockServices.mockBuilder.$getDockerfilePath.wasCalled)
        XCTAssertTrue(mockServices.mockBuilder.$prepareDockerImage.wasCalled)
        XCTAssertTrue(mockServices.mockBuilder.$executeShellCommand.wasCalled)
        XCTAssertEqual(mockServices.mockBuilder.$executeShellCommand.usage.history.count, 2, "executeShellCommand should have been called twice. Once for the pre-build command and once for the post-build command.")
        XCTAssertTrue(mockServices.mockBuilder.$buildProduct.wasCalled)
        XCTAssertTrue(mockServices.mockBuilder.$getBuiltProductPath.wasCalled)
    }
    
    func testBuildProductsThrowsWithMissingProduct() throws {
        // Setup
        let packageDirectory = try createTempPackage()
        // Given an archive that doesn't exist after the build
        let archive = "invalid.zip"
        mockServices.mockShell.launchShell = { _ throws -> LogCollector.Logs in
            return .stubMessage(level: .trace, message: archive) // Stub the result to return an archive but skip the actual building process
        }

        // When calling buildProduct
        do {
            _ = try instance.buildProducts([ExamplePackage.executableOne], at: packageDirectory, services: mockServices)

            XCTFail("An error should have been thrown.")
        } catch BuildInDockerError.builtProductNotFound(_) {
            // Then an error should be throw
        } catch {
            XCTFail(error)
        }
    }

    func testBuildProduct() throws {
        // Setup
        let packageDirectory = try createTempPackage()
        // Given a valid package
        let instance = BuildInDocker()

        // When calling buildProduct
        _ = try instance.buildProduct(ExamplePackage.executableOne, at: packageDirectory, services: mockServices)

        // Then the correct command should be issued
        let message = mockServices.logCollector.logs.allMessages()
        XCTAssertString(message, contains: "/usr/local/bin/docker")
        XCTAssertString(message, contains: "run -i --rm -e TERM=dumb")
        XCTAssertString(message, contains: "-e GIT_TERMINAL_PROMPT=1")
        XCTAssertString(message, contains: "-v \(ExamplePackage.tempDirectory)/\(ExamplePackage.name):\(ExamplePackage.tempDirectory)/\(ExamplePackage.name)")
        XCTAssertString(message, contains: "-w \(ExamplePackage.tempDirectory)/\(ExamplePackage.name)")
        XCTAssertString(message, contains: Docker.Config.containerName)
        XCTAssertString(message, contains: "/usr/bin/bash -c \"swift build -c release --product \(ExamplePackage.executableOne)\"")
    }

    func testBuildProductWithPrivateKey() throws {
        // Setup
        let packageDirectory = try createTempPackage()
        // Given an ssh key path
        let keyPath = URL(fileURLWithPath: "\(ExamplePackage.tempDirectory)/ssh/key")

        // When calling buildProduct with valid input and a private key
        _ = try instance.buildProduct(ExamplePackage.executableOne,
                                      at: packageDirectory,
                                      services: mockServices,
                                      sshPrivateKeyPath: keyPath)

        // Then the correct command should be issued and contain the key's path in a volume mount
        let message = mockServices.logCollector.logs.allMessages()
        XCTAssertString(message, contains: "/usr/local/bin/docker")
        XCTAssertString(message, contains: "run -i --rm -e TERM=dumb")
        XCTAssertString(message, contains: "-e GIT_TERMINAL_PROMPT=1")
        XCTAssertString(message, contains: "-v \(ExamplePackage.tempDirectory)/\(ExamplePackage.name):\(ExamplePackage.tempDirectory)/\(ExamplePackage.name)")
        XCTAssertString(message, contains: "-w \(ExamplePackage.tempDirectory)/\(ExamplePackage.name)")
        XCTAssertString(message, contains: "-v \(keyPath.path):\(keyPath.path)")
        XCTAssertString(message, contains: Docker.Config.containerName)
        XCTAssertString(message, contains: "ssh-agent bash -c")
        XCTAssertString(message, contains: "ssh-add -c \(keyPath.path);")
        XCTAssertString(message, contains: "swift build -c release --product \(ExamplePackage.executableOne)")
    }
    func testBuildProductHandlesInvalidDirectory() throws {
        // If there is no Swift package at the path, there should be a useful tip about it.
        // Given a invalid package path
        let packageDirectory = URL(fileURLWithPath: "/tmp")
        mockServices.mockShell.launchShell = { _ throws -> LogCollector.Logs in
            throw ShellOutError.init(terminationStatus: 127, output: "root manifest not found")
        }

        do {
            // When calling buildProductInDocker
            _ = try instance.buildProduct(ExamplePackage.executableOne, at: packageDirectory, services: mockServices)

            XCTFail("An error should have been thrown.")
        } catch _ {
            // Then a suggestion about the path should be logged
            let message = mockServices.logCollector.logs.allMessages()
            XCTAssertString(message, contains: "Did you specify a path to a Swift Package")
        }
    }
    
    func testExecuteShellCommand() throws {
        // Given a preBuild command
        let command = "ls -al"
        let path =  tempPackageDirectory()
        
        // When calling executeShellCommand
        try instance.executeShellCommand(command, for: ExamplePackage.executableOne, at: path, services: mockServices)
        
        // Then the shell should be called with the command
        XCTAssertTrue(mockServices.mockShell.$launchShell.wasCalled)
        XCTAssertTrue(mockServices.mockShell.$launchShell.wasCalled(with: command), "Shell was not executed with \(command). Here is the history: \(mockServices.mockShell.$launchShell.usage.history.map({ $0.context }))")
    }
    func testExecuteShellCommandHandlesEmptyString() throws {
        // Given an empty preBuild command
        let command = ""
        let path =  tempPackageDirectory()
        
        // When calling executeShellCommand
        try instance.executeShellCommand(command, for: ExamplePackage.executableOne, at: path, services: mockServices)
        
        // Then the shell should NOT be called
        XCTAssertFalse(mockServices.mockShell.$launchShell.wasCalled)
    }
}
