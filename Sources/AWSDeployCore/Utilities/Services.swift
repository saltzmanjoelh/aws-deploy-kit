//
//  Services.swift
//
//
//  Created by Joel Saltzman on 3/26/21.
//

import Foundation
import Logging
import LogKit
import SotoLambda
import SotoS3
import SotoSTS
import SotoIAM
import Mocking

public protocol Servicable {
    var logCollector: LogCollector { get set }
    var logger: Logger { get set }
    var fileManager: FileManageable { get set }
    var sts: STS  { get set }
    var s3: S3 { get set }
    var iam: IAM { get set }
    var lambda: Lambda { get set }
    /// Optionally get logs for aws services
    var awsLogger: Logger { get set }

    var shell: ShellExecutable { get set }
    var builder: DockerizedBuilder { get set }
    var packager: ProductPackager { get set }
//    var uploader: ArchiveUploader { get set }
    var publisher: BlueGreenPublisher { get set }
    var invoker: LambdaInvoker { get set }
}

public class Services: Servicable {
    
    public static var shared: Servicable = Services()

    public static func createSTSService(region: String = "us-west-1", client: AWSClient) -> STS {
        return STS(client: client, region: .init(rawValue: region))
    }
    
    public static func createS3Service(region: String = "us-west-1", client: AWSClient) -> S3 {
        // We use a long timeout for the archive uploads
        return S3(client: client, region: .init(rawValue: region), timeout: TimeAmount.minutes(4))
    }
    
    public static func createIAMService(region: String = "us-west-1", client: AWSClient) -> IAM {
        // We use a long timeout for the archive uploads
        return IAM(client: client)
    }

    public static func createLambdaService(region: String = "us-west-1", client: AWSClient) -> Lambda {
        // We use a long timeout for the archive uploads
        return Lambda(client: client, region: .init(rawValue: region), timeout: TimeAmount.minutes(4))
    }

    public var logCollector: LogCollector
    public var logger: Logger
    public var fileManager: FileManageable
    public var client: AWSClient
    public var sts: STS
    public var s3: S3
    public var iam: IAM
    public var lambda: Lambda
    public var awsLogger: Logger = AWSClient.loggingDisabled

    public var shell: ShellExecutable = Shell()
    public var builder: DockerizedBuilder = Builder()
    public var packager: ProductPackager = Packager()
    public var publisher: BlueGreenPublisher = Publisher()
    public var invoker: LambdaInvoker = Invoker()

    public init(region: String = "us-west-1") {
        let client = AWSClient(credentialProvider: .default, httpClientProvider: .createNew)
        self.client = client
        self.sts = Self.createSTSService(region: region, client: client)
        self.s3 = Self.createS3Service(region: region, client: client)
        self.iam = Self.createIAMService(region: region, client: client)
        self.lambda = Self.createLambdaService(region: region, client: client)
        self.fileManager = FileManager.default
        self.logCollector = LogCollector()
        self.logger = CollectingLogger(label: "AWSDeployKit", logCollector: logCollector)
        self.logger.logLevel = .trace
    }

    deinit {
        try? client.syncShutdown()
    }
}
