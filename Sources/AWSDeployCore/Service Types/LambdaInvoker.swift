//
//  Invoker.swift
//  
//
//  Created by Joel Saltzman on 6/22/21.
//

import Foundation
import NIO
import SotoLambda

public protocol Invoker {
    func parsePayload(_ payload: String, services: Servicable) -> EventLoopFuture<ByteBuffer>
    func loadPayloadFile(at file: String, services: Servicable) -> EventLoopFuture<ByteBuffer>
    func invoke(function: String, with payload: String, services: Servicable) -> EventLoopFuture<Data?>
}

public struct LambdaInvoker: Invoker {
    
    public init() { }
    
    /// Converts the provided payload into Data.
    /// - Parameters:
    ///   - payload: A file path or JSON string
    ///   - services: The set of services which will be used to execute your request with.
    /// - Returns: JSON data
    public func parsePayload(_ payload: String, services: Servicable) -> EventLoopFuture<ByteBuffer> {
        if payload.hasPrefix("file://") {
            return services.invoker.loadPayloadFile(at: payload, services: services)
        }
        return services.lambda.eventLoopGroup.next().makeSucceededFuture(ByteBuffer(string: payload))
    }
    
    /// Reads a file to get the JSON contents.
    /// - Parameters:
    ///   - file: Path to the file you want to load.
    ///   - services: The set of services which will be used to execute your request with.
    /// - Returns: ByteBuffer of the contents of the file.
    public func loadPayloadFile(at file: String, services: Servicable) -> EventLoopFuture<ByteBuffer> {
        guard let data = services.fileManager.contents(atPath: file) else {
            return services.lambda.eventLoopGroup.next().makeFailedFuture(LambdaInvokerError.emptyPayloadFile(file))
        }
        return services.lambda.eventLoopGroup.next().makeSucceededFuture(ByteBuffer(data: data))
    }
    
    /// Invoke a Lambda function.
    /// - Parameters:
    ///   - function: The name of the Lambda function, version, or alias.  Name formats     Function name - my-function (name-only), my-function:v1 (with alias).    Function ARN - arn:aws:lambda:us-west-2:123456789012:function:my-function.    Partial ARN - 123456789012:function:my-function.   You can append a version number or alias to any of the formats. The length constraint applies only to the full ARN. If you specify only the function name, it is limited to 64 characters in length.
    ///   - payload: Either a path prefixed with "file://" that points to a JSON file, or a JSON string. This is be sent to your Lambda.
    ///   - services: The set of services which will be used to execute your request with.
    /// - Throws: Throws if there was a problem executing your Lambda.
    /// - Returns: Data of the response from your Lambda.
    public func invoke(function: String, with payload: String, services: Servicable) -> EventLoopFuture<Data?> {
        services.logger.trace("Invoking Lambda: \(function). Payload: \(payload)")
        return services.invoker.parsePayload(payload, services: services)
            .flatMap { (buffer: ByteBuffer) -> EventLoopFuture<Lambda.InvocationResponse> in
                services.lambda.invoke(.init(functionName: function, payload: .byteBuffer(buffer)),
                                       logger: services.awsLogger)
            }
            .flatMapThrowing { (response: Lambda.InvocationResponse) -> Data? in
                // Throw if there was an error executing the function
                if let _ = response.functionError,
                   let responseMessage = response.payload?.asString()
                {
                    throw LambdaInvokerError.invokeLambdaFailed(function, responseMessage)
                }
                return response.payload?.asData()
            }
    }
}