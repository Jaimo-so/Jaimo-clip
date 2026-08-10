import Foundation

public enum TextChunker {
    public struct Chunk: Equatable, Sendable {
        public let text: String
        public let trailingSeparator: String

        public init(text: String, trailingSeparator: String) {
            self.text = text
            self.trailingSeparator = trailingSeparator
        }
    }

    public static let defaultTargetLength = 2_400
    public static let defaultMaximumLength = 3_200

    public static func chunks(
        from text: String,
        targetLength: Int = defaultTargetLength,
        maximumLength: Int = defaultMaximumLength
    ) -> [Chunk] {
        guard !text.isEmpty else { return [Chunk(text: "", trailingSeparator: "")] }

        let targetLength = max(1, targetLength)
        let maximumLength = max(targetLength, maximumLength)
        var chunks: [Chunk] = []
        var chunkStart = text.startIndex
        var index = text.startIndex
        var characterCount = 0

        while index < text.endIndex {
            let nextIndex = text.index(after: index)
            characterCount += 1

            if text[index].isNewline, characterCount >= targetLength {
                chunks.append(
                    Chunk(
                        text: String(text[chunkStart..<index]),
                        trailingSeparator: String(text[index..<nextIndex])
                    )
                )
                chunkStart = nextIndex
                characterCount = 0
            } else if characterCount >= maximumLength {
                chunks.append(
                    Chunk(
                        text: String(text[chunkStart..<nextIndex]),
                        trailingSeparator: ""
                    )
                )
                chunkStart = nextIndex
                characterCount = 0
            }

            index = nextIndex
        }

        if chunkStart < text.endIndex {
            chunks.append(Chunk(text: String(text[chunkStart...]), trailingSeparator: ""))
        } else if let last = chunks.last, !last.trailingSeparator.isEmpty {
            chunks.append(Chunk(text: "", trailingSeparator: ""))
        }

        return chunks
    }
}
