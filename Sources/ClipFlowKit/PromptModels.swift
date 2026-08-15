import Foundation

public struct PromptVariable: Codable, Hashable, Sendable {
    public var name: String
    public var defaultValue: String
    public var isRequired: Bool

    public init(name: String, defaultValue: String = "", isRequired: Bool = true) {
        self.name = name
        self.defaultValue = defaultValue
        self.isRequired = isRequired
    }
}

public struct PromptItem: Identifiable, Hashable, Sendable {
    public let id: Int64
    public var title: String
    public var body: String
    public var groupName: String
    public var isFavorite: Bool
    public var variables: [PromptVariable]
    public var createdAt: Date
    public var updatedAt: Date
    public var lastUsedAt: Date?
    public var useCount: Int

    public init(
        id: Int64 = 0,
        title: String,
        body: String,
        groupName: String = "未分组",
        isFavorite: Bool = false,
        variables: [PromptVariable] = [],
        createdAt: Date = Date(),
        updatedAt: Date = Date(),
        lastUsedAt: Date? = nil,
        useCount: Int = 0
    ) {
        self.id = id
        self.title = title
        self.body = body
        self.groupName = groupName
        self.isFavorite = isFavorite
        self.variables = variables
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.lastUsedAt = lastUsedAt
        self.useCount = useCount
    }
}

public enum PromptTemplate {
    private static let expression = try! NSRegularExpression(
        pattern: #"\{\{\s*([^{}]+?)\s*\}\}"#
    )

    public static func variableNames(in body: String) -> [String] {
        let range = NSRange(body.startIndex..<body.endIndex, in: body)
        var seen = Set<String>()
        var names: [String] = []

        for match in expression.matches(in: body, range: range) {
            guard let captureRange = Range(match.range(at: 1), in: body) else { continue }
            let name = body[captureRange].trimmingCharacters(in: .whitespacesAndNewlines)
            guard !name.isEmpty, seen.insert(name).inserted else { continue }
            names.append(name)
        }
        return names
    }

    public static func variables(
        in body: String,
        preserving existing: [PromptVariable] = []
    ) -> [PromptVariable] {
        let previous = Dictionary(uniqueKeysWithValues: existing.map { ($0.name, $0) })
        return variableNames(in: body).map { previous[$0] ?? PromptVariable(name: $0) }
    }

    public static func render(_ body: String, values: [String: String]) -> String {
        let fullRange = NSRange(body.startIndex..<body.endIndex, in: body)
        let matches = expression.matches(in: body, range: fullRange)
        var result = body

        for match in matches.reversed() {
            guard let tokenRange = Range(match.range(at: 0), in: result),
                  let nameRange = Range(match.range(at: 1), in: result) else { continue }
            let name = result[nameRange].trimmingCharacters(in: .whitespacesAndNewlines)
            if let value = values[name] {
                result.replaceSubrange(tokenRange, with: value)
            }
        }
        return result
    }
}
