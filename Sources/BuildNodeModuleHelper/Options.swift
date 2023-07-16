struct BuildOptions: Codable {
    static let prefix = "options="

    let isDebug: Bool
    let isVerbose: Bool
    let isVeryVerbose: Bool
    let linkerFlags: [String]
    let swiftcFlags: [String]
    let cFlags: [String]
    let cxxFlags: [String]
    let product: String?
}
