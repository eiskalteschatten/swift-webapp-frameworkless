//
//  layoutView.swift
//  ServerApp
//
//  Created by Alex Seifert on 13/06/2026.
//

/// The shared outer page shell used by every route that returns a full HTML page.
///
/// Renders a complete HTML document including:
/// - The page `<title>` tag
/// - A link to the shared stylesheet (`/css/main.css`)
/// - The client-side script tag (`/js/scripts.js`) — placed in `<head>` with
///   `DOMContentLoaded` handling in the script itself
/// - A `<main>` element containing the page-specific `content`
/// - A shared name input field and two navigation buttons at the bottom of every page
///
/// Parameters:
/// - `title`   — injected into `<title>` and used as the browser tab label
/// - `content` — the page-specific `HTML` fragment to render inside `<main>`
/// - `name`    — pre-fills the name input field; defaults to empty string
func layoutView(title: String, content: HTML, name: String = "") -> HTML {
    return """
    <!DOCTYPE html>
    <html>
        <head><title>\(title)</title></head>
        <link rel="stylesheet" href="/css/main.css">
        <script src="/js/scripts.js"></script>
        <body>
            <nav>
                <a href="/">Home</a>
            </nav>
            <main>\(content)</main>
            <p>Input your name: <input type="text" id="name" value="\(name)"></p>
            <div class="buttons">
                <button type="button" id="sayHelloButton">Say Hello!</button>
                <button type="button" id="sayHelloGermanButton">Say Hello in German!</button>
            </div>
        </body>
    </html>
    """
}
