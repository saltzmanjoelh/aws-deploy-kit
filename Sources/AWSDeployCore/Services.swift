//
//  Services.swift
//
//
//  Created by Joel Saltzman on 3/26/21.
//

import Foundation
import Logging
import SotoLambda
import SotoS3

public protocol Servicable {
    var logger: Logger { get set }
    var s3: S3 { get set }
    var lambda: Lambda { get set }
    /// Optionally get logs for aws services
    var awsLogger: Logger { get set }

    var builder: BuildInDocker { get set }
//    var uploader: ArchiveUploader { get set }
    var publisher: BlueGreenPublisher { get set }
}

public class Services: Servicable {
    public static var shared: Servicable = Services()

    public static func createS3Service(region: String = "us-west-1", client: AWSClient) -> S3 {
        // We use a long timeout for the archive uploads
        return S3(client: client, region: .init(rawValue: region), timeout: TimeAmount.minutes(4))
    }

    public static func createLambdaService(region: String = "us-west-1", client: AWSClient) -> Lambda {
        // We use a long timeout for the archive uploads
        return Lambda(client: client, region: .init(rawValue: region), timeout: TimeAmount.minutes(4))
    }

    public var logger: Logger
    public var client: AWSClient
    public var s3: S3
    public var lambda: Lambda
    public var awsLogger: Logger = AWSClient.loggingDisabled

    public var builder: BuildInDocker = .init()
    public var publisher: BlueGreenPublisher = .init()

    public init(region: String = "us-west-1") {
        let client = AWSClient(credentialProvider: .default, httpClientProvider: .createNew)
        self.client = client
        self.s3 = Self.createS3Service(region: region, client: client)
        self.lambda = Self.createLambdaService(region: region, client: client)
        self.logger = Logger(label: "AWSDeployKit")
        self.logger.logLevel = .trace
    }

    deinit {
        try? client.syncShutdown()
    }
}
