//
//  helloView.swift
//  ServerApp
//
//  Created by Alex Seifert on 13/06/2026.
//

/// Renders a personalised greeting heading.
///
/// The greeting language is controlled by `isGerman`:
/// - `false` (default) — "Hello {name}!"
/// - `true`            — "Hallo {name}!"
///
/// `name` is interpolated as a plain `String` into an `HTML` value, so any special
/// characters in the name (e.g. `<`, `>`, `&`) are automatically HTML-escaped by
/// the `HTML` type's custom string interpolation.
///
/// Parameters:
/// - `name`     — the name to greet; sourced from the `:name` URL path parameter
/// - `isGerman` — when `true`, renders the greeting in German
func helloView(name: String, isGerman: Bool = false) -> HTML {
    // Build the greeting string first so the HTML type escapes `name` once,
    // then wrap it in a heading tag.
    let greeting = isGerman ? "Hallo \(name)!" : "Hello \(name)!"
    return "<h1>\(greeting)</h1>"
}
