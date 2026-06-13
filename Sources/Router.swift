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
    public let body: String

    public init(status: HTTPResponseStatus, contentType: String = "text/plain; charset=utf-8", body: String = "") {
        self.status = status
        self.contentType = contentType
        self.body = body
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
