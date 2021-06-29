//
//  MockBuilder.swift
//  
//
//  Created by Joel Saltzman on 6/22/21.
//

import Foundation
import Mocking
import Logging
import LogKit
@testable import AWSDeployCore

class MockBuilder: Builder {
    
    var preBuildCommand: String = ""
    var postBuildCommand: String = ""
    
    static var liveBuilder = DockerizedBuilder()
    
    func buildProducts(_ products: [String], at packageDirectory: URL, skipProducts: String = "", services: Servicable) throws -> [URL] {
        return try $buildProducts.getValue((products, packageDirectory, skipProducts, services))
    }
    @ThrowingMock
    var buildProducts = { (products: [String], packageDirectory: URL, skipProducts: String, services: Servicable) throws -> [URL] in
        return try liveBuilder.buildProducts(products, at: packageDirectory, skipProducts: skipProducts, services: services)
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

