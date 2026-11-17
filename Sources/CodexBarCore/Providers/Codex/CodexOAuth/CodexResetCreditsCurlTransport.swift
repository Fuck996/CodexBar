#if os(macOS)
import Foundation

/// The system curl can negotiate this endpoint when macOS URLSession fails the TLS handshake.
struct CodexResetCreditsCurlTransport: ProviderHTTPTransport {
    static let endpoint = URL(string: "https://chatgpt.com/backend-api/wham/rate-limit-reset-credits")!

    func data(for request: URLRequest) async throws -> (Data, URLResponse) {
        let headers = try Self.headerInput(for: request)
        let input = Pipe()
        // The 4 KiB limit in headerInput keeps the pre-launch write within pipe capacity.
        try input.fileHandleForWriting.write(contentsOf: headers)
        try input.fileHandleForWriting.close()

        let response = try await SubprocessRunner.run(
            binary: "/usr/bin/curl",
            arguments: [
                "-q", "--silent", "--show-error", "--proto", "=https",
                "--max-time", String(request.timeoutInterval), "--header", "@-",
                "--write-out", "\n%{http_code}", Self.endpoint.absoluteString,
            ],
            environment: [:],
            timeout: request.timeoutInterval + 1,
            maxOutputBytes: 512 * 1024,
            standardInput: input,
            label: "Codex reset credits")

        guard let separator = response.stdout.lastIndex(of: "\n"),
              let status = Int(response.stdout[response.stdout.index(after: separator)...]),
              let http = HTTPURLResponse(url: Self.endpoint, statusCode: status, httpVersion: nil, headerFields: nil)
        else { throw CodexOAuthFetchError.invalidResponse }
        return (Data(response.stdout[..<separator].utf8), http)
    }

    static func headerInput(for request: URLRequest) throws -> Data {
        guard request.url == Self.endpoint, request.httpMethod == "GET" else {
            throw URLError(.badURL)
        }
        let headers = request.allHTTPHeaderFields ?? [:]
        guard headers.values.allSatisfy({ !$0.contains(where: \.isNewline) }) else {
            throw URLError(.badURL)
        }
        // Keep secrets off argv, the environment, disk, and logs.
        let payload = Data(headers.map { "\($0.key): \($0.value)\n" }.joined().utf8)
        guard payload.count <= 4096 else { throw URLError(.dataLengthExceedsMaximum) }
        return payload
    }
}
#endif
