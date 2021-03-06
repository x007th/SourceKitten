//
//  DocCommand.swift
//  SourceKitten
//
//  Created by JP Simard on 2015-01-07.
//  Copyright (c) 2015 SourceKitten. All rights reserved.
//

import Commandant
import Foundation
import LlamaKit
import SourceKittenFramework

public struct DocCommand: CommandType {
    public let verb = "doc"
    public let function = "Print Swift docs as JSON or Objective-C docs as XML"

    public func run(mode: CommandMode) -> Result<()> {
        return DocOptions.evaluate(mode).flatMap { options in
            let args = Process.arguments
            if options.objc {
                return DocCommand.runObjC(options, args: args)
            }
            if options.singleFile {
                return DocCommand.runSwiftSingleFile(args)
            }
            let moduleName: String? = countElements(options.moduleName) > 0 ? options.moduleName : nil
            return DocCommand.runSwiftModule(moduleName, args: args)
        }
    }

    public static func runSwiftModule(moduleName: String?, args: [String]) -> Result<()> {
        let xcodeBuildArgumentsStart = (moduleName != nil) ? 4 : 2
        let xcodeBuildArguments = Array<String>(args[xcodeBuildArgumentsStart..<args.count])
        let module = Module(xcodeBuildArguments: xcodeBuildArguments, name: moduleName)

        // FIXME: Don't spawn new processes once this SourceKit bug is fixed:
        // https://github.com/jpsim/sourcekitten/pull/19#issuecomment-69715853
        if let docs = module?.docsBySpawningNewProcesses {
            println(toJSON(docs))
            return success(())
        }
//        if let docs = module?.docs {
//            println(docs)
//            return success(())
//        }
        return failure(SourceKittenError.DocFailed.error)
    }

    public static func runSwiftSingleFile(args: [String]) -> Result<()> {
        if args.count < 5 {
            return failure(SourceKittenError.InvalidArgument(description: "at least 5 arguments are required when using `--single-file`").error)
        }
        let sourcekitdArguments = Array<String>(args[4..<args.count])
        if let file = File(path: args[3]) {
            let docs = SwiftDocs(file: file, arguments: sourcekitdArguments)
            println(docs)
            return success(())
        }
        return failure(SourceKittenError.ReadFailed(path: args[3]).error)
    }

    public static func runObjC(options: DocOptions, args: [String]) -> Result<()> {
        if args.count < 5 {
            return failure(SourceKittenError.InvalidArgument(description: "at least 5 arguments are required when using `--objc`").error)
        }
        let startIndex = options.singleFile ? 4 : 3
        let (headerFiles, xcodebuildArguments) = parseHeaderFilesAndXcodebuildArguments(Array<String>(args[startIndex..<args.count]))
        if headerFiles.count == 0 {
            return failure(SourceKittenError.InvalidArgument(description: "must pass in at least one Objective-C header file").error)
        }
        if let translationUnit = ClangTranslationUnit(headerFiles: headerFiles, xcodeBuildArguments: xcodebuildArguments) {
            println(translationUnit)
            return success(())
        }
        return failure(SourceKittenError.DocFailed.error)
    }
}

public struct DocOptions: OptionsType {
    public let singleFile: Bool
    public let moduleName: String
    public let objc: Bool

    public static func create(singleFile: Bool)(moduleName: String)(objc: Bool) -> DocOptions {
        return self(singleFile: singleFile, moduleName: moduleName, objc: objc)
    }

    public static func evaluate(m: CommandMode) -> Result<DocOptions> {
        return create
            <*> m <| Option(key: "single-file", defaultValue: false, usage: "only document one file")
            <*> m <| Option(key: "module-name", defaultValue: "",    usage: "name of module to document (can't be used with `--single-file` or `--objc`)")
            <*> m <| Option(key: "objc",        defaultValue: false, usage: "document Objective-C headers")
    }
}
