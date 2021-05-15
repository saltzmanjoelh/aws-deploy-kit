//
//  AppDeployerError.swift
//  
//
//  Created by Joel Saltzman on 5/14/21.
//

import Foundation

public enum AppDeployerError: Error, CustomStringConvertible {
    case missingProducts
    case packageDumpFailure
    
    public var description: String {
        switch self {
        case .missingProducts:
            return "No executable products were found. Does the package description contain a products section with at least one executable type?"
        case .packageDumpFailure:
            return "There was an error trying to parse the package manifest."
        }
    }
}
