//
//  MockPackager.swift
//  
//
//  Created by Joel Saltzman on 6/22/21.
//

import Foundation
import Mocking
import Logging
import LogKit
@testable import AWSDeployCore


class MockPackager: ProductPackager {
    
    static var livePackager = Packager()
    
    func destinationURLForProduct(_ product: String, in packageDirectory: URL) -> URL {
        return Self.livePackager.destinationURLForProduct(product, in: packageDirectory)
    }
    
    @ThrowingMock
    var packageProduct = { (product: String, packageDirectory: URL, services: Servicable) throws -> URL in
        return try livePackager.packageProduct(product, at: packageDirectory, services: services)
    }
    func packageProduct(_ product: String, at packageDirectory: URL, services: Servicable) throws -> URL {
        return try $packageProduct.getValue((product, packageDirectory, services))
    }
    
    @ThrowingMock
    var createDestinationDirectory = { (destinationDirectory: URL, services: Servicable) throws in
        try livePackager.createDestinationDirectory(destinationDirectory, services: services)
    }
    func createDestinationDirectory(_ destinationDirectory: URL, services: Servicable) throws {
        try $createDestinationDirectory.getValue((destinationDirectory, services))
    }
    
    @ThrowingMock
    var prepareDestinationDirectory = { (product: String, packageDirectory: URL, destinationDirectory: URL, services: Servicable) throws in
        try livePackager.prepareDestinationDirectory(product: product,
                                                     packageDirectory: packageDirectory,
                                                     destinationDirectory: destinationDirectory,
                                                     services: services)
    }
    func prepareDestinationDirectory(product: String, packageDirectory: URL, destinationDirectory: URL, services: Servicable) throws {
        try $prepareDestinationDirectory.getValue((product, packageDirectory, destinationDirectory, services))
    }
    
    @ThrowingMock
    var copyProduct = { (product: String, packageDirectory: URL, destinationDirectory: URL, services: Servicable) throws in
        try livePackager.copyProduct(product: product,
                                        at: packageDirectory,
                                        destinationDirectory: destinationDirectory,
                                        services: services)
    }
    func copyProduct(product: String, at packageDirectory: URL, destinationDirectory: URL, services: Servicable) throws {
        try $copyProduct.getValue((product, packageDirectory, destinationDirectory, services))
    }
    
    @ThrowingMock
    var copyEnvFile = { (packageDirectory: URL, product: String, destinationDirectory: URL, services: Servicable) throws in
        try livePackager.copyEnvFile(at: packageDirectory,
                                     product: product,
                                     destinationDirectory: destinationDirectory,
                                     services: services)
    }
    func copyEnvFile(at packageDirectory: URL, product: String, destinationDirectory: URL, services: Servicable) throws {
        try $copyEnvFile.getValue((packageDirectory, product, destinationDirectory, services))
    }
    
    @ThrowingMock
    var copySwiftDependencies = { (product: String, packageDirectory: URL, destinationDirectory: URL, services: Servicable) throws in
        try livePackager.copySwiftDependencies(for: product,
                                               at: packageDirectory,
                                               to: destinationDirectory,
                                               services: services)
    }
    func copySwiftDependencies(for product: String, at packageDirectory: URL, to destinationDirectory: URL, services: Servicable) throws {
        try $copySwiftDependencies.getValue((product, packageDirectory, destinationDirectory, services))
    }
    
    @ThrowingMock
    var addBootstrap = { (product: String, destinationDirectory: URL, services: Servicable) throws -> LogCollector.Logs in
        return try livePackager.addBootstrap(for: product, in: destinationDirectory, services: services)
    }
    func addBootstrap(for product: String, in destinationDirectory: URL, services: Servicable) throws -> LogCollector.Logs {
        return try $addBootstrap.getValue((product, destinationDirectory, services))
    }
    
    @ThrowingMock
    var archiveContents = { (product: String, destinationDirectory: URL, services: Servicable) throws -> URL in
        return try livePackager.archiveContents(for: product, in: destinationDirectory, services: services)
    }
    func archiveContents(for product: String, in destinationDirectory: URL, services: Servicable) throws -> URL {
        return try $archiveContents.getValue((product, destinationDirectory, services))
    }
    
    @Mock
    var archivePath = { (product: String, destinationDirectory: URL) -> URL in
        return livePackager.archivePath(for: product, in: destinationDirectory)
    }
    func archivePath(for product: String, in destinationDirectory: URL) -> URL {
        return $archivePath.getValue((product, destinationDirectory))
    }
    
    
    @ThrowingMock
    var getLddDependencies = { (product: String, packageDirectory: URL, services: Servicable) throws -> [URL] in
        return try livePackager.getLddDependencies(for: product, at: packageDirectory, services: services)
    }
    func getLddDependencies(for product: String, at packageDirectory: URL, services: Servicable) throws -> [URL] {
        return try $getLddDependencies.getValue((product, packageDirectory, services))
    }
    
    @ThrowingMock
    var copyDependency = { (dependency: URL, packageDirectory: URL, destinationDirectory: URL, services: Servicable) throws in
        return try livePackager.copyDependency(dependency, in: packageDirectory, to: destinationDirectory, services: services)
    }
    func copyDependency(_ dependency: URL, in packageDirectory: URL, to destinationDirectory: URL, services: Servicable) throws {
        return try $copyDependency.getValue((dependency, packageDirectory, destinationDirectory, services))
    }
    
    @Mock
    var URLForEnvFile = { (packageDirectory: URL, product: String) -> URL in
        return livePackager.URLForEnvFile(packageDirectory: packageDirectory, product: product)
    }
    func URLForEnvFile(packageDirectory: URL, product: String) -> URL {
        return $URLForEnvFile.getValue((packageDirectory, product))
    }
}
