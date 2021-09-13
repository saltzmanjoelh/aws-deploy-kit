//
//  InvocationTask.swift
//  
//
//  Created by Joel Saltzman on 7/10/21.
//

import Foundation
import NIO

public struct InvocationTask {
    
    /// The name of the Lambda function to invoke.
    public var functionName: String
    
    /// Optionally, before invoking the Lambda, you can run some async tasks with this like setting up some existing data in the datastore.
    public var setUp: ((Servicable) -> EventLoopFuture<Void>)?
    
    /// The payload to invoke with.
    public var payload: String
    
    /// Verify the response from invoking with the payload.
    public var verifyResponse: (Data) throws -> Void
    
    /// If this InvocationTask added anything for example, to the datastore, you can use tearDown to clean it up.
    public var tearDown: ((Servicable) -> EventLoopFuture<Void>)?
    
    public init(functionName: String,
                payload: String,
                setUp: ((Servicable) -> EventLoopFuture<Void>)? = nil,
                verifyResponse: @escaping (Data) throws -> Void,
                tearDown: ((Servicable) -> EventLoopFuture<Void>)? = nil) {
        self.functionName = functionName
        self.payload = payload
        self.setUp = setUp
        self.verifyResponse = verifyResponse
        self.tearDown = tearDown
    }
    
    public func run(services: Servicable) -> EventLoopFuture<Data> {
        // Handle setup
        let setUp: (Servicable) -> EventLoopFuture<Void>
        if let action = self.setUp {
            setUp = action
        } else {
            // If we don't have a setUp action, just return
            setUp = { (services: Servicable) -> EventLoopFuture<Void> in
                services.lambda.eventLoopGroup.next().makeSucceededVoidFuture()
            }
        }
        return setUp(services).flatMap({ _ -> EventLoopFuture<Data> in
            services.invoker.verifyLambda(function: functionName,
                                         with: payload,
                                         verifyResponse: verifyResponse,
                                         services: services)
        })
        .flatMap { (data: Data) -> EventLoopFuture<Data> in
            guard let tearDownAction = self.tearDown else {
                return services.lambda.eventLoopGroup.next().makeSucceededFuture(data)
            }
            return tearDownAction(services).map({ _ in data })
        }
    }
}
