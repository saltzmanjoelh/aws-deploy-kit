//
//  TestServices.swift
//
//
//  Created by Joel Saltzman on 4/1/21.
//

import AWSDeployCore
import Foundation
import Logging
import LogKit
import SotoLambda
import SotoS3
import SotoTestUtils
import XCTest

class TestServices: Servicable {
    private var didStart = false
    let logCollector = LogCollector()
    lazy var logger: Logger = {
        var result = CollectingLogger(label: "Testing Logger", logCollector: logCollector)
        result.logLevel = .trace
        return result
    }()

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

    var builder: BuildInDocker = .init()
    var publisher: BlueGreenPublisher = .init()

    deinit {
        if didStart {
            XCTAssertNoThrow(try client.syncShutdown())
            XCTAssertNoThrow(try awsServer.stop())
        }
        
    }
}
