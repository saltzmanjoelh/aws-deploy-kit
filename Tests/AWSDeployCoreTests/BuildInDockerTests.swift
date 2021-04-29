//
//  BuildInDockerTests.swift
//  
//
//  Created by Joel Saltzman on 3/25/21.
//

import Foundation
import XCTest
import Logging
import LogKit
@testable import AWSDeployCore

class BuildInDockerTests: XCTestCase {
    
    override func setUpWithError() throws {
        ShellExecutor.shellOutAction = { (to: String,
                    arguments: [String],
                    at: String,
                    process: Process,
                    outputHandle: FileHandle?,
                    errorHandle: FileHandle?) throws -> String in
            let components = [to] + arguments + [at]
            return components.joined(separator: " ")
        }
    }
    
    func createTempScript(at scriptPath: String) throws -> String {
        let output = "/tmp/archive.zip"
        let fileURL = URL(fileURLWithPath: scriptPath)
        let script = "echo \"\(output)\""
        try (script as NSString).write(to: fileURL,
                                       atomically: true,
                                       encoding: String.Encoding.utf8.rawValue)
        try FileManager.default.setAttributes([FileAttributeKey.posixPermissions : 0o777], ofItemAtPath: scriptPath)
        return output
    }
    
    func testPrepareDockerImage() throws {
        // Given an instance
        let instance = BuildInDocker()
        
        // When calling prepareDockerImage with valid input
        let result = try instance.prepareDockerImage(at: "/tmp", logger: Logger.default)
        
        // Then the correct command should be issued
        XCTAssertTrue(result.contains("/bin/bash -c"))
        XCTAssertTrue(result.contains("export PATH"))
        XCTAssertTrue(result.contains("/usr/local/bin/"))
        XCTAssertTrue(result.contains("/usr/local/bin/docker build . -t builder"))
        XCTAssertTrue(result.contains("--no-cache"))
    }
    func testBuildAndPackage_returnsArchivePath() throws {
        // Given a successful shellOut
        let instance = BuildInDocker()
        ShellExecutor.shellOutAction = { (to: String,
                    arguments: [String],
                    at: String,
                    process: Process,
                    outputHandle: FileHandle?,
                    errorHandle: FileHandle?) throws -> String in
            return "archive.zip"
        }
        
        // When calling buildAndPackage
        let result = try instance.buildAndPackageInDocker(product: "Example", at: ".", logger: Logger.default)
        
        // Then an archive should be returned
        XCTAssertEqual(result, "archive.zip")
    }
    func testBuildAndPackage_throwsWithUnexpectedResult() throws {
        // Given an unexpected shellOut result
        let instance = BuildInDocker()
        ShellExecutor.shellOutAction = { (to: String,
                    arguments: [String],
                    at: String,
                    process: Process,
                    outputHandle: FileHandle?,
                    errorHandle: FileHandle?) throws -> String in
            return "??"
        }
        
        // When calling buildAndPackage
        do {
            _ = try instance.buildAndPackageInDocker(product: "Example", at: ".", logger: Logger.default)
        
            XCTFail("An error should have been thrown.")
        } catch BuildInDockerError.archivePathNotReceived("Example") {
            // Then archiveNotFound should be thrown
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
        
    }
    func testBuildProductsThrowsWithMissingArchive() throws {
        // Given an archive that doesn't exist
        let archive = "invalid.zip"
        ShellExecutor.shellOutAction = { (to: String,
                    arguments: [String],
                    at: String,
                    process: Process,
                    outputHandle: FileHandle?,
                    errorHandle: FileHandle?) throws -> String in
            return archive
        }
        let instance = BuildInDocker()
        let path = try createTempPackage()
        
        // When calling buildProduct
        // Then an error should be throw
        do {
            _ = try instance.buildProducts(["TestExecutable"], at: path, logger: Logger.default)
            
            XCTFail("An error should have been thrown.")
        } catch {
            XCTAssertEqual("\(error)", BuildInDockerError.invalidArchivePath(archive).description)
        }
    }
    func testBuildProduct() throws {
        // Given an instance
        let instance = BuildInDocker()
        let path = try createTempPackage()
        
        // When calling buildProduct with valid input
        let result = try instance.buildProductInDocker("TestExecutable", at: path, logger: Logger.default)
        
        // Then the correct command should be issued
        XCTAssertEqual(result, "/usr/local/bin/docker run -it --rm -e TERM=dumb -e GIT_TERMINAL_PROMPT=1 -v /tmp/TestPackage:/tmp/TestPackage -w /tmp/TestPackage -v $HOME/.ssh:/root/.ssh builder /usr/bin/bash -c \"swift build -c release --product TestExecutable\" .")
    }
    func testBuildProductWithPrivateKey() throws {
        // Given an instance
        let instance = BuildInDocker()
        let path = try createTempPackage()
        
        // When calling buildProduct with valid input and a private key
        let result = try instance.buildProductInDocker("TestExecutable", at: path, logger: Logger.default, sshPrivateKeyPath: "/tmp/ssh/key")
        
        // Then the correct command should be issued
        XCTAssertEqual(result, "/usr/local/bin/docker run -it --rm -e TERM=dumb -e GIT_TERMINAL_PROMPT=1 -v /tmp/TestPackage:/tmp/TestPackage -w /tmp/TestPackage -v /tmp/ssh/key:/tmp/ssh/key -v $HOME/.ssh:/root/.ssh builder ssh-agent bash -c ssh-add -c /tmp/ssh/key; swift build -c release --product TestExecutable .")
    }
    func testPackageProduct() throws {
        // Given an instance
        let instance = BuildInDocker()
        
        // When calling packageProduct with valid input
        let result = try instance.packageProduct("Test", at: "/tmp", logger: Logger.default)
        
        // Then the correct command should be issued
        XCTAssertNotNil(result)
        XCTAssertTrue(result!.contains(".bundle/Contents/Resources/packageInDocker.sh /tmp Test ."), "Invalid shell command.")
    }
    
    func testRunScriptThrowsWithInvalidScript() {
        // Given an invalid script
        let script = "invalid.sh"
        let instance = BuildInDocker()
        
        do {
            // When calling run(script:)
            _ = try instance.run(script: script, logger: Logger.default)
            
            XCTFail("An error should have been thrown.")
        } catch {
            // Then an error should be thrown
            XCTAssertEqual("\(error)", BuildInDockerError.scriptNotFound(script).description)
        }
    }
}
