import Foundation

/// Splits a TCP byte stream into newline-delimited messages. Compact JSON
/// never contains a raw newline, so one line is exactly one `Envelope`.
public struct LineFramer: Sendable {
    public static let maxLineBytes = 4096

    private var buffer = Data()

    public init() {}

    public enum FramingError: Error, Equatable { case lineTooLong }

    /// Feeds bytes and returns every complete line. Throws if a peer sends an
    /// oversized line, so a misbehaving client cannot grow memory without bound.
    public mutating func push(_ data: Data) throws -> [Data] {
        buffer.append(data)
        var lines: [Data] = []
        while let newline = buffer.firstIndex(of: 0x0A) {
            let line = buffer[buffer.startIndex..<newline]
            buffer.removeSubrange(buffer.startIndex...newline)
            if !line.isEmpty { lines.append(Data(line)) }
        }
        if buffer.count > Self.maxLineBytes {
            buffer.removeAll()
            throw FramingError.lineTooLong
        }
        return lines
    }

    public static func encode(_ envelope: Envelope) throws -> Data {
        var d = try JSONEncoder().encode(envelope)
        d.append(0x0A)
        return d
    }
}
