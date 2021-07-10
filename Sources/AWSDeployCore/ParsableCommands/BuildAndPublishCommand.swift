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
        // Convert the String to URL
        let sshPrivateKey: URL?
        if let keyPath = buildOptions.sshKeyPath,
           services.fileManager.fileExists(atPath: keyPath){
            sshPrivateKey = URL(fileURLWithPath: keyPath)
        } else {
            sshPrivateKey = nil
        }
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
                                                             sshPrivateKeyPath: sshPrivateKey,
                                                             services: services)
        // Publish
        _ = try archiveURLs.map({ archiveURL in
            try services.publisher.publishArchive(archiveURL,
                                                  invokePayload: publishOptions.payloadOption.payload,
                                                  from: packageDirectory,
                                                  verifyResponse: nil,
                                                  alias: publishOptions.alias,
                                                  services: services).wait()
        })
        
    }

}

