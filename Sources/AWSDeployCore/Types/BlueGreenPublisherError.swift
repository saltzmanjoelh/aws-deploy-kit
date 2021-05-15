//
//  BlueGreenPublisherError.swift
//  
//
//  Created by Joel Saltzman on 5/14/21.
//

import Foundation

public enum BlueGreenPublisherError: Error, CustomStringConvertible {
    case archiveDoesNotExist(String)
    case invokeLambdaFailed(String, String)
    case invalidArchiveName(String)
    case invalidFunctionConfiguration(String, String)

    public var description: String {
        switch self {
        case .archiveDoesNotExist(let path):
            return "The archive at path: \(path) could not be found."
        case .invokeLambdaFailed(let functionName, let message):
            return "There was an error invoking the \(functionName) lambda. Message: \(message))"
        case .invalidArchiveName(let path):
            return "Invalid archive name: \(path). It should be in the format: $executable_yyyymmdd_HHMM.zip"
        case .invalidFunctionConfiguration(let field, let source):
            return "Invalid FunctionConfiguration. Required field \"\(field)\" was missing in \(source)."
        }
    }
}
