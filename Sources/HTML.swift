//
//  HTML.swift
//  ServerApp
//
//  Created by Alex Seifert on 13/06/2026.
//

import Foundation

/// This is a custom string interpolation that will ensure that all content rendered to HTML in the templates is safe.
/// It prevents XSS attacks.

public struct HTML: ExpressibleByStringInterpolation, CustomStringConvertible {
    public let description: String

    // Standard string literal initializer (e.g., let html: HTML = "Hello")
    public init(stringLiteral value: String) {
        self.description = value
    }

    // Connects our custom interpolation engine to the HTML struct
    public init(stringInterpolation: StringInterpolation) {
        self.description = stringInterpolation.buffer
    }

    // The core interpolation engine
    public struct StringInterpolation: StringInterpolationProtocol {
        public var buffer: String = ""

        // 1. Mandatory Protocol Initializer
        public init(literalCapacity: Int, interpolationCount: Int) {
            buffer.reserveCapacity(literalCapacity + interpolationCount * 2)
        }

        // 2. Mandatory Protocol Literal Appender
        public mutating func appendLiteral(_ literal: String) {
            buffer.append(literal)
        }

        // 3. Custom Rule: Automatically HTML-escape standard Strings
        public mutating func appendInterpolation(_ value: String) {
            let escaped = value
                .replacingOccurrences(of: "&", with: "&amp;")
                .replacingOccurrences(of: "<", with: "&lt;")
                .replacingOccurrences(of: ">", with: "&gt;")
                .replacingOccurrences(of: "\"", with: "&quot;")
                .replacingOccurrences(of: "'", with: "&#039;")
            buffer.append(escaped)
        }

        // 4. Custom Rule: Allow nesting HTML components WITHOUT double-escaping them
        public mutating func appendInterpolation(_ html: HTML) {
            buffer.append(html.description)
        }
        
        // 5. Custom Rule: Handle loop rendering blocks cleanly
        public mutating func appendInterpolation<T>(each items: [T], render: (T) -> HTML) {
            for item in items {
                buffer.append(render(item).description)
            }
        }
    }
}
