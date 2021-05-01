//
//  TestServices.swift
//  
//
//  Created by Joel Saltzman on 4/1/21.
//

import Foundation
import AWSDeployCore
import XCTest
import LogKit
import Logging
import SotoTestUtils
import SotoLambda
import SotoS3

class TestServices: Servicable {
    
    let logCollector = LogCollector()
    lazy var logger: Logger = Logger.CollectingLogger(label: "Testing Logger", logCollector: logCollector)
    let awsServer = AWSTestServer(serviceProtocol: .json)
    let client = createAWSClient(credentialProvider: .static(accessKeyId: "foo", secretAccessKey: "bar"))
    lazy var lambda: Lambda = {
        Lambda(client: client, region: .uswest1, endpoint: awsServer.address)
    }()
    lazy var s3: S3 = { S3(client: client, region: .uswest1, endpoint: awsServer.address) }()
    var awsLogger: Logger = AWSClient.loggingDisabled
    
    var builder: BuildInDocker = .init()
    var uploader: ArchiveUploader = .init()
    var publisher: BlueGreenPublisher = .init()
    
    deinit {
        XCTAssertNoThrow(try client.syncShutdown())
        XCTAssertNoThrow(try awsServer.stop())
    }
}
