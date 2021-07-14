//
//  MockServices.swift
//
//
//  Created by Joel Saltzman on 4/1/21.
//

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
@testable import AWSDeployCore

class MockServices: Servicable {
    
    private var didStart = false
    var logCollector = LogCollector()
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
    
    var builder: DockerizedBuilder = MockBuilder()
    var mockBuilder: MockBuilder { return builder as! MockBuilder }
    
    var packager: ExecutablePackager = MockPackager()
    var mockPackager: MockPackager { return packager as! MockPackager }
    
    var publisher: BlueGreenPublisher = MockPublisher()
    var mockPublisher: MockPublisher { return publisher as! MockPublisher }
    
    var invoker: LambdaInvoker = MockInvoker()
    var mockInvoker: MockInvoker { return invoker as! MockInvoker }

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
    func stubFunctionConfiguration(functionName: String = "functionName") -> EventLoopFuture<Lambda.FunctionConfiguration> {
        let promise = lambda.eventLoopGroup.next().makePromise(of: Lambda.FunctionConfiguration.self)
        promise.succeed(.init(codeSha256: "1234", functionName: functionName, version: "1"))
        return promise.futureResult
    }
}
