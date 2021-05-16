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
    
    var instance = BuildInDocker()
    var services = TestServices()
    
    override func setUp() {
        instance = BuildInDocker()
        services = TestServices()
        ShellExecutor.shellOutAction = { (_, _, _) throws -> LogCollector.Logs in
            return .stubMessage(level: .trace, message: "/path/to/app.zip")
        }
    }
    override func tearDownWithError() throws {
        try super.tearDownWithError()
        ShellExecutor.resetAction()
        try cleanupTestPackage()
    }
    
    func testPrepareDockerImage() throws {
        // Given an a valid package with a Dockerfile
        let path = try createTempPackage()
        let dockerFile = URL(string: path)!.appendingPathComponent("Dockerfile")

        // When calling prepareDockerImage
        _ = try instance.prepareDockerImage(at: dockerFile.absoluteString, logger: services.logger)

        // Then the correct command should be issued
        let message = services.logCollector.logs.allMessages()
//        XCTAssertString(message, contains: "/bin/bash -c")
        XCTAssertString(message, contains: "export PATH")
        XCTAssertString(message, contains: "/usr/local/bin/")
        XCTAssertString(message, contains: "/usr/local/bin/docker build --file \(dockerFile.absoluteString) . -t \(BuildInDocker.DockerConfig.containerName)")
        XCTAssertString(message, contains: "--no-cache")
    }
    func testPrepareDockerImageHandlesInvalidDockerfilePath() throws {
        // Given an invalid path to a dockerfile
        let path = "invalid"

        do {
            // When calling prepareDockerImage
            _ = try instance.prepareDockerImage(at:path, logger: services.logger)
        
        } catch BuildInDockerError.invalidDockerfilePath(_) {
            // Then BuildInDockerError.invalidDockerfilePath should be thrown
        } catch {
            XCTFail(error)
        }
    }
    func testGetDefaultDockerfilePath() throws {
        // Given a package without a Dockerfile
        let path = try createTempPackage(includeSource: true, includeDockerfile: false)

        // When calling prepareDockerImage
        let result = try instance.getDockerfilePath(from: path, logger: services.logger)

        // Then a default Dockerfile should be used
        XCTAssertString(result, contains: "/tmp/")
        XCTAssertString(result, contains: "Dockerfile")
        let message = services.logCollector.logs.allMessages()
        XCTAssertString(message, contains: "Creating temporary Dockerfile")
    }
    func testGetProjectDockerfilePath() throws {
        // Given a package with a Dockerfile
        let path = try createTempPackage(includeSource: true, includeDockerfile: true)

        // When calling prepareDockerImage
        let result = try instance.getDockerfilePath(from: path, logger: services.logger)

        // Then the Dockerfile from the project should be used
        XCTAssertEqual(result, "\(path)/Dockerfile")
    }

    func testPackageProduct_returnsArchivePath() throws {
        // Live run within Docker
        ShellExecutor.resetAction() // Don't use the stub from setup
        // Given a valid package
        let path = try createTempPackage()

        // When calling buildAndPackage
        let result = try instance.buildAndPackageInDocker(product: ExamplePackage.executableOne,
                                                          at: path,
                                                          logger: services.logger)

        // Then an archive should be returned
        XCTAssertTrue(result.contains(ExamplePackage.executableOne), "Executable name: \(ExamplePackage.executableOne) should have been in the archive name: \(result)")
        XCTAssertTrue(result.contains(".zip"), ".zip should have been in the archive name: \(result)")
        XCTAssertTrue(result.components(separatedBy: "_").count == 3, "There should have been 3 parts in the archive name: \(result)")
    }

    func testBuildAndPackage_throwsWithUnexpectedResult() throws {
        // Given an unexpected shellOut result
        ShellExecutor.shellOutAction = { (_, _, _) throws -> LogCollector.Logs in
            return .stubMessage(level: .trace, message: "??")
        }
        // When calling buildAndPackage
        do {
            _ = try instance.buildAndPackageInDocker(product: "Example", at: ".", logger: AWSClient.loggingDisabled)

            XCTFail("An error should have been thrown.")
        } catch BuildInDockerError.archivePathNotReceived("Example") {
            // Then archiveNotFound should be thrown
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testBuildProductsThrowsWithMissingArchive() throws {
        // Setup
        let path = try createTempPackage()
        // Given an archive that doesn't exist after the build
        let archive = "invalid.zip"
        ShellExecutor.shellOutAction = { (_, _, _) throws -> LogCollector.Logs in
            return .stubMessage(level: .trace, message: archive) // Stub the result to return an archive but skip the actual building process
        }

        // When calling buildProduct
        do {
            _ = try instance.buildProducts([ExamplePackage.executableOne], at: path, logger: AWSClient.loggingDisabled)

            XCTFail("An error should have been thrown.")
        } catch BuildInDockerError.archiveNotFound(_) {
            // Then an error should be throw
        } catch {
            XCTFail(error)
        }
    }

    func testBuildProduct() throws {
        // Setup
        let path = try createTempPackage()
        // Given a valid package
        let instance = BuildInDocker()

        // When calling buildProduct
        _ = try instance.buildProductInDocker(ExamplePackage.executableOne, at: path, logger: services.logger)

        // Then the correct command should be issued
        let message = services.logCollector.logs.allMessages()
        XCTAssertString(message, contains: "/usr/local/bin/docker")
        XCTAssertString(message, contains: "run -i --rm -e TERM=dumb")
        XCTAssertString(message, contains: "-e GIT_TERMINAL_PROMPT=1")
        XCTAssertString(message, contains: "-v \(ExamplePackage.tempDirectory)/\(ExamplePackage.name):\(ExamplePackage.tempDirectory)/\(ExamplePackage.name)")
        XCTAssertString(message, contains: "-w \(ExamplePackage.tempDirectory)/\(ExamplePackage.name)")
        XCTAssertString(message, contains: BuildInDocker.DockerConfig.containerName)
        XCTAssertString(message, contains: "/usr/bin/bash -c \"swift build -c release --product \(ExamplePackage.executableOne)\"")
    }

    func testBuildProductWithPrivateKey() throws {
        // Setup
        let path = try createTempPackage()
        // Given an ssh key path
        let keyPath = "\(ExamplePackage.tempDirectory)/ssh/key"

        // When calling buildProduct with valid input and a private key
        _ = try instance.buildProductInDocker(ExamplePackage.executableOne,
                                                       at: path,
                                                       logger: services.logger,
                                                       sshPrivateKeyPath: keyPath)

        // Then the correct command should be issued and contain the key's path in a volume mount
        let message = services.logCollector.logs.allMessages()
        XCTAssertString(message, contains: "/usr/local/bin/docker")
        XCTAssertString(message, contains: "run -i --rm -e TERM=dumb")
        XCTAssertString(message, contains: "-e GIT_TERMINAL_PROMPT=1")
        XCTAssertString(message, contains: "-v \(ExamplePackage.tempDirectory)/\(ExamplePackage.name):\(ExamplePackage.tempDirectory)/\(ExamplePackage.name)")
        XCTAssertString(message, contains: "-w \(ExamplePackage.tempDirectory)/\(ExamplePackage.name)")
        XCTAssertString(message, contains: "-v \(keyPath):\(keyPath)")
        XCTAssertString(message, contains: BuildInDocker.DockerConfig.containerName)
        XCTAssertString(message, contains: "ssh-agent bash -c")
        XCTAssertString(message, contains: "ssh-add -c \(keyPath);")
        XCTAssertString(message, contains: "swift build -c release --product \(ExamplePackage.executableOne)")
    }
    func testBuildProductsHandlesInvalidDirectory() throws {
        // If there is no Swift package at the path, there should be a useful tip about it.
        // Given a invalid package path
        let path = "\(ExamplePackage.tempDirectory)/invalid"

        do {
            // When calling buildProductInDocker
            _ = try instance.buildProductInDocker(ExamplePackage.executableOne, at: path, logger: services.logger)

        } catch _ {
            // Then a suggestion about the path should be logged
            let message = services.logCollector.logs.allMessages()
            XCTAssertString(message, contains: "Did you specify a path to a Swift Package")
        }
    }

    func testPackageProduct() throws {
        // Given a valid package
        let path = try createTempPackage()

        // When calling packageProduct
        _ = try instance.packageProduct(ExamplePackage.executableOne, at: path, logger: services.logger)

        // Then the correct command should be issued
        let message = services.logCollector.logs.allMessages()
        XCTAssertString(message, contains: "/packageInDocker.sh \(ExamplePackage.tempDirectory)/\(ExamplePackage.name) \(ExamplePackage.executableOne)")
    }

    func testRunBundledScriptThrowsWithInvalidScript() {
        // Given an invalid script
        let script = "invalid.sh"

        do {
            // When calling run(script:)
            _ = try instance.runBundledScript(script, logger: AWSClient.loggingDisabled)

            XCTFail("An error should have been thrown.")
        } catch {
            // Then an error should be thrown
            XCTAssertEqual("\(error)", BuildInDockerError.scriptNotFound(script).description)
        }
    }
    
}
