//
//  Redirect.swift
//  
//
//  Created by Joel Saltzman on 5/6/21.
//

import Foundation
import Logging

/// Reading the pipe happens in chunks and does not always end on valid character boundries.
/// Buffer the output until we hit a newline.
/// https://www.objc.io/blog/2019/04/30/reading-from-standard-input-output/
public class BufferedPipe {
    
    var internalPipe = Pipe()
    var buffer = Data()
    
    open var fileHandleForReading: FileHandle { internalPipe.fileHandleForReading }

    open var fileHandleForWriting: FileHandle { internalPipe.fileHandleForWriting }
    
    /// @param readabilityHandler A closure that you want executed once a valid String is available.
    public init(readabilityHandler: @escaping (String) -> Void) {
        internalPipe = Pipe()
        fileHandleForReading.readabilityHandler = { [weak self] handle in
            guard let strongSelf = self else { return }

            let data = handle.availableData
            strongSelf.buffer.append(data)
            guard let string = String(data: strongSelf.buffer, encoding: .utf8),
                  string.last?.isNewline == true
            else { return }

            strongSelf.buffer.removeAll()
            readabilityHandler(string)
        }
    }
    
}
