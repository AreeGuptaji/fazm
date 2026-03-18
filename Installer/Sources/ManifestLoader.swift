import Foundation

struct ReleaseManifest: Decodable {
    let version: String
    let arm64: Payload
    let x86_64: Payload

    func payload(for arch: String) -> Payload? {
        switch arch {
        case "arm64": return arm64
        case "x86_64": return x86_64
        default: return nil
        }
    }
}

struct Payload: Decodable {
    let url: URL
    let size: Int64
    let sha256: String
}

enum ManifestLoader {
    static let manifestURL = URL(string: "https://storage.googleapis.com/fazm-prod-releases/desktop/latest.json")!

    static func fetchManifest() async throws -> ReleaseManifest {
        let (data, response) = try await URLSession.shared.data(from: manifestURL)

        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200 else {
            throw ManifestError.fetchFailed
        }

        let decoder = JSONDecoder()
        return try decoder.decode(ReleaseManifest.self, from: data)
    }
}

enum ManifestError: LocalizedError {
    case fetchFailed

    var errorDescription: String? {
        switch self {
        case .fetchFailed:
            return "Could not reach the Fazm download server. Please check your internet connection and try again."
        }
    }
}
