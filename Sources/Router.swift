//
//  Router.swift
//  ServerApp
//
//  Created by Alex Seifert on 13/06/2026.
//

import Foundation
import NIOHTTP1

// MARK: - HTTPResponse

/// Represents a complete HTTP response that a route handler returns to the server.
/// It is `Sendable` so it can be safely passed across actor/task boundaries in Swift's
/// structured concurrency model.
public struct HTTPResponse: Sendable {
    public let status: HTTPResponseStatus
    public let contentType: String
    /// The raw bytes of the response body, stored as `Data` so the server layer
    /// can write them directly to the NIO `ByteBuffer` without re-encoding.
    let bodyData: Data

    /// Convenience initialiser for text-based responses (HTML, JSON strings, plain text, etc.).
    /// Defaults to `text/plain; charset=utf-8` so callers only need to override `contentType`
    /// when they're returning something other than plain text.
    public init(status: HTTPResponseStatus, contentType: String = "text/plain; charset=utf-8", body: String = "") {
        self.status = status
        self.contentType = contentType
        self.bodyData = Data(body.utf8)
    }

    /// Initialiser for binary responses (images, fonts, pre-encoded JSON `Data`, etc.)
    /// where the bytes are already available and don't need UTF-8 encoding.
    public init(status: HTTPResponseStatus, contentType: String, data: Data) {
        self.status = status
        self.contentType = contentType
        self.bodyData = data
    }
}

// MARK: - Handler & Route

/// The function signature that every route handler must conform to.
///
/// Parameters passed to each handler:
/// - `HTTPRequestHead`    — the request method, URI, and headers
/// - `[String: String]`  — named URL path parameters (e.g. `["name": "Alex"]` for `/hello/:name`)
/// - `URLComponents`     — the fully parsed URL, useful for reading query string items via `.queryItems`
/// - `Data`              — the raw request body bytes (empty for GET requests)
///
/// Handlers are `async`, so they can `await` database calls, file I/O, or any other
/// asynchronous work before returning a response.
public typealias Handler = (HTTPRequestHead, [String: String], URLComponents, Data) async -> HTTPResponse

/// A single registered route, storing everything needed to match an incoming request
/// and dispatch it to the correct handler.
public struct Route {
    let method: HTTPMethod
    /// Pre-compiled regex derived from the path pattern (e.g. `/hello/:name` becomes `^/hello/([^/]+)$`).
    /// Compiling once at registration time keeps request matching fast.
    let regex: Regex<AnyRegexOutput>
    /// The ordered list of parameter names extracted from the path pattern (e.g. `["name"]`).
    /// Used to map regex capture groups back to named keys in the params dictionary.
    let paramNames: [String]
    let handler: Handler
}

// MARK: - Router

/// A thread-safe HTTP router that maps `(method, path pattern)` pairs to async handler functions.
///
/// ## Thread safety
/// Routes are stored in a plain `Array`, which is not thread-safe by default. An `NSLock`
/// is used to serialise all reads and writes. When handling a request, the current route list
/// is copied out under the lock and then iterated without holding it — this "copy-on-read"
/// pattern keeps the lock held for the minimum possible time and avoids blocking other
/// threads during potentially slow handler execution.
///
/// The class is marked `@unchecked Sendable` because Swift's concurrency checker cannot
/// automatically verify the manual locking strategy, so we assert correctness ourselves.
public final class Router: @unchecked Sendable {
    private let lock = NSLock()
    private var routes: [Route] = []

    public init() {}

    // MARK: Route Registration

    /// Registers a route for the given HTTP method and path pattern.
    ///
    /// Path segments starting with `:` are treated as named parameters and will be
    /// captured and passed to the handler at request time. For example:
    /// ```swift
    /// router.add(.GET, "/users/:id") { _, params, _, _ in
    ///     let id = params["id"] ?? "unknown"
    ///     return HTTPResponse(status: .ok, body: "User \(id)")
    /// }
    /// ```
    /// The path is compiled into a `Regex` at registration time so matching is efficient.
    public func add(_ method: HTTPMethod, _ path: String, _ handler: @escaping Handler) {
        var paramNames: [String] = []

        // Replace each `:paramName` segment with a regex capture group `([^/]+)`,
        // and record the parameter name so we can map captures back to names later.
        let regexString = path.replacing(/:([a-zA-Z0-9_]+)/) { match in
            paramNames.append(String(match.output.1))
            return "([^/]+)"
        }

        guard let regex = try? Regex("^" + regexString + "$") else { return }
        lock.withLock { routes.append(Route(method: method, regex: regex, paramNames: paramNames, handler: handler)) }
    }

    /// Registers a catch-all GET route that serves files from the given directory.
    ///
    /// Any GET request whose path matches an existing file under `directory` will be
    /// served with the appropriate `Content-Type` header inferred from the file extension.
    ///
    /// Path traversal attacks are mitigated by stripping empty segments and any `..`
    /// components before constructing the final file path.
    public func serveStaticFiles(from directory: String) {
        // Resolve the base directory to an absolute path so file lookups work regardless
        // of what the current working directory is at runtime.
        let baseDir = directory.hasPrefix("/")
            ? directory
            : FileManager.default.currentDirectoryPath + "/" + directory

        guard let regex = try? Regex("^/(.+)$") else { return }
        let route = Route(
            method: .GET,
            regex: regex,
            paramNames: ["filePath"],
            handler: { _, params, _, _ in
                guard let filePath = params["filePath"] else {
                    return HTTPResponse(status: .notFound, body: "Not Found")
                }

                // Sanitise the path by removing empty components and any `..` segments
                // to prevent directory traversal (e.g. `GET /../../etc/passwd`).
                let sanitized = filePath
                    .components(separatedBy: "/")
                    .filter { !$0.isEmpty && $0 != ".." }
                    .joined(separator: "/")

                guard !sanitized.isEmpty else {
                    return HTTPResponse(status: .notFound, body: "Not Found")
                }

                let fullPath = baseDir + "/" + sanitized

                guard let data = try? Data(contentsOf: URL(fileURLWithPath: fullPath)) else {
                    return HTTPResponse(status: .notFound, body: "Not Found")
                }

                // Infer the Content-Type from the file extension so browsers handle
                // CSS, JS, images, fonts, etc. correctly.
                let ext = (fullPath as NSString).pathExtension
                return HTTPResponse(status: .ok, contentType: mimeType(for: ext), data: data)
            }
        )
        lock.withLock { routes.append(route) }
    }

    // MARK: Request Handling

    /// Finds the first route that matches the incoming request and calls its handler.
    ///
    /// Routes are tested in registration order. The first match wins, so more specific
    /// routes should be registered before broader ones (e.g. register `/users/me` before
    /// `/users/:id`).
    ///
    /// Returns a `404 Not Found` response if no route matches.
    public func handle(head: HTTPRequestHead, body: Data = Data()) async -> HTTPResponse {
        guard let components = URLComponents(string: head.uri) else {
            return HTTPResponse(status: .badRequest, body: "Invalid URL")
        }

        let path = components.path

        // Copy the route list under the lock, then release immediately.
        // This means we only block other threads for the duration of the array copy,
        // not for the entire (potentially slow) route matching and handler execution.
        let currentRoutes = lock.withLock { routes }

        for route in currentRoutes {
            if route.method != head.method { continue }

            if let match = try? route.regex.wholeMatch(in: path) {
                // Map each regex capture group back to its named parameter.
                // Capture group indices are 1-based (index 0 is the full match).
                var params: [String: String] = [:]
                for (index, name) in route.paramNames.enumerated() {
                    let captureIndex = index + 1
                    if captureIndex < match.output.count,
                       let value = match[captureIndex].value as? Substring {
                        params[name] = String(value)
                    }
                }
                return await route.handler(head, params, components, body)
            }
        }

        return HTTPResponse(status: .notFound, body: "Not Found")
    }
}

// MARK: - MIME Type Helpers

/// Maps a file extension to its corresponding MIME type string.
/// Falls back to `application/octet-stream` for unknown extensions, which tells
/// the browser to treat the file as a generic binary download.
private func mimeType(for ext: String) -> String {
    switch ext.lowercased() {
    case "html": return "text/html; charset=utf-8"
    case "css":  return "text/css; charset=utf-8"
    case "js":   return "application/javascript; charset=utf-8"
    case "json": return "application/json; charset=utf-8"
    case "png":  return "image/png"
    case "jpg", "jpeg": return "image/jpeg"
    case "gif":  return "image/gif"
    case "svg":  return "image/svg+xml"
    case "ico":  return "image/x-icon"
    case "woff": return "font/woff"
    case "woff2": return "font/woff2"
    case "ttf":  return "font/ttf"
    case "txt":  return "text/plain; charset=utf-8"
    default:     return "application/octet-stream"
    }
}
