//
//  Application.swift
//  swift-webapp-frameworkless
//
//  Created by Alex Seifert on 13/06/2026.
//

import Foundation

let router = Router()

router.add(.GET, "/") { head, _, _, _ in
    let pageHtml = layoutView(title: "Homepage", content: homeView())
    return HTTPResponse(status: .ok, contentType: "text/html", body: pageHtml.description)
}

// GET Request with Route Parameters and Query String Parsing
router.add(.GET, "/hello/:name") { head, params, urlComponents, _ in
    let name = params["name"] ?? "unknown"

    // Extract query param: ?german=true
    let germanParam = urlComponents.queryItems?.first(where: { $0.name == "german" })?.value
    let isGerman = germanParam == "true"
    
    let title = isGerman ? "Hallo \(name)!" : "Hello \(name)!"
    let pageHtml = layoutView(title: title, content: helloView(name: name, isGerman: isGerman), name: name)

    return HTTPResponse(status: .ok, contentType: "text/html", body: pageHtml.description)
}

// Resolve the project root by checking several candidate paths in priority order:
//   1. Current working directory — correct when using `swift run`
//   2. Three levels above the binary — correct for a deployed release binary (.build/release/ServerApp)
//   3. Compile-time source path — correct when running from Xcode (binary is in DerivedData)
let binaryURL = URL(fileURLWithPath: CommandLine.arguments[0])
    .standardized.resolvingSymlinksInPath()

let candidates: [URL] = [
    URL(fileURLWithPath: FileManager.default.currentDirectoryPath),
    binaryURL.deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent(),
    URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
]

let projectRoot = candidates.first {
    FileManager.default.fileExists(atPath: $0.appendingPathComponent("Public").path)
} ?? candidates[0]
router.serveStaticFiles(from: projectRoot.appendingPathComponent("Public").path)

// Start the SwiftNIO engine
let server = HTTPServer(host: "127.0.0.1", port: 8080, router: router)
try await server.start()
