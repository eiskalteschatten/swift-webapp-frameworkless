//
//  helloView.swift
//  ServerApp
//
//  Created by Alex Seifert on 13/06/2026.
//

func helloView(name: String, isGerman: Bool = false) -> HTML {
    let greeting = isGerman ? "Hallo \(name)!" : "Hello \(name)!"
    return "<p>\(greeting)</p>"
}
