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
    
    func buildProducts(_ products: [Product], at packageDirectory: URL, services: Servicable) throws -> [URL] {
        return try $buildProducts.getValue((products, packageDirectory, services))
    }
    @ThrowingMock
    var buildProducts = { (products: [Product], packageDirectory: URL, services: Servicable) throws -> [URL] in
        return try liveBuilder.buildProducts(products, at: packageDirectory, services: services)
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
    
    func parseProducts(_ products: [String], skipProducts: String, at packageDirectory: URL, services: Servicable) throws -> [Product] {
        return try $parseProducts.getValue((products, skipProducts, packageDirectory, services))
    }
    @ThrowingMock
    var parseProducts = { (products: [String], skipProducts: String, packageDirectory: URL, services: Servicable) throws -> [Product] in
        return try liveBuilder.parseProducts(products, skipProducts: skipProducts, at: packageDirectory, services: services)
    }
    func loadProducts(at packageDirectory: URL, services: Servicable) throws -> [Product] {
        return try $loadProducts.getValue((packageDirectory, services))
    }
    @ThrowingMock
    var loadProducts = { (packageDirectory: URL, services: Servicable) throws -> [Product] in
        return try liveBuilder.loadProducts(at: packageDirectory, services: services)
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
    
    func executeShellCommand(_ command: String, for product: Product, at packageDirectory: URL, services: Servicable) throws {
        return try $executeShellCommand.getValue((command, product, packageDirectory, services))
    }
    @ThrowingMock
    var executeShellCommand = { (command: String, product: Product, packageDirectory: URL, services: Servicable) throws in
        try liveBuilder.executeShellCommand(command, for: product, at: packageDirectory, services: services)
    }
    
    func buildAndPackage(product: Product, at packageDirectory: URL, services: Servicable) throws -> URL {
        return try $buildAndPackage.getValue((product, packageDirectory, services))
    }
    @ThrowingMock
    var buildAndPackage = { (product: Product, packageDirectory: URL, services: Servicable) throws -> URL in
        try liveBuilder.buildAndPackage(product: product, at: packageDirectory, services: services)
    }
    
    func buildProduct(_ product: Product, at packageDirectory: URL, services: Servicable) throws -> URL {
        return try $buildProduct.getValue((product, packageDirectory, services))
    }
    @ThrowingMock
    var buildProduct = { (product: Product, packageDirectory: URL, services: Servicable) throws -> URL in
        return try liveBuilder.buildProduct(product, at: packageDirectory, services: services)
    }
    
    func buildProductInDocker(_ product: Product, at packageDirectory: URL, services: Servicable) throws -> LogCollector.Logs {
        return try $buildProductInDocker.getValue((product, packageDirectory, services))
    }
    @ThrowingMock
    var buildProductInDocker = { (product: Product, packageDirectory: URL, services: Servicable) throws -> LogCollector.Logs in
        return try liveBuilder.buildProductInDocker(product, at: packageDirectory, services: services)
    }
    
    func getBuiltProductPath(product: Product, at packageDirectory: URL, services: Servicable) throws -> URL {
        return try $getBuiltProductPath.getValue((product, packageDirectory, services))
    }
    @ThrowingMock
    var getBuiltProductPath = { (product: Product, packageDirectory: URL, services: Servicable) throws -> URL in
        return try liveBuilder.getBuiltProductPath(product: product, at: packageDirectory, services: services)
    }
}

