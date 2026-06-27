//
//  homeView.swift
//  ServerApp
//
//  Created by Alex Seifert on 13/06/2026.
//

/// Renders the home page content fragment.
///
/// Returns a simple heading to be embedded inside `layoutView`. This is intentionally
/// minimal — it exists as a separate function so the home page content can grow
/// independently without touching the shared layout.
func homeView() -> HTML {
    return """
    <h1>Home!</h1>
    """
}
