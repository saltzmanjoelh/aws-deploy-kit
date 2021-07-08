//
//  BuilderTests.swift
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

class BuilderTests: XCTestCase {
    
    var mockServices: MockServices!
    
    override func setUp() {
        mockServices = MockServices()
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
        mockServices.mockShell.launchShell = { _ throws -> LogCollector.Logs in
            return .stubMessage(level: .trace, message: "")
        }

        // When calling prepareDockerImage
        _ = try mockServices.builder.prepareDockerImage(at: dockerFile, services: mockServices)

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
            _ = try mockServices.builder.prepareDockerImage(at: URL(fileURLWithPath: packageDirectory), services: mockServices)
        
            XCTFail("An error should have been thrown")
        } catch {
            // Then BuildInDockerError.invalidDockerfilePath should be thrown
            XCTAssertEqual("\(error)", DockerizedBuilderError.invalidDockerfilePath(URL(fileURLWithPath: packageDirectory).path).description)
        }
    }
    func testGetDefaultDockerfilePath() throws {
        // Given a package without a Dockerfile
        let path = try createTempPackage(includeSource: true, includeDockerfile: false)

        // When calling prepareDockerImage
        let result = try mockServices.builder.getDockerfilePath(from: path, services: mockServices)

        // Then a default Dockerfile should be used
        XCTAssertString(result.path, contains: "/tmp/aws-deploy")
        XCTAssertString(result.path, contains: "Dockerfile")
        let message = mockServices.logCollector.logs.allMessages()
        XCTAssertString(message, contains: "Creating temporary Dockerfile")
    }
    func testCreateTemporaryDockerfile() throws {
        // Given a valid environment
        mockServices.mockFileManager.createDirectory = { _ in }
        
        // When calling createTemporaryDockerfile
        let result = try mockServices.builder.createTemporaryDockerfile(services: mockServices)
        
        // Then a file URL is returned
        XCTAssertTrue(result.isFileURL)
        XCTAssertTrue(mockServices.mockFileManager.$removeItem.wasCalled)
        XCTAssertTrue(mockServices.mockFileManager.$createDirectory.wasCalled)
    }
    
    func testGetProjectDockerfilePath() throws {
        // Given a package with a Dockerfile
        let packageDirectory = try createTempPackage(includeSource: true, includeDockerfile: true)

        // When calling prepareDockerImage
        let result = try mockServices.builder.getDockerfilePath(from: packageDirectory, services: mockServices)

        // Then the Dockerfile from the project should be used
        XCTAssertEqual(result, packageDirectory.appendingPathComponent("Dockerfile"))
    }

    func testGetBuiltProductPath() throws {
        // Given a package
        let packageDirectory = URL(fileURLWithPath: "/tmp/package/")
        mockServices.mockFileManager.fileExists = { _ in return true }
        
        // When calling getBuiltProduct
        let result = try mockServices.builder.getBuiltProductPath(at: packageDirectory, for: "executable", services: mockServices)
        
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
            _ = try mockServices.builder.getBuiltProductPath(at: URL(fileURLWithPath: "/tmp"), for: "executable", services: mockServices)
            
            XCTFail("An error should have been thrown")
        } catch DockerizedBuilderError.builtProductNotFound(_) {
            // Then BuildInDockerError.builtProductNotFound should be thrown
        } catch {
            XCTFail(error)
        }
    }
    
    func testBuildProducts() throws {
        let packageDirectory = tempPackageDirectory()
        let sshKey = "/path/to/key"
        let executable = Builder.URLForBuiltExecutable(ExamplePackage.executableOne, at: packageDirectory, services: self.mockServices)
        let archive = mockServices.packager.archivePath(for: executable.lastPathComponent, in: packageDirectory)
        mockServices.mockBuilder.getDockerfilePath = { _ in return URL(fileURLWithPath: "/tmp").appendingPathComponent("Dockerfile") }
        mockServices.mockBuilder.prepareDockerImage = { _ in return .init() }
        mockServices.mockBuilder.buildProduct = { _ in
            return executable
        }
        mockServices.mockPackager.packageExecutable = { _ in archive }
        
        let result = try mockServices.builder.buildProducts([ExamplePackage.executableOne], at: packageDirectory, skipProducts: "", sshPrivateKeyPath: sshKey, services: mockServices)
        
        XCTAssertEqual([archive], result)
        XCTAssertTrue(mockServices.mockBuilder.$getDockerfilePath.wasCalled)
        XCTAssertTrue(mockServices.mockBuilder.$prepareDockerImage.wasCalled)
        XCTAssertTrue(mockServices.mockBuilder.$buildProduct.wasCalled)
        XCTAssertTrue(mockServices.mockPackager.$packageExecutable.wasCalled)
        XCTAssertEqual(mockServices.mockBuilder.$buildProduct.usage.history[0].context.3, URL(fileURLWithPath: sshKey), "The supplied ssh key should have been passed to buildProduct as an URL")
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
            _ = try mockServices.builder.buildProducts([ExamplePackage.executableOne], at: packageDirectory, skipProducts: "", sshPrivateKeyPath: nil, services: mockServices)

            XCTFail("An error should have been thrown.")
        } catch DockerizedBuilderError.builtProductNotFound(_) {
            // Then an error should be throw
        } catch {
            XCTFail(error)
        }
    }
    
    func testBuildProduct() throws {
        let packageDirectory = tempPackageDirectory()
        let buildDir = Builder.URLForBuiltExecutable(ExamplePackage.executableOne, at: packageDirectory, services: mockServices)
        mockServices.mockBuilder.preBuildCommand = "ls -al"
        mockServices.mockBuilder.postBuildCommand = "ls -al"
        mockServices.mockBuilder.executeShellCommand = { _ in }
        mockServices.mockBuilder.buildProductInDocker = { _ in return .init() }
        mockServices.mockBuilder.getBuiltProductPath = { _ in return buildDir }
        
        XCTAssertNoThrow(try mockServices.builder.buildProduct(ExamplePackage.executableOne, at: packageDirectory, services: mockServices, sshPrivateKeyPath: nil))
        
        XCTAssertTrue(mockServices.mockBuilder.$executeShellCommand.wasCalled)
        XCTAssertEqual(mockServices.mockBuilder.$executeShellCommand.usage.history.count, 2, "executeShellCommand should have been called twice. Once for the pre-build command and once for the post-build command.")
        XCTAssertTrue(mockServices.mockBuilder.$buildProductInDocker.wasCalled)
        XCTAssertTrue(mockServices.mockBuilder.$getBuiltProductPath.wasCalled)
    }

    func testBuildProductInDocker() throws {
        // Given a valid package
        let packageDirectory = try createTempPackage()
        mockServices.mockShell.launchShell = { _ throws -> LogCollector.Logs in
            return .stubMessage(level: .trace, message: "/path/to/app.zip")
        }

        // When calling buildProduct
        _ = try mockServices.builder.buildProductInDocker(ExamplePackage.executableOne, at: packageDirectory, services: mockServices, sshPrivateKeyPath: nil)

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

    func testBuildProductInDockerWithPrivateKey() throws {
        // Setup
        let packageDirectory = try createTempPackage()
        // Given an ssh key path
        let keyPath = URL(fileURLWithPath: "\(ExamplePackage.tempDirectory)/ssh/key")
        mockServices.mockShell.launchShell = { _ -> LogCollector.Logs in
            return .init()
        }

        // When calling buildProduct with valid input and a private key
        _ = try mockServices.builder.buildProductInDocker(ExamplePackage.executableOne,
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
            _ = try mockServices.builder.buildProductInDocker(ExamplePackage.executableOne, at: packageDirectory, services: mockServices, sshPrivateKeyPath: nil)

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
        try mockServices.builder.executeShellCommand(command, for: ExamplePackage.executableOne, at: path, services: mockServices)
        
        // Then the shell should be called with the command
        XCTAssertTrue(mockServices.mockShell.$launchShell.wasCalled)
        XCTAssertTrue(mockServices.mockShell.$launchShell.wasCalled(with: command), "Shell was not executed with \(command). Here is the history: \(mockServices.mockShell.$launchShell.usage.history.map({ $0.context }))")
    }
    func testExecuteShellCommandHandlesEmptyString() throws {
        // Given an empty preBuild command
        let command = ""
        let path =  tempPackageDirectory()
        
        // When calling executeShellCommand
        try mockServices.builder.executeShellCommand(command, for: ExamplePackage.executableOne, at: path, services: mockServices)
        
        // Then the shell should NOT be called
        XCTAssertFalse(mockServices.mockShell.$launchShell.wasCalled)
    }
    
    func testValidateProducts_logsWhenSkippingProducts() throws {
        // Given a product to skip
        let skipProducts = ExamplePackage.executableThree
        let packageDirectory = try createTempPackage()

        // When calling verifyConfiguration
        _ = try mockServices.builder.validateProducts([], skipProducts: skipProducts, at: packageDirectory, services: mockServices)

        // Then a "Skipping $PRODUCT" log should be received
        let messages = mockServices.logCollector.logs.allMessages()
        XCTAssertString(messages, contains: "Skipping: \(ExamplePackage.executableThree)")
    }
    func testVerifyConfiguration_throwsWithMissingProducts() throws {
        // Given a package without any executables
        let packageDirectory = URL(fileURLWithPath: "/invalid")
        mockServices.mockShell.launchShell = { _ throws -> LogCollector.Logs in
            let packageManifest = "{\"products\" : []}" // Result of an empty package
            return .stubMessage(level: .trace, message: packageManifest)
        }

        do {
            // When calling validateProducts
            _ = try mockServices.builder.validateProducts([], skipProducts: "", at: packageDirectory, services: mockServices)

            XCTFail("An error should have been thrown.")
        } catch DockerizedBuilderError.missingProducts {
            // Then the DockerizedBuilderError.missingProducts error should be thrown
        } catch {
            XCTFail(String(describing: error))
        }
    }

    func testGetProducts() throws {
        // Given a package with a library and multiple executables
        let packageDirectory = try createTempPackage()

        // When calling getProducts
        let result = try mockServices.builder.getProducts(at: packageDirectory, type: .executable, services: mockServices)

        // Then all executables should be returned
        XCTAssertEqual(result.count, ExamplePackage.executables.count)
    }
    func testGetProductsThrowsWithInvalidShellOutput() throws {
        // Give a failed shell output
        mockServices.mockShell.launchShell = { _ throws -> LogCollector.Logs in
            return .stubMessage(level: .trace, message: "")
        }

        // When calling getProducts
        do {
            _ = try mockServices.builder.getProducts(at: URL(fileURLWithPath: ""), type: .executable, services: mockServices)

            XCTFail("An error should have been thrown.")
        } catch {
            // Then DockerizedBuilderError.packageDumpFailure is thrown
            XCTAssertEqual("\(error)", DockerizedBuilderError.packageDumpFailure.description)
        }
    }

    func testRemoveSkippedProducts() {
        // Given a list of skipProducts for a process
        let skipProducts = ExamplePackage.executableThree
        let processName = ExamplePackage.executableTwo // Simulating that executableTwo is the executable that does the deployment

        // When calling removeSkippedProducts
        let result = Builder.removeSkippedProducts(skipProducts,
                                                             from: ExamplePackage.executables,
                                                             logger: mockServices.logger,
                                                             processName: processName)

        // Then the remaining products should not contain the skipProducts
        XCTAssertFalse(result.contains(skipProducts), "The \"skipProducts\": \(skipProducts) should have been removed.")
        // or a product with a matching processName
        XCTAssertFalse(result.contains(processName), "The \"processName\": \(processName) should have been removed.")
    }
}
