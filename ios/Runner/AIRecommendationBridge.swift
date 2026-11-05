import Flutter
import Foundation
import FoundationModels

@Generable
struct RecommendationOutput {
    @Guide(description: "Exact title from the unread library if possible")
    let title: String

    @Guide(description: "Creator credit (writer/artist), optional")
    let creator: String?

    @Guide(description: "Library series ID if title is in the unread list, else null")
    let seriesId: String?

    @Guide(description: "1-2 sentences explaining the pick grounded in the reader's taste")
    let reasoning: String
}

private let instructions = """
You recommend ONE next comic to read for a specific reader.
STRONGLY prefer titles from the reader's unread library. Only suggest \
something outside the library if no library item is a reasonable fit.
Set series_id to the library ID when (and only when) the pick is from the \
unread library shortlist provided. Otherwise leave series_id null.
Keep reasoning to one or two sentences and ground it in the reader's taste \
or recent activity.
"""

final class AIRecommendationBridge {
    private let channel: FlutterMethodChannel
    private var warmSession: LanguageModelSession?

    init(messenger: FlutterBinaryMessenger) {
        channel = FlutterMethodChannel(
            name: "app.comic_reader/ai_recs",
            binaryMessenger: messenger
        )
        channel.setMethodCallHandler { [weak self] call, result in
            self?.handle(call: call, result: result)
        }
    }

    private func handle(call: FlutterMethodCall, result: @escaping FlutterResult) {
        switch call.method {
        case "isAvailable":
            result(Self.isAvailable())
        case "prewarm":
            prewarm()
            result(nil)
        case "recommend":
            guard let payload = call.arguments as? [String: Any] else {
                result(FlutterError(
                    code: "INVALID_ARGS",
                    message: "expected Map context",
                    details: nil
                ))
                return
            }
            Task { await self.recommend(payload: payload, result: result) }
        default:
            result(FlutterMethodNotImplemented)
        }
    }

    private func prewarm() {
        guard case .available = SystemLanguageModel.default.availability else {
            return
        }
        if warmSession != nil { return }
        let session = LanguageModelSession(instructions: instructions)
        session.prewarm()
        warmSession = session
    }

    private static func isAvailable() -> Bool {
        switch SystemLanguageModel.default.availability {
        case .available: return true
        case .unavailable: return false
        }
    }

    private func recommend(
        payload: [String: Any],
        result: @escaping FlutterResult
    ) async {
        guard case .available = SystemLanguageModel.default.availability else {
            result(FlutterError(
                code: "MODEL_UNAVAILABLE",
                message: "Apple Intelligence is not available",
                details: nil
            ))
            return
        }

        let prompt = Self.buildPrompt(from: payload)
        let session = warmSession ?? LanguageModelSession(instructions: instructions)
        warmSession = nil

        do {
            let response = try await session.respond(
                to: prompt,
                generating: RecommendationOutput.self
            )
            let out = response.content
            result([
                "title": out.title,
                "creator": out.creator as Any,
                "series_id": out.seriesId as Any,
                "reasoning": out.reasoning,
            ])
        } catch let error as LanguageModelSession.GenerationError {
            result(FlutterError(
                code: Self.code(for: error),
                message: error.errorDescription ?? "generation failed",
                details: nil
            ))
        } catch {
            result(FlutterError(
                code: "UNKNOWN",
                message: error.localizedDescription,
                details: nil
            ))
        }
    }

    private static func code(for error: LanguageModelSession.GenerationError) -> String {
        switch error {
        case .assetsUnavailable: return "MODEL_UNAVAILABLE"
        case .decodingFailure:   return "DECODING_FAILURE"
        case .exceededContextWindowSize: return "CONTEXT_TOO_LARGE"
        case .guardrailViolation: return "GUARDRAIL"
        case .rateLimited:       return "RATE_LIMITED"
        case .refusal:           return "REFUSAL"
        case .concurrentRequests: return "CONCURRENT"
        case .unsupportedGuide:  return "UNSUPPORTED_GUIDE"
        case .unsupportedLanguageOrLocale: return "UNSUPPORTED_LOCALE"
        @unknown default:        return "UNKNOWN"
        }
    }

    private static func buildPrompt(from payload: [String: Any]) -> String {
        func arr(_ key: String) -> [Any] { payload[key] as? [Any] ?? [] }

        func joinNames(_ items: [Any], _ map: ([String: Any]) -> String) -> String {
            items.compactMap { $0 as? [String: Any] }.map(map).joined(separator: "; ")
        }

        let topGenres = (payload["top_genres"] as? [String] ?? []).joined(separator: ", ")
        let topPubs = (payload["top_publishers"] as? [String] ?? []).joined(separator: ", ")

        let completed = joinNames(arr("completed")) { d in
            let name = d["name"] as? String ?? "?"
            let writer = d["writer"] as? String ?? ""
            return writer.isEmpty ? name : "\(name) (\(writer))"
        }

        let inProgress = joinNames(arr("in_progress")) { d in
            let name = d["name"] as? String ?? "?"
            let pct = d["progress_pct"] as? Int ?? 0
            return "\(name) (\(pct)% in)"
        }

        let sessions = joinNames(arr("sessions")) { d in
            let name = d["series_name"] as? String ?? "?"
            let days = d["days_ago"] as? Int ?? 0
            return "\(name) \(days)d ago"
        }

        let shortlist = joinNames(arr("shortlist")) { d in
            let id = d["series_id"] as? String ?? ""
            let name = d["name"] as? String ?? "?"
            let writer = d["writer"] as? String ?? ""
            let genres = (d["genres"] as? [String] ?? []).joined(separator: "/")
            let year = (d["year"] as? Int).map(String.init) ?? ""
            var parts = ["[\(id)] \(name)"]
            if !writer.isEmpty { parts.append(writer) }
            if !genres.isEmpty { parts.append(genres) }
            if !year.isEmpty   { parts.append(year) }
            return parts.joined(separator: " — ")
        }

        let avoid = (payload["avoid_titles"] as? [String] ?? []).joined(separator: ", ")

        return """
        Their taste:
        - Top genres: \(topGenres)
        - Top publishers: \(topPubs)
        - Recently completed: \(completed)
        - Currently reading: \(inProgress)
        - Recent activity: \(sessions)

        Their unread library shortlist (prefer these strongly):
        \(shortlist)

        \(avoid.isEmpty ? "" : "Avoid (already shown today): \(avoid)")

        Pick ONE series. Output title, creator (optional), series_id (only if \
        the pick is one of the shortlist IDs above), and one-line reasoning.
        """
    }
}
