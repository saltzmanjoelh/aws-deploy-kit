//
//  BuildInDockerError.swift
//  
//
//  Created by Joel Saltzman on 5/14/21.
//

import Foundation

public enum BuildInDockerError: Error, CustomStringConvertible {
    case builtProductNotFound(String)
    case invalidDockerfilePath(String)

    public var description: String {
        switch self {
        case .builtProductNotFound(let path):
            return "The build succeeded but the executable was not found at: \(path)."
        case .invalidDockerfilePath(let path):
            return "Invalid URL to dockerfile: \(path)"
        }
    }
}
