import Foundation

typealias JSONObject = [String: JSONValue]

enum JSONValue: Decodable, Equatable, Sendable {
    case string(String)
    case number(Double)
    case bool(Bool)
    case object(JSONObject)
    case array([JSONValue])
    case null

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()

        if container.decodeNil() {
            self = .null
        } else if let value = try? container.decode(Bool.self) {
            self = .bool(value)
        } else if let value = try? container.decode(Double.self) {
            self = .number(value)
        } else if let value = try? container.decode(String.self) {
            self = .string(value)
        } else if let value = try? container.decode([String: JSONValue].self) {
            self = .object(value)
        } else if let value = try? container.decode([JSONValue].self) {
            self = .array(value)
        } else {
            throw DecodingError.typeMismatch(
                JSONValue.self,
                DecodingError.Context(
                    codingPath: decoder.codingPath,
                    debugDescription: "Unsupported JSON value"
                )
            )
        }
    }

    var stringValue: String? {
        switch self {
        case .string(let value):
            return value
        case .number(let value):
            return value.truncatingRemainder(dividingBy: 1) == 0
                ? String(Int(value))
                : String(value)
        case .bool(let value):
            return value ? "true" : "false"
        default:
            return nil
        }
    }

    var doubleValue: Double? {
        switch self {
        case .number(let value):
            return value
        case .string(let value):
            return Double(value.trimmingCharacters(in: .whitespacesAndNewlines))
        case .bool(let value):
            return value ? 1 : 0
        default:
            return nil
        }
    }

    var boolValue: Bool? {
        switch self {
        case .bool(let value):
            return value
        case .number(let value):
            return value != 0
        case .string(let value):
            switch value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
            case "true", "1", "yes", "on":
                return true
            case "false", "0", "no", "off":
                return false
            default:
                return nil
            }
        default:
            return nil
        }
    }

    var objectValue: JSONObject? {
        guard case .object(let value) = self else {
            return nil
        }

        return value
    }

    var arrayValue: [JSONValue]? {
        guard case .array(let value) = self else {
            return nil
        }

        return value
    }

    var isMeaningful: Bool {
        switch self {
        case .null:
            return false
        case .string(let value):
            return value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
        case .array(let values):
            return values.isEmpty == false
        default:
            return true
        }
    }

    var serializableObject: Any {
        switch self {
        case .string(let value):
            return value
        case .number(let value):
            return value
        case .bool(let value):
            return value
        case .object(let value):
            return value.mapValues(\.serializableObject)
        case .array(let values):
            return values.map(\.serializableObject)
        case .null:
            return NSNull()
        }
    }

    func normalizedJSONText() -> String {
        switch self {
        case .string(let value):
            return value
        case .number(let value):
            return String(value)
        case .bool(let value):
            return value ? "true" : "false"
        case .null:
            return "null"
        case .object, .array:
            guard JSONSerialization.isValidJSONObject(serializableObject),
                  let data = try? JSONSerialization.data(
                    withJSONObject: serializableObject,
                    options: [.sortedKeys]
                  ),
                  let text = String(data: data, encoding: .utf8) else {
                return String(describing: serializableObject)
            }

            return text
        }
    }

    static func parse(from text: String) -> JSONValue? {
        let data = Data(text.utf8)
        return try? JSONDecoder().decode(JSONValue.self, from: data)
    }
}

extension Dictionary where Key == String, Value == JSONValue {
    func string(_ key: String) -> String? {
        self[key]?.stringValue?.trimmedNonEmpty
    }

    func double(_ key: String) -> Double? {
        self[key]?.doubleValue
    }

    func boolish(_ key: String) -> Bool? {
        self[key]?.boolValue
    }

    func object(_ key: String) -> JSONObject? {
        self[key]?.objectValue
    }

    func array(_ key: String) -> [JSONValue]? {
        self[key]?.arrayValue
    }
}

extension String {
    var trimmedNonEmpty: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    var removingJSONFileExtension: String {
        lowercased().hasSuffix(".json")
            ? String(dropLast(5))
            : self
    }
}
