//
//  BuildInDockerError.swift
//  
//
//  Created by Joel Saltzman on 5/14/21.
//

import Foundation

public enum DockerizedBuilderError: Error, CustomStringConvertible {
    case missingProducts
    case packageDumpFailure
    case builtProductNotFound(String)
    case invalidDockerfilePath(String)

    public var description: String {
        switch self {
        case .missingProducts:
            return "No executable products were found. Does the package description contain a products section with at least one executable type?"
        case .packageDumpFailure:
            return "There was an error trying to parse the package manifest."
        case .builtProductNotFound(let path):
            return "The build succeeded but the executable was not found at: \(path)."
        case .invalidDockerfilePath(let path):
            return "Invalid URL to dockerfile: \(path)"
        }
    }
}
