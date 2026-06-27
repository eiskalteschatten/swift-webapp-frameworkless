//
//  Application.swift
//  swift-webapp-frameworkless
//
//  Created by Alex Seifert on 13/06/2026.
//

import Foundation

// MARK: - Router setup

/// The single shared router instance. All routes are registered on this object
/// before the server starts accepting connections.
let router = Router()

// MARK: - Routes

/// Home page — renders a static welcome page.
router.add(.GET, "/") { head, _, _, _ in
    let pageHtml = layoutView(title: "Homepage", content: homeView())
    return HTTPResponse(status: .ok, contentType: "text/html", body: pageHtml.description)
}

/// Greeting page — renders a personalised hello message.
///
/// Route parameter:
///   - `:name`  — the person's name, captured from the URL path (e.g. `/hello/Alex`)
///
/// Query parameter:
///   - `?german=true`  — if present and set to "true", the greeting is rendered in German
router.add(.GET, "/hello/:name") { head, params, urlComponents, _ in
    let name = params["name"] ?? "unknown"

    // Extract the optional `?german=true` query parameter.
    let germanParam = urlComponents.queryItems?.first(where: { $0.name == "german" })?.value
    let isGerman = germanParam == "true"

    let title = isGerman ? "Hallo \(name)!" : "Hello \(name)!"
    let pageHtml = layoutView(title: title, content: helloView(name: name, isGerman: isGerman), name: name)

    return HTTPResponse(status: .ok, contentType: "text/html", body: pageHtml.description)
}

// MARK: - Static file serving

// Resolve the project root by checking several candidate paths in priority order:
//   1. Current working directory — correct when using `swift run` (CWD = project root)
//   2. Three levels above the binary — correct for a deployed release binary (.build/release/ServerApp)
//   3. Two levels above the compile-time source path — correct when running from Xcode
//      (the binary is deep in DerivedData, but #filePath gives us the source location)
let binaryURL = URL(fileURLWithPath: CommandLine.arguments[0])
    .standardized
    .resolvingSymlinksInPath()

let candidates: [URL] = [
    URL(fileURLWithPath: FileManager.default.currentDirectoryPath),
    binaryURL.deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent(),
    URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
]

// Use the first candidate directory that actually contains a `Public/` folder.
// Falling back to candidates[0] is safe — `serveStaticFiles` will simply return
// 404 for every static file request if the directory doesn't exist.
let projectRoot = candidates.first {
    FileManager.default.fileExists(atPath: $0.appendingPathComponent("Public").path)
} ?? candidates[0]

// Register a catch-all GET route that serves any file found under Public/.
router.serveStaticFiles(from: projectRoot.appendingPathComponent("Public").path)

// MARK: - Server startup

/// Bind to localhost on port 8080 and start the SwiftNIO event loop.
/// `start()` suspends indefinitely — the process runs until it is killed.
let server = HTTPServer(host: "127.0.0.1", port: 8080, router: router)
try await server.start()
