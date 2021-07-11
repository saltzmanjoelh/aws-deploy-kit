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

class MockBuilder: DockerizedBuilder {
    
    var preBuildCommand: String = ""
    var postBuildCommand: String = ""
    
    static var liveBuilder = Builder()
    
    func buildProducts(_ products: [String], at packageDirectory: URL, sshPrivateKeyPath: URL? = nil, services: Servicable) throws -> [URL] {
        return try $buildProducts.getValue((products, packageDirectory, sshPrivateKeyPath, services))
    }
    @ThrowingMock
    var buildProducts = { (products: [String], packageDirectory: URL, sshPrivateKeyPath: URL?, services: Servicable) throws -> [URL] in
        return try liveBuilder.buildProducts(products, at: packageDirectory, sshPrivateKeyPath: sshPrivateKeyPath, services: services)
    }
    
    func getDockerfilePath(from packageDirectory: URL, services: Servicable) throws -> URL {
        return try $getDockerfilePath.getValue((packageDirectory, services))
    }
    @ThrowingMock
    var getDockerfilePath = { (packageDirectory: URL, services: Servicable) throws -> URL in
        return try liveBuilder.getDockerfilePath(from: packageDirectory, services: services)
    }
    
    func createTemporaryDockerfile(services: Servicable) throws -> URL {
        return try $createTemporaryDockerfile.getValue(services)
    }
    @ThrowingMock
    var createTemporaryDockerfile = { (services: Servicable) throws -> URL in
        return try liveBuilder.createTemporaryDockerfile(services: services)
    }
    
    func parseProducts(_ products: [String], skipProducts: String, at packageDirectory: URL, services: Servicable) throws -> [String] {
        return try $parseProducts.getValue((products, skipProducts, packageDirectory, services))
    }
    @ThrowingMock
    var parseProducts = { (products: [String], skipProducts: String, packageDirectory: URL, services: Servicable) throws -> [String] in
        return try liveBuilder.parseProducts(products, skipProducts: skipProducts, at: packageDirectory, services: services)
    }
    func loadProducts(at packageDirectory: URL, type: ProductType = .executable, services: Servicable) throws -> [String] {
        return try $loadProducts.getValue((packageDirectory, type, services))
    }
    @ThrowingMock
    var loadProducts = { (packageDirectory: URL, type: ProductType, services: Servicable) throws -> [String] in
        return try liveBuilder.loadProducts(at: packageDirectory, type: type, services: services)
    }
    
    func prepareDocker(packageDirectory: URL, services: Servicable) throws {
        try $prepareDocker.getValue((packageDirectory, services))
    }
    @ThrowingMock
    var prepareDocker = { (packageDirectory: URL, services: Servicable) throws in
        try liveBuilder.prepareDocker(packageDirectory: packageDirectory, services: services)
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
    
    func buildProduct(_ product: String, at packageDirectory: URL, services: Servicable, sshPrivateKeyPath: URL?) throws -> URL {
        return try $buildProduct.getValue((product, packageDirectory, services, sshPrivateKeyPath))
    }
    @ThrowingMock
    var buildProduct = { (product: String, packageDirectory: URL, services: Servicable, sshPrivateKeyPath: URL?) throws -> URL in 
        return try liveBuilder.buildProduct(product, at: packageDirectory, services: services, sshPrivateKeyPath: sshPrivateKeyPath)
    }
    
    func buildProductInDocker(_ product: String, at packageDirectory: URL, services: Servicable, sshPrivateKeyPath: URL?) throws -> LogCollector.Logs {
        return try $buildProductInDocker.getValue((product, packageDirectory, services, sshPrivateKeyPath))
    }
    @ThrowingMock
    var buildProductInDocker = { (product: String, packageDirectory: URL, services: Servicable, sshPrivateKeyPath: URL?) throws -> LogCollector.Logs in
        return try liveBuilder.buildProductInDocker(product, at: packageDirectory, services: services, sshPrivateKeyPath: sshPrivateKeyPath)
    }
    
    func getBuiltProductPath(at packageDirectory: URL, for product: String, services: Servicable) throws -> URL {
        return try $getBuiltProductPath.getValue((packageDirectory, product, services))
    }
    @ThrowingMock
    var getBuiltProductPath = { (packageDirectory: URL, product: String, services: Servicable) throws -> URL in
        return try liveBuilder.getBuiltProductPath(at: packageDirectory, for: product, services: services)
    }
}

