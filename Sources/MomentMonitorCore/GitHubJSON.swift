import Foundation

extension JSONDecoder {
  static var github: JSONDecoder {
    let decoder = JSONDecoder()
    decoder.keyDecodingStrategy = .convertFromSnakeCase
    decoder.dateDecodingStrategy = .custom { decoder in
      let container = try decoder.singleValueContainer()
      let raw = try container.decode(String.self)

      let fractional = ISO8601DateFormatter()
      fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
      if let date = fractional.date(from: raw) {
        return date
      }

      let standard = ISO8601DateFormatter()
      standard.formatOptions = [.withInternetDateTime]
      if let date = standard.date(from: raw) {
        return date
      }

      throw DecodingError.dataCorruptedError(
        in: container,
        debugDescription: "Unsupported GitHub date: \(raw)"
      )
    }
    return decoder
  }
}
