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
    let functionName: String
    
    /// Optionally, before invoking the Lambda, you can run some async tasks with this like setting up some existing data in the datastore.
    let preVerifyAction: (() -> EventLoopFuture<Void>)?
    
    /// The payload to invoke with.
    let payload: String
    
    /// Verify the response from invoking with the payload.
    let verifyResponse: ((Data) -> Bool)?
    
    public init(functionName: String,
                payload: String,
                preVerifyAction: (() -> EventLoopFuture<Void>)? = nil,
                verifyResponse: ((Data) -> Bool)? = nil) {
        self.functionName = functionName
        self.payload = payload
        self.preVerifyAction = preVerifyAction
        self.verifyResponse = verifyResponse
    }
}
