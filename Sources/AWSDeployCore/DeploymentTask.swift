//
//  DeploymentTask.swift
//  
//
//  Created by Joel Saltzman on 7/10/21.
//

import Foundation
import SotoLambda
import NIO

public protocol DeploymentTask {
    
    /// The name of the Lambda function that will be tested.
    var functionName: String { get }
    
    /// Called before building the executable
    func buildSetUp() throws
    
    /// Called before invoking the Lambda function. You can perform some
    /// setup like creating some fixture data in a datastore so that your test has data to modify.
    func testSetUp() -> EventLoopFuture<Void>
    
    /// Called after the test to remove anything that may have been needed to perform the test.
    func testTearDown() -> EventLoopFuture<Void>
    
    /// Create a InvocationTask which describes how to test the Lambda.
    func createInvocationTask() throws -> InvocationTask
}
extension DeploymentTask {
    // Default implementations to make it optional functions
    public func buildSetUp() throws {}
    public func testSetUp() -> EventLoopFuture<Void> { return Services.shared.lambda.eventLoopGroup.next().makeSucceededFuture(Void()) }
    public func testTearDown() -> EventLoopFuture<Void> { return Services.shared.lambda.eventLoopGroup.next().makeSucceededFuture(Void()) }
}

extension DeploymentTask {
    
    public func deploy(from packageDirectory: URL, alias: String = Publisher.defaultAlias, services: Servicable) throws -> EventLoopFuture<Lambda.AliasConfiguration> {
        let archiveURL = try build(from: packageDirectory, services: services)
        return try publish(archiveURL: archiveURL, from: packageDirectory, services: services)
            
    }
    public func build(from packageDirectory: URL, services: Servicable) throws -> URL {
        // Prepare for the build step
        try buildSetUp()
        // Build and package everything to a zip
        let archiveURL = try services.builder.buildAndPackage(product: functionName,
                                                              at: packageDirectory,
                                                              sshPrivateKeyPath: nil,
                                                              services: services)
        return archiveURL
    }
    // * Publish the archive
    // * Test that it is working correctly by invoking the function and verifying the response
    // * Update the alias to point to the new version if it succeeds
    public func publish(archiveURL: URL, from packageDirectory: URL, alias: String = Publisher.defaultAlias, services: Servicable) throws -> EventLoopFuture<Lambda.AliasConfiguration> {
        let invocationTest = try createInvocationTask()
        return services.publisher.publishArchive(archiveURL,
                                                 from: packageDirectory,
                                                 invokePayload: invocationTest.payload,
                                                 preVerifyAction: {
                                                    // Prepare to run the test
                                                    return testSetUp()
                                                 },
                                                 verifyResponse: invocationTest.verifyResponse,
                                                 alias: alias,
                                                 services: services)
            .flatMap({ (config: Lambda.AliasConfiguration) -> EventLoopFuture<Lambda.AliasConfiguration> in
                // Cleanup from testing
                testTearDown()
                    .map({ config })
            })
    }
}

extension Collection where Element == DeploymentTask {
    
    /// Deploys Lambda functions defined in the DeploymentTasks
    /// - Parameters:
    ///    - packageDirectory: The Swift packag you are deploying from.
    ///    - alias: The alias to update after successful deployment
    ///    - services: The set of services which will be used to execute your request with.
    /// - Returns: The updated `Lambda.AliasConfiguration`.
    public func deploy(from packageDirectory: URL, alias: String = Publisher.defaultAlias, services: Servicable) throws -> EventLoopFuture<[Lambda.AliasConfiguration]> {
        // Prepare the Docker image
        try services.builder.prepareDocker(packageDirectory: packageDirectory, services: services)
        
        let futures = try self.map { (task: DeploymentTask) -> EventLoopFuture<Lambda.AliasConfiguration> in
            try task.deploy(from: packageDirectory, alias: alias, services: services)
        }
        
        return EventLoopFuture<[Lambda.AliasConfiguration]>.reduce(into: [Lambda.AliasConfiguration](),
                                                            futures,
                                                            on: services.lambda.eventLoopGroup.next(),
                                                            { array, nextValue in
                                                                array.append(nextValue)
                                                            })
    }
}
