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
    func buildSetUp(services: Servicable) throws
    
    /// Called before invoking the Lambda function. You can perform some
    /// setup like creating some fixture data in a datastore so that your test has data to modify.
    func invocationSetUp(services: Servicable) -> EventLoopFuture<Void>
    
    func invocationPayload() throws -> String
    
    /// The Lambda returns Data when being invoked. Verify that it is returning the correct data.
    func verifyInvocation(_ responseData: Data) -> Bool
    
    /// Called after the test to remove anything that may have been needed to perform the test.
    func invocationTearDown(services: Servicable) -> EventLoopFuture<Void>
}
extension DeploymentTask {
    
    // The protocol defines
    public func createInvocationTask(services: Servicable) throws -> InvocationTask {
        return InvocationTask.init(functionName: functionName,
                                   payload: try invocationPayload(),
                                   setUp: invocationSetUp,
                                   verifyResponse: verifyInvocation,
                                   tearDown: invocationTearDown)
    }
    
    // Default implementations to make it optional functions
    public func buildSetUp(services: Servicable) throws {}
    public func invocationSetUp(services: Servicable) -> EventLoopFuture<Void> {
        return Services.shared.lambda.eventLoopGroup.next().makeSucceededFuture(Void())
    }
    public func invocationTearDown(services: Servicable) -> EventLoopFuture<Void> {
        return Services.shared.lambda.eventLoopGroup.next().makeSucceededFuture(Void())
    }
}

extension DeploymentTask {
    
    public func deploy(from packageDirectory: URL, alias: String = Publisher.defaultAlias, services: Servicable) throws -> EventLoopFuture<Lambda.AliasConfiguration> {
        let archiveURL = try build(from: packageDirectory, services: services)
        return try publish(archiveURL: archiveURL, from: packageDirectory, services: services)
            
    }
    public func build(from packageDirectory: URL, services: Servicable) throws -> URL {
        // Prepare for the build step
        try buildSetUp(services: services)
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
        let invocationTask = try createInvocationTask(services: services)
        return services.publisher.publishArchive(archiveURL,
                                                 from: packageDirectory,
                                                 invokePayload: invocationTask.payload,
                                                 invocationSetUp: invocationTask.setUp,
                                                 verifyResponse: invocationTask.verifyResponse,
                                                 invocationTearDown: invocationTask.tearDown,
                                                 alias: alias,
                                                 services: services)
            .flatMap({ (config: Lambda.AliasConfiguration) -> EventLoopFuture<Lambda.AliasConfiguration> in
                // Cleanup from testing
                invocationTearDown(services: services)
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
