//
//  LambdaInvokerError.swift
//  
//
//  Created by Joel Saltzman on 6/22/21.
//

import Foundation

public enum LambdaInvokerError: Error, CustomStringConvertible {
    case emptyPayloadFile(String)
    case invokeLambdaFailed(String, String)
    case verificationFailed(String)
    
    public var description: String {
        switch self {
        case .emptyPayloadFile(let file):
            return "No data was returned when trying to load payload file: \(file)"
        case .invokeLambdaFailed(let functionName, let message):
            return "There was an error invoking th Lambda \(functionName). Message: \(message))"
        case .verificationFailed(let functionName):
            return "The Lambda \(functionName) was invoked but an invalid response was returned."
        }
    }
}
