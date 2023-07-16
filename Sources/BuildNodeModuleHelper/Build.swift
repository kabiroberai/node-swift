import Foundation
import ArgumentParser

enum Configuration: String, ExpressibleByArgument {
    case release, debug
}

@main struct Module: ParsableCommand {
    @Option(name: .shortAndLong) var configuration: Configuration = .debug
    @Option(name: .customLong("Xcc", withSingleDash: true)) var cFlags: [String] = []
    @Option(name: .customLong("Xswiftc", withSingleDash: true)) var swiftcFlags: [String] = []
    @Option(name: .customLong("Xcxx", withSingleDash: true)) var cxxFlags: [String] = []
    @Option(name: .customLong("Xlinker", withSingleDash: true)) var linkerFlags: [String] = []
    @Option(name: .long) var product: String?
    @Flag(name: .shortAndLong) var verbose = false
    @Flag(name: [.long, .customLong("vv")]) var veryVerbose = false

    func run() throws {
        let options = BuildOptions(
            isDebug: configuration == .debug,
            isVerbose: verbose,
            isVeryVerbose: veryVerbose,
            linkerFlags: linkerFlags,
            swiftcFlags: swiftcFlags,
            cFlags: cFlags,
            cxxFlags: cxxFlags,
            product: product
        )
        let encoded = try JSONEncoder().encode(options)
        print("options=" + String(decoding: encoded, as: UTF8.self))
    }
}
