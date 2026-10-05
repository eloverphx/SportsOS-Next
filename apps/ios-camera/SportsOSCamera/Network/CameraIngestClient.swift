import Foundation

struct CameraIngestSession {
    let gameId: String
    let protocolName: String
    let host: String
    let port: UInt16
    let latencyMs: Int
    let mode: String
    let streamId: String
    let issuedAt: Date
    let expiresAt: Date
}

enum CameraIngestClientError: LocalizedError {
    case invalidGameId
    case invalidResponse
    case unauthorized
    case forbidden
    case unavailable(String)
    case invalidSession

    var errorDescription: String? {
        switch self {
        case .invalidGameId:
            return "A valid SportsOS game is required"

        case .invalidResponse:
            return "SportsOS returned an invalid camera ingest response"

        case .unauthorized:
            return "SportsOS authentication is required"

        case .forbidden:
            return "This account cannot manage streaming for this game"

        case .unavailable(let message):
            return message

        case .invalidSession:
            return "SportsOS returned an invalid camera ingest session"
        }
    }
}

final class CameraIngestClient {

    private struct APIResponse: Decodable {
        let success: Bool
        let data: ResponseData?
        let error: APIError?
    }

    private struct ResponseData: Decodable {
        let session: SessionPayload
    }

    private struct APIError: Decodable {
        let code: String?
        let message: String?
    }

    private struct SessionPayload: Decodable {
        let gameId: String
        let `protocol`: String
        let host: String
        let port: Int
        let latencyMs: Int
        let mode: String
        let streamId: String
        let issuedAt: String
        let expiresAt: String
    }

    private let baseURL: URL
    private let urlSession: URLSession

    init(
        baseURL: URL = URL(
            string:
                "https://api.crashthenet.online"
        )!,
        urlSession: URLSession = .shared
    ) {
        self.baseURL = baseURL
        self.urlSession = urlSession
    }

    func requestSession(
        gameId: String,
        accessToken: String
    ) async throws -> CameraIngestSession {

        let trimmedGameId =
            gameId.trimmingCharacters(
                in: .whitespacesAndNewlines
            )

        guard
            !trimmedGameId.isEmpty,
            Int(trimmedGameId) != nil
        else {
            throw CameraIngestClientError.invalidGameId
        }

        let url =
            baseURL
                .appendingPathComponent(
                    "streaming"
                )
                .appendingPathComponent(
                    "camera-ingest"
                )
                .appendingPathComponent(
                    trimmedGameId
                )
                .appendingPathComponent(
                    "session"
                )

        var request =
            URLRequest(
                url: url
            )

        request.httpMethod =
            "POST"

        request.timeoutInterval =
            15

        request.setValue(
            "Bearer \(accessToken)",
            forHTTPHeaderField:
                "Authorization"
        )

        request.setValue(
            "application/json",
            forHTTPHeaderField:
                "Accept"
        )

        let (
            data,
            response
        ) =
            try await urlSession.data(
                for: request
            )

        guard
            let http =
                response
                    as? HTTPURLResponse
        else {
            throw CameraIngestClientError.invalidResponse
        }

        if http.statusCode == 401 {
            throw CameraIngestClientError.unauthorized
        }

        if http.statusCode == 403 {
            throw CameraIngestClientError.forbidden
        }

        let decoded: APIResponse

        do {
            decoded =
                try JSONDecoder()
                    .decode(
                        APIResponse.self,
                        from: data
                    )
        } catch {
            throw CameraIngestClientError.invalidResponse
        }

        guard
            (200...299)
                .contains(
                    http.statusCode
                ),
            decoded.success,
            let payload =
                decoded.data?
                    .session
        else {
            throw CameraIngestClientError.unavailable(
                decoded.error?.message
                    ?? "SportsOS camera ingest is unavailable"
            )
        }

        guard
            payload.protocol == "srt",
            payload.mode == "caller",
            !payload.host.isEmpty,
            payload.port > 0,
            payload.port <= 65_535,
            !payload.streamId.isEmpty
        else {
            throw CameraIngestClientError.invalidSession
        }

        let fractionalFormatter =
            ISO8601DateFormatter()
        fractionalFormatter.formatOptions = [
            .withInternetDateTime,
            .withFractionalSeconds,
        ]

        let standardFormatter =
            ISO8601DateFormatter()
        standardFormatter.formatOptions = [
            .withInternetDateTime,
        ]

        func parseISO8601(_ value: String) -> Date? {
            fractionalFormatter.date(from: value)
                ?? standardFormatter.date(from: value)
        }

        guard
            let issuedAt =
                parseISO8601(
                    payload.issuedAt
                ),
            let expiresAt =
                parseISO8601(
                    payload.expiresAt
                )
        else {
            throw CameraIngestClientError.invalidSession
        }

        guard expiresAt > Date() else {
            throw CameraIngestClientError.invalidSession
        }

        return CameraIngestSession(
            gameId:
                payload.gameId,
            protocolName:
                payload.protocol,
            host:
                payload.host,
            port:
                UInt16(
                    payload.port
                ),
            latencyMs:
                payload.latencyMs,
            mode:
                payload.mode,
            streamId:
                payload.streamId,
            issuedAt:
                issuedAt,
            expiresAt:
                expiresAt
        )
    }
}
