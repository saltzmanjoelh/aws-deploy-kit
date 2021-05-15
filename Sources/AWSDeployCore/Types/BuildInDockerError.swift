//
//  BuildInDockerError.swift
//  
//
//  Created by Joel Saltzman on 5/14/21.
//

import Foundation

public enum BuildInDockerError: Error, CustomStringConvertible {
    case scriptNotFound(String)
    case archivePathNotReceived(String)
    case archiveNotFound(String)
    case invalidDockerfilePath(String)

    public var description: String {
        switch self {
        case .scriptNotFound(let scriptName):
            return "The \(scriptName) script was not found in the resources."
        case .archivePathNotReceived(let productName):
            return "The path to the completed archive was not found for \(productName)."
        case .archiveNotFound(let path):
            return "The build succeeded but the archive was not found at: \(path)."
        case .invalidDockerfilePath(let path):
            return "Invalid URL to dockerfile: \(path)"
        }
    }
}
