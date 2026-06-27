# swift-webapp-frameworkless

A frameworkless Swift web server built on top of [SwiftNIO](https://github.com/apple/swift-nio). It demonstrates how to build a fully functional HTTP server — with routing, dynamic HTML templating, static file serving, and XSS-safe string interpolation — without reaching for a high-level web framework like Vapor.

---

## Table of Contents

- [Requirements](#requirements)
- [Running the Server](#running-the-server)
  - [Terminal](#terminal)
  - [Xcode](#xcode)
  - [Linux Server](#linux-server)
- [Project Structure](#project-structure)
- [How It Works](#how-it-works)
  - [1. HTTP Server](#1-http-server-httpserverswift)
  - [2. Router](#2-router-routerswift)
  - [3. HTML Type & XSS Safety](#3-html-type--xss-safety-htmlswift)
  - [4. Views](#4-views-sourcesviews)
  - [5. Routes](#5-routes-mainswift)
  - [6. Client-Side JavaScript](#6-client-side-javascript-publicjsscriptsjs)
- [Key Design Decisions](#key-design-decisions)

---

## Requirements

- Swift 6.0+
- macOS 14+ or Linux (only supported on Windows via WSL)

---

## Running the Server

### Terminal

```bash
swift run
```

The server will start at `http://127.0.0.1:8080`.

### Xcode

1. Open the project in Xcode: `File > Open` and select the `swift-webapp-frameworkless` folder (Xcode will detect the `Package.swift` automatically).
2. Select the **ServerApp** scheme from the scheme picker in the toolbar.
3. Press **⌘R** to build and run.

> **Note:** Xcode sets the working directory to the build products folder, not the project root. This is fine — the project resolves the path to `Public/` at runtime by walking up from the binary's location, so static files will be served correctly without any extra Xcode configuration.

The server will start at `http://127.0.0.1:8080`. Output (including the startup message) will appear in the Xcode console.

### Linux Server

1. **Install Swift** on your server. The recommended way is via [swiftly](https://swift.org/install), the official Swift toolchain installer:
   ```bash
   curl -L https://swift.org/install.sh | bash
   swiftly install latest
   ```
   Alternatively, download a toolchain directly from [swift.org/download](https://www.swift.org/download/).

2. **Copy the project** to your server (e.g. via `scp`, `rsync`, or by cloning the repository).

3. **Build a release binary:**
   ```bash
   swift build -c release
   ```

4. **Run the server:**
   ```bash
   .build/release/ServerApp
   ```

---

## Project Structure

```
Sources/
├── main.swift          # Entry point — defines routes and starts the server
├── HTTPServer.swift    # SwiftNIO-based HTTP server and request pipeline
├── Router.swift        # Route registration, matching, and static file serving
├── HTML.swift          # XSS-safe HTML string interpolation type
└── views/
    ├── layoutView.swift    # Shared page layout (shell HTML, stylesheet, scripts)
    ├── homeView.swift      # Home page view
    └── helloView.swift     # Greeting view (supports English and German)
Public/
├── css/
│   └── main.css        # Stylesheet, served as a static file
└── js/
    └── scripts.js      # Client-side JavaScript, served as a static file
```

---

## How It Works

### 1. HTTP Server (`HTTPServer.swift`)

The server is built directly on SwiftNIO's `ServerBootstrap`. It spawns a thread pool sized to the number of CPU cores and listens for incoming TCP connections. Each connection is handled by `HTTPHandler`, a `ChannelInboundHandler` that processes the three parts of every HTTP/1.1 request in sequence:

- **`.head`** — captures the request line and headers (`HTTPRequestHead`)
- **`.body`** — accumulates any body bytes into a `ByteBuffer`
- **`.end`** — converts the accumulated buffer to `Data`, then dispatches to the `Router` inside a Swift `Task` (so async handlers work naturally)

Once the router returns an `HTTPResponse`, the handler writes the response head, body, and end frame back to the channel, then closes the connection.

### 2. Router (`Router.swift`)

The `Router` is a thread-safe class (protected by `NSLock`) that maps `(HTTPMethod, path pattern)` pairs to async handler functions.

**Route registration** uses `add(_:_:_:)`:

```swift
router.add(.GET, "/hello/:name") { head, params, urlComponents, body in
    let name = params["name"] ?? "unknown"
    return HTTPResponse(status: .ok, contentType: "text/html", body: "Hello, \(name)!")
}
```

Path segments prefixed with `:` (e.g. `:name`) are treated as named parameters. Under the hood they are compiled into a `Regex` capture group, and the captured values are extracted into the `params: [String: String]` dictionary that is passed to the handler.

The `Handler` typealias defines the signature every route handler must conform to:

```swift
public typealias Handler = (HTTPRequestHead, [String: String], URLComponents, Data) async -> HTTPResponse
```

| Parameter | Description |
|---|---|
| `HTTPRequestHead` | Method, URI, and headers |
| `[String: String]` | Named URL path parameters |
| `URLComponents` | Parsed URL — use `.queryItems` to read query strings |
| `Data` | Raw request body bytes |

**Static file serving** is enabled with a single call:

```swift
router.serveStaticFiles(from: projectRoot.appendingPathComponent("Public").path)
```

This registers a catch-all `GET` route that maps any request path to a file under the given directory. Path traversal (`..`) is sanitised before the file is read. The correct `Content-Type` header is inferred from the file extension.

### 3. HTML Type & XSS Safety (`HTML.swift`)

`HTML` is a custom Swift type that leverages `ExpressibleByStringInterpolation` to make HTML template authoring both ergonomic and safe. It has three interpolation rules:

| Interpolated value | Behaviour |
|---|---|
| `String` | **HTML-escaped** — `<`, `>`, `&`, `"`, `'` are replaced with their HTML entities, preventing XSS |
| `HTML` | Passed through **raw** — so nested components are not double-escaped |
| `[T]` via `\(each: items, render:)` | Renders a collection using a closure, appending each result as raw `HTML` |

Views return `HTML` values, not plain `String`s, so the compiler enforces that dynamic data always flows through the escaping path unless it has been explicitly marked as trusted `HTML`.

### 4. Views (`Sources/views/`)

Views are plain Swift functions that return `HTML`. They use Swift string interpolation with the `HTML` type to compose markup safely.

| View | Function signature | Description |
|---|---|---|
| `layoutView` | `(title: String, content: HTML, name: String) -> HTML` | Outer page shell — includes the `<html>`, `<head>`, stylesheet link, script tag, and shared UI controls |
| `homeView` | `() -> HTML` | Simple home page heading |
| `helloView` | `(name: String, isGerman: Bool) -> HTML` | Greeting heading; renders in German when `isGerman` is `true` |

### 5. Routes (`main.swift`)

| Method | Path | Description |
|---|---|---|
| `GET` | `/` | Renders the home page |
| `GET` | `/hello/:name` | Renders a greeting for `name`; pass `?german=true` to switch language |
| `GET` | `/*` | Static file handler — serves anything under `Public/` |

### 6. Client-Side JavaScript (`Public/js/scripts.js`)

Two buttons in the shared layout let users navigate to the greeting page:

- **Say Hello!** — navigates to `/hello/{name}`
- **Say Hello in German!** — navigates to `/hello/{name}?german=true`

Both listeners are registered inside a `DOMContentLoaded` handler to ensure the DOM is ready before the script runs.

---

## Key Design Decisions

- **No web framework** — only [SwiftNIO](https://github.com/apple/swift-nio) (`NIO` + `NIOHTTP1`) is used as a dependency, giving full visibility into every layer of the stack.
- **Swift 6 strict concurrency** — the project targets Swift 6.0. `Router` uses `NSLock` for thread-safe route registration and a copy-on-read snapshot pattern to avoid holding the lock during route matching.
- **Compile-time XSS safety** — the `HTML` type makes it impossible to accidentally interpolate an unescaped `String` into a template; safety is enforced by the type system rather than by convention.
- **Runtime-relative static files** — the path to `Public/` is resolved at runtime by walking up from the running binary's location (`CommandLine.arguments[0]`), rather than using `#filePath` at compile time. This means the binary can be built on one machine and deployed to another without breaking static file serving.
