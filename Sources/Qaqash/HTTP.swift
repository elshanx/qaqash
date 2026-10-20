import Foundation
import Network

struct Request {
    var method = ""
    var path = ""
    var query = ""
    var headers: [String: String] = [:]
    var body = Data()
}

struct Response {
    var status = 200
    var body = Data()
}

final class HTTPServer {
    private let listener: NWListener
    private let handle: (Request) -> Response
    private static let headerEnd = Data("\r\n\r\n".utf8)

    init(port: UInt16, parameters: NWParameters, service: NWListener.Service? = nil, failed: @escaping () -> Void = {}, handle: @escaping (Request) -> Response) throws {
        listener = try NWListener(using: parameters, on: NWEndpoint.Port(rawValue: port)!)
        listener.service = service
        self.handle = handle
        listener.newConnectionHandler = { [unowned self] connection in
            connection.start(queue: .global())
            receive(connection, Data(), continued: false)
        }
        listener.stateUpdateHandler = { state in
            if case .failed = state { failed() }
        }
        listener.start(queue: .global())
    }

    private func receive(_ connection: NWConnection, _ buffer: Data, continued: Bool) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 1 << 16) { [self] data, _, done, error in
            let buffer = buffer + (data ?? Data())
            let closed = done || error != nil
            guard let end = buffer.range(of: Self.headerEnd) else {
                return closed || buffer.count > 64 << 10 ? connection.cancel() : receive(connection, buffer, continued: false)
            }
            var request = Self.head(buffer[..<end.lowerBound])
            let length = Int(request.headers["content-length"] ?? "") ?? 0
            let body = buffer[end.upperBound...]
            if body.count >= length {
                request.body = Data(body.prefix(length))
                DispatchQueue.global().async { self.respond(connection, self.handle(request)) }
            } else if closed || length > 16 << 20 {
                connection.cancel()
            } else {
                if !continued && request.headers["expect"]?.lowercased() == "100-continue" {
                    connection.send(content: Data("HTTP/1.1 100 Continue\r\n\r\n".utf8), completion: .idempotent)
                }
                receive(connection, buffer, continued: true)
            }
        }
    }

    private static func head(_ data: Data) -> Request {
        let lines = String(decoding: data, as: UTF8.self).components(separatedBy: "\r\n")
        let parts = lines.first?.split(separator: " ").map(String.init) ?? []
        let target = parts.count > 1 ? parts[1] : "/"
        let pieces = target.split(separator: "?", maxSplits: 1).map(String.init)
        var request = Request(method: parts.first ?? "", path: pieces.first ?? "/", query: pieces.count > 1 ? pieces[1] : "")
        for line in lines.dropFirst() {
            guard let colon = line.firstIndex(of: ":") else { continue }
            request.headers[line[..<colon].lowercased()] = line[line.index(after: colon)...].trimmingCharacters(in: .whitespaces)
        }
        return request
    }

    private func respond(_ connection: NWConnection, _ response: Response) {
        let head = "HTTP/1.1 \(response.status) \(response.status == 200 ? "OK" : "Error")\r\nContent-Type: application/json\r\nContent-Length: \(response.body.count)\r\nConnection: close\r\n\r\n"
        connection.send(content: Data(head.utf8) + response.body, completion: .contentProcessed { _ in connection.cancel() })
    }
}
