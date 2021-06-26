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

class MockPublisher: Publisher {
    
    static var livePublisher = BlueGreenPublisher()
    
    public var functionRole: String? = nil
    public var alias: String = BlueGreenPublisher.defaultAlias
    
    @ThrowingMock
    var publishArchives = { (archiveURLs: [URL], services: Servicable) throws -> EventLoopFuture<[Lambda.AliasConfiguration]> in
        try MockPublisher.livePublisher.publishArchives(archiveURLs, services: services)
    }
    func publishArchives(_ archiveURLs: [URL], services: Servicable) throws -> EventLoopFuture<[Lambda.AliasConfiguration]> {
        return try $publishArchives.getValue((archiveURLs, services))
    }
    
    @Mock
    var publishArchive = { (archiveURL: URL, alias: String, services: Servicable) -> EventLoopFuture<Lambda.AliasConfiguration> in
        return livePublisher.publishArchive(archiveURL, alias: alias, services: services)
    }
    func publishArchive(_ archiveURL: URL, alias: String, services: Servicable) -> EventLoopFuture<Lambda.AliasConfiguration> {
        return $publishArchive.getValue((archiveURL, alias, services))
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
