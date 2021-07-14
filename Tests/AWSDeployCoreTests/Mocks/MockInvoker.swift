//
//  MockInvoker.swift
//  
//
//  Created by Joel Saltzman on 6/23/21.
//

import Foundation
import AWSDeployCore
import NIO
import Mocking

struct MockInvoker: LambdaInvoker {
    
    static var liveInvoker = Invoker()
    
    @Mock
    var parsePayload = { (payload: String, services: Servicable) -> EventLoopFuture<ByteBuffer> in
        return MockInvoker.liveInvoker.parsePayload(payload, services: services)
    }
    func parsePayload(_ payload: String, services: Servicable) -> EventLoopFuture<ByteBuffer> {
        return $parsePayload.getValue((payload, services))
    }
    
    @Mock
    var loadPayloadFile = { (file: URL, services: Servicable) -> EventLoopFuture<ByteBuffer> in
        return MockInvoker.liveInvoker.loadPayloadFile(at: file, services: services)
    }
    func loadPayloadFile(at file: URL, services: Servicable) -> EventLoopFuture<ByteBuffer> {
        return $loadPayloadFile.getValue((file, services))
    }
    
    @Mock
    var verifyLambda = { (function: String, payload: String, verifyResponse: ((Data) -> Bool)?, services: Servicable) -> EventLoopFuture<Data> in
        return MockInvoker.liveInvoker.verifyLambda(function: function, with: payload, verifyResponse: verifyResponse, services: services)
    }
    func verifyLambda(function: String, with payload: String, verifyResponse: ((Data) -> Bool)?, services: Servicable) -> EventLoopFuture<Data> {
        return $verifyLambda.getValue((function, payload, verifyResponse, services))
    }
    
    @Mock
    var invoke = { (function: String, payload: String, services: Servicable) -> EventLoopFuture<Data> in
        return MockInvoker.liveInvoker.invoke(function: function, with: payload, services: services)
    }
    func invoke(function: String, with payload: String, services: Servicable) -> EventLoopFuture<Data> {
        return $invoke.getValue((function, payload, services))
    }
}
