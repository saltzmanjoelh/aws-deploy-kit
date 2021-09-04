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
        mockServices.mockFileManager.createDirectoryMock = { _ in }
        
        // When calling createTemporaryDockerfile
        let result = try mockServices.builder.createTemporaryDockerfile(services: mockServices)
        
        // Then a file URL is returned
        XCTAssertTrue(result.isFileURL)
        XCTAssertTrue(mockServices.mockFileManager.$removeItemMock.wasCalled)
        XCTAssertTrue(mockServices.mockFileManager.$createDirectoryMock.wasCalled)
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
        mockServices.mockFileManager.fileExistsMock = { _ in return true }
        
        // When calling getBuiltProduct
        let result = try mockServices.builder.getBuiltProductPath(product: ExamplePackage.executableOne, at: packageDirectory, services: mockServices)
        
        // Then the archive path is returned
        XCTAssertEqual(result, packageDirectory
                        .appendingPathComponent(".build")
                        .appendingPathComponent("release")
                        .appendingPathComponent(ExamplePackage.executableOne.name))
    }
    func testGetBuiltProductPath_handlesMissingFile() throws {
        // Given the path to a built product that doesn't exist
        mockServices.mockFileManager.fileExistsMock = { _ in return false }
        
        // When calling getBuiltProduct
        do {
            _ = try mockServices.builder.getBuiltProductPath(product: ExamplePackage.executableOne, at: URL(fileURLWithPath: "/tmp"), services: mockServices)
            
            XCTFail("An error should have been thrown")
        } catch DockerizedBuilderError.builtProductNotFound(_) {
            // Then BuildInDockerError.builtProductNotFound should be thrown
        } catch {
            XCTFail(error)
        }
    }
    
    func testBuildProducts() throws {
        let packageDirectory = tempPackageDirectory()
        let executableURL = Builder.URLForBuiltProduct(ExamplePackage.executableOne, at: packageDirectory, services: self.mockServices)
        let archive = mockServices.packager.archivePath(for: ExamplePackage.executableOne, in: packageDirectory)
        mockServices.mockBuilder.getDockerfilePath = { _ in return URL(fileURLWithPath: "/tmp").appendingPathComponent("Dockerfile") }
        mockServices.mockBuilder.prepareDockerImage = { _ in return .init() }
        mockServices.mockBuilder.buildProduct = { _ in
            return executableURL
        }
        mockServices.mockPackager.packageProduct = { _ in archive }
        
        let result = try mockServices.builder.buildProducts([ExamplePackage.executableOne], at: packageDirectory, services: mockServices)
        
        XCTAssertEqual([archive], result)
        XCTAssertTrue(mockServices.mockBuilder.$getDockerfilePath.wasCalled)
        XCTAssertTrue(mockServices.mockBuilder.$prepareDockerImage.wasCalled)
        XCTAssertTrue(mockServices.mockBuilder.$buildProduct.wasCalled)
        XCTAssertTrue(mockServices.mockPackager.$packageProduct.wasCalled)
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
            _ = try mockServices.builder.buildProducts([ExamplePackage.executableOne], at: packageDirectory, services: mockServices)

            XCTFail("An error should have been thrown.")
        } catch DockerizedBuilderError.builtProductNotFound(_) {
            // Then an error should be throw
        } catch {
            XCTFail(error)
        }
    }
    
    func testBuildProduct() throws {
        let packageDirectory = tempPackageDirectory()
        let buildDir = Builder.URLForBuiltProduct(ExamplePackage.executableOne, at: packageDirectory, services: mockServices)
        mockServices.mockBuilder.preBuildCommand = "ls -al"
        mockServices.mockBuilder.postBuildCommand = "ls -al"
        mockServices.mockBuilder.executeShellCommand = { _ in }
        mockServices.mockBuilder.buildProductInDocker = { _ in return .init() }
        mockServices.mockBuilder.getBuiltProductPath = { _ in return buildDir }
        
        XCTAssertNoThrow(try mockServices.builder.buildProduct(ExamplePackage.executableOne, at: packageDirectory, services: mockServices))
        
        XCTAssertTrue(mockServices.mockBuilder.$executeShellCommand.wasCalled)
        XCTAssertEqual(mockServices.mockBuilder.$executeShellCommand.usage.history.count, 2, "executeShellCommand should have been called twice. Once for the pre-build command and once for the post-build command.")
        XCTAssertTrue(mockServices.mockBuilder.$buildProductInDocker.wasCalled)
        XCTAssertTrue(mockServices.mockBuilder.$getBuiltProductPath.wasCalled)
    }

    func testBuildExecutableInDocker() throws {
        // Given a valid executable
        let packageDirectory = try createTempPackage()
        mockServices.mockShell.launchShell = { _ throws -> LogCollector.Logs in
            return .stubMessage(level: .trace, message: "/path/to/app.zip")
        }
        mockServices.mockFileManager.fileExistsMock = { _ in return false } // no .ssh directory

        // When calling buildProduct
        _ = try mockServices.builder.buildProductInDocker(ExamplePackage.executableOne, at: packageDirectory, services: mockServices)

        // Then the correct command should be issued
        let message = mockServices.logCollector.logs.allMessages()
        XCTAssertString(message, contains: "/usr/local/bin/docker")
        XCTAssertString(message, contains: "run -it --rm -e TERM=dumb")
        XCTAssertString(message, contains: "-e GIT_TERMINAL_PROMPT=1")
        XCTAssertString(message, contains: "-v \(ExamplePackage.tempDirectory)/\(ExamplePackage.name):\(ExamplePackage.tempDirectory)/\(ExamplePackage.name)")
        XCTAssertString(message, contains: "-w \(ExamplePackage.tempDirectory)/\(ExamplePackage.name)")
        XCTAssertString(message, contains: Docker.Config.containerName)
        XCTAssertString(message, contains: "/usr/bin/bash -c \"swift build -c release --product \(ExamplePackage.executableOne.name)\"")
    }
    func testBuildLibraryInDocker() throws {
        // Given a valid library
        let packageDirectory = try createTempPackage()
        mockServices.mockShell.launchShell = { _ throws -> LogCollector.Logs in
            return .stubMessage(level: .trace, message: "/path/to/app.zip")
        }
        mockServices.mockFileManager.fileExistsMock = { _ in return false } // no .ssh directory

        // When calling buildProduct
        _ = try mockServices.builder.buildProductInDocker(ExamplePackage.library, at: packageDirectory, services: mockServices)

        // Then the correct command should be issued
        let message = mockServices.logCollector.logs.allMessages()
        XCTAssertString(message, contains: "/usr/local/bin/docker")
        XCTAssertString(message, contains: "run -it --rm -e TERM=dumb")
        XCTAssertString(message, contains: "-e GIT_TERMINAL_PROMPT=1")
        XCTAssertString(message, contains: "-v \(ExamplePackage.tempDirectory)/\(ExamplePackage.name):\(ExamplePackage.tempDirectory)/\(ExamplePackage.name)")
        XCTAssertString(message, contains: "-w \(ExamplePackage.tempDirectory)/\(ExamplePackage.name)")
        XCTAssertString(message, contains: Docker.Config.containerName)
        XCTAssertString(message, contains: "/usr/bin/bash -c \"swift build -c release --target \(ExamplePackage.library.name)\"")
    }

    func testBuildProductInDockerWithSSHDirectoryAvailable() throws {
        // Setup
        let packageDirectory = try createTempPackage()
        // Given a user with a .ssh directory
        mockServices.mockShell.launchShell = { _ -> LogCollector.Logs in
            return .init()
        }
        mockServices.mockFileManager.usersHomeDirectoryMock = { _ in
            return URL(fileURLWithPath: "/Users/janedoe/")
        }
        mockServices.mockFileManager.fileExistsMock = { _ in
            return true
        }

        // When calling buildProduct with valid input and a private key
        _ = try mockServices.builder.buildProductInDocker(ExamplePackage.executableOne,
                                      at: packageDirectory,
                                      services: mockServices)

        // Then the correct command should be issued and contain the key's path in a volume mount
        let message = mockServices.logCollector.logs.allMessages()
        XCTAssertString(message, contains: "/usr/local/bin/docker")
        XCTAssertString(message, contains: "run -it --rm -e TERM=dumb")
        XCTAssertString(message, contains: "-e GIT_TERMINAL_PROMPT=1")
        XCTAssertString(message, contains: "-v \(ExamplePackage.tempDirectory)/\(ExamplePackage.name):\(ExamplePackage.tempDirectory)/\(ExamplePackage.name)")
        XCTAssertString(message, contains: "-w \(ExamplePackage.tempDirectory)/\(ExamplePackage.name)")
        XCTAssertString(message, contains: "-v /Users/janedoe/.ssh:/Users/janedoe/.ssh")
        XCTAssertString(message, contains: Docker.Config.containerName)
        XCTAssertString(message, contains: "ssh-agent bash -c \"")
        // Make the .ssh directory
        XCTAssertString(message, contains: "mkdir -p ~/.ssh/")
        // Copy the .ssh contents
        XCTAssertString(message, contains: "cp /Users/janedoe/.ssh/* ~/.ssh/")
        XCTAssertString(message, contains: "swift build -c release --product \(ExamplePackage.executableOne.name)\"")
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
            _ = try mockServices.builder.buildProductInDocker(ExamplePackage.executableOne, at: packageDirectory, services: mockServices)

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
    
    func testParseProducts_logsWhenSkippingProducts() throws {
        // Given a product to skip
        let skipProducts = ExamplePackage.executableThree.name
        let packageDirectory = try createTempPackage()
        mockServices.mockBuilder.loadProducts = { _ in return ExamplePackage.products }

        // When calling parseProducts
        _ = try mockServices.builder.parseProducts([], skipProducts: skipProducts, at: packageDirectory, services: mockServices)

        // Then a "Skipping $PRODUCT" log should be received
        let messages = mockServices.logCollector.logs.allMessages()
        XCTAssertString(messages, contains: "Skipping: \(ExamplePackage.executableThree.name)")
    }
    func testVerifyConfiguration_throwsWithMissingProducts() throws {
        // Given a package without any executables
        let packageDirectory = URL(fileURLWithPath: "/invalid")
        mockServices.mockShell.launchShell = { _ throws -> LogCollector.Logs in
            let packageManifest = "{\"products\" : []}" // Result of an empty package
            return .stubMessage(level: .trace, message: packageManifest)
        }

        do {
            // When calling parseProducts
            _ = try mockServices.builder.parseProducts([], skipProducts: "", at: packageDirectory, services: mockServices)

            XCTFail("An error should have been thrown.")
        } catch DockerizedBuilderError.missingProducts {
            // Then the DockerizedBuilderError.missingProducts error should be thrown
        } catch {
            XCTFail(String(describing: error))
        }
    }

    func testLoadProducts() throws {
        // Given a package with a library and multiple executables
        let packageDirectory = try createTempPackage()
        mockServices.mockShell.launchShell = { _ throws -> LogCollector.Logs in
            LogCollector.Logs.swiftPackageDump()
        }

        // When calling loadProducts
        let result = try mockServices.builder.loadProducts(at: packageDirectory, services: mockServices)

        // Then all products should be returned
        XCTAssertEqual(result.count, ExamplePackage.executables.count + ExamplePackage.libraries.count)
    }
    func testLoadProductsThrowsWithInvalidShellOutput() throws {
        // Give a failed shell output
        mockServices.mockShell.launchShell = { _ throws -> LogCollector.Logs in
            return .stubMessage(level: .trace, message: "")
        }

        // When calling loadProducts
        do {
            _ = try mockServices.builder.loadProducts(at: URL(fileURLWithPath: ""), services: mockServices)

            XCTFail("An error should have been thrown.")
        } catch {
            // Then DockerizedBuilderError.packageDumpFailure is thrown
            XCTAssertEqual("\(error)", DockerizedBuilderError.packageDumpFailure.description)
        }
    }

    func testRemoveSkippedProducts() {
        // Given a list of skipProducts for a process
        let skipProduct = ExamplePackage.executableThree
        let processName = ExamplePackage.executableTwo // Simulating that executableTwo is the executable that does the deployment

        // When calling removeSkippedProducts
        let result = Builder.removeSkippedProducts(skipProduct.name,
                                                   from: ExamplePackage.executables,
                                                   logger: mockServices.logger,
                                                   processName: processName.name)

        // Then the remaining products should not contain the skipProducts
        XCTAssertFalse(result.contains(skipProduct), "The \"skipProduct\": \(skipProduct) should have been removed.")
        // or a product with a matching processName
        XCTAssertFalse(result.contains(processName), "The \"processName\": \(processName) should have been removed.")
    }
}
