//
//  APIGateway.V2.Request+Extensions.swift
//  
//
//  Created by Joel Saltzman on 4/30/21.
//

import Foundation
import AWSLambdaEvents

extension APIGateway.V2.Request {
    
    /// Takes a raw Lambda body for a request and wraps
    /// it in a dictionary that the APIGateway would use if you
    /// make a request to an APIGateway route.
    /// - Parameters:
    ///   - url: The url for the APIGateway route
    ///   - httpMethod: The HTTPMethod used when requesting the route
    ///   - body: The raw Lambda body you want wrapped
    /// - Returns: Dictionary with the keys required to create an APIGateway.V2.Request
    public static func wrapRawBody(url: URL,
                                   httpMethod: HTTPMethod,
                                   body: String) -> Data {
        var gatewayBody = [String: Any]()
        gatewayBody["routeKey"] = httpMethod.rawValue
        gatewayBody["version"] = "2.0"
        gatewayBody["rawPath"] = url.path
        gatewayBody["stageVariables"] = [String: String]()
        gatewayBody["isBase64Encoded"] = false
        gatewayBody["rawQueryString"] = url.query ?? ""
        gatewayBody["headers"] = ["host": url.host!]
        gatewayBody["requestContext"] = ["time": "\(Date())",
                                         "timeEpoch": Int(Date().timeIntervalSinceNow),
                                         "accountId": UUID().uuidString,
                                         "apiId": UUID().uuidString,
                                         "requestId": UUID().uuidString,
                                         "stage": "$default",
                                         "domainName": url.host!,
                                         "domainPrefix": "",
                                         "http": ["path": url.path,
                                                  "method": httpMethod.rawValue,
                                                  "protocol": "HTTP/1.1",
                                                  "sourceIp": "127.0.0.1",
                                                  "userAgent": "LocalDebugging"]]
        gatewayBody["body"] = body
        let data = try! JSONSerialization.data(withJSONObject: gatewayBody, options: [])
        return data
    }
}
