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
        .init("Expected 'class' declaration")
    }

    static var expectedFinal: Self {
        .init("NodeClass must be final")
    }

    static var tooManyConstructors: Self {
        .init("A NodeClass can have at most one @NodeConstructor initializer; multiple found")
    }
}
