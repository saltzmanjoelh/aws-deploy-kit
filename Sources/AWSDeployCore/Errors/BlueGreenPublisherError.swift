//
//  BlueGreenPublisherError.swift
//  
//
//  Created by Joel Saltzman on 5/14/21.
//

import Foundation
import SotoIAM

public enum BlueGreenPublisherError: Error, CustomStringConvertible {
    case archiveDoesNotExist(String)
    case invalidArchiveName(String)
    case invalidFunctionConfiguration(String, String)
    case accountIdUnavailable
    case invalidCreateRoleResponse(String, String)

    public var description: String {
        switch self {
        case .archiveDoesNotExist(let path):
            return "The archive at path: \(path) could not be found."
        case .invalidArchiveName(let path):
            return "Invalid archive name: \(path). It should be in the format: $EXECUTABLE_NAME.zip"
        case .invalidFunctionConfiguration(let field, let source):
            return "Invalid FunctionConfiguration. Required field \"\(field)\" was missing in \(source)."
        case .accountIdUnavailable:
            return "The account id from STS was unavailable. Please provide the full arn for the role."
        case .invalidCreateRoleResponse(let expectedRoleName, let receivedRoleName):
            return "Unexpected role received from createRole. Expected: \(expectedRoleName), received: \(receivedRoleName)"
        }
    }
}
