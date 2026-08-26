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

public struct OMLXDevelopmentObserverClient: DevelopmentObserverModelCalling, Sendable {
  public static let defaultEndpoint = URL(string: "http://127.0.0.1:8011")!
  public static let defaultModel = "Qwen3.5-0.8B-MLX-4bit"
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
    return try Self.decodeResponse(
      data,
      assessment: assessment,
      expectedModel: self.model
    )
  }

  public func makeRequest(assessment: DevelopmentObservationAssessment) throws -> URLRequest {
    let apiURL = self.endpoint
      .appending(path: "v1")
      .appending(path: "chat")
      .appending(path: "completions")
    var request = URLRequest(url: apiURL)
    request.httpMethod = "POST"
    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
    request.setValue("application/json", forHTTPHeaderField: "Accept")
    request.cachePolicy = .reloadIgnoringLocalAndRemoteCacheData
    request.httpBody = try JSONEncoder.observerEncoder.encode(
      OMLXRequest(
        model: self.model,
        messages: [
          OMLXMessage(role: "system", content: Self.systemPrompt),
          OMLXMessage(
            role: "user",
            content: try Self.userPrompt(assessment: assessment)
          ),
        ],
        stream: false,
        maximumTokens: 256,
        temperature: 0,
        responseFormat: OMLXResponseFormat(type: "json_object"),
        chatTemplateArguments: OMLXChatTemplateArguments(enableThinking: false)
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
    assessment: DevelopmentObservationAssessment,
    expectedModel: String = Self.defaultModel
  ) throws -> DevelopmentModelDiagnosis {
    let response: OMLXResponse
    do {
      response = try JSONDecoder.observerDecoder.decode(OMLXResponse.self, from: data)
    } catch {
      throw DevelopmentObserverError.invalidResponse
    }
    guard response.model == expectedModel,
      response.choices.count == 1,
      let choice = response.choices.first,
      choice.index == 0,
      choice.finishReason == "stop",
      choice.message.role == "assistant",
      let contentData = choice.message.content.data(using: .utf8),
      contentData.count <= 2_048,
      let object = try? JSONSerialization.jsonObject(with: contentData) as? [String: Any],
      Set(object.keys) == ["classification", "recommendation", "summary"]
    else { throw DevelopmentObserverError.invalidResponse }

    let result: OMLXModelResult
    do {
      result = try JSONDecoder().decode(OMLXModelResult.self, from: contentData)
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
    let envelope = OMLXPromptEnvelope(
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

private struct OMLXPromptEnvelope: Codable, Sendable {
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

private struct OMLXRequest: Codable, Sendable {
  let model: String
  let messages: [OMLXMessage]
  let stream: Bool
  let maximumTokens: Int
  let temperature: Int
  let responseFormat: OMLXResponseFormat
  let chatTemplateArguments: OMLXChatTemplateArguments

  private enum CodingKeys: String, CodingKey {
    case model, messages, stream, temperature
    case maximumTokens = "max_tokens"
    case responseFormat = "response_format"
    case chatTemplateArguments = "chat_template_kwargs"
  }
}

private struct OMLXResponseFormat: Codable, Sendable {
  let type: String
}

private struct OMLXChatTemplateArguments: Codable, Sendable {
  let enableThinking: Bool

  private enum CodingKeys: String, CodingKey {
    case enableThinking = "enable_thinking"
  }
}

private struct OMLXMessage: Codable, Sendable {
  let role: String
  let content: String
}

private struct OMLXResponse: Codable, Sendable {
  let model: String
  let choices: [OMLXChoice]
}

private struct OMLXChoice: Codable, Sendable {
  let index: Int
  let message: OMLXMessage
  let finishReason: String

  private enum CodingKeys: String, CodingKey {
    case index, message
    case finishReason = "finish_reason"
  }
}

private struct OMLXModelResult: Codable, Sendable {
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
