import Foundation

public protocol DevelopmentObserverHTTPTransporting: Sendable {
  func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse)
}

public struct URLSessionDevelopmentObserverTransport: DevelopmentObserverHTTPTransporting,
  @unchecked Sendable
{
  private let session: URLSession

  public init(timeout: TimeInterval = 60) {
    let configuration = URLSessionConfiguration.ephemeral
    configuration.timeoutIntervalForRequest = timeout
    configuration.timeoutIntervalForResource = timeout
    configuration.urlCache = nil
    configuration.httpCookieStorage = nil
    configuration.httpShouldSetCookies = false
    self.session = URLSession(configuration: configuration)
  }

  public func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
    do {
      let (data, response) = try await self.session.data(for: request)
      guard let httpResponse = response as? HTTPURLResponse else {
        throw DevelopmentObserverError.invalidResponse
      }
      return (data, httpResponse)
    } catch let error as URLError where error.code == .timedOut {
      throw DevelopmentObserverError.timedOut
    } catch is CancellationError {
      throw CancellationError()
    } catch {
      throw DevelopmentObserverError.unavailable
    }
  }
}

public struct OllamaDevelopmentObserverClient: DevelopmentObserverModelCalling, Sendable {
  public static let defaultEndpoint = URL(string: "http://127.0.0.1:11434")!
  public static let defaultModel = "qwen3.5:27b"
  public static let maximumResponseBytes = 65_536
  public static let maximumSummaryCharacters = 240

  private let endpoint: URL
  private let model: String
  private let transport: any DevelopmentObserverHTTPTransporting

  public init(
    endpoint: URL,
    model: String = Self.defaultModel,
    transport: any DevelopmentObserverHTTPTransporting = URLSessionDevelopmentObserverTransport()
  ) throws {
    guard Self.isPermittedLoopbackEndpoint(endpoint), Self.isPermittedModelName(model) else {
      throw DevelopmentObserverError.invalidEndpoint
    }
    self.endpoint = endpoint
    self.model = model
    self.transport = transport
  }

  public static func live() throws -> Self {
    try Self(endpoint: Self.defaultEndpoint)
  }

  public func diagnose(assessment: DevelopmentObservationAssessment) async throws
    -> DevelopmentModelDiagnosis
  {
    let request = try self.makeRequest(assessment: assessment)
    let (data, response) = try await self.transport.send(request)
    guard data.count <= Self.maximumResponseBytes else {
      throw DevelopmentObserverError.responseTooLarge
    }
    guard response.statusCode == 200 else { throw DevelopmentObserverError.unavailable }
    return try Self.decodeResponse(data, assessment: assessment)
  }

  public func makeRequest(assessment: DevelopmentObservationAssessment) throws -> URLRequest {
    let apiURL = self.endpoint.appending(path: "api/chat")
    var request = URLRequest(url: apiURL)
    request.httpMethod = "POST"
    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
    request.setValue("application/json", forHTTPHeaderField: "Accept")
    request.cachePolicy = .reloadIgnoringLocalAndRemoteCacheData
    request.httpBody = try JSONEncoder.observerEncoder.encode(
      OllamaRequest(
        model: self.model,
        messages: [
          OllamaMessage(role: "system", content: Self.systemPrompt),
          OllamaMessage(
            role: "user",
            content: try Self.userPrompt(assessment: assessment)
          ),
        ],
        stream: false,
        think: false,
        format: "json",
        keepAlive: "0s",
        options: OllamaOptions(temperature: 0, numContext: 8_192, numPredict: 256)
      )
    )
    return request
  }

  public static func isPermittedLoopbackEndpoint(_ url: URL) -> Bool {
    guard url.scheme?.lowercased() == "http",
      url.user == nil,
      url.password == nil,
      url.query == nil,
      url.fragment == nil,
      url.path.isEmpty || url.path == "/",
      let host = url.host?.lowercased(),
      ["127.0.0.1", "localhost", "::1"].contains(host)
    else { return false }
    return true
  }

  public static func decodeResponse(
    _ data: Data,
    assessment: DevelopmentObservationAssessment
  ) throws -> DevelopmentModelDiagnosis {
    let response: OllamaResponse
    do {
      response = try JSONDecoder.observerDecoder.decode(OllamaResponse.self, from: data)
    } catch {
      throw DevelopmentObserverError.invalidResponse
    }
    guard response.done == true,
      response.doneReason == nil || response.doneReason == "stop",
      response.message.role == "assistant",
      let contentData = response.message.content.data(using: .utf8),
      contentData.count <= 2_048,
      let object = try? JSONSerialization.jsonObject(with: contentData) as? [String: Any],
      Set(object.keys) == ["classification", "recommendation", "summary"]
    else { throw DevelopmentObserverError.invalidResponse }

    let result: OllamaModelResult
    do {
      result = try JSONDecoder().decode(OllamaModelResult.self, from: contentData)
    } catch {
      throw DevelopmentObserverError.invalidResponse
    }
    let summary = result.summary.trimmingCharacters(in: .whitespacesAndNewlines)
    guard result.classification == assessment.classification,
      result.recommendation == assessment.recommendation,
      !summary.isEmpty,
      summary.count <= Self.maximumSummaryCharacters,
      !summary.contains(where: \Character.isNewline),
      summary.unicodeScalars.allSatisfy({ !CharacterSet.controlCharacters.contains($0) })
    else { throw DevelopmentObserverError.policyMismatch }

    return DevelopmentModelDiagnosis(
      classification: result.classification,
      recommendation: result.recommendation,
      summary: summary
    )
  }

  private static func isPermittedModelName(_ model: String) -> Bool {
    guard !model.isEmpty, model.utf8.count <= 96 else { return false }
    return model.unicodeScalars.allSatisfy {
      CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "._:-")).contains($0)
    }
  }

  private static func userPrompt(assessment: DevelopmentObservationAssessment) throws -> String {
    let envelope = OllamaPromptEnvelope(
      deterministicClassification: assessment.classification,
      deterministicRecommendation: assessment.recommendation,
      focusIssueNumber: assessment.issueNumber,
      observation: assessment.payload
    )
    let data = try JSONEncoder.observerEncoder.encode(envelope)
    guard data.count <= 16_384 else { throw DevelopmentObserverError.responseTooLarge }
    return String(decoding: data, as: UTF8.self)
  }

  private static let systemPrompt = """
    You summarize a read-only software-development observation using Traditional Chinese.
    The input contains only closed, prevalidated enums and identifiers. Do not infer missing facts.
    Copy deterministic_classification and deterministic_recommendation exactly; you have no authority to change them.
    Return one JSON object with exactly classification, recommendation, and summary.
    summary must be one line, at most 120 Traditional Chinese characters, factual, and must not claim that any repair, dispatch, approval, merge, notification, or external action occurred.
    """
}

private struct OllamaPromptEnvelope: Codable, Sendable {
  let deterministicClassification: DevelopmentObservationClassification
  let deterministicRecommendation: DevelopmentObservationRecommendation
  let focusIssueNumber: Int?
  let observation: DevelopmentObservationPayload

  private enum CodingKeys: String, CodingKey {
    case deterministicClassification = "deterministic_classification"
    case deterministicRecommendation = "deterministic_recommendation"
    case focusIssueNumber = "focus_issue_number"
    case observation
  }
}

private struct OllamaRequest: Codable, Sendable {
  let model: String
  let messages: [OllamaMessage]
  let stream: Bool
  let think: Bool
  let format: String
  let keepAlive: String
  let options: OllamaOptions

  private enum CodingKeys: String, CodingKey {
    case model, messages, stream, think, format, options
    case keepAlive = "keep_alive"
  }
}

private struct OllamaOptions: Codable, Sendable {
  let temperature: Int
  let numContext: Int
  let numPredict: Int

  private enum CodingKeys: String, CodingKey {
    case temperature
    case numContext = "num_ctx"
    case numPredict = "num_predict"
  }
}

private struct OllamaMessage: Codable, Sendable {
  let role: String
  let content: String
}

private struct OllamaResponse: Codable, Sendable {
  let message: OllamaMessage
  let done: Bool?
  let doneReason: String?

  private enum CodingKeys: String, CodingKey {
    case message, done
    case doneReason = "done_reason"
  }
}

private struct OllamaModelResult: Codable, Sendable {
  let classification: DevelopmentObservationClassification
  let recommendation: DevelopmentObservationRecommendation
  let summary: String
}

extension JSONEncoder {
  fileprivate static var observerEncoder: JSONEncoder {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
    return encoder
  }
}

extension JSONDecoder {
  fileprivate static var observerDecoder: JSONDecoder { JSONDecoder() }
}
