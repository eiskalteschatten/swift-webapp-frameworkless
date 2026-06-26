# swift-webapp-frameworkless

A frameworkless Swift web server built on top of [SwiftNIO](https://github.com/apple/swift-nio). It demonstrates how to build a fully functional HTTP server — with routing, dynamic HTML templating, static file serving, and XSS-safe string interpolation — without reaching for a high-level web framework like Vapor.

---

## Requirements

- Swift 6.0+

---

## Running the Server

```bash
swift run
```

The server will start at `http://127.0.0.1:8080`.

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
    ├── helloView.swift     # Greeting view (supports English and German)
    └── userListView.swift  # Renders a list of users
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
| `userListView` | `(users: [String]) -> HTML` | Unordered list of user names using the `each:render:` interpolation helper |

### 5. Routes (`main.swift`)

| Method | Path | Description |
|---|---|---|
| `GET` | `/` | Renders the home page |
| `GET` | `/hello/:name` | Renders a greeting for `name`; pass `?german=true` to switch language |
| `POST` | `/hello` | Skeleton POST handler — receives a JSON or form body via the `body: Data` parameter |
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
- **Project-relative static files** — `#filePath` is used at compile time to derive the absolute path to `Public/`, so static file serving works correctly regardless of the working directory Xcode or `swift run` sets at launch.
