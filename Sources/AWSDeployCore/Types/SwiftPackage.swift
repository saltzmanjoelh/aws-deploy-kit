//
//  SwiftPackage.swift
//  
//
//  Created by Joel Saltzman on 5/14/21.
//
//  https://github.com/yonaskolb/Mint/blob/master/Sources/MintKit/SwiftPackage.swift

import Foundation

public struct SwiftPackage: Decodable {
    let products: [Product]
    
    struct Product: Decodable {

            let name: String
            let isExecutable: Bool

            enum CodingKeys: String, CodingKey {
                case name
                case type
                case productType = "product_type"
            }

            init(from decoder: Decoder) throws {
                let container = try decoder.container(keyedBy: CodingKeys.self)
                name = try container.decode(String.self, forKey: .name)
                if container.contains(.productType) {
                    // <= Swift 4.2
                    let type = try container.decode(String.self, forKey: .productType)
                    isExecutable = type == "executable"
                } else {
                    // > Swift 5.0
                    enum ProductCodingKeys: String, CodingKey {
                        case executable
                        case library
                    }

                    let typeContainer = try container.nestedContainer(keyedBy: ProductCodingKeys.self, forKey: .type)
                    isExecutable = typeContainer.contains(.executable)
                }
            }
        }
    
}
