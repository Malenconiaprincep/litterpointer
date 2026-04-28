import Foundation
import UIKit

enum PointReadingAIState: Equatable {
    case idle
    case missingAPIKey
    case recognizing
    case failed(String)

    var message: String? {
        switch self {
        case .idle:
            return nil
        case .missingAPIKey:
            return "未配置 AI Key"
        case .recognizing:
            return "AI 识别中..."
        case .failed(let reason):
            return reason
        }
    }
}

struct PointReadingAIRequest {
    let imageData: Data
}

final class PointReadingAIService {
    static let shared = PointReadingAIService()

    private let session: URLSession

    private init(session: URLSession = .shared) {
        self.session = session
    }

    func recognize(request: PointReadingAIRequest) async throws -> String {
        let config = PointReadingAIConfig.current
        guard !config.apiKey.isEmpty else {
            throw PointReadingAIError.missingAPIKey
        }

        let url = config.baseURL.appendingPathComponent("chat/completions")

        var urlRequest = URLRequest(url: url)
        urlRequest.httpMethod = "POST"
        urlRequest.timeoutInterval = 25
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        urlRequest.setValue("Bearer \(config.apiKey)", forHTTPHeaderField: "Authorization")

        let body = ChatCompletionRequest(
            model: config.model,
            messages: [
                ChatMessage(
                    role: "system",
                    content: [
                        .text("""
                        You are a point-reading assistant. The image is a crop around a user's index fingertip. A green dot marks the exact point to read. Return only the text the user is pointing at. Prefer the same visual line or title block. Do not return lower paragraphs unless the dot is on that paragraph. Keep Chinese and English exactly as seen when possible.
                        """)
                    ]
                ),
                ChatMessage(
                    role: "user",
                    content: [
                        .text("识别绿色点正在指向的文字。只输出目标文字，不要解释。"),
                        .imageURL(ImageURL(url: "data:image/jpeg;base64,\(request.imageData.base64EncodedString())"))
                    ]
                )
            ],
            maxTokens: 120,
            temperature: 0
        )

        urlRequest.httpBody = try JSONEncoder().encode(body)

        let (data, response) = try await session.data(for: urlRequest)
        if let httpResponse = response as? HTTPURLResponse, !(200...299).contains(httpResponse.statusCode) {
            let message = String(data: data, encoding: .utf8) ?? "HTTP \(httpResponse.statusCode)"
            throw PointReadingAIError.requestFailed(message)
        }

        let result = try JSONDecoder().decode(ChatCompletionResponse.self, from: data)
        let text = result.choices.first?.message.content.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !text.isEmpty else {
            throw PointReadingAIError.emptyResponse
        }
        return text
    }
}

private struct PointReadingAIConfig {
    let apiKey: String
    let baseURL: URL
    let model: String

    static var current: PointReadingAIConfig {
        let secrets = Self.secretsPlist
        return PointReadingAIConfig(
            apiKey: secrets["apiKey"] as? String ?? "",
            baseURL: URL(string: secrets["baseURL"] as? String ?? "https://dashscope.aliyuncs.com/compatible-mode/v1")!,
            model: secrets["model"] as? String ?? "qwen3.5-flash"
        )
    }

    private static var secretsPlist: [String: Any] {
        guard
            let url = Bundle.main.url(forResource: "PointReadingSecrets", withExtension: "plist"),
            let dictionary = NSDictionary(contentsOf: url) as? [String: Any]
        else {
            return [:]
        }
        return dictionary
    }
}

private enum PointReadingAIError: LocalizedError {
    case missingAPIKey
    case invalidURL
    case requestFailed(String)
    case emptyResponse

    var errorDescription: String? {
        switch self {
        case .missingAPIKey:
            return "未配置 AI Key"
        case .invalidURL:
            return "AI 服务地址无效"
        case .requestFailed(let message):
            return "AI 请求失败：\(message)"
        case .emptyResponse:
            return "AI 没有返回文字"
        }
    }
}

private struct ChatCompletionRequest: Encodable {
    let model: String
    let messages: [ChatMessage]
    let maxTokens: Int
    let temperature: Double

    enum CodingKeys: String, CodingKey {
        case model
        case messages
        case maxTokens = "max_tokens"
        case temperature
    }
}

private struct ChatMessage: Encodable {
    let role: String
    let content: [ChatContent]
}

private enum ChatContent: Encodable {
    case text(String)
    case imageURL(ImageURL)

    enum CodingKeys: String, CodingKey {
        case type
        case text
        case imageURL = "image_url"
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .text(let text):
            try container.encode("text", forKey: .type)
            try container.encode(text, forKey: .text)
        case .imageURL(let imageURL):
            try container.encode("image_url", forKey: .type)
            try container.encode(imageURL, forKey: .imageURL)
        }
    }
}

private struct ImageURL: Encodable {
    let url: String
}

private struct ChatCompletionResponse: Decodable {
    let choices: [Choice]

    struct Choice: Decodable {
        let message: ResponseMessage
    }

    struct ResponseMessage: Decodable {
        let content: String
    }
}
