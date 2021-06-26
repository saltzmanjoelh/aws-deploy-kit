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


class MockPackager: ExecutablePackager {
    
    static var livePackager = Packager()
    
    func destinationURLForExecutable(_ executable: String, in packageDirectory: URL) -> URL {
        return Self.livePackager.destinationURLForExecutable(executable, in: packageDirectory)
    }
    
    @ThrowingMock
    var packageExecutable = { (executable: String, packageDirectory: URL, services: Servicable) throws -> URL in
        return try livePackager.packageExecutable(executable, at: packageDirectory, services: services)
    }
    func packageExecutable(_ executable: String, at packageDirectory: URL, services: Servicable) throws -> URL {
        return try $packageExecutable.getValue((executable, packageDirectory, services))
    }
    
    @ThrowingMock
    var createDestinationDirectory = { (destinationDirectory: URL, services: Servicable) throws in
        try livePackager.createDestinationDirectory(destinationDirectory, services: services)
    }
    func createDestinationDirectory(_ destinationDirectory: URL, services: Servicable) throws {
        try $createDestinationDirectory.getValue((destinationDirectory, services))
    }
    
    @ThrowingMock
    var prepareDestinationDirectory = { (executable: String, packageDirectory: URL, destinationDirectory: URL, services: Servicable) throws in
        try livePackager.prepareDestinationDirectory(executable: executable,
                                                     packageDirectory: packageDirectory,
                                                     destinationDirectory: destinationDirectory,
                                                     services: services)
    }
    func prepareDestinationDirectory(executable: String, packageDirectory: URL, destinationDirectory: URL, services: Servicable) throws {
        try $prepareDestinationDirectory.getValue((executable, packageDirectory, destinationDirectory, services))
    }
    
    @ThrowingMock
    var copyExecutable = { (executable: String, packageDirectory: URL, destinationDirectory: URL, services: Servicable) throws in
        try livePackager.copyExecutable(executable: executable,
                                        at: packageDirectory,
                                        destinationDirectory: destinationDirectory,
                                        services: services)
    }
    func copyExecutable(executable: String, at packageDirectory: URL, destinationDirectory: URL, services: Servicable) throws {
        try $copyExecutable.getValue((executable, packageDirectory, destinationDirectory, services))
    }
    
    @ThrowingMock
    var copyEnvFile = { (packageDirectory: URL, executable: String, destinationDirectory: URL, services: Servicable) throws in
        try livePackager.copyEnvFile(at: packageDirectory,
                                     executable: executable,
                                     destinationDirectory: destinationDirectory,
                                     services: services)
    }
    func copyEnvFile(at packageDirectory: URL, executable: String, destinationDirectory: URL, services: Servicable) throws {
        try $copyEnvFile.getValue((packageDirectory, executable, destinationDirectory, services))
    }
    
    @ThrowingMock
    var copySwiftDependencies = { (executable: String, packageDirectory: URL, destinationDirectory: URL, services: Servicable) throws in
        try livePackager.copySwiftDependencies(for: executable,
                                               at: packageDirectory,
                                               to: destinationDirectory,
                                               services: services)
    }
    func copySwiftDependencies(for executable: String, at packageDirectory: URL, to destinationDirectory: URL, services: Servicable) throws {
        try $copySwiftDependencies.getValue((executable, packageDirectory, destinationDirectory, services))
    }
    
    @ThrowingMock
    var addBootstrap = { (executable: String, destinationDirectory: URL, services: Servicable) throws -> LogCollector.Logs in
        return try livePackager.addBootstrap(for: executable, in: destinationDirectory, services: services)
    }
    func addBootstrap(for executable: String, in destinationDirectory: URL, services: Servicable) throws -> LogCollector.Logs {
        return try $addBootstrap.getValue((executable, destinationDirectory, services))
    }
    
    @ThrowingMock
    var archiveContents = { (executable: String, destinationDirectory: URL, services: Servicable) throws -> URL in
        return try livePackager.archiveContents(for: executable, in: destinationDirectory, services: services)
    }
    func archiveContents(for executable: String, in destinationDirectory: URL, services: Servicable) throws -> URL {
        return try $archiveContents.getValue((executable, destinationDirectory, services))
    }
    
    @Mock
    var archivePath = { (executable: String, destinationDirectory: URL) -> URL in
        return livePackager.archivePath(for: executable, in: destinationDirectory)
    }
    func archivePath(for executable: String, in destinationDirectory: URL) -> URL {
        return $archivePath.getValue((executable, destinationDirectory))
    }
}
