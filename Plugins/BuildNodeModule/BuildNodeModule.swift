import PackagePlugin
import Foundation

@main struct Plugin: CommandPlugin {
    func performCommand(context: PluginContext, arguments: [String]) async throws {
        print("Starting build...")

        let helper = try context.tool(named: "BuildNodeModuleHelper").path
        let options: BuildOptions
        do {
            options = try await BuildOptions.parse(helper: helper, arguments: arguments)
        } catch is ExitError {
            return
        }

        var parameters = PackageManager.BuildParameters()
        parameters.configuration = options.configuration
        parameters.logging = options.logging
        parameters.otherCFlags = options.cFlags
        parameters.otherCxxFlags = options.cxxFlags
        parameters.otherSwiftcFlags = options.swiftcFlags
        parameters.otherLinkerFlags = options.linkerFlags

        let root = Path(#filePath)
            .removingLastComponent()
            .removingLastComponent()
            .removingLastComponent()
        _ = root
        // TODO: Determine flags based on deployment target (can we do this?)
        #if os(macOS)
        parameters.otherLinkerFlags += ["-undefined", "dynamic_lookup"]
        #elseif os(Linux)
        parameters.otherLinkerFlags += ["-undefined"]
        #elseif os(Windows)
        #if arch(x86_64)
        parameters.otherLinkerFlags += [root.appending("vendored", "node", "lib", "node-win32-x64.lib").string]
        #else
        #warning("The current architecture is unsupported on Windows.")
        #endif
        parameters.otherLinkerFlags += ["delayimp.lib", "/DELAYLOAD:node.exe"]
        #else
        #warning("The current OS is unsupported.")
        #endif

        let product: LibraryProduct
        if let productName = options.product {
            let found = try context.package.products(named: [productName])[0]
            guard let found = found as? LibraryProduct else {
                throw BuildError("Product '\(productName)' must be a library")
            }
            guard found.kind == .dynamic else {
                throw BuildError("Product '\(productName)' must have type '.dynamic'")
            }
            product = found
        } else {
            let dylibs = context.package.products(ofType: LibraryProduct.self).filter { $0.kind == .dynamic }
            switch dylibs.count {
            case 0:
                throw BuildError("Please add a .dynamic library product to your package")
            case 1:
                product = dylibs[0]
            default:
                throw BuildError("Multiple dynamic library products found. Specify which one to build with --product. Options: \(dylibs.map(\.name))")
            }
        }

        // we could optimize this a bit to skip repeated vertices but a product most commonly
        // only has one target anyway, and we can assume recursiveTargetDependencies is optimized
        guard product.targets.lazy.flatMap(\.recursiveTargetDependencies).contains(where: { $0.name == "NodeModuleSupport" })
        else {
            throw BuildError(#"Product '\#(product.name)' must have '.product(name: "NodeModuleSupport", package: "node-swift")'as a dependency."#)
        }

        let outputName = "\(product.name).node"
        print("Building \(outputName)...")

        let result = try packageManager.build(.product(product.name), parameters: parameters)
        print(result.logText, terminator: "")
        guard result.succeeded else { throw BuildError("Build failed") }
        guard let artifact = result.builtArtifacts.first(where: { $0.kind == .dynamicLibrary })
            else { throw BuildError("Could not find module artifact") }

        let moduleDir = artifact.path.removingLastComponent()
        let modulePath = moduleDir.appending(outputName)
        let buildDir = moduleDir.removingLastComponent().removingLastComponent()
        let linkPath = buildDir.appending(outputName)

        try? FileManager.default.removeItem(atPath: modulePath.string)
        try FileManager.default.copyItem(
            atPath: artifact.path.string,
            toPath: modulePath.string
        )

        try? FileManager.default.removeItem(atPath: linkPath.string)
        try FileManager.default.createSymbolicLink(atPath: linkPath.string, withDestinationPath: modulePath.string)
    }
}

struct BuildError: Error, CustomStringConvertible {
    let description: String
    init(_ description: String) {
        self.description = description
    }
}

struct ExitError: Error {}

extension BuildOptions {
    static func parse(helper: Path, arguments: [String]) async throws -> Self {
        let output = Pipe()
        let process = Process()
        process.executableURL = URL(filePath: helper.string)
        process.arguments = arguments
        process.standardOutput = output
        try await process.run()
        guard process.terminationStatus == 0 else { throw ExitError() }

        var data = try output.fileHandleForReading.readToEnd() ?? Data()
        let prefix = self.prefix.utf8
        guard data.starts(with: prefix) else {
            try FileHandle.standardOutput.write(contentsOf: data)
            throw ExitError()
        }
        data.trimPrefix(prefix)
        return try JSONDecoder().decode(BuildOptions.self, from: data)
    }

    var configuration: PackageManager.BuildConfiguration {
        isDebug ? .debug : .release
    }

    var logging: PackageManager.BuildLogVerbosity {
        if isVeryVerbose { .debug }
        else if isVerbose { .verbose }
        else { .concise }
    }
}

extension Process {
    func run() async throws {
        let oldHandler = terminationHandler
        async let didTerminate: Void = withCheckedContinuation { cont in
            terminationHandler = {
                oldHandler?($0)
                cont.resume()
            }
        }
        try { try run() }()
        await didTerminate
    }
}
