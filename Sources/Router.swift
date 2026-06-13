//
//  Router.swift
//  ServerApp
//
//  Created by Alex Seifert on 13/06/2026.
//

import Foundation
import NIOHTTP1

public struct HTTPResponse: Sendable {
    public let status: HTTPResponseStatus
    public let contentType: String
    let bodyData: Data

    public init(status: HTTPResponseStatus, contentType: String = "text/plain; charset=utf-8", body: String = "") {
        self.status = status
        self.contentType = contentType
        self.bodyData = Data(body.utf8)
    }

    public init(status: HTTPResponseStatus, contentType: String, data: Data) {
        self.status = status
        self.contentType = contentType
        self.bodyData = data
    }
}

public typealias Handler = (HTTPRequestHead, [String: String], URLComponents) async -> HTTPResponse

public struct Route {
    let method: HTTPMethod
    let regex: Regex<AnyRegexOutput>
    let paramNames: [String]
    let handler: Handler
}

public final class Router: @unchecked Sendable {
    private let lock = NSLock()
    private var routes: [Route] = []

    public init() {}

    public func add(_ method: HTTPMethod, _ path: String, _ handler: @escaping Handler) {
        var paramNames: [String] = []
        let regexString = path.replacing(/:([a-zA-Z0-9_]+)/) { match in
            paramNames.append(String(match.output.1))
            return "([^/]+)"
        }
        guard let regex = try? Regex("^" + regexString + "$") else { return }
        lock.withLock { routes.append(Route(method: method, regex: regex, paramNames: paramNames, handler: handler)) }
    }

    public func serveStaticFiles(from directory: String) {
        let baseDir = directory.hasPrefix("/")
            ? directory
            : FileManager.default.currentDirectoryPath + "/" + directory

        guard let regex = try? Regex("^/(.+)$") else { return }
        let route = Route(
            method: .GET,
            regex: regex,
            paramNames: ["filePath"],
            handler: { _, params, _ in
                guard let filePath = params["filePath"] else {
                    return HTTPResponse(status: .notFound, body: "Not Found")
                }

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

                let ext = (fullPath as NSString).pathExtension
                return HTTPResponse(status: .ok, contentType: mimeType(for: ext), data: data)
            }
        )
        lock.withLock { routes.append(route) }
    }

    public func handle(head: HTTPRequestHead) async -> HTTPResponse {
        guard let components = URLComponents(string: head.uri) else {
            return HTTPResponse(status: .badRequest, body: "Invalid URL")
        }

        let path = components.path
        let currentRoutes = lock.withLock { routes }

        for route in currentRoutes {
            if route.method != head.method { continue }

            if let match = try? route.regex.wholeMatch(in: path) {
                var params: [String: String] = [:]
                for (index, name) in route.paramNames.enumerated() {
                    let captureIndex = index + 1
                    if captureIndex < match.output.count,
                       let value = match[captureIndex].value as? Substring {
                        params[name] = String(value)
                    }
                }
                return await route.handler(head, params, components)
            }
        }
        return HTTPResponse(status: .notFound, body: "Not Found")
    }
}

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
