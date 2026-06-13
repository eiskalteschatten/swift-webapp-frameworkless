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
    <body>
        <nav><a href="/">Dashboard</a></nav>
        <main>\(content)</main>
    </body>
    </html>
    """
}

