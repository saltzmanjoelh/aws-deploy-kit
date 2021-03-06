//
//  BuildAndPublishCommand.swift
//  
//
//  Created by Joel Saltzman on 6/21/21.
//

import Foundation
import ArgumentParser

struct BuildAndPublishCommand: ParsableCommand {
    public static let configuration = CommandConfiguration(commandName: "build-and-publish",
                                                           abstract: "Run both build and publish commands in one shot. `aws-deploy build-and-publish` supports all options from both commands. Please see the `aws-deploy build --help` and `aws-deploy publish --help` for a full reference.")
    
    @OptionGroup
    var buildOptions: BuildOptions

    @OptionGroup
    var publishOptions: PublishOptions

    
    public mutating func run() throws {
        Services.shared.builder.preBuildCommand = buildOptions.preBuildCommand
        Services.shared.builder.postBuildCommand = buildOptions.postBuildCommand
        Services.shared.publisher.functionRole = publishOptions.functionRole
        try self.run(services: Services.shared)
    }

    public mutating func run(services: Servicable) throws {
        // Get the packageDirectory
        let packageDirectory = URL(fileURLWithPath: buildOptions.directory.path)
        // Get the final list of products we will be building
        let parsedProducts = try services.builder.parseProducts(buildOptions.products,
                                                                skipProducts: buildOptions.skipProducts,
                                                                at: packageDirectory,
                                                                services: services)
        // Build and archive
        let archiveURLs = try services.builder.buildProducts(parsedProducts,
                                                             at: packageDirectory,
                                                             services: services)
        // Publish
        _ = try archiveURLs.map({ archiveURL in
            var invocationTask: InvocationTask? = nil
            if publishOptions.payloadOption.payload.count > 1 {
                invocationTask = InvocationTask(functionName: archiveURL.lastPathComponent,
                                                payload: publishOptions.payloadOption.payload,
                                                setUp: nil,
                                                verifyResponse: { _ in /* valid */ },
                                                tearDown: nil)
            }
        
            _ = try services.publisher.publishArchive(archiveURL,
                                                  from: packageDirectory,
                                                  invocationTask: invocationTask,
                                                  alias: publishOptions.alias,
                                                  services: services).wait()
        })
        
    }

}

