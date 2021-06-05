//
//  MockServices.swift
//
//
//  Created by Joel Saltzman on 4/1/21.
//

@testable import AWSDeployCore
import Foundation
import Logging
import LogKit
import SotoLambda
import SotoS3
import SotoTestUtils
import XCTest
import Mocking

class MockServices: Servicable {
    
    private var didStart = false
    let logCollector = LogCollector()
    lazy var logger: Logger = {
        var result = CollectingLogger(label: "Testing Logger", logCollector: logCollector)
        result.logLevel = .trace
        return result
    }()
    var fileManager: FileManageable = MockFileManager()
    var mockFileManager: MockFileManager { fileManager as! MockFileManager }

    lazy var awsServer: AWSTestServer = {
        didStart = true
        return AWSTestServer(serviceProtocol: .json)
    }()
    lazy var client: AWSClient = {
        didStart = true
        return createAWSClient(credentialProvider: .static(accessKeyId: "foo", secretAccessKey: "bar"))
    }()
    lazy var lambda: Lambda = {
        Lambda(client: client, region: .uswest1, endpoint: awsServer.address)
    }()

    lazy var s3: S3 = { S3(client: client, region: .uswest1, endpoint: awsServer.address) }()
    var awsLogger: Logger = AWSClient.loggingDisabled

    var shell: ShellExecutable = MockShell()
    var mockShell: MockShell { shell as! MockShell }
    
    var builder: Builder = MockBuildInDocker()
    var mockBuilder: MockBuildInDocker { return builder as! MockBuildInDocker }
    
    var packager: Packager = MockPackageInDocker()
    var mockPackager: MockPackageInDocker { return packager as! MockPackageInDocker }
    
    var publisher: Publisher = MockBlueGreenPublisher()
    var mockPublisher: MockBlueGreenPublisher { return publisher as! MockBlueGreenPublisher }

    deinit {
        cleanup()
    }
    func cleanup() {
        if didStart {
            XCTAssertNoThrow(try client.syncShutdown())
            XCTAssertNoThrow(try awsServer.stop())
        }
    }
}

// MARK: - MockShell
public struct MockShell: ShellExecutable {
    public func launchBash(command: String, at workingDirectory: URL?, logger: Logger?) throws -> LogCollector.Logs {
        return try _launchBash.getValue(EquatableTuple([CodableInput(command), CodableInput(workingDirectory)]))
    }
    
    /// The function to perform in bash. You can modify this for tests.
    /// You could set this to a custom closure that simply returns a fixed String to test how
    /// your code handles specific output. Make sure to reset it for the next test though.
    /// ```swift
    /// ShellExecutor.shellOutAction = { _, _, _ in return "File not found." }
    /// defer { ShellExecutor.resetAction() }
    /// ```
    @ThrowingMock
    public var launchBash = { (tuple: EquatableTuple<CodableInput>) throws -> LogCollector.Logs in
        let process = Process.init()
        return try process.launchBash(try tuple.inputs[0].decode(), at: try tuple.inputs[1].decode(), logger: nil)
    }
}

// MARK: - MockBuildInDocker
class MockBuildInDocker: Builder {
    static var liveBuilder = BuildInDocker()
    
    func buildProducts(_ products: [String], at packageDirectory: URL, services: Servicable) throws -> [URL] {
        return try $buildProducts.getValue((products, packageDirectory, services))
    }
    @ThrowingMock
    var buildProducts = { (products: [String], packageDirectory: URL, services: Servicable) throws -> [URL] in
        return try liveBuilder.buildProducts(products, at: packageDirectory, services: services)
    }
}

// MARK: - MockPackageInDocker
class MockPackageInDocker: Packager {
    static var livePackager = PackageInDocker()
    
    @ThrowingMock
    var packageExecutable = { (executable: String, packageDirectory: URL, services: Servicable) throws -> URL in
        return try livePackager.packageExecutable(executable, at: packageDirectory, services: services)
    }
    func packageExecutable(_ executable: String, at packageDirectory: URL, services: Servicable) throws -> URL {
        return try $packageExecutable.getValue((executable, packageDirectory, services))
    }
    
    @ThrowingMock
    var createDestinationDirectory = { (destinationDirectory: URL, services: Servicable) throws in
        try livePackager.createDestinationDirectory(destinationDirectory, services: services)
    }
    func createDestinationDirectory(_ destinationDirectory: URL, services: Servicable) throws {
        try $createDestinationDirectory.getValue((destinationDirectory, services))
    }
    
    @ThrowingMock
    var prepareDestinationDirectory = { (executable: String, packageDirectory: URL, destinationDirectory: URL, services: Servicable) throws in
        try livePackager.prepareDestinationDirectory(executable: executable,
                                                     packageDirectory: packageDirectory,
                                                     destinationDirectory: destinationDirectory,
                                                     services: services)
    }
    func prepareDestinationDirectory(executable: String, packageDirectory: URL, destinationDirectory: URL, services: Servicable) throws {
        try $prepareDestinationDirectory.getValue((executable, packageDirectory, destinationDirectory, services))
    }
    
    @ThrowingMock
    var copyExecutable = { (executable: String, packageDirectory: URL, destinationDirectory: URL, services: Servicable) throws in
        try livePackager.copyExecutable(executable: executable,
                                        at: packageDirectory,
                                        destinationDirectory: destinationDirectory,
                                        services: services)
    }
    func copyExecutable(executable: String, at packageDirectory: URL, destinationDirectory: URL, services: Servicable) throws {
        try $copyExecutable.getValue((executable, packageDirectory, destinationDirectory, services))
    }
    
    @ThrowingMock
    var copyEnvFile = { (packageDirectory: URL, executable: String, destinationDirectory: URL, services: Servicable) throws in
        try livePackager.copyEnvFile(at: packageDirectory,
                                     executable: executable,
                                     destinationDirectory: destinationDirectory,
                                     services: services)
    }
    func copyEnvFile(at packageDirectory: URL, executable: String, destinationDirectory: URL, services: Servicable) throws {
        try $copyEnvFile.getValue((packageDirectory, executable, destinationDirectory, services))
    }
    
    @ThrowingMock
    var copySwiftDependencies = { (executable: String, packageDirectory: URL, destinationDirectory: URL, services: Servicable) throws in
        try livePackager.copySwiftDependencies(for: executable,
                                               at: packageDirectory,
                                               to: destinationDirectory,
                                               services: services)
    }
    func copySwiftDependencies(for executable: String, at packageDirectory: URL, to destinationDirectory: URL, services: Servicable) throws {
        try $copySwiftDependencies.getValue((executable, packageDirectory, destinationDirectory, services))
    }
    
    @ThrowingMock
    var addBootstrap = { (executable: String, destinationDirectory: URL, services: Servicable) throws -> LogCollector.Logs in
        return try livePackager.addBootstrap(for: executable, in: destinationDirectory, services: services)
    }
    func addBootstrap(for executable: String, in destinationDirectory: URL, services: Servicable) throws -> LogCollector.Logs {
        return try $addBootstrap.getValue((executable, destinationDirectory, services))
    }
    
    @ThrowingMock
    var archiveContents = { (executable: String, destinationDirectory: URL, services: Servicable) throws -> URL in
        return try livePackager.archiveContents(for: executable, in: destinationDirectory, services: services)
    }
    func archiveContents(for executable: String, in destinationDirectory: URL, services: Servicable) throws -> URL {
        return try $archiveContents.getValue((executable, destinationDirectory, services))
    }
}

// MARK: - MockBlueGreenPublisher
class MockBlueGreenPublisher: Publisher {
    
    static var livePublisher = BlueGreenPublisher()
    
    @ThrowingMock
    var publishArchives = { (archiveURLs: [URL], services: Servicable) throws -> EventLoopFuture<[Lambda.AliasConfiguration]> in
        try MockBlueGreenPublisher.livePublisher.publishArchives(archiveURLs, services: services)
    }
    func publishArchives(_ archiveURLs: [URL], services: Servicable) throws -> EventLoopFuture<[Lambda.AliasConfiguration]> {
        let promise = services.lambda.eventLoopGroup.next().makePromise(of: [Lambda.AliasConfiguration].self)
        promise.succeed(.init()) // Just return with empty array
        return promise.futureResult
    }
}
