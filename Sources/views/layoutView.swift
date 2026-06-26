//
//  layoutView.swift
//  ServerApp
//
//  Created by Alex Seifert on 13/06/2026.
//

func layoutView(title: String, content: HTML) -> HTML {
    return """
    <!DOCTYPE html>
    <html>
    <head><title>\(title)</title></head>
    <link rel="stylesheet" href="/css/main.css">
    <script src="/js/scripts.js"></script>
    <body>
        <nav><a href="/">Home</a></nav>
        <main>\(content)</main>
        <p>Input your name: <input type="text" id="name"></p>
        <p><button type="button" id="sayHelloButton">Say Hello!</button></p>
        <p><button type="button" id="sayHelloGermanButton">Say Hello in German!</button></p>
    </body>
    </html>
    """
}

