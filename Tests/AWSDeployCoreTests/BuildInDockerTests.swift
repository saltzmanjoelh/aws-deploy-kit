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

class BuildInDockerTests: XCTestCase {
    
    var instance: BuildInDocker!
    var testServices: TestServices!
    
    override func setUp() {
        instance = BuildInDocker()
        testServices = TestServices()
        testServices.mockShell.launchBash = { _ throws -> LogCollector.Logs in
            return .stubMessage(level: .trace, message: "/path/to/app.zip")
        }
    }
    override func tearDownWithError() throws {
        try super.tearDownWithError()
        testServices.cleanup()
        try cleanupTestPackage()
    }
    
    func testPrepareDockerImage() throws {
        // Given an a valid package with a Dockerfile
        let packageDirectory = tempPackageDirectory()
        let dockerFile = packageDirectory.appendingPathComponent("Dockerfile")

        // When calling prepareDockerImage
        _ = try instance.prepareDockerImage(at: dockerFile, services: testServices)

        // Then the correct command should be issued
        XCTAssertTrue(testServices.mockShell.$launchBash.wasCalled)
//        let message = testServices.mockShell.$launchBash.wasCalled
//        XCTAssertString(message, contains: "/usr/local/bin/docker build --file \(dockerFile.path) . -t \(Docker.Config.containerName)")
//        XCTAssertString(message, contains: "--no-cache")
    }
    func testPrepareDockerImageHandlesInvalidDockerfilePath() throws {
        // Given an invalid path to a dockerfile
        let packageDirectory = "invalid"

        do {
            // When calling prepareDockerImage
            _ = try instance.prepareDockerImage(at: URL(fileURLWithPath: packageDirectory), services: testServices)
        
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
        let result = try instance.getDockerfilePath(from: path, services: testServices)

        // Then a default Dockerfile should be used
        XCTAssertString(result.path, contains: "/tmp/")
        XCTAssertString(result.path, contains: "Dockerfile")
        let message = testServices.logCollector.logs.allMessages()
        XCTAssertString(message, contains: "Creating temporary Dockerfile")
    }
    func testGetProjectDockerfilePath() throws {
        // Given a package with a Dockerfile
        let packageDirectory = try createTempPackage(includeSource: true, includeDockerfile: true)

        // When calling prepareDockerImage
        let result = try instance.getDockerfilePath(from: packageDirectory, services: testServices)

        // Then the Dockerfile from the project should be used
        XCTAssertEqual(result, packageDirectory.appendingPathComponent("Dockerfile"))
    }

    func testGetBuiltProductPath() throws {
        // Given a package
        let packageDirectory = URL(fileURLWithPath: "/tmp/package/")
        testServices.mockFileManager.fileExists = { _ in return true }
        
        // When calling getBuiltProduct
        let result = try instance.getBuiltProductPath(at: packageDirectory, for: "executable", services: testServices)
        
        // Then the archive path is returned
        XCTAssertEqual(result, packageDirectory
                        .appendingPathComponent(".build")
                        .appendingPathComponent("release")
                        .appendingPathComponent("executable"))
    }
    func testGetBuiltProductPath_handlesMissingFile() throws {
        // Given the path to a built product that doesn't exist
        testServices.mockFileManager.fileExists = { _ in return false }
        
        // When calling getBuiltProduct
        do {
            _ = try instance.getBuiltProductPath(at: URL(fileURLWithPath: "/tmp"), for: "executable", services: testServices)
            
            XCTFail("An error should have been thrown")
        } catch BuildInDockerError.builtProductNotFound(_) {
            // Then BuildInDockerError.builtProductNotFound should be thrown
        } catch {
            XCTFail(error)
        }
    }

    func testBuildProductsThrowsWithMissingProduct() throws {
        // Setup
        let packageDirectory = try createTempPackage()
        // Given an archive that doesn't exist after the build
        let archive = "invalid.zip"
        testServices.mockShell.launchBash = { _ throws -> LogCollector.Logs in
            return .stubMessage(level: .trace, message: archive) // Stub the result to return an archive but skip the actual building process
        }

        // When calling buildProduct
        do {
            _ = try instance.buildProducts([ExamplePackage.executableOne], at: packageDirectory, services: testServices)

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
        _ = try instance.buildProduct(ExamplePackage.executableOne, at: packageDirectory, services: testServices)

        // Then the correct command should be issued
        let message = testServices.logCollector.logs.allMessages()
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
                                      services: testServices,
                                      sshPrivateKeyPath: keyPath)

        // Then the correct command should be issued and contain the key's path in a volume mount
        let message = testServices.logCollector.logs.allMessages()
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
        let packageDirectory = URL(fileURLWithPath: "\(ExamplePackage.tempDirectory)/invalid")

        do {
            // When calling buildProductInDocker
            _ = try instance.buildProduct(ExamplePackage.executableOne, at: packageDirectory, services: testServices)

        } catch _ {
            // Then a suggestion about the path should be logged
            let message = testServices.logCollector.logs.allMessages()
            XCTAssertString(message, contains: "Did you specify a path to a Swift Package")
        }
    }
    
}
