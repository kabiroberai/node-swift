import SwiftDiagnostics

struct NodeDiagnosticMessage: DiagnosticMessage {
    let message: String
    private let messageID: String

    fileprivate init(_ message: String, messageID: String = #function) {
        self.message = message
        self.messageID = messageID
    }

    var diagnosticID: MessageID {
        MessageID(domain: "NodeAPIMacros", id: "\(type(of: self)).\(messageID)")
    }

    var severity: DiagnosticSeverity { .error }
}


extension DiagnosticMessage where Self == NodeDiagnosticMessage {
    static var expectedClassDecl: Self {
        .init("@NodeClass can only be applied to a class")
    }

    static var expectedFinal: Self {
        .init("@NodeClass classes must be final")
    }

    static var expectedFunction: Self {
        .init("@NodeMethod can only be applied to a function")
    }

    static var expectedProperty: Self {
        .init("@NodeProperty can only be applied to a property")
    }

    static var expectedInit: Self {
        .init("@NodeConstructor can only be applied to an initializer")
    }

    static var expectedName: Self {
        .init("@NodeName must have a name provided")
    }
}
