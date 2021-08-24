//
//  ProductType.swift
//  
//
//  Created by Joel Saltzman on 5/14/21.
//

import Foundation

public enum ProductType: String {
    case library
    case executable
}

public struct Product: Equatable {
    public let name: String
    public let type: ProductType
}
