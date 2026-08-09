import BookLensSupport
import Foundation

public struct LineFramer: Sendable {
    private var buffer = Data()
    private let maximumLineLength: Int

    public init(maximumLineLength: Int = 8 * 1_024 * 1_024) {
        self.maximumLineLength = maximumLineLength
    }

    public mutating func append(_ chunk: Data) throws -> [Data] {
        buffer.append(chunk)

        var lines: [Data] = []
        while let newline = buffer.firstIndex(of: 0x0A) {
            guard newline <= maximumLineLength else {
                throw BookLensError.protocolViolation(code: "line-too-long")
            }
            var line = buffer.prefix(upTo: newline)
            if line.last == 0x0D {
                line = line.dropLast()
            }
            if !line.isEmpty {
                lines.append(Data(line))
            }
            buffer.removeSubrange(...newline)
        }
        guard buffer.count <= maximumLineLength else {
            throw BookLensError.protocolViolation(code: "line-too-long")
        }
        return lines
    }
}
