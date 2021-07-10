//
//  MockPublisher.swift
//  
//
//  Created by Joel Saltzman on 6/22/21.
//

import Foundation
import Mocking
import Logging
import LogKit
import NIO
import SotoLambda
@testable import AWSDeployCore

class MockPublisher: BlueGreenPublisher {
    
    static var livePublisher = Publisher()
    
    public var functionRole: String? = nil
    public var alias: String = Publisher.defaultAlias
    
    @Mock
    var publishArchive = { (archiveURL: URL, invokePayload: String, packageDirectory: URL, verifyResponse: ((Data?) -> Bool)?, alias: String, services: Servicable) -> EventLoopFuture<Lambda.AliasConfiguration> in
        return livePublisher.publishArchive(archiveURL, invokePayload: invokePayload, from: packageDirectory, verifyResponse: verifyResponse, alias: alias, services: services)
    }
    func publishArchive(_ archiveURL: URL, invokePayload: String, from packageDirectory: URL, verifyResponse: ((Data?) -> Bool)?, alias: String, services: Servicable) -> EventLoopFuture<Lambda.AliasConfiguration> {
        return $publishArchive.getValue((archiveURL, invokePayload, packageDirectory, verifyResponse, alias, services))
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
    var verifyLambda = { (configuration: Lambda.FunctionConfiguration, invokePayload: String, packageDirectory: URL, verifyResponse: ((Data?) -> Bool)?, services: Servicable) -> EventLoopFuture<Lambda.FunctionConfiguration> in
        return livePublisher.verifyLambda(configuration, invokePayload: invokePayload, packageDirectory: packageDirectory, verifyResponse: verifyResponse, services: services)
    }
    func verifyLambda(_ configuration: Lambda.FunctionConfiguration, invokePayload: String, packageDirectory: URL, verifyResponse: ((Data?) -> Bool)?, services: Servicable) -> EventLoopFuture<Lambda.FunctionConfiguration> {
        return $verifyLambda.getValue((configuration, invokePayload, packageDirectory, verifyResponse, services))
    }
    
    @Mock
    var publishFunctionCode = { (archiveURL: URL, services: Servicable) -> EventLoopFuture<Lambda.FunctionConfiguration> in
        return livePublisher.publishFunctionCode(archiveURL, services: services)
    }
    func publishFunctionCode(_ archiveURL: URL, services: Servicable) -> EventLoopFuture<Lambda.FunctionConfiguration> {
        return $publishFunctionCode.getValue((archiveURL, services))
    }
    
    @Mock
    var updateAliasVersion = { (configuration: Lambda.FunctionConfiguration, alias: String, services: Servicable) -> EventLoopFuture<Lambda.AliasConfiguration> in
        return livePublisher.updateAliasVersion(configuration, alias: alias, services: services)
    }
    func updateAliasVersion(_ configuration: Lambda.FunctionConfiguration, alias: String, services: Servicable) -> EventLoopFuture<Lambda.AliasConfiguration> {
        return $updateAliasVersion.getValue((configuration, alias, services))
    }
    
    @Mock
    var createLambda = { (archiveURL: URL, services: Servicable) -> EventLoopFuture<Lambda.FunctionConfiguration> in
        return livePublisher.createLambda(with: archiveURL, services: services)
    }
    func createLambda(with archiveURL: URL, services: Servicable) -> EventLoopFuture<Lambda.FunctionConfiguration> {
        return $createLambda.getValue((archiveURL, services))
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
    
    @Mock
    var handlePublishingError = { (error: Error, archiveURL: URL, services: Servicable) -> EventLoopFuture<Lambda.FunctionConfiguration> in
        livePublisher.handlePublishingError(error, for: archiveURL, services: services)
    }
    func handlePublishingError(_ error: Error, for archiveURL: URL, services: Servicable) -> EventLoopFuture<Lambda.FunctionConfiguration> {
        return $handlePublishingError.getValue((error, archiveURL, services))
    }
    
    @Mock
    var getRoleName = { (archiveURL: URL, services: Servicable) -> EventLoopFuture<String> in
        return livePublisher.getRoleName(archiveURL: archiveURL, services: services)
    }
    func getRoleName(archiveURL: URL, services: Servicable) -> EventLoopFuture<String> {
        return $getRoleName.getValue((archiveURL, services))
    }
    
    @Mock
    var generateRoleName = { (archiveURL: URL, services: Servicable) -> EventLoopFuture<String> in
        return livePublisher.generateRoleName(archiveURL: archiveURL, services: services)
    }
    func generateRoleName(archiveURL: URL, services: Servicable) -> EventLoopFuture<String> {
        return $generateRoleName.getValue((archiveURL, services))
    }
}
