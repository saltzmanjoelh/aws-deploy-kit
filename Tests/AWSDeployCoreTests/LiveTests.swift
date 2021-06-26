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
    
    
    
    func testBuildAndPublishNewLambda() throws {
        guard shouldTestWithLive() else { return }
        // Create the package
        let packageDirectory = try createTempPackage()
        // Make sure that the function does not already exist
        try deleteLambda(ExamplePackage.executableOne).wait()
        
        // Build and publish
        var instance = try AWSDeployCommand.parseAsRoot([BuildAndPublishCommand.configuration.commandName!, "-d", packageDirectory.path, ExamplePackage.executableOne]) as! BuildAndPublishCommand

        // When calling run
        // Then no errors should be thrown
        XCTAssertNoThrow(try instance.run())
    }
    
    
    func deleteLambda(_ functionName: String) -> EventLoopFuture<Void> {
        // Check if there is a role to delete
        Services.shared.lambda.getFunctionConfiguration(.init(functionName: functionName))
            .map { (config: Lambda.FunctionConfiguration) -> String? in
                if let components = config.role?.components(separatedBy: ":role/"), // arn:aws:iam::123456789012:role/executableOne-role-2CFF0F14
                   components.count == 2, // [arn:aws:iam::123456789012, executableOne-role-2CFF0F14]
                   let role = components.last, // executableOne-role-2CFF0F14
                    role.contains(functionName) {
                    return role
                }
                return nil
                
            }
            .flatMap({ (role: String?) -> EventLoopFuture<Void> in
                
                guard let roleName = role else { // Move on
                    return Services.shared.iam.eventLoopGroup.next().makeSucceededFuture(Void())
                }
                // Get the role polices so that we can detach them
                return Services.shared.iam.listAttachedRolePolicies(.init(roleName: roleName))
                    .flatMap({ policies -> EventLoopFuture<Void> in
                        let promise = Services.shared.iam.eventLoopGroup.next().makePromise(of: Void.self)
                        // Detach all policies
                        let futures = policies.attachedPolicies!.map({ policy in
                            Services.shared.iam.detachRolePolicy(.init(policyArn: policy.policyArn!, roleName: roleName))
                        })
                        EventLoopFuture.andAllSucceed(futures, promise: promise)
                        return promise.futureResult
                    })
            })
            // Delete the Lambda
            .flatMap({ _ in
                Services.shared.lambda.deleteFunction(.init(functionName: functionName))
            })
            .flatMapError { (error: Error) in
                guard "\(error)".contains("Function not found") else {
                    return self.mockServices.lambda.eventLoopGroup.next().makeFailedFuture(error)
                }
                print("There was a problem deleting the function: \(error)")
                return self.mockServices.lambda.eventLoopGroup.next().makeSucceededVoidFuture()
            }
    }
}
