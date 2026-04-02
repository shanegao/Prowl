// ProwlShared/CommandResponse.swift
// Structured response from app command service back to CLI.

import Foundation

/// Top-level response wrapper.
/// For v1, `data` is left as raw JSON bytes so each command can define
/// its own strongly-typed success payload without introducing `Any`.
public struct CommandResponse: Codable, Sendable {
  public let ok: Bool
  public let command: String
  public let schemaVersion: String

  /// Raw JSON data payload (success case). Consumers decode into
  /// command-specific types. Nil when `ok == false`.
  public let data: RawJSON?

  /// Error payload (failure case). Nil when `ok == true`.
  public let error: CommandError?

  public init(
    ok: Bool,
    command: String,
    schemaVersion: String,
    data: RawJSON? = nil,
    error: CommandError? = nil
  ) {
    self.ok = ok
    self.command = command
    self.schemaVersion = schemaVersion
    self.data = data
    self.error = error
  }

  enum CodingKeys: String, CodingKey {
    case ok
    case command
    case schemaVersion = "schema_version"
    case data
    case error
  }
}

public struct CommandError: Codable, Sendable {
  public let code: String
  public let message: String

  public init(code: String, message: String) {
    self.code = code
    self.message = message
  }
}

// MARK: - RawJSON

/// A type-safe wrapper around raw JSON bytes.
/// Preserves the original JSON without round-tripping through `Any`.
/// Fully `Sendable` because it only holds `Data`.
public struct RawJSON: Codable, Sendable {
  public let bytes: Data

  public init(_ bytes: Data) {
    self.bytes = bytes
  }

  /// Create from an Encodable value.
  public init<T: Encodable>(encoding value: T) throws {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys]
    self.bytes = try encoder.encode(value)
  }

  public init(from decoder: Decoder) throws {
    // When decoding as part of a larger structure, capture the raw JSON.
    // This works by re-encoding the decoded JSON value container.
    let container = try decoder.singleValueContainer()
    // Decode as a generic JSON value, then re-encode to bytes.
    let jsonValue = try container.decode(JSONValue.self)
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys]
    self.bytes = try encoder.encode(jsonValue)
  }

  public func encode(to encoder: Encoder) throws {
    // Decode bytes back to JSONValue, then encode inline.
    let decoder = JSONDecoder()
    let jsonValue = try decoder.decode(JSONValue.self, from: bytes)
    var container = encoder.singleValueContainer()
    try container.encode(jsonValue)
  }

  /// Decode the raw JSON into a specific type.
  public func decode<T: Decodable>(as type: T.Type) throws -> T {
    try JSONDecoder().decode(type, from: bytes)
  }
}

// MARK: - JSONValue (internal helper for RawJSON round-tripping)

/// A simple recursive JSON value type that is fully Codable and Sendable.
enum JSONValue: Codable, Sendable {
  case null
  case bool(Bool)
  case int(Int)
  case double(Double)
  case string(String)
  case array([JSONValue])
  case object([String: JSONValue])

  init(from decoder: Decoder) throws {
    let container = try decoder.singleValueContainer()
    if container.decodeNil() {
      self = .null
    } else if let b = try? container.decode(Bool.self) {
      self = .bool(b)
    } else if let i = try? container.decode(Int.self) {
      self = .int(i)
    } else if let d = try? container.decode(Double.self) {
      self = .double(d)
    } else if let s = try? container.decode(String.self) {
      self = .string(s)
    } else if let a = try? container.decode([JSONValue].self) {
      self = .array(a)
    } else if let o = try? container.decode([String: JSONValue].self) {
      self = .object(o)
    } else {
      throw DecodingError.dataCorruptedError(
        in: container,
        debugDescription: "Unsupported JSON value"
      )
    }
  }

  func encode(to encoder: Encoder) throws {
    var container = encoder.singleValueContainer()
    switch self {
    case .null: try container.encodeNil()
    case .bool(let b): try container.encode(b)
    case .int(let i): try container.encode(i)
    case .double(let d): try container.encode(d)
    case .string(let s): try container.encode(s)
    case .array(let a): try container.encode(a)
    case .object(let o): try container.encode(o)
    }
  }
}
