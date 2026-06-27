//
//  HTML.swift
//  ServerApp
//
//  Created by Alex Seifert on 13/06/2026.
//

import Foundation

// MARK: - HTML

/// A type-safe wrapper for HTML strings that uses Swift's `ExpressibleByStringInterpolation`
/// protocol to enforce XSS safety at the type system level.
///
/// ## How it works
/// Any plain `String` interpolated into an `HTML` value is **automatically HTML-escaped**
/// (e.g. `<` → `&lt;`), so user-supplied data can never inject raw HTML tags.
/// Nested `HTML` values are passed through **unescaped**, allowing safe composition of
/// trusted template components without double-encoding.
///
/// ## Usage
/// ```swift
/// let name: String = "<script>alert('xss')</script>"
/// let safe: HTML = "<p>Hello \(name)</p>"
/// // Renders as: <p>Hello &lt;script&gt;alert(&#039;xss&#039;)&lt;/script&gt;</p>
///
/// let inner: HTML = "<strong>world</strong>"
/// let outer: HTML = "<p>\(inner)</p>"
/// // Renders as: <p><strong>world</strong></p>  ← not double-escaped
/// ```
public struct HTML: ExpressibleByStringInterpolation, CustomStringConvertible {
    /// The final rendered HTML string. Accessing `.description` is also how
    /// `CustomStringConvertible` exposes the value (e.g. for `String(describing:)`).
    public let description: String

    /// Allows an `HTML` value to be created from a plain string literal with no
    /// interpolation (e.g. `let html: HTML = "<p>Hello</p>"`).
    /// The string is used verbatim — no escaping — because it is a compile-time literal
    /// written by the developer, not dynamic user data.
    public init(stringLiteral value: String) {
        self.description = value
    }

    /// Called by the Swift compiler after it has finished building the `StringInterpolation`
    /// object. We simply extract the accumulated buffer as our final HTML string.
    public init(stringInterpolation: StringInterpolation) {
        self.description = stringInterpolation.buffer
    }

    // MARK: - StringInterpolation Engine

    /// The custom interpolation engine for the `HTML` type.
    ///
    /// Swift calls `appendLiteral` for each raw string segment between interpolations,
    /// and `appendInterpolation` for each `\(value)` placeholder. By overloading
    /// `appendInterpolation` with different parameter types, we control exactly how
    /// each type of value is embedded into the output.
    public struct StringInterpolation: StringInterpolationProtocol {
        /// The mutable string being built up as the interpolation is processed.
        public var buffer: String = ""

        /// Required by `StringInterpolationProtocol`. Pre-allocates buffer capacity
        /// using the compiler's hints about how much literal text and how many
        /// interpolation segments there are, reducing reallocations.
        public init(literalCapacity: Int, interpolationCount: Int) {
            buffer.reserveCapacity(literalCapacity + interpolationCount * 2)
        }

        /// Appends a raw literal segment (the text between `\(...)` placeholders).
        /// This is always developer-written markup and is copied verbatim.
        public mutating func appendLiteral(_ literal: String) {
            buffer.append(literal)
        }

        /// Appends a plain `String` value with HTML escaping applied.
        ///
        /// This is the core XSS-prevention rule. Any `String` interpolated into an
        /// `HTML` value — including user input, database values, or URL parameters —
        /// goes through this method and has its special characters replaced with
        /// their safe HTML entity equivalents:
        /// - `&`  →  `&amp;`   (must be escaped first to avoid double-escaping)
        /// - `<`  →  `&lt;`
        /// - `>`  →  `&gt;`
        /// - `"`  →  `&quot;`
        /// - `'`  →  `&#039;`
        public mutating func appendInterpolation(_ value: String) {
            let escaped = value
                .replacingOccurrences(of: "&", with: "&amp;")
                .replacingOccurrences(of: "<", with: "&lt;")
                .replacingOccurrences(of: ">", with: "&gt;")
                .replacingOccurrences(of: "\"", with: "&quot;")
                .replacingOccurrences(of: "'", with: "&#039;")
            buffer.append(escaped)
        }

        /// Appends a nested `HTML` value **without** escaping.
        ///
        /// Because the value is already of type `HTML`, it has either come from a
        /// string literal (developer-written) or has already been through the escaping
        /// pipeline. Appending it raw prevents double-escaping (e.g. `&amp;` becoming
        /// `&amp;amp;`).
        ///
        /// This overload is what makes component composition work:
        /// ```swift
        /// let content: HTML = "<p>Hello</p>"
        /// let page: HTML = "<body>\(content)</body>"  // content is not re-escaped
        /// ```
        public mutating func appendInterpolation(_ html: HTML) {
            buffer.append(html.description)
        }

        /// Renders a collection of items into HTML using a closure, appending each
        /// result directly to the buffer.
        ///
        /// This makes list rendering concise and safe:
        /// ```swift
        /// let items = ["Alice", "Bob"]
        /// let html: HTML = "<ul>\(each: items, render: { "<li>\($0)</li>" })</ul>"
        /// // Each item string is escaped via the String overload inside the closure.
        /// ```
        public mutating func appendInterpolation<T>(each items: [T], render: (T) -> HTML) {
            for item in items {
                // Each rendered item is already an `HTML` value, so append raw.
                buffer.append(render(item).description)
            }
        }
    }
}
