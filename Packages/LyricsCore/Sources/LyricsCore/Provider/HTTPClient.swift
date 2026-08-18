import Foundation

public protocol HTTPClient: Sendable {
    func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse)
}

public enum HTTPClientError: Error, Equatable, Sendable {
    case nonHTTPResponse
}
