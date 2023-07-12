import SwiftDiagnostics

public struct NodeDiagnosticMessage: DiagnosticMessage {
    public let message: String
    private let messageID: String

    fileprivate init(_ message: String, messageID: String = #function) {
        self.message = message
        self.messageID = messageID
    }

    public var diagnosticID: MessageID {
        MessageID(domain: "NodeAPIMacros", id: "\(type(of: self)).\(messageID)")
    }

    public var severity: DiagnosticSeverity { .error }
}


extension DiagnosticMessage where Self == NodeDiagnosticMessage {
    public static var expectedClassDecl: Self {
        .init("Expected 'class' declaration")
    }

    public static var expectedFinal: Self {
        .init("NodeClass must be final")
    }

    public static var tooManyConstructors: Self {
        .init("A NodeClass can have at most one @NodeConstructor initializer; multiple found")
    }
}
