//
//  PackageInDockerError.swift
//  
//
//  Created by Joel Saltzman on 5/27/21.
//

import Foundation

public enum PackagerError: Error, CustomStringConvertible {
    case productNotFound(String)
    case bootstrapFailure(String)
    case archivingFailure(String)
    case archiveNotFound(String)
    case dependencyFailure([URL], String)
    
    public var description: String {
        switch self {
        case .productNotFound(let path):
            return "Product was not found at path: \(path)"
        case .bootstrapFailure(let messages):
            return "Errors symlinking bootstrap: \(messages)"
        case .archivingFailure(let messages):
            return "Errors archiving: \(messages)"
        case .archiveNotFound(let path):
            return "Archiving completed but the zip was not found at path: \(path)"
        case .dependencyFailure(let dependencies, let message):
            return "Error trying to copy dependencies: \(dependencies.map(\.path)). Message: \(message)"
        }
    }
}
