//
//  BlueGreenPublisherTests.swift
//
//
//  Created by Joel Saltzman on 3/26/21.
//

@testable import AWSDeployCore
import Foundation
import Logging
import LogKit
import SotoLambda
import SotoS3
@testable import SotoTestUtils
import XCTest

class BlueGreenPublisherTests: XCTestCase {
    
    var mockServices: MockServices!
    func eventLoop() -> EventLoop {
        return mockServices.lambda.eventLoopGroup.next()
    }
    
    override func setUp() {
        super.setUp()
        mockServices = MockServices()
        MockPublisher.livePublisher = BlueGreenPublisher()
    }
    
    override func tearDownWithError() throws {
        try super.tearDownWithError()
        mockServices.cleanup()
        try cleanupTestPackage()
    }
    
    func testPublishMultipleArchives() throws {
        // Setup
        let functionName = "my-function"
        let version = Int.random(in: 1..<10)
        let aliasConfig: Lambda.AliasConfiguration = .init(functionVersion: "\(version)", revisionId: "\(version)")
        let functionConfiguration = String(
            data: try JSONEncoder().encode([
                "FunctionName": functionName,
                "RevisionId": "\(version)",
                "Version": "\(version)",
                "CodeSha256": UUID().uuidString,
            ]),
            encoding: .utf8
        )!
        // getFunctionConfiguration, updateFunctionCode, publishLatest, verifyLambda, updateAlias
        let fixtureResults: [ByteBuffer] = .init(repeating: ByteBuffer(string: functionConfiguration), count: 5)
        // Given an archive
        let archiveURL = URL(fileURLWithPath: "\(ExamplePackage.tempDirectory)/\(functionName).zip")
        try? FileManager.default.createDirectory(atPath: ExamplePackage.tempDirectory,
                                                withIntermediateDirectories: false,
                                                attributes: nil)
        FileManager.default.createFile(atPath: archiveURL.path, contents: "File".data(using: .utf8)!, attributes: nil)
        let resultReceived = expectation(description: "Result received")

        // When publishing
        try mockServices.publisher.publishArchives([archiveURL], services: mockServices)
            .whenComplete { (publishResult: Result<[Lambda.AliasConfiguration], Error>) in
                // Then the updated version number should be included in the results
                do {
                    let result = try publishResult.get()
                    XCTAssertEqual(result[0].revisionId, aliasConfig.revisionId)
                    //XCTAssertEqual(result[0].functionVersion, aliasConfig.functionVersion)
                } catch {
                    XCTFail(String(describing: error))
                }
                resultReceived.fulfill()
            }

        try waitToProcess(fixtureResults, mockServices: mockServices)
        wait(for: [resultReceived], timeout: 2.0)
    }
    
    func testPublishArchiveErrorsAreLogged() throws {
        // Setup
        let errorReceived = expectation(description: "Error received")
        // Given an invalid zip path
        let archiveURL = URL(fileURLWithPath: "\(ExamplePackage.tempDirectory)/.zip")

        // When calling publishArchive
        mockServices.publisher.publishArchive(archiveURL, alias: mockServices.publisher.alias, services: mockServices)
            .whenFailure { (error: Error) in
                // Then an error should be thrown
                XCTAssertEqual("\(error)", BlueGreenPublisherError.invalidArchiveName(archiveURL.path).description)
                errorReceived.fulfill()
            }

        wait(for: [errorReceived], timeout: 2.0)
        // Then an error should b received
        XCTAssertTrue("\(mockServices.logCollector.logs.allEntries)".contains("Error publishing"), "\"Error publishing\" was not found in the logs: \(mockServices.logCollector.logs.allEntries)")
    }

    func testPublishArchiveHandlesUpdates() throws {
        // Setup
        let functionName = "my-function"
        let revisionId = Int.random(in: 1..<10)
        let aliasConfig: Lambda.AliasConfiguration = .init(revisionId: "\(revisionId)")
        let functionConfiguration = String(
            data: try JSONEncoder().encode([
                "FunctionName": functionName,
                "RevisionId": "\(revisionId)",
                "Version": "4",
                "CodeSha256": UUID().uuidString,
            ]),
            encoding: .utf8
        )!
        // getFunctionConfiguration, updateFunctionCode, publishLatest, verifyLambda, updateAlias
        let fixtureResults: [ByteBuffer] = .init(repeating: ByteBuffer(string: functionConfiguration), count: 5)
        // Given an archive
        let archiveURL = URL(fileURLWithPath: "\(ExamplePackage.tempDirectory)/\(functionName).zip")
        try? FileManager.default.createDirectory(atPath: ExamplePackage.tempDirectory,
                                                withIntermediateDirectories: false,
                                                attributes: nil)
        FileManager.default.createFile(atPath: archiveURL.path, contents: "File".data(using: .utf8)!, attributes: nil)
        let resultReceived = expectation(description: "Result received")

        // When publishing to an existing function
        mockServices.publisher.publishArchive(archiveURL, alias: mockServices.publisher.alias, services: mockServices)
            .whenComplete { (publishResult: Result<Lambda.AliasConfiguration, Error>) in
                // Then a String that represents the revisionId should be returned
                do {
                    let result = try publishResult.get()
                    XCTAssertEqual(result.revisionId, aliasConfig.revisionId)
                } catch {
                    XCTFail(String(describing: error))
                }
                resultReceived.fulfill()
            }

        try waitToProcess(fixtureResults, mockServices: mockServices)
        wait(for: [resultReceived], timeout: 2.0)
    }
    func testPublishArchiveHandlesCreation() throws {
        // Setup stubs
        let functionName = "my-function"
        let role = "role"
        MockPublisher.livePublisher.functionRole = role
        mockServices.mockPublisher.parseFunctionName = { _ in self.eventLoop().makeSucceededFuture(functionName) }
        mockServices.mockPublisher.getFunctionConfiguration = { _ -> EventLoopFuture<Lambda.FunctionConfiguration> in
            // .init(string: "{\"Type\":\"User\",\"Message\":\"Function not found: arn:aws:lambda:us-west-1:1234567890:function:my-function\"}")
            // Any error will do
            let error = NSError.init(domain: "Function not found: arn:aws:lambda:us-west-1:1234567890:function:my-function", code: 1, userInfo: nil)
            return self.eventLoop().makeFailedFuture(error)
        }
        mockServices.mockPublisher.validateRole = { _ in self.eventLoop().makeSucceededFuture(role) }
        mockServices.mockPublisher.createLambda = { _ in self.mockServices.stubAliasConfiguration() }
        // Given an archive
        let archiveURL = mockServices.packager.archivePath(for: functionName, in: URL(fileURLWithPath: ExamplePackage.tempDirectory))

        // When publishing to a new function
        _ = try mockServices.publisher.publishArchive(archiveURL, alias: mockServices.publisher.alias, services: mockServices).wait()
        
        // Then createLambda should be called
        XCTAssertEqual(mockServices.mockPublisher.$createLambda.usage.history.count, 1, "createLambda should have been called.")
    }
    
    func testParseFunctionName() throws {
        // Given a valid archive name
        let functionName = "my-function"
        let archiveName = "\(functionName).zip"

        // When calling parseFunctionName
        let result = try BlueGreenPublisher.parseFunctionName(from: URL(fileURLWithPath: "\(ExamplePackage.tempDirectory)/\(archiveName)"))

        // Then we should receive the function prefix
        XCTAssertEqual(result, functionName)
    }

    func testParseFunctionNameThrowsWithInvalidArchiveName() throws {
        // Given an invalid archive name
        let archiveName = ".zip"
        let invalidURL = URL(fileURLWithPath: "\(ExamplePackage.tempDirectory)/\(archiveName)")

        do {
            // When calling parseFunctionName
            _ = try BlueGreenPublisher.parseFunctionName(from: invalidURL)
            
            // Then an error should be thrown
            XCTFail("An error should have been thrown.")
        } catch BlueGreenPublisherError.invalidArchiveName(let archiveURL) {
            XCTAssertEqual(archiveURL, invalidURL.path)
        } catch {
            XCTFail(error)
        }
    }
    
    func testGetFunctionConfigurationThrowsWithMissingFunctionName() throws {
        // Given an invalid archive path
        let archiveURL = URL(fileURLWithPath: ".zip")
        let errorReceived = expectation(description: "Error received")

        // When calling publishArchive
        mockServices.publisher.getFunctionConfiguration(for: archiveURL, services: mockServices)
            .whenFailure { (error: Error) in
                // Then an error should be thrown
                XCTAssertEqual("\(error)", BlueGreenPublisherError.invalidArchiveName(archiveURL.path).description)
                errorReceived.fulfill()
            }

        wait(for: [errorReceived], timeout: 2.0)
    }

    func testPublishLatestThrowsWithMissingFunctionName() {
        // Given an invalid FunctionConfiguration
        let configuration: Lambda.FunctionConfiguration = .init()
        let errorReceived = expectation(description: "Error received")

        // When calling publishLatest
        mockServices.publisher.publishLatest(configuration, services: mockServices)
            .whenFailure { (error: Error) in
                // Then an error should be thrown
                XCTAssertEqual("\(error)", BlueGreenPublisherError.invalidFunctionConfiguration("functionName", "publishLatest").description)
                errorReceived.fulfill()
            }

        wait(for: [errorReceived], timeout: 2.0)
    }

    func testPublishLatestThrowsWithMissingCodeSha256() {
        // Given an invalid FunctionConfiguration
        let configuration: Lambda.FunctionConfiguration = .init(functionName: "my-function")
        let errorReceived = expectation(description: "Error received")

        // When calling publishLatest
        mockServices.publisher.publishLatest(configuration, services: mockServices)
            .whenFailure { (error: Error) in
                // Then an error should be thrown
                XCTAssertEqual("\(error)", BlueGreenPublisherError.invalidFunctionConfiguration("codeSha256", "publishLatest").description)
                errorReceived.fulfill()
            }

        wait(for: [errorReceived], timeout: 2.0)
    }

    func testPublishLatest() throws {
        // Given an invalid FunctionConfiguration
        let configuration: Lambda.FunctionConfiguration = .init(codeSha256: "12345", functionName: "my-function")
        let resultReceived = expectation(description: "Result received")

        // When calling publishLatest
        mockServices.publisher.publishLatest(configuration, services: mockServices)
            .whenSuccess { (_: Lambda.FunctionConfiguration) in
                // Then a success result should be received
                resultReceived.fulfill()
            }

        try waitToProcess([ByteBuffer(string: "{\"CodeSha256\": \"12345\"}")], mockServices: mockServices)
        wait(for: [resultReceived], timeout: 2.0)
    }

    func testVerifyLambdaThrowsWithMissingFunctionName() {
        // Given a missing functionName in a FunctionConfiguration
        let configuration: Lambda.FunctionConfiguration = .init()
        let errorReceived = expectation(description: "Error received")

        // When calling verifyLambda
        mockServices.publisher.verifyLambda(configuration, services: mockServices)
            .whenFailure { (error: Error) in
                // Then an error should be thrown
                XCTAssertEqual("\(error)", BlueGreenPublisherError.invalidFunctionConfiguration("functionName", "verifyLambda").description)
                errorReceived.fulfill()
            }

        wait(for: [errorReceived], timeout: 2.0)
    }

    func testVerifyLambdaThrowsWithMissingVersion() {
        // Given a missing version in a FunctionConfiguration
        let configuration: Lambda.FunctionConfiguration = .init(functionName: "my-function")
        let errorReceived = expectation(description: "Error received")

        // When calling verifyLambda
        mockServices.publisher.verifyLambda(configuration, services: mockServices)
            .whenFailure { (error: Error) in
                // Then an error should be thrown
                XCTAssertEqual("\(error)", BlueGreenPublisherError.invalidFunctionConfiguration("version", "verifyLambda").description)
                errorReceived.fulfill()
            }

        wait(for: [errorReceived], timeout: 2.0)
    }

    func testVerifyLambda() throws {
        // Given an invalid FunctionConfiguration
        let configuration: Lambda.FunctionConfiguration = .init(functionName: "my-function", version: "2")
        let resultReceived = expectation(description: "Result received")

        // When calling verifyLambda
        mockServices.publisher.verifyLambda(configuration, services: mockServices)
            .whenSuccess { (_: Lambda.FunctionConfiguration) in
                resultReceived.fulfill()
            }

        try waitToProcess([ByteBuffer(string: "{\"CodeSha256\": \"12345\", \"Version\": \"1\"}")], mockServices: mockServices)
        wait(for: [resultReceived], timeout: 2.0)
    }

    func testVerifyLambdaThrowsWhenReceivingErrorResults() throws {
        // Given an invalid FunctionConfiguration
        let functionName = "my-function"
        let configuration: Lambda.FunctionConfiguration = .init(functionName: functionName, version: "2")
        let errorReceived = expectation(description: "Error received")
        let payload = "{\"errorMessage\":\"RequestId: 590ec71e-14c1-4498-8edf-2bd808dc3c0e Error: Runtime exited without providing a reason\",\"errorType\":\"Runtime.ExitError\"}"

        // When calling verifyLambda
        mockServices.publisher.verifyLambda(configuration, services: mockServices)
            .whenFailure { (error: Error) in
                XCTAssertEqual("\(error)", LambdaInvokerError.invokeLambdaFailed("\(functionName):2", payload).description)
                errorReceived.fulfill()
            }

        try mockServices.awsServer.processRaw { (_: AWSTestServer.Request) -> AWSTestServer.Result<AWSTestServer.Response> in
            let buffer = ByteBuffer(string: payload)
            return .result(.init(httpStatus: .ok, headers: ["X-Amz-Function-Error": "Unhandled"], body: buffer))
        }
        wait(for: [errorReceived], timeout: 3.0)
    }
    
    func testUpdateLambda() throws {
        // This is a control function, this test is more for coverage
        // Given a valid configuration
        let functionName = "my-function"
        let alias = BlueGreenPublisher.defaultAlias
        let archiveURL = mockServices.packager.archivePath(for: functionName, in: URL(fileURLWithPath: ExamplePackage.tempDirectory))
        // Setup some stubs
        mockServices.mockPublisher.updateFunctionCode = { _ in self.mockServices.stubFunctionConfiguration() }
        mockServices.mockPublisher.publishLatest = { _ in self.mockServices.stubFunctionConfiguration() }
        mockServices.mockPublisher.verifyLambda = { _ in self.mockServices.stubFunctionConfiguration() }
        mockServices.mockPublisher.updateAliasVersion = { _ in self.mockServices.stubAliasConfiguration(alias: alias) }
        
        // When calling updateLambda
        let result = try mockServices.publisher.updateLambda(with: archiveURL,
                                                configuration: .init(functionName: functionName),
                                                alias: alias,
                                                services: mockServices).wait()
        
        // Then the AliasConfiguration should be returned
        XCTAssertEqual(result.name, alias)
        XCTAssertEqual(mockServices.mockPublisher.$updateFunctionCode.usage.history.count, 1, "updateFunctionCode should have been called.")
        XCTAssertEqual(mockServices.mockPublisher.$publishLatest.usage.history.count, 1, "publishLatest should have been called.")
        XCTAssertEqual(mockServices.mockPublisher.$verifyLambda.usage.history.count, 1, "verifyLambda should have been called.")
        XCTAssertEqual(mockServices.mockPublisher.$updateAliasVersion.usage.history.count, 1, "updateAliasVersion should have been called.")
    }

    func testUpdateFunctionCode() throws {
        // Given an archive
        let functionName = UUID().uuidString
        let archiveURL = URL(fileURLWithPath: "\(ExamplePackage.tempDirectory)/\(functionName).zip")
        try? FileManager.default.createDirectory(atPath: ExamplePackage.tempDirectory,
                                                 withIntermediateDirectories: true,
                                                 attributes: nil)
        FileManager.default.createFile(atPath: archiveURL.path, contents: "File".data(using: .utf8)!, attributes: nil)
        let sha256 = UUID().uuidString

        // When calling updateFunctionCode
        mockServices.publisher.updateFunctionCode(
            .init(functionName: functionName, revisionId: UUID().uuidString),
            archiveURL: archiveURL,
            services: mockServices
        )
        .whenComplete { (result: Result<Lambda.FunctionConfiguration, Error>) in
            // Then we should receive a codeSha256
            do {
                let config = try result.get()
                XCTAssertEqual(config.codeSha256, sha256)
            } catch {
                XCTFail(String(describing: error))
            }
        }

        try mockServices.awsServer.processRaw { (_: AWSTestServer.Request) -> AWSTestServer.Result<AWSTestServer.Response> in
            let buffer = ByteBuffer(string: "{\"CodeSha256\": \"\(sha256)\"}")
            return .result(.init(httpStatus: .ok, body: buffer))
        }
    }

    func testUpdateFunctionCodeThrowsWithInvalidArchive() throws {
        // Given an archive
        let functionName = UUID().uuidString
        let archiveURL = URL(fileURLWithPath: "\(ExamplePackage.tempDirectory)/\(functionName).zip")
        try? FileManager.default.createDirectory(atPath: archiveURL.path,
                                                 withIntermediateDirectories: true,
                                                 attributes: nil)
        FileManager.default.createFile(atPath: archiveURL.path, contents: "contents".data(using: .utf8)!, attributes: nil)
        let resultReceived = expectation(description: "Result received")

        // When calling updateCode
        mockServices.publisher.updateFunctionCode(
            .init(functionName: functionName, revisionId: UUID().uuidString),
            archiveURL: archiveURL,
            services: mockServices
        )
        .whenComplete { (result: Result<Lambda.FunctionConfiguration, Error>) in
            do {
                _ = try result.get()
                XCTFail("An error should have been thrown.")
            } catch {
                // Then an error should be thrown
                XCTAssertEqual("\(error)", BlueGreenPublisherError.archiveDoesNotExist(archiveURL.path).description)
            }
            resultReceived.fulfill()
        }

        wait(for: [resultReceived], timeout: 2.0)
    }

    func testUpdateFunctionCodeThrowsWithMissingFunctionName() {
        // Given an invalid FunctionConfiguration
        let configuration: Lambda.FunctionConfiguration = .init()
        let archiveURL = URL(fileURLWithPath: "\(ExamplePackage.tempDirectory)/my-function.zip")
        try? FileManager.default.createDirectory(atPath: ExamplePackage.tempDirectory,
                                                 withIntermediateDirectories: false,
                                                 attributes: nil)
        FileManager.default.createFile(atPath: archiveURL.path,
                                       contents: "contents".data(using: .utf8),
                                       attributes: nil)
        let errorReceived = expectation(description: "Error received")

        // When calling updateFunctionCode
        mockServices.publisher.updateFunctionCode(configuration, archiveURL: archiveURL, services: mockServices)
            .whenFailure { (error: Error) in
                // Then an error should be thrown
                XCTAssertEqual("\(error)", BlueGreenPublisherError.invalidFunctionConfiguration("functionName", "updateFunctionCode").description)
                errorReceived.fulfill()
            }

        wait(for: [errorReceived], timeout: 2.0)
    }

    func testUpdateFunctionCodeThrowsWithMissingRevisionId() {
        // Given an invalid FunctionConfiguration
        let configuration: Lambda.FunctionConfiguration = .init(functionName: "my-function")
        let archiveURL = URL(fileURLWithPath: "\(ExamplePackage.tempDirectory)/my-function.zip")
        try? FileManager.default.createDirectory(atPath: ExamplePackage.tempDirectory,
                                                 withIntermediateDirectories: true,
                                                 attributes: nil)
        FileManager.default.createFile(atPath: archiveURL.path,
                                       contents: "contents".data(using: .utf8),
                                       attributes: nil)
        let errorReceived = expectation(description: "Error received")

        // When calling updateFunctionCode
        mockServices.publisher.updateFunctionCode(configuration, archiveURL: archiveURL, services: mockServices)
            .whenFailure { (error: Error) in
                // Then an error should be thrown
                XCTAssertEqual("\(error)", BlueGreenPublisherError.invalidFunctionConfiguration("revisionId", "updateFunctionCode").description)
                errorReceived.fulfill()
            }

        wait(for: [errorReceived], timeout: 2.0)
    }

    func testUpdateAliasVersionThrowsWithMissingFunctionName() throws {
        // Given a missing FunctioName in the FunctionConfiguration
        let configuration: Lambda.FunctionConfiguration = .init()
        let errorReceived = expectation(description: "Error received")

        // When calling updateAliasVersion
        mockServices.publisher.updateAliasVersion(configuration, alias: BlueGreenPublisher.defaultAlias, services: mockServices)
            .whenFailure { (error: Error) in
                // Then an error should be thrown
                XCTAssertEqual("\(error)", BlueGreenPublisherError.invalidFunctionConfiguration("functionName", "updateFunctionVersion").description)
                errorReceived.fulfill()
            }

        wait(for: [errorReceived], timeout: 2.0)
    }

    func testUpdateAliasVersionThrowsWithMissingVersion() throws {
        // Given a missing FunctioName in the FunctionConfiguration
        let configuration: Lambda.FunctionConfiguration = .init(functionName: "my-function")
        let errorReceived = expectation(description: "Error received")

        // When calling updateFunctionVersion
        mockServices.publisher.updateAliasVersion(configuration, alias: BlueGreenPublisher.defaultAlias, services: mockServices)
            .whenFailure { (error: Error) in
                // Then an error should be thrown
                XCTAssertEqual("\(error)", BlueGreenPublisherError.invalidFunctionConfiguration("version", "updateFunctionVersion").description)
                errorReceived.fulfill()
            }

        wait(for: [errorReceived], timeout: 2.0)
    }
    
    func testCreateLambda() throws {
        // This is a control function, this test is more for coverage
        // Given a valid configuration
        let functionName = "my-function"
        let role = "my-function-role"
        let alias = "development"
        let archiveURL = mockServices.packager.archivePath(for: functionName, in: URL(fileURLWithPath: ExamplePackage.tempDirectory))
        // Setup some stubs
        mockServices.mockPublisher.createFunctionCode = { _ in self.mockServices.stubFunctionConfiguration() }
        mockServices.mockPublisher.publishLatest = { _ in self.mockServices.stubFunctionConfiguration() }
        mockServices.mockPublisher.verifyLambda = { _ in self.mockServices.stubFunctionConfiguration() }
        mockServices.mockPublisher.updateAliasVersion = { _ in self.mockServices.stubAliasConfiguration(alias: alias) }
        
        // When calling createLambda
        let result = try mockServices.publisher.createLambda(with: archiveURL,
                                                role: role,
                                                alias: alias,
                                                services: mockServices).wait()
        
        // Then the AliasConfiguration should be returned
        XCTAssertEqual(result.name, alias)
        XCTAssertEqual(mockServices.mockPublisher.$createFunctionCode.usage.history.count, 1, "createFunctionCode should have been called.")
        XCTAssertEqual(mockServices.mockPublisher.$publishLatest.usage.history.count, 1, "publishLatest should have been called.")
        XCTAssertEqual(mockServices.mockPublisher.$verifyLambda.usage.history.count, 1, "verifyLambda should have been called.")
        XCTAssertEqual(mockServices.mockPublisher.$updateAliasVersion.usage.history.count, 1, "updateAliasVersion should have been called.")
    }
    
    func testCreateFunctionCodeHandlesMissingArchive() throws {
        // Given a path to an archive that doesn't exist
        let archiveURL = URL(fileURLWithPath: "/invalid.zip")
        
        // When calling createFunctionCode
        do {
            _ = try mockServices.publisher.createFunctionCode(archiveURL: archiveURL,
                                                 role: "role",
                                                 services: mockServices).wait()
            
            XCTFail("An error should have been thrown.")
        } catch BlueGreenPublisherError.archiveDoesNotExist(_) {
            // Then the BlueGreenPublisherError.archiveDoesNotExist error should thrown
        } catch {
            XCTFail(error)
        }
    }
    func testCreateFunctionCode() throws {
        // Given a valid archive
        let archiveURL = mockServices.packager.archivePath(for: ExamplePackage.executableOne,
                                                           in: mockServices.packager.destinationURLForExecutable(ExamplePackage.executableOne,
                                                                                                                 in: tempPackageDirectory()))
        try? FileManager.default.createDirectory(atPath: archiveURL.deletingPathExtension().path,
                                                 withIntermediateDirectories: true,
                                                 attributes: nil)
        FileManager.default.createFile(atPath: archiveURL.path, contents: "File".data(using: .utf8)!, attributes: nil)
        // createFunction then createAlias and stop
        let fixtureResults = [ByteBuffer(string: "{\"CodeSha256\": \"1234\"}"), ByteBuffer(string: "{\"CodeSha256\": \"1234\"}")]
        let resultReceived = expectation(description: "Result Received")
        
        // When calling createFunctionCode
        mockServices.publisher.createFunctionCode(archiveURL: archiveURL,
                                     role: "arn:aws:iam::123456789012:role/\(ExamplePackage.executableOne)-Role",
                                     services: mockServices)
            .whenComplete({ (result: Result<Lambda.FunctionConfiguration, Error>) in
                do {
                    // Then createFunction should be called
                    _ = try result.get()
                    resultReceived.fulfill()
                } catch {
                    XCTFail(error)
                }
            })
        
        try waitToProcess(fixtureResults, mockServices: mockServices)
        wait(for: [resultReceived], timeout: 2.0)
    }
    func testGetRoleNameUsesExistingFunctionRole() throws {
        // Given a valid functionRole
        let role = "arn:aws:iam::123456789012:role/my-role"
        MockPublisher.livePublisher.functionRole = role
        let archiveURL = mockServices.packager.archivePath(for: "functionName", in: URL(fileURLWithPath: ExamplePackage.tempDirectory))
        
        // When calling getRole
        let result = try mockServices.publisher.getRoleName(archiveURL: archiveURL, services: mockServices).wait()
        
        // Then the role should be returned
        XCTAssertEqual(role, result)
    }
    func testGetRoleNameGeneratesUniqueRoleName() throws {
        // Given an nil functionRole
        MockPublisher.livePublisher.functionRole = nil
        let archiveURL = mockServices.packager.archivePath(for: "function-name", in: URL(fileURLWithPath: ExamplePackage.tempDirectory))
        mockServices.mockPublisher.createRole = { (context: (roleName: String, services: Servicable)) -> EventLoopFuture<String> in
            return self.eventLoop().makeSucceededFuture(context.roleName)
        }
        
        // When calling getRole
        let result = try mockServices.publisher.getRoleName(archiveURL: archiveURL, services: mockServices).wait()
            
        // Then a new role should be returned
        XCTAssertNotNil(result)
        XCTAssertTrue(result.contains("function-name"), "The role should contain the function name")
        XCTAssertTrue(result.contains("role"), "The role should contain\"\role\" im it's name.")
    }
    func testValidateRole() throws {
        // Given a valid functionRole
        let role = "my-role"
        let resultReceived = expectation(description: "Result received")
        
        // When calling validateRole
        mockServices.publisher.validateRole(role, services: mockServices)
            .whenComplete { (result: Result<String, Error>) in
                do {
                    let updatedRole = try result.get()
                    // Then the updated role should be returned
                    XCTAssertNotEqual(role, updatedRole)
                } catch {
                    XCTFail(error)
                }
                resultReceived.fulfill()
            }
        
        
        // Mock the AWS response for lambda.createFunction
        try waitToProcess([ByteBuffer(string: "<GetCallerIdentityResponse xmlns=\"https://sts.amazonaws.com/doc/2011-06-15/\">\n  <GetCallerIdentityResult>\n    <Arn>arn:aws:iam::123456789012:user/MY_USER</Arn>\n    <UserId>123456789012345678901</UserId>\n    <Account>123456789012</Account>\n  </GetCallerIdentityResult>\n  <ResponseMetadata>\n    <RequestId>cf192f38-9e25-43fa-8d6c-1234567890</RequestId>\n  </ResponseMetadata>\n</GetCallerIdentityResponse>\n")], mockServices: mockServices)
        wait(for: [resultReceived], timeout: 2.0)
    }
    func testValidateRoleThrowsWithMissingAccountId() throws {
        // Given an account without an id (won't happen be we have code handling it)
        let buffer = ByteBuffer(string: "<GetCallerIdentityResponse xmlns=\"https://sts.amazonaws.com/doc/2011-06-15/\">\n  <GetCallerIdentityResult>\n    <Arn>arn:aws:iam::123456789012:user/MY_USER</Arn>\n    <UserId>123456789012345678901</UserId>\n   \n  </GetCallerIdentityResult>\n  <ResponseMetadata>\n    <RequestId>cf192f38-9e25-43fa-8d6c-1234567890</RequestId>\n  </ResponseMetadata>\n</GetCallerIdentityResponse>\n")
        let role = "my-role"
        let resultReceived = expectation(description: "Result received")
        
        // When calling validateRole
        mockServices.publisher.validateRole(role, services: mockServices)
            .whenComplete { (result: Result<String, Error>) in
                do {
                    _ = try result.get()
                    
                    XCTFail("An error should have been thrown.")
                } catch {
                    XCTAssertEqual("\(error)", BlueGreenPublisherError.accountIdUnavailable.description)
                }
                resultReceived.fulfill()
            }
        
        
        // Mock the AWS response for lambda.createFunction
        try waitToProcess([buffer], mockServices: mockServices)
        wait(for: [resultReceived], timeout: 2.0)
    }
    func testValidateReturnsWhenAlreadyValidRole() throws {
        // Given a complete arn:* role
        let role = "arn:aws:iam::123456789012:user/MY_USER/my-role"
        
        // When calling validateRole
        let result = try mockServices.publisher.validateRole(role, services: mockServices).wait()
        
        // The the provided role is returned
        XCTAssertEqual(result, role)
    }
    func testCreateRole() throws {
        // Given a role
        let roleName = "role-name"
        let resultReceived = expectation(description: "Result received")
        
        // When calling createRole
        mockServices.publisher.createRole(roleName, services: mockServices)
            .whenComplete { (result: Result<String, Error>) in
                do {
                    let value = try result.get()
                    XCTAssertEqual(value, roleName)
                } catch {
                    XCTFail(error)
                }
                resultReceived.fulfill()
            }
        
        // Then createRole and attachRolePolicy should be called
        // and the role should be returned
        let createRoleResponse = """
            <CreateRoleResponse xmlns=\"https://iam.amazonaws.com/doc/2010-05-08/\">
              <CreateRoleResult>
                <Role>
                  <Path>/</Path>
                  <AssumeRolePolicyDocument>%7B%22Version%22%3A%20%222012-10-17%22%2C%22Statement%22%3A%20%5B%7B%20%22Effect%22%3A%20%22Allow%22%2C%20%22Principal%22%3A%20%7B%22Service%22%3A%20%22lambda.amazonaws.com%22%7D%2C%20%22Action%22%3A%20%22sts%3AAssumeRole%22%7D%5D%7D</AssumeRolePolicyDocument>
                  <RoleId>123456789012345678901</RoleId>
                  <RoleName>role-name</RoleName>
                  <Arn>arn:aws:iam::123456789012:role/role-name</Arn>
                  <CreateDate>2021-06-14T15:15:43Z</CreateDate>
                </Role>
              </CreateRoleResult>
              <ResponseMetadata>
                <RequestId>1234567-7833-4471-a4f1-12345678912</RequestId>
              </ResponseMetadata>
            </CreateRoleResponse>
            """
        // createRole, attachRolePolicy
        try waitToProcess([ByteBuffer(string: createRoleResponse), ByteBuffer(string: createRoleResponse)], mockServices: mockServices)
        wait(for: [resultReceived], timeout: 20.0)
    }
    func testCreateRoleThrowsWithInvalidResponse() throws {
        // Given a role
        let roleName = "role-name"
        let resultReceived = expectation(description: "Result received")
        
        // When calling createRole
        mockServices.publisher.createRole(roleName, services: mockServices)
            .whenComplete { (result: Result<String, Error>) in
                do {
                    _ = try result.get()
                    
                    // Then createRole and attachRolePolicy should be called
                    XCTFail("An error should have been thrown.")
                } catch {
                    XCTAssertEqual("\(error)", BlueGreenPublisherError.invalidCreateRoleResponse(roleName, "invalid-role-name").description)
                }
                resultReceived.fulfill()
            }
        
        // Stub the response
        let createRoleResponse = """
        <CreateRoleResponse xmlns=\"https://iam.amazonaws.com/doc/2010-05-08/\">
          <CreateRoleResult>
            <Role>
              <Path>/</Path>
              <AssumeRolePolicyDocument>%7B%22Version%22%3A%20%222012-10-17%22%2C%22Statement%22%3A%20%5B%7B%20%22Effect%22%3A%20%22Allow%22%2C%20%22Principal%22%3A%20%7B%22Service%22%3A%20%22lambda.amazonaws.com%22%7D%2C%20%22Action%22%3A%20%22sts%3AAssumeRole%22%7D%5D%7D</AssumeRolePolicyDocument>
              <RoleId>123456789012345678901</RoleId>
              <RoleName>invalid-role-name</RoleName>
              <Arn>arn:aws:iam::123456789012:role/invalid-role-name</Arn>
              <CreateDate>2021-06-14T15:15:43Z</CreateDate>
            </Role>
          </CreateRoleResult>
          <ResponseMetadata>
            <RequestId>1234567-7833-4471-a4f1-12345678912</RequestId>
          </ResponseMetadata>
        </CreateRoleResponse>
        """
        try waitToProcess([ByteBuffer(string: createRoleResponse)], mockServices: mockServices)
        wait(for: [resultReceived], timeout: 20.0)
    }

//    func testInvokeLambda() throws {
//        // Given a working Lambda
//
//        // When calling verifyLambda
//
//        // Then
//        let expectedResponse = expectation(description: "response")
//        //arn:aws:lambda:us-west-1:796145072238:function:login
//        //arn:aws:lambda:us-west-1:796145072238:function:error
//        instance.verifyLambda(Lambda.FunctionConfiguration.init(codeSha256: "", functionName: "login:13"), services: Services.shared)//TestServices()
//            .whenComplete({ (result: Result<Lambda.FunctionConfiguration, Error>) in
//                do {
//                    let response = try result.get()
//                    print("result: \(response)")
//                } catch {
//                    print("error: \(error)")
//                }
//                expectedResponse.fulfill()
//            })
//        wait(for: [expectedResponse], timeout: 5.0)
//    }
}
