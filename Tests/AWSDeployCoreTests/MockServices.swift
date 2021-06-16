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
import SotoSTS
import SotoIAM
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
    lazy var lambda: Lambda = { Lambda(client: client, region: .uswest1, endpoint: awsServer.address) }()
    lazy var sts: STS = { STS(client: client, region: .uswest1, endpoint: awsServer.address) }()
    lazy var s3: S3 = { S3(client: client, region: .uswest1, endpoint: awsServer.address) }()
    lazy var iam: IAM = { IAM(client: client, endpoint: awsServer.address) }()
    var awsLogger: Logger = AWSClient.loggingDisabled

    var shell: ShellExecutable = MockShell()
    var mockShell: MockShell { shell as! MockShell }
    
    var builder: Builder = MockBuilder()
    var mockBuilder: MockBuilder { return builder as! MockBuilder }
    
    var packager: ExecutablePackable = MockPackager()
    var mockPackager: MockPackager { return packager as! MockPackager }
    
    var publisher: Publisher = MockPublisher()
    var mockPublisher: MockPublisher { return publisher as! MockPublisher }

    deinit {
        cleanup()
    }
    func cleanup() {
        if didStart {
            XCTAssertNoThrow(try client.syncShutdown())
            XCTAssertNoThrow(try awsServer.stop())
        }
    }
    
    func stubAliasConfiguration(alias: String? = nil) -> EventLoopFuture<Lambda.AliasConfiguration> {
        let promise = lambda.eventLoopGroup.next().makePromise(of: Lambda.AliasConfiguration.self)
        promise.succeed(.init(name: alias))
        return promise.futureResult
    }
    func stubFunctionConfiguration() -> EventLoopFuture<Lambda.FunctionConfiguration> {
        let promise = lambda.eventLoopGroup.next().makePromise(of: Lambda.FunctionConfiguration.self)
        promise.succeed(.init(codeSha256: "1234", functionName: "functionName"))
        return promise.futureResult
    }
}

// MARK: - MockShell
public struct MockShell: ShellExecutable {
    public func launchShell(command: String, at workingDirectory: URL?, logger: Logger?) throws -> LogCollector.Logs {
        return try _launchShell.getValue(EquatableTuple([CodableInput(command), CodableInput(workingDirectory)]))
    }
    
    /// The function to perform in bash. You can modify this for tests.
    /// You could set this to a custom closure that simply returns a fixed String to test how
    /// your code handles specific output. Make sure to reset it for the next test though.
    /// ```swift
    /// ShellExecutor.shellOutAction = { _, _, _ in return "File not found." }
    /// defer { ShellExecutor.resetAction() }
    /// ```
    @ThrowingMock
    public var launchShell = { (tuple: EquatableTuple<CodableInput>) throws -> LogCollector.Logs in
        let process = Process.init()
        return try process.launchBash(try tuple.inputs[0].decode(), at: try tuple.inputs[1].decode(), logger: nil)
    }
}

// MARK: - MockBuilder
class MockBuilder: Builder {
    
    var preBuildCommand: String = ""
    var postBuildCommand: String = ""
    
    static var liveBuilder = BuildInDocker()
    
    func buildProducts(_ products: [String], at packageDirectory: URL, services: Servicable) throws -> [URL] {
        return try $buildProducts.getValue((products, packageDirectory, services))
    }
    @ThrowingMock
    var buildProducts = { (products: [String], packageDirectory: URL, services: Servicable) throws -> [URL] in
        return try liveBuilder.buildProducts(products, at: packageDirectory, services: services)
    }
    
    func getDockerfilePath(from packageDirectory: URL, services: Servicable) throws -> URL {
        return try $getDockerfilePath.getValue((packageDirectory, services))
    }
    @ThrowingMock
    var getDockerfilePath = { (packageDirectory: URL, services: Servicable) throws -> URL in
        return try liveBuilder.getDockerfilePath(from: packageDirectory, services: services)
    }
    
    func prepareDockerImage(at dockerfilePath: URL, services: Servicable) throws -> String {
        return try $prepareDockerImage.getValue((dockerfilePath, services))
    }
    @ThrowingMock
    var prepareDockerImage = { (dockerfilePath: URL, services: Servicable) throws -> String in
        return try liveBuilder.prepareDockerImage(at: dockerfilePath, services: services)
    }
    
    func executeShellCommand(_ command: String, for product: String, at packageDirectory: URL, services: Servicable) throws {
        return try $executeShellCommand.getValue((command, product, packageDirectory, services))
    }
    @ThrowingMock
    var executeShellCommand = { (command: String, product: String, packageDirectory: URL, services: Servicable) throws in
        try liveBuilder.executeShellCommand(command, for: product, at: packageDirectory, services: services)
    }
    
    func buildProduct(_ product: String, at packageDirectory: URL, services: Servicable, sshPrivateKeyPath: URL?) throws -> LogCollector.Logs {
        return try $buildProduct.getValue((product, packageDirectory, services, sshPrivateKeyPath))
    }
    @ThrowingMock
    var buildProduct = { (product: String, packageDirectory: URL, services: Servicable, sshPrivateKeyPath: URL?) throws -> LogCollector.Logs in
        return try liveBuilder.buildProduct(product, at: packageDirectory, services: services)
    }
    
    func getBuiltProductPath(at packageDirectory: URL, for product: String, services: Servicable) throws -> URL {
        return try $getBuiltProductPath.getValue((packageDirectory, product, services))
    }
    @ThrowingMock
    var getBuiltProductPath = { (packageDirectory: URL, product: String, services: Servicable) throws -> URL in
        return try liveBuilder.getBuiltProductPath(at: packageDirectory, for: product, services: services)
    }
}

// MARK: - MockPackageInDocker
class MockPackager: ExecutablePackable {
    
    static var livePackager = Packager()
    
    func destinationURLForExecutable(_ executable: String, in packageDirectory: URL) -> URL {
        return Self.livePackager.destinationURLForExecutable(executable, in: packageDirectory)
    }
    
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
    
    @Mock
    var archivePath = { (executable: String, destinationDirectory: URL) -> URL in
        return livePackager.archivePath(for: executable, in: destinationDirectory)
    }
    func archivePath(for executable: String, in destinationDirectory: URL) -> URL {
        return $archivePath.getValue((executable, destinationDirectory))
    }
}

// MARK: - MockPublisher
class MockPublisher: Publisher {
    
    static var livePublisher = BlueGreenPublisher()
    
    public var functionRole: String? = nil
    
    @ThrowingMock
    var publishArchives = { (archiveURLs: [URL], services: Servicable) throws -> EventLoopFuture<[Lambda.AliasConfiguration]> in
        try MockPublisher.livePublisher.publishArchives(archiveURLs, services: services)
    }
    func publishArchives(_ archiveURLs: [URL], services: Servicable) throws -> EventLoopFuture<[Lambda.AliasConfiguration]> {
        return try $publishArchives.getValue((archiveURLs, services))
    }
    
    @Mock
    var updateFunctionCode = { (configuration: Lambda.FunctionConfiguration, archiveURL: URL, services: Servicable) -> EventLoopFuture<Lambda.FunctionConfiguration> in
        return livePublisher.updateFunctionCode(configuration, archiveURL: archiveURL, services: services)
    }
    func updateFunctionCode(_ configuration: Lambda.FunctionConfiguration, archiveURL: URL, services: Servicable) -> EventLoopFuture<Lambda.FunctionConfiguration> {
        return $updateFunctionCode.getValue((configuration, archiveURL, services))
    }
    
    @Mock
    var publishLatest = { (configuration: Lambda.FunctionConfiguration, services: Servicable) -> EventLoopFuture<Lambda.FunctionConfiguration> in
        return livePublisher.publishLatest(configuration, services: services)
    }
    func publishLatest(_ configuration: Lambda.FunctionConfiguration, services: Servicable) -> EventLoopFuture<Lambda.FunctionConfiguration> {
        return $publishLatest.getValue((configuration, services))
    }
    
    @Mock
    var verifyLambda = { (configuration: Lambda.FunctionConfiguration, services: Servicable) -> EventLoopFuture<Lambda.FunctionConfiguration> in
        return livePublisher.verifyLambda(configuration, services: services)
    }
    func verifyLambda(_ configuration: Lambda.FunctionConfiguration, services: Servicable) -> EventLoopFuture<Lambda.FunctionConfiguration> {
        return $verifyLambda.getValue((configuration, services))
    }
    
    @Mock
    var updateAliasVersion = { (configuration: Lambda.FunctionConfiguration, alias: String, services: Servicable) -> EventLoopFuture<Lambda.AliasConfiguration> in
        return livePublisher.updateAliasVersion(configuration, alias: alias, services: services)
    }
    func updateAliasVersion(_ configuration: Lambda.FunctionConfiguration, alias: String, services: Servicable) -> EventLoopFuture<Lambda.AliasConfiguration> {
        return $updateAliasVersion.getValue((configuration, alias, services))
    }
    
    @Mock
    var createLambda = { (archiveURL: URL, role: String, alias: String, services: Servicable) -> EventLoopFuture<Lambda.AliasConfiguration> in
        return livePublisher.createLambda(with: archiveURL, role: role, alias: alias, services: services)
    }
    func createLambda(with archiveURL: URL, role: String, alias: String, services: Servicable) -> EventLoopFuture<Lambda.AliasConfiguration> {
        return $createLambda.getValue((archiveURL, role, alias, services))
    }
    
    @Mock
    var parseFunctionName = { (archiveURL: URL, services: Servicable) -> EventLoopFuture<String> in
        return livePublisher.parseFunctionName(from: archiveURL, services: services)
    }
    func parseFunctionName(from archiveURL: URL, services: Servicable) -> EventLoopFuture<String> {
        return $parseFunctionName.getValue((archiveURL, services))
    }
    
    @Mock
    var getFunctionConfiguration = { (archiveURL: URL, services: Servicable) -> EventLoopFuture<Lambda.FunctionConfiguration> in
        return livePublisher.getFunctionConfiguration(for: archiveURL, services: services)
    }
    func getFunctionConfiguration(for archiveURL: URL, services: Servicable) -> EventLoopFuture<Lambda.FunctionConfiguration> {
        return $getFunctionConfiguration.getValue((archiveURL, services))
    }
    
    @Mock
    var updateLambda = { (archiveURL: URL, configuration: Lambda.FunctionConfiguration, alias: String, services: Servicable) -> EventLoopFuture<Lambda.AliasConfiguration> in
        return livePublisher.updateLambda(with: archiveURL, configuration: configuration, alias: alias, services: services)
    }
    func updateLambda(with archiveURL: URL, configuration: Lambda.FunctionConfiguration, alias: String, services: Servicable) -> EventLoopFuture<Lambda.AliasConfiguration> {
        return $updateLambda.getValue((archiveURL, configuration, alias, services))
    }
    
    @Mock
    var createFunctionCode = { (archiveURL: URL, role: String, services: Servicable) -> EventLoopFuture<Lambda.FunctionConfiguration> in
        return livePublisher.createFunctionCode(archiveURL: archiveURL, role: role, services: services)
    }
    func createFunctionCode(archiveURL: URL, role: String, services: Servicable) -> EventLoopFuture<Lambda.FunctionConfiguration> {
        return $createFunctionCode.getValue((archiveURL, role, services))
    }
    
    @Mock
    var validateRole = { (role: String, services: Servicable) -> EventLoopFuture<String> in
        return livePublisher.validateRole(role, services: services)
    }
    func validateRole(_ role: String, services: Servicable) -> EventLoopFuture<String> {
        return $validateRole.getValue((role, services))
    }
    
    @Mock
    var createRole = { (roleName: String, services: Servicable) -> EventLoopFuture<String> in
        return livePublisher.createRole(roleName, services: services)
    }
    func createRole(_ roleName: String, services: Servicable) -> EventLoopFuture<String> {
        return $createRole.getValue((roleName, services))
    }
    
    func handlePublishingError(_ error: Error, for archiveURL: URL, alias: String, services: Servicable) -> EventLoopFuture<Lambda.AliasConfiguration> {
        return Self.livePublisher.handlePublishingError(error, for: archiveURL, alias: alias, services: services)
    }
    func getRoleName(archiveURL: URL, services: Servicable) -> EventLoopFuture<String> {
        return Self.livePublisher.getRoleName(archiveURL: archiveURL, services: services)
    }
}
