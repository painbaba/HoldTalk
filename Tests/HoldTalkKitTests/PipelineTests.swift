import XCTest
@testable import HoldTalkKit

/// Answers web requests in-process, so these tests never touch a real service.
final class MockAPI: URLProtocol {
    struct Seen { let request: URLRequest; let body: Data }
    nonisolated(unsafe) static var seen: [Seen] = []
    nonisolated(unsafe) static var respond: (URLRequest) -> (Int, String) = { _ in (200, "{}") }
    nonisolated(unsafe) static var delay: TimeInterval = 0

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func stopLoading() {}

    override func startLoading() {
        var body = request.httpBody ?? Data()
        if let stream = request.httpBodyStream {
            stream.open()
            var buffer = [UInt8](repeating: 0, count: 65536)
            while stream.hasBytesAvailable {
                let count = stream.read(&buffer, maxLength: buffer.count)
                if count <= 0 { break }
                body.append(buffer, count: count)
            }
            stream.close()
        }
        Self.seen.append(Seen(request: request, body: body))
        let (status, text) = Self.respond(request)
        DispatchQueue.global().asyncAfter(deadline: .now() + Self.delay) { [self] in
            let response = HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: nil)!
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: Data(text.utf8))
            client?.urlProtocolDidFinishLoading(self)
        }
    }

    static var session: URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [MockAPI.self]
        return URLSession(configuration: configuration)
    }
}

private struct FixedTranscriber: Transcriber {
    let name = "fixed"
    let text: String
    func transcribe(wav: URL) async throws -> String { text }
}

private struct FailingTranscriber: Transcriber {
    let name = "failing"
    func transcribe(wav: URL) async throws -> String { throw TranscriptionError("nope") }
}

private struct FixedCleaner: TextCleaner {
    let output: String
    func clean(_ transcript: String) async throws -> String { output }
}

private struct FailingCleaner: TextCleaner {
    func clean(_ transcript: String) async throws -> String { throw URLError(.notConnectedToInternet) }
}

final class PipelineTests: XCTestCase {
    private let wav = URL(fileURLWithPath: "/nonexistent.wav")

    override func setUp() {
        MockAPI.seen = []
        MockAPI.delay = 0
    }

    func testCleanedTextIsUsed() async throws {
        let pipeline = DictationPipeline(transcribers: [FixedTranscriber(text: " um hello there ")],
                                         cleaner: FixedCleaner(output: "Hello there."))
        let result = try await pipeline.run(wav: wav)
        XCTAssertEqual(result, .init(text: "Hello there.", notice: nil))
    }

    func testOfflineCleanupStillDeliversRawText() async throws {
        let pipeline = DictationPipeline(transcribers: [FixedTranscriber(text: "um hello")], cleaner: FailingCleaner())
        let result = try await pipeline.run(wav: wav)
        XCTAssertEqual(result.text, "um hello")
        XCTAssertNotNil(result.notice)
    }

    func testNoCleanerMeansRawText() async throws {
        let pipeline = DictationPipeline(transcribers: [FixedTranscriber(text: "um hello")], cleaner: nil)
        let result = try await pipeline.run(wav: wav)
        XCTAssertEqual(result, .init(text: "um hello", notice: nil))
    }

    func testModelAnsweringInsteadOfEditingIsRejected() async throws {
        let essay = String(repeating: "Sure! Here is a long answer to your question. ", count: 10)
        let pipeline = DictationPipeline(transcribers: [FixedTranscriber(text: "what is the capital of france")],
                                         cleaner: FixedCleaner(output: essay))
        let result = try await pipeline.run(wav: wav)
        XCTAssertEqual(result.text, "what is the capital of france")
        XCTAssertNotNil(result.notice)
    }

    func testBlankAudioMarkerMeansNoSpeechAndSkipsCleanup() async throws {
        let pipeline = DictationPipeline(transcribers: [FixedTranscriber(text: " [BLANK_AUDIO]\n")],
                                         cleaner: FixedCleaner(output: "should not be used"))
        let result = try await pipeline.run(wav: wav)
        XCTAssertEqual(result.text, "")
    }

    func testCloudFailureFallsBackToLocal() async throws {
        let pipeline = DictationPipeline(transcribers: [FailingTranscriber(), FixedTranscriber(text: "hello")], cleaner: nil)
        let result = try await pipeline.run(wav: wav)
        XCTAssertEqual(result.text, "hello")
        XCTAssertEqual(result.notice, "failing failed, used fixed")
    }

    func testAllTranscribersFailing() async {
        let pipeline = DictationPipeline(transcribers: [FailingTranscriber()], cleaner: nil)
        do {
            _ = try await pipeline.run(wav: wav)
            XCTFail("Expected an error")
        } catch {
            XCTAssertEqual(error.localizedDescription, "nope")
        }
    }

    func testTidyTranscript() {
        XCTAssertEqual(tidyTranscript(" Hello there.\n And more. \n"), "Hello there. And more.")
        XCTAssertEqual(tidyTranscript("[BLANK_AUDIO]"), "")
        XCTAssertEqual(tidyTranscript("(wind blowing)\n"), "")
        XCTAssertEqual(tidyTranscript("keep (these words) here"), "keep (these words) here")
    }

    // MARK: - Choosing services

    func testLocalChoiceNeverUsesCloudForSpeech() {
        var config = Config()
        config.transcriber = "local"
        let pipeline = DictationPipeline.make(config: config, env: EnvFile("GROQ_API_KEY=k\nOPENAI_API_KEY=k"))
        XCTAssertFalse(pipeline.transcribers.contains { $0 is WhisperAPITranscriber })
    }

    func testCloudChoiceWithKeyComesFirstAndMissingKeyFallsBack() {
        var config = Config()
        config.transcriber = "groq"
        let withKey = DictationPipeline.make(config: config, env: EnvFile("GROQ_API_KEY=k"))
        XCTAssertEqual(withKey.transcribers.first?.name, "Groq")

        let noKey = DictationPipeline.make(config: config, env: EnvFile(""))
        XCTAssertNil(noKey.transcribers.first { $0 is WhisperAPITranscriber })
        XCTAssertEqual(noKey.setupNotice, "No GROQ_API_KEY in .env, used local Whisper")
    }

    func testCleanupProviderChoice() {
        var config = Config()
        let session = MockAPI.session
        XCTAssertNil(DictationPipeline.makeCleaner(config: config, env: EnvFile(""), session: session))
        XCTAssertTrue(DictationPipeline.makeCleaner(config: config, env: EnvFile("ANTHROPIC_API_KEY=k"), session: session) is AnthropicCleaner)
        config.cleanupProvider = "openai"
        XCTAssertNil(DictationPipeline.makeCleaner(config: config, env: EnvFile("ANTHROPIC_API_KEY=k"), session: session))
        config.cleanupEnabled = false
        XCTAssertNil(DictationPipeline.makeCleaner(config: config, env: EnvFile("OPENAI_API_KEY=k"), session: session))
    }

    // MARK: - Requests sent to the services (against the mock, not live)

    func testWhisperAPIRequest() async throws {
        MockAPI.respond = { _ in (200, #"{"text":"hello world"}"#) }
        let wavFile = FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID()).wav")
        try SpeechAudio(samples: [0.1, 0.2]).wavData().write(to: wavFile)
        defer { try? FileManager.default.removeItem(at: wavFile) }

        let transcriber = WhisperAPITranscriber(name: "Groq", endpoint: URL(string: "https://example.test/audio")!,
                                                apiKey: "secret", model: "m1", language: "en", session: MockAPI.session)
        let text = try await transcriber.transcribe(wav: wavFile)
        XCTAssertEqual(text, "hello world")

        let seen = try XCTUnwrap(MockAPI.seen.first)
        XCTAssertEqual(seen.request.value(forHTTPHeaderField: "Authorization"), "Bearer secret")
        let body = String(decoding: seen.body, as: UTF8.self)
        XCTAssertTrue(body.contains("name=\"model\"\r\n\r\nm1"))
        XCTAssertTrue(body.contains("name=\"language\"\r\n\r\nen"))
        XCTAssertTrue(body.contains("filename=\"speech.wav\""))
        XCTAssertTrue(seen.body.range(of: Data("RIFF".utf8)) != nil)
    }

    func testAPIErrorNeverExposesKey() async throws {
        MockAPI.respond = { _ in (401, #"{"error":"bad key secret"}"#) }
        let wavFile = FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID()).wav")
        try SpeechAudio(samples: [0.1]).wavData().write(to: wavFile)
        defer { try? FileManager.default.removeItem(at: wavFile) }
        let transcriber = WhisperAPITranscriber(name: "Groq", endpoint: URL(string: "https://example.test/a")!,
                                                apiKey: "secret", model: "m", language: "auto", session: MockAPI.session)
        do {
            _ = try await transcriber.transcribe(wav: wavFile)
            XCTFail("Expected an error")
        } catch {
            XCTAssertEqual(error.localizedDescription, "Groq returned error 401.")
        }
        XCTAssertFalse(String(decoding: MockAPI.seen[0].body, as: UTF8.self).contains("language"), "auto sends no language")
    }

    func testChatCleanupRequest() async throws {
        MockAPI.respond = { _ in (200, #"{"choices":[{"message":{"content":"Hello."}}]}"#) }
        let cleaner = ChatCompletionsCleaner(endpoint: URL(string: "https://example.test/chat")!, apiKey: "secret",
                                             model: "m2", casing: "lowercase", timeout: 2, session: MockAPI.session)
        let output = try await cleaner.clean("um hello")
        XCTAssertEqual(output, "Hello.")
        let seen = try XCTUnwrap(MockAPI.seen.first)
        XCTAssertEqual(seen.request.value(forHTTPHeaderField: "Authorization"), "Bearer secret")
        let body = try XCTUnwrap(JSONSerialization.jsonObject(with: seen.body) as? [String: Any])
        XCTAssertEqual(body["model"] as? String, "m2")
        let messages = try XCTUnwrap(body["messages"] as? [[String: String]])
        XCTAssertTrue(messages[0]["content"]!.contains("lowercase"))
        XCTAssertEqual(messages[1]["content"], "<transcript>\num hello\n</transcript>")
    }

    func testAnthropicCleanupRequest() async throws {
        MockAPI.respond = { _ in (200, #"{"content":[{"type":"text","text":"Hello."}]}"#) }
        let cleaner = AnthropicCleaner(endpoint: URL(string: "https://example.test/messages")!, apiKey: "secret",
                                       model: "m3", casing: "sentence", timeout: 2, session: MockAPI.session)
        let output = try await cleaner.clean("um hello")
        XCTAssertEqual(output, "Hello.")
        let seen = try XCTUnwrap(MockAPI.seen.first)
        XCTAssertEqual(seen.request.value(forHTTPHeaderField: "x-api-key"), "secret")
        XCTAssertNil(seen.request.value(forHTTPHeaderField: "Authorization"))
        let body = try XCTUnwrap(JSONSerialization.jsonObject(with: seen.body) as? [String: Any])
        XCTAssertEqual(body["model"] as? String, "m3")
        XCTAssertNotNil(body["system"])
    }

    func testCancellingStopsAnAPICallAndNothingIsReturned() async throws {
        MockAPI.delay = 5
        MockAPI.respond = { _ in (200, #"{"choices":[{"message":{"content":"late"}}]}"#) }
        let cleaner = ChatCompletionsCleaner(endpoint: URL(string: "https://example.test/chat")!, apiKey: "k",
                                             model: "m", casing: "sentence", timeout: 30, session: MockAPI.session)
        let pipeline = DictationPipeline(transcribers: [FixedTranscriber(text: "hello")], cleaner: cleaner)
        let wav = self.wav
        let started = Date()
        let task = Task { try await pipeline.run(wav: wav) }
        try await Task.sleep(nanoseconds: 100_000_000)
        task.cancel()
        do {
            _ = try await task.value
            XCTFail("Cancelled work must not return text")
        } catch {
            XCTAssertLessThan(Date().timeIntervalSince(started), 2)
        }
    }
}
