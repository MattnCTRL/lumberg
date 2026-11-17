import AppKit
import LumbergCore

/// Sends a photo of a calendar to Claude and gets structured events back.
enum PhotoInterpreter {
    enum Failure: LocalizedError {
        case noCredentials, badImage, refused, truncated, noContent
        case http(Int, String)
        case claudeCode(String)

        var errorDescription: String? {
            switch self {
            case .noCredentials:
                return "No way to reach Claude. Install Claude Code and sign in, or add an API key in Settings."
            case .claudeCode(let message):
                return "Claude Code could not read the photo: \(message)"
            case .badImage: return "That image could not be read."
            case .refused: return "Claude declined to read this image."
            case .truncated: return "The calendar had more on it than fit in one reply. Try a tighter photo."
            case .noContent: return "Claude returned nothing readable."
            case .http(let code, let body): return "Claude API error \(code): \(body)"
            }
        }
    }

    enum Auth {
        case apiKey(String)
        case bearer(String)
    }

    static var storedAPIKey: String? {
        guard let key = try? String(contentsOf: Store.apiKeyFile, encoding: .utf8)
            .trimmingCharacters(in: .whitespacesAndNewlines), !key.isEmpty else { return nil }
        return key
    }

    static func saveAPIKey(_ key: String) {
        let trimmed = key.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            try? FileManager.default.removeItem(at: Store.apiKeyFile)
            return
        }
        try? trimmed.write(to: Store.apiKeyFile, atomically: true, encoding: .utf8)
        try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: Store.apiKeyFile.path)
    }

    static var antPath: String? {
        ["/opt/homebrew/bin/ant", "/usr/local/bin/ant", NSHomeDirectory() + "/.local/bin/ant"]
            .first { FileManager.default.isExecutableFile(atPath: $0) }
    }

    /// A stored API key wins; otherwise a short-lived token from the `ant` CLI profile.
    static func credentials() async throws -> Auth {
        if let key = storedAPIKey { return .apiKey(key) }
        guard let ant = antPath else { throw Failure.noCredentials }
        let token: String? = await Task.detached {
            let p = Process()
            p.executableURL = URL(fileURLWithPath: ant)
            p.arguments = ["auth", "print-credentials", "--access-token"]
            let out = Pipe()
            p.standardOutput = out
            p.standardError = Pipe()
            do { try p.run() } catch { return nil }
            let data = out.fileHandleForReading.readDataToEndOfFile()
            p.waitUntilExit()
            guard p.terminationStatus == 0 else { return nil }
            let s = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines)
            return (s?.isEmpty ?? true) ? nil : s
        }.value
        guard let token else { throw Failure.noCredentials }
        return .bearer(token)
    }

    /// JPEG, long edge capped at 2400 px.
    static func jpeg(_ image: NSImage) -> Data? {
        guard let cg = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return nil }
        let scale = min(1, 2400 / CGFloat(max(cg.width, cg.height)))
        let w = Int(CGFloat(cg.width) * scale), h = Int(CGFloat(cg.height) * scale)
        guard let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0,
                                  space: CGColorSpaceCreateDeviceRGB(),
                                  bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue) else { return nil }
        ctx.interpolationQuality = .high
        ctx.setFillColor(CGColor(gray: 1, alpha: 1))
        ctx.fill(CGRect(x: 0, y: 0, width: w, height: h))
        ctx.draw(cg, in: CGRect(x: 0, y: 0, width: w, height: h))
        guard let scaled = ctx.makeImage() else { return nil }
        return NSBitmapImageRep(cgImage: scaled).representation(using: .jpeg, properties: [.compressionFactor: 0.88])
    }

    static var claudePath: String? {
        [NSHomeDirectory() + "/.local/bin/claude", "/opt/homebrew/bin/claude", "/usr/local/bin/claude"]
            .first { FileManager.default.isExecutableFile(atPath: $0) }
    }

    /// How the next photo will be read, for the Settings screen.
    static var route: String {
        if storedAPIKey != nil { return "Using the API key saved on this Mac (billed per use)." }
        if claudePath != nil { return "Using Claude Code on this Mac, so photos are read on your Claude subscription." }
        if antPath != nil { return "Using your `ant` command-line sign-in." }
        return "No way to reach Claude yet. Install Claude Code and sign in, or paste an API key below."
    }

    /// Reads the photo by running Claude Code headless, which uses the Claude subscription it is signed in with.
    /// User settings are not loaded, so no hooks run and nothing is saved as a session.
    static func interpretWithClaudeCode(jpeg: Data, model: String, claude: String) async throws -> PhotoParser.Result {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("lumberg-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let file = dir.appendingPathComponent("calendar.jpg")
        try jpeg.write(to: file)

        let schema = String(data: try JSONSerialization.data(withJSONObject: PhotoParser.schema), encoding: .utf8) ?? "{}"
        let prompt = "Read the image file at \(file.path) with the Read tool, then answer.\n\n" + PhotoParser.prompt(today: Date())

        let output: (status: Int32, out: Data, err: Data) = try await Task.detached {
            let p = Process()
            p.executableURL = URL(fileURLWithPath: claude)
            p.currentDirectoryURL = dir
            p.arguments = ["-p", prompt, "--json-schema", schema, "--output-format", "json",
                           "--allowedTools", "Read", "--model", model,
                           "--no-session-persistence", "--setting-sources", ""]
            let out = Pipe(), err = Pipe()
            p.standardOutput = out
            p.standardError = err
            p.standardInput = FileHandle.nullDevice
            try p.run()
            let killer = DispatchWorkItem { if p.isRunning { p.terminate() } }
            DispatchQueue.global().asyncAfter(deadline: .now() + 240, execute: killer)
            let data = out.fileHandleForReading.readDataToEndOfFile()
            let errData = err.fileHandleForReading.readDataToEndOfFile()
            p.waitUntilExit()
            killer.cancel()
            return (p.terminationStatus, data, errData)
        }.value

        let object = (try? JSONSerialization.jsonObject(with: output.out)) as? [String: Any]
        if output.status != 0 || object?["is_error"] as? Bool == true || object == nil {
            let said = object?["result"] as? String
                ?? String(data: output.err.isEmpty ? output.out : output.err, encoding: .utf8) ?? ""
            let trimmed = said.trimmingCharacters(in: .whitespacesAndNewlines)
            throw Failure.claudeCode(trimmed.isEmpty ? "it exited with status \(output.status)." : String(trimmed.prefix(400)))
        }
        if let structured = object?["structured_output"], !(structured is NSNull),
           let json = try? JSONSerialization.data(withJSONObject: structured) {
            return try PhotoParser.parse(json: json)
        }
        guard let text = object?["result"] as? String, let json = text.data(using: .utf8) else { throw Failure.noContent }
        return try PhotoParser.parse(json: json)
    }

    static func interpret(image: NSImage, model: String) async throws -> PhotoParser.Result {
        guard let data = jpeg(image) else { throw Failure.badImage }
        // A saved API key wins. Otherwise Claude Code, which rides the Claude subscription.
        if storedAPIKey == nil, let claude = claudePath {
            return try await interpretWithClaudeCode(jpeg: data, model: model, claude: claude)
        }
        let auth = try await credentials()

        let body: [String: Any] = [
            "model": model,
            "max_tokens": 16000,
            "output_config": [
                "effort": "medium",
                "format": ["type": "json_schema", "schema": PhotoParser.schema],
            ] as [String: Any],
            "fallbacks": "default",
            "messages": [[
                "role": "user",
                "content": [
                    ["type": "image",
                     "source": ["type": "base64", "media_type": "image/jpeg", "data": data.base64EncodedString()]],
                    ["type": "text", "text": PhotoParser.prompt(today: Date())],
                ] as [[String: Any]],
            ] as [String: Any]],
        ]

        var request = URLRequest(url: URL(string: "https://api.anthropic.com/v1/messages")!)
        request.httpMethod = "POST"
        request.timeoutInterval = 240
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("2026-10-21", forHTTPHeaderField: "anthropic-version")
        var betas = ["server-side-fallback-2026-07-01"]
        switch auth {
        case .apiKey(let key):
            request.setValue(key, forHTTPHeaderField: "x-api-key")
        case .bearer(let token):
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            betas.insert("oauth-2025-04-20", at: 0)
        }
        request.setValue(betas.joined(separator: ","), forHTTPHeaderField: "anthropic-beta")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (reply, response) = try await URLSession.shared.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard status == 200 else {
            let object = try? JSONSerialization.jsonObject(with: reply) as? [String: Any]
            let message = (object?["error"] as? [String: Any])?["message"] as? String
            throw Failure.http(status, message ?? String(data: reply.prefix(300), encoding: .utf8) ?? "")
        }
        guard let object = try JSONSerialization.jsonObject(with: reply) as? [String: Any] else { throw Failure.noContent }
        switch object["stop_reason"] as? String {
        case "refusal": throw Failure.refused
        case "max_tokens": throw Failure.truncated
        default: break
        }
        let blocks = object["content"] as? [[String: Any]] ?? []
        guard let text = blocks.first(where: { $0["type"] as? String == "text" })?["text"] as? String,
              let json = text.data(using: .utf8) else { throw Failure.noContent }
        return try PhotoParser.parse(json: json)
    }
}
