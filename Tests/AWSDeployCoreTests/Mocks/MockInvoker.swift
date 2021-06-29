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

struct MockInvoker: Invoker {
    
    static var liveInvoker = LambdaInvoker()
    
    @Mock
    var parsePayload = { (payload: String, services: Servicable) -> EventLoopFuture<ByteBuffer> in
        return MockInvoker.liveInvoker.parsePayload(payload, services: services)
    }
    func parsePayload(_ payload: String, services: Servicable) -> EventLoopFuture<ByteBuffer> {
        return $parsePayload.getValue((payload, services))
    }
    
    @Mock
    var loadPayloadFile = { (file: String, services: Servicable) -> EventLoopFuture<ByteBuffer> in
        return MockInvoker.liveInvoker.loadPayloadFile(at: file, services: services)
    }
    func loadPayloadFile(at file: String, services: Servicable) -> EventLoopFuture<ByteBuffer> {
        return $loadPayloadFile.getValue((file, services))
    }
    
    @Mock
    var invoke = { (function: String, payload: String, services: Servicable) -> EventLoopFuture<Data?> in
        return MockInvoker.liveInvoker.invoke(function: function, with: payload, services: services)
    }
    func invoke(function: String, with payload: String, services: Servicable) -> EventLoopFuture<Data?> {
        return $invoke.getValue((function, payload, services))
    }
}