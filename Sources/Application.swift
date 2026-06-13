//
//  Application.swift
//  swift-webapp-frameworkless
//
//  Created by Alex Seifert on 13/06/2026.
//

@main
struct Application {
    static func main() async throws {
        let router = Router()
        let db = try DatabaseContext(path: "app.db")

        // GET Request with Route Parameters and Query String Parsing
        router.add(.GET, "/blog/post/:slug") { head, params, urlComponents in
            let slug = params["slug"] ?? "unknown"
            
            // Extract query param: ?preview=true
            let previewParam = urlComponents.queryItems?.first(where: { $0.name == "preview" })?.value
            let isPreview = previewParam == "true"
            
            let users = ["Alice", "Bob", "<script>alert('xss')</script>"] // Escapes safely!
            let pageHtml = layoutView(title: "Viewing Post", content: userListView(users: users))
            
            return HTTPResponse(status: .ok, contentType: "text/html", body: pageHtml.description)
        }

        // POST Request dealing with persistent Actor state
        router.add(.POST, "/user/:id") { head, params, _ in
            guard let idString = params["id"], let id = Int(idString) else {
                return HTTPResponse(status: .badRequest, body: "Invalid ID")
            }
            
            // Asynchronously switch execution contexts context safely to the Database Actor
            if let user = await db.queryUser(id: id) {
                return HTTPResponse(status: .ok, body: "Fetched user: \(user["username"] ?? "")")
            }
            
            return HTTPResponse(status: .notFound, body: "User record missing")
        }

        // Start the SwiftNIO engine
        let server = HTTPServer(host: "127.0.0.1", port: 8080, router: router)
        try server.start()
    }
}
