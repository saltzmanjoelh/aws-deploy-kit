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
    let preVerifyAction: (() -> EventLoopFuture<Void>)? = nil
    
    /// The payload to invoke with.
    let payload: String
    
    /// Verify the response from invoking with the payload.
    let verifyResponse: (Data) -> Bool
    
    public init(functionName: String,
                payload: String,
                verifyResponse: @escaping (Data) -> Bool) {
        self.functionName = functionName
        self.payload = payload
        self.verifyResponse = verifyResponse
    }
}
