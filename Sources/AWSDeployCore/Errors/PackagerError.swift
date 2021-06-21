//
//  PackageInDockerError.swift
//  
//
//  Created by Joel Saltzman on 5/27/21.
//

import Foundation

public enum PackagerError: Error, CustomStringConvertible {
    case executableNotFound(String)
    case bootstrapFailure(String)
    case archivingFailure(String)
    case archiveNotFound(String)
    case dependencyFailure(URL, String)
    
    public var description: String {
        switch self {
        case .executableNotFound(let path):
            return "Executable was not found at path: \(path)"
        case .bootstrapFailure(let messages):
            return "Errors symlinking bootstrap: \(messages)"
        case .archivingFailure(let messages):
            return "Errors archiving: \(messages)"
        case .archiveNotFound(let path):
            return "Archiving completed but the zip was not found at path: \(path)"
        case .dependencyFailure(let dependency, let message):
            return "Error trying to copy dependency: \(dependency.path). Message: \(message)"
        }
    }
}
