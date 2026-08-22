import Foundation

public struct MobileDashboardAssets: Sendable {
  public let indexHTML: Data
  public let stylesheet: Data
  public let javascript: Data

  public init(indexHTML: Data, stylesheet: Data, javascript: Data) {
    self.indexHTML = indexHTML
    self.stylesheet = stylesheet
    self.javascript = javascript
  }

  public static func bundled() throws -> Self {
    Self(
      indexHTML: try Self.load(name: "index", extension: "html"),
      stylesheet: try Self.load(name: "app", extension: "css"),
      javascript: try Self.load(name: "app", extension: "js")
    )
  }

  private static func load(name: String, extension fileExtension: String) throws -> Data {
    if let appURL = Bundle.main.resourceURL?
      .appendingPathComponent("MobileDashboard", isDirectory: true)
      .appendingPathComponent("\(name).\(fileExtension)", isDirectory: false),
      FileManager.default.isReadableFile(atPath: appURL.path)
    {
      return try Data(contentsOf: appURL, options: [.mappedIfSafe])
    }

    let packageURL = Bundle.module.url(forResource: name, withExtension: fileExtension)
    if let packageURL, FileManager.default.isReadableFile(atPath: packageURL.path) {
      return try Data(contentsOf: packageURL, options: [.mappedIfSafe])
    }
    throw MobileDashboardAssetError.missing("\(name).\(fileExtension)")
  }
}

public enum MobileDashboardAssetError: LocalizedError {
  case missing(String)

  public var errorDescription: String? {
    switch self {
    case .missing(let name): "Mobile dashboard asset is missing: \(name)"
    }
  }
}

#if os(macOS)
  import Network

  public enum MobileDashboardServerState: Equatable, Sendable {
    case stopped
    case starting
    case ready(port: Int)
    case failed(message: String)
  }

  public enum MobileDashboardServerError: LocalizedError {
    case invalidPort

    public var errorDescription: String? {
      switch self {
      case .invalidPort: "Mobile dashboard port must be between 1024 and 65535."
      }
    }
  }

  public final class MobileDashboardServer: @unchecked Sendable {
    public static let loopbackHost = "127.0.0.1"
    public static let defaultPort = 48_127

    private static let maximumRequestBytes = 8 * 1024
    private static let maximumConnections = 16

    private let queue = DispatchQueue(label: "com.timyeou.momentmonitor.mobile-dashboard")
    private let assets: MobileDashboardAssets
    private let snapshotStore: MobileDashboardSnapshotStore
    private let stateHandler: @Sendable (MobileDashboardServerState) -> Void
    private var listener: NWListener?
    private var connections: [UUID: NWConnection] = [:]

    public init(
      snapshotStore: MobileDashboardSnapshotStore,
      assets: MobileDashboardAssets,
      stateHandler: @escaping @Sendable (MobileDashboardServerState) -> Void = { _ in }
    ) {
      self.snapshotStore = snapshotStore
      self.assets = assets
      self.stateHandler = stateHandler
    }

    public convenience init(
      snapshotStore: MobileDashboardSnapshotStore,
      stateHandler: @escaping @Sendable (MobileDashboardServerState) -> Void = { _ in }
    ) throws {
      try self.init(
        snapshotStore: snapshotStore,
        assets: MobileDashboardAssets.bundled(),
        stateHandler: stateHandler
      )
    }

    public func start(port: Int = MobileDashboardServer.defaultPort) throws {
      guard port == 0 || (1_024...65_535).contains(port) else {
        throw MobileDashboardServerError.invalidPort
      }
      let endpointPort = NWEndpoint.Port(rawValue: UInt16(port))!
      let parameters = NWParameters.tcp
      parameters.allowLocalEndpointReuse = true
      parameters.requiredLocalEndpoint = .hostPort(
        host: NWEndpoint.Host(Self.loopbackHost),
        port: endpointPort
      )
      let listener = try NWListener(using: parameters)
      self.queue.sync {
        self.stopLocked(notify: false)
        self.listener = listener
        listener.stateUpdateHandler = { [weak self, weak listener] state in
          guard let self, let listener else { return }
          switch state {
          case .ready:
            self.stateHandler(.ready(port: Int(listener.port?.rawValue ?? endpointPort.rawValue)))
          case .failed(let error):
            self.stateHandler(.failed(message: error.localizedDescription))
          case .cancelled:
            self.stateHandler(.stopped)
          default:
            break
          }
        }
        listener.newConnectionHandler = { [weak self] connection in
          self?.accept(connection)
        }
        self.stateHandler(.starting)
        listener.start(queue: self.queue)
      }
    }

    public func stop() {
      self.queue.sync {
        self.stopLocked(notify: true)
      }
    }

    private func stopLocked(notify: Bool) {
      self.listener?.stateUpdateHandler = nil
      self.listener?.newConnectionHandler = nil
      self.listener?.cancel()
      self.listener = nil
      for connection in self.connections.values { connection.cancel() }
      self.connections.removeAll()
      if notify { self.stateHandler(.stopped) }
    }

    private func accept(_ connection: NWConnection) {
      guard self.connections.count < Self.maximumConnections else {
        connection.cancel()
        return
      }
      let identifier = UUID()
      self.connections[identifier] = connection
      connection.stateUpdateHandler = { [weak self] state in
        guard case .failed = state else { return }
        self?.finishConnection(identifier)
      }
      connection.start(queue: self.queue)
      self.receive(connection, identifier: identifier, buffer: Data())
      self.queue.asyncAfter(deadline: .now() + 5) { [weak self] in
        self?.finishConnection(identifier)
      }
    }

    private func receive(_ connection: NWConnection, identifier: UUID, buffer: Data) {
      connection.receive(minimumIncompleteLength: 1, maximumLength: 2_048) {
        [weak self] data, _, isComplete, error in
        guard let self else { return }
        var request = buffer
        if let data { request.append(data) }
        if request.count > Self.maximumRequestBytes {
          self.send(.requestTooLarge, on: connection, identifier: identifier, includeBody: true)
          return
        }
        if request.range(of: Data("\r\n\r\n".utf8)) != nil {
          let response = self.response(for: request)
          self.send(
            response.value, on: connection, identifier: identifier, includeBody: response.body)
          return
        }
        if isComplete || error != nil {
          self.send(.badRequest, on: connection, identifier: identifier, includeBody: true)
          return
        }
        self.receive(connection, identifier: identifier, buffer: request)
      }
    }

    private func response(for request: Data) -> (value: HTTPResponse, body: Bool) {
      guard let text = String(data: request, encoding: .utf8),
        let headerEnd = text.range(of: "\r\n\r\n")
      else { return (.badRequest, true) }
      let headerText = String(text[..<headerEnd.lowerBound])
      let lines = headerText.components(separatedBy: "\r\n")
      guard let requestLine = lines.first else { return (.badRequest, true) }
      let parts = requestLine.split(separator: " ", omittingEmptySubsequences: true)
      guard parts.count == 3, parts[2].hasPrefix("HTTP/1.") else {
        return (.badRequest, true)
      }
      let method = String(parts[0])
      let includeBody = method != "HEAD"
      guard method == "GET" || method == "HEAD" else {
        return (.methodNotAllowed, includeBody)
      }
      guard
        let hostLine = lines.dropFirst().first(where: {
          $0.lowercased().hasPrefix("host:")
        })
      else { return (.forbiddenHost, includeBody) }
      let host = hostLine.dropFirst(5).trimmingCharacters(in: .whitespaces)
      guard Self.isAllowedHost(host) else { return (.forbiddenHost, includeBody) }

      let target = String(parts[1])
      guard target.hasPrefix("/"), !target.hasPrefix("//") else {
        return (.badRequest, includeBody)
      }
      let path = String(target.split(separator: "?", maxSplits: 1).first ?? "")
      switch path {
      case "/", "/index.html":
        return (
          .ok(contentType: "text/html; charset=utf-8", body: self.assets.indexHTML), includeBody
        )
      case "/app.css":
        return (
          .ok(contentType: "text/css; charset=utf-8", body: self.assets.stylesheet), includeBody
        )
      case "/app.js":
        return (
          .ok(contentType: "text/javascript; charset=utf-8", body: self.assets.javascript),
          includeBody
        )
      case "/api/v1/snapshot":
        do {
          return (
            .ok(
              contentType: "application/json; charset=utf-8",
              body: try self.snapshotStore.encodedSnapshot()
            ),
            includeBody
          )
        } catch {
          return (.serviceUnavailable, includeBody)
        }
      case "/health":
        return (
          .ok(
            contentType: "application/json; charset=utf-8",
            body: Data("{\"schemaVersion\":1,\"status\":\"ok\"}".utf8)
          ),
          includeBody
        )
      default:
        return (.notFound, includeBody)
      }
    }

    private static func isAllowedHost(_ value: String) -> Bool {
      guard value.count <= 255,
        let host = URLComponents(string: "http://\(value)")?.host?.lowercased()
      else { return false }
      return host == "localhost" || host == Self.loopbackHost || host == "::1"
        || host.hasSuffix(".ts.net")
    }

    private func send(
      _ response: HTTPResponse,
      on connection: NWConnection,
      identifier: UUID,
      includeBody: Bool
    ) {
      let content = response.serialized(includeBody: includeBody)
      connection.send(
        content: content,
        completion: .contentProcessed { [weak self] _ in
          self?.finishConnection(identifier)
        })
    }

    private func finishConnection(_ identifier: UUID) {
      guard let connection = self.connections.removeValue(forKey: identifier) else { return }
      connection.stateUpdateHandler = nil
      connection.cancel()
    }
  }

  private struct HTTPResponse: Sendable {
    let status: Int
    let reason: String
    let contentType: String
    let body: Data
    let allow: String?

    static func ok(contentType: String, body: Data) -> Self {
      Self(status: 200, reason: "OK", contentType: contentType, body: body, allow: nil)
    }

    static let badRequest = Self.text(status: 400, reason: "Bad Request")
    static let forbiddenHost = Self.text(status: 403, reason: "Forbidden")
    static let notFound = Self.text(status: 404, reason: "Not Found")
    static let methodNotAllowed = Self(
      status: 405,
      reason: "Method Not Allowed",
      contentType: "text/plain; charset=utf-8",
      body: Data("Method Not Allowed\n".utf8),
      allow: "GET, HEAD"
    )
    static let requestTooLarge = Self.text(status: 431, reason: "Request Header Too Large")
    static let serviceUnavailable = Self.text(status: 503, reason: "Service Unavailable")

    private static func text(status: Int, reason: String) -> Self {
      Self(
        status: status,
        reason: reason,
        contentType: "text/plain; charset=utf-8",
        body: Data("\(reason)\n".utf8),
        allow: nil
      )
    }

    func serialized(includeBody: Bool) -> Data {
      var headers = [
        "HTTP/1.1 \(self.status) \(self.reason)",
        "Content-Type: \(self.contentType)",
        "Content-Length: \(self.body.count)",
        "Cache-Control: no-store, max-age=0",
        "Pragma: no-cache",
        "Content-Security-Policy: default-src 'self'; script-src 'self'; style-src 'self'; connect-src 'self'; img-src 'self' data:; base-uri 'none'; frame-ancestors 'none'; form-action 'none'",
        "Cross-Origin-Resource-Policy: same-origin",
        "Referrer-Policy: no-referrer",
        "X-Content-Type-Options: nosniff",
        "X-Frame-Options: DENY",
        "Connection: close",
      ]
      if let allow { headers.append("Allow: \(allow)") }
      var result = Data((headers.joined(separator: "\r\n") + "\r\n\r\n").utf8)
      if includeBody { result.append(self.body) }
      return result
    }
  }
#endif
