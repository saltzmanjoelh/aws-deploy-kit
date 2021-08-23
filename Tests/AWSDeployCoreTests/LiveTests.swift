//
//  LiveTests.swift
//  
//
//  Created by Joel Saltzman on 6/24/21.
//

import Foundation
import XCTest
import Logging
import LogKit
import SotoLambda
import SotoIAM
@testable import AWSDeployCore


/*
 * !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
 * !!! THESE WILL RUN AGAINST THE AWS SERVERS !!!
 * !!! THEY CAN ONLY BE ACTIVATED IF YOU      !!!
 * !!! ADD  TEST-WITH-LIVE  TO YOUR ENV VARS  !!!
 * !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
 */


/// These are integration tests with live services. We won't stub the services.
class LiveTests: XCTestCase {
    
    var mockServices: MockServices!
    
    override func setUp() {
        continueAfterFailure = false
        mockServices = MockServices()
    }
    override func tearDownWithError() throws {
        try super.tearDownWithError()
        mockServices.cleanup()
        try cleanupTestPackage()
    }
    
    func testWithLiveAWS() throws {
        guard shouldTestWithLive() else { return }
        // Make sure that the function does not already exist
        try deleteLambda(ExamplePackage.executableOne).wait()
        // Create the package
        let packageDirectory = try createTempPackage()

        // -- Build Command --
        // Build the ExamplePackage
        var build = try AWSDeployCommand.parseAsRoot([BuildCommand.configuration.commandName!, "-d", packageDirectory.path, ExamplePackage.executableOne]) as! BuildCommand
        try build.run()
        // After a successful build, there should be a zip file
        let destinationDirectory = Services.shared.packager.destinationURLForProduct(ExamplePackage.executableOne, in: packageDirectory)
        let archivePath = Services.shared.packager.archivePath(for: ExamplePackage.executableOne, in: destinationDirectory)
        XCTAssertTrue(Services.shared.fileManager.fileExists(atPath: archivePath.path))

        // -- Publish Command --
        // Publish the zip to a new Lambda
        var publisher = try AWSDeployCommand.parseAsRoot([PublishCommand.configuration.commandName!, archivePath.path]) as! PublishCommand
        try publisher.run()
        // The Lambda should now exist
        let newConfig = try Services.shared.lambda.getFunctionConfiguration(.init(functionName: ExamplePackage.executableOne)).wait()
        // The alias should be created, we check it's version later
        let newAlias = try Services.shared.lambda.getAlias(.init(functionName: ExamplePackage.executableOne, name: Publisher.defaultAlias)).wait()

        // -- Build And Publish Command --
        // Update and existing
        var buildAndPublish = try AWSDeployCommand.parseAsRoot([BuildAndPublishCommand.configuration.commandName!, "-d", packageDirectory.path, ExamplePackage.executableOne]) as! BuildAndPublishCommand
        try buildAndPublish.run()
        // The Lambda should be updated now
        let updatedConfig = try Services.shared.lambda.getFunctionConfiguration(.init(functionName: ExamplePackage.executableOne)).wait()
        // The alias should be created and pointed to the first version
        let updatedAlias = try Services.shared.lambda.getAlias(.init(functionName: ExamplePackage.executableOne, name: Publisher.defaultAlias)).wait()

        // Check that the new and updated versions are different
        XCTAssertNotEqual(newConfig.revisionId, updatedConfig.revisionId)
        XCTAssertNotEqual(newAlias.functionVersion, updatedAlias.functionVersion)
        
        // -- Invoke Command --
        // Invoke the Lambda
        var invoke = try AWSDeployCommand.parseAsRoot([InvokeCommand.configuration.commandName!, ExamplePackage.executableOne, ExamplePackage.invokeJSON]) as! InvokeCommand
        try invoke.run()
        XCTAssertNotNil(Services.shared.logCollector.logs.allEntries.first(where: { $0.message.contains("Hello") }), "There should be a response log that contains \"Hello\"")
    }
    
    func buildAndPublishExistingLambda() {
        
    }
    
    func testInvoke() {
        
    }
    
    
    func deleteLambda(_ functionName: String) -> EventLoopFuture<Void> {
        // Check if there is a role to delete
        print("Cleaning up: \(functionName)")
        return Services.shared.lambda.getFunctionConfiguration(.init(functionName: functionName))
            .map { (config: Lambda.FunctionConfiguration) -> String? in
                if let components = config.role?.components(separatedBy: ":role/"), // arn:aws:iam::123456789012:role/executableOne-role-2CFF0F14
                   components.count == 2, // [arn:aws:iam::123456789012, executableOne-role-2CFF0F14]
                   let role = components.last, // executableOne-role-2CFF0F14
                    role.contains(functionName) {
                    print("Found role: \(role)")
                    return role
                }
                print("Nothing to cleanup")
                return nil
                
            }
            .flatMap({ (role: String?) -> EventLoopFuture<Void> in
                return self.deleteRole(role)
            })
            
            // Delete the Lambda
            .flatMap({ _ -> EventLoopFuture<Void> in
                print("Deleting Lambda: \(functionName)")
                return Services.shared.lambda.deleteFunction(.init(functionName: functionName))
            })
            .flatMapError { (error: Error) in
                guard !"\(error)".contains("Function not found") else {
                    return self.mockServices.lambda.eventLoopGroup.next().makeSucceededVoidFuture()
                }
                print("There was a problem deleting the function: \(error)")
                return self.mockServices.lambda.eventLoopGroup.next().makeFailedFuture(error)
            }
    }
    func deleteRole(_ role: String?) -> EventLoopFuture<Void> {
        guard let roleName = role else { // Move on
            print("Nothing to delete")
            return Services.shared.iam.eventLoopGroup.next().makeSucceededFuture(Void())
        }
        // Get the role polices so that we can detach them
        return Services.shared.iam.listAttachedRolePolicies(.init(roleName: roleName))
            .flatMap({ policies -> EventLoopFuture<Void> in
                let promise = Services.shared.iam.eventLoopGroup.next().makePromise(of: Void.self)
                // Detach all policies
                let futures = policies.attachedPolicies!.map({ (policy: IAM.AttachedPolicy) -> EventLoopFuture<Void> in
                    print("Detaching \(policy.policyArn!)")
                    return Services.shared.iam.detachRolePolicy(.init(policyArn: policy.policyArn!, roleName: roleName))
                })
                EventLoopFuture.andAllSucceed(futures, promise: promise)
                return promise.futureResult
            })
            .flatMap({ _ in
                print("Deleting role: \(roleName)")
                return Services.shared.iam.deleteRole(.init(roleName: roleName))
            })
    }
}
