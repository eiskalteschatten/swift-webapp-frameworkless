//
//  Application.swift
//  swift-webapp-frameworkless
//
//  Created by Alex Seifert on 13/06/2026.
//

import Foundation

let router = Router()

router.add(.GET, "/") { head, _, _ in
    let pageHtml = layoutView(title: "Homepage", content: homeView())
    return HTTPResponse(status: .ok, contentType: "text/html", body: pageHtml.description)
}

// GET Request with Route Parameters and Query String Parsing
router.add(.GET, "/hello/:name") { head, params, urlComponents in
    let name = params["name"] ?? "unknown"

    // Extract query param: ?preview=true
    let germanParam = urlComponents.queryItems?.first(where: { $0.name == "german" })?.value
    let isGerman = germanParam == "true"
    
    let title = isGerman ? "Hallo \(name)!" : "Hello \(name)!"
    let pageHtml = layoutView(title: title, content: helloView(name: name, isGerman: isGerman))

    return HTTPResponse(status: .ok, contentType: "text/html", body: pageHtml.description)
}

// POST Request dealing with persistent Actor state
//router.add(.POST, "/user/:id") { head, params, _ in
//    guard let idString = params["id"], let id = Int(idString) else {
//        return HTTPResponse(status: .badRequest, body: "Invalid ID")
//    }
//
//    // Asynchronously switch execution contexts context safely to the Database Actor
//    if let user = await db.queryUser(id: id) {
//        return HTTPResponse(status: .ok, body: "Fetched user: \(user["username"] ?? "")")
//    }
//
//    return HTTPResponse(status: .notFound, body: "User record missing")
//}

// Derive the project root from this source file's compile-time path,
// since the working directory when run from Xcode is not the project root.
let projectRoot = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent() // Sources/
    .deletingLastPathComponent() // project root
router.serveStaticFiles(from: projectRoot.appendingPathComponent("Public").path)

// Start the SwiftNIO engine
let server = HTTPServer(host: "127.0.0.1", port: 8080, router: router)
try await server.start()
