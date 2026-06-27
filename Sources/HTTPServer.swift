//
//  HTTPServer.swift
//  ServerApp
//
//  Created by Alex Seifert on 13/06/2026.
//

import NIO
import NIOHTTP1
import Foundation

// MARK: - HTTPHandler

/// The per-connection NIO channel handler responsible for reading HTTP request parts,
/// assembling them into a complete request, dispatching to the `Router`, and writing
/// the response back to the client.
///
/// NIO delivers HTTP/1.1 requests in three sequential parts:
/// 1. `.head`  — the request line and headers
/// 2. `.body`  — zero or more chunks of body bytes (may arrive in multiple calls)
/// 3. `.end`   — signals the request is complete; may carry trailing headers (unused here)
///
/// This handler accumulates all three parts before dispatching, so route handlers always
/// receive a fully-formed request rather than a stream of fragments.
///
/// One `HTTPHandler` instance is created per accepted TCP connection by the
/// `childChannelInitializer` in `HTTPServer.start()`.
private final class HTTPHandler: ChannelInboundHandler, @unchecked Sendable {
    /// Tell NIO what type we expect to read from the pipeline (assembled HTTP parts).
    typealias InboundIn = HTTPServerRequestPart
    /// Tell NIO what type we will write back into the pipeline (assembled HTTP parts).
    typealias OutboundOut = HTTPServerResponsePart

    private let router: Router
    /// Stored when the `.head` part arrives; cleared after the request is dispatched.
    private var requestHead: HTTPRequestHead?
    /// Accumulates body chunks as they arrive; may be nil for body-less requests (GET, etc.).
    private var bodyBuffer: ByteBuffer?
    /// Stored so we can write the response back on the correct event loop thread.
    private var context: ChannelHandlerContext?

    init(router: Router) {
        self.router = router
    }

    /// Called by NIO when this handler is added to the pipeline.
    /// We capture the context so we can use it later when writing the response
    /// from inside the async `Task`.
    func handlerAdded(context: ChannelHandlerContext) {
        self.context = context
    }

    /// Called by NIO when this handler is removed from the pipeline (e.g. after the
    /// connection closes). Nil out the context to avoid dangling references.
    func handlerRemoved(context: ChannelHandlerContext) {
        self.context = nil
    }

    /// Called by NIO each time a new piece of data arrives on the channel.
    /// We switch on the HTTP part type and handle each one accordingly.
    func channelRead(context: ChannelHandlerContext, data: NIOAny) {
        switch unwrapInboundIn(data) {

        case .head(let head):
            // A new request is starting. Store the head and reset the body buffer
            // so any leftover data from a previous request (shouldn't happen with
            // HTTP/1.1 + Connection: close, but defensive) is discarded.
            requestHead = head
            bodyBuffer = nil

        case .body(var buffer):
            // Accumulate body chunks. For small bodies this will be a single call;
            // for larger bodies NIO may deliver multiple chunks.
            if bodyBuffer == nil {
                bodyBuffer = buffer
            } else {
                // Append the new chunk to the existing buffer.
                bodyBuffer!.writeBuffer(&buffer)
            }

        case .end:
            // The full request has been received. Convert the accumulated body bytes
            // to `Data` (empty `Data` for requests with no body), then dispatch.
            guard let head = requestHead else { return }

            let body: Data
            if var buf = bodyBuffer, let bytes = buf.readBytes(length: buf.readableBytes) {
                body = Data(bytes)
            } else {
                body = Data()
            }

            // Clear state so this handler is ready for the next request on this connection.
            requestHead = nil
            bodyBuffer = nil

            // Capture locals to avoid retaining `self` inside the Task.
            let router = self.router
            let eventLoop = context.eventLoop

            // Dispatch to the router on the Swift concurrency thread pool.
            // Route handlers are `async` and may do I/O, so we don't want to block
            // the NIO event loop thread while they run.
            Task { [head = head] in
                let response = await router.handle(head: head, body: body)

                // NIO channel operations must happen on the event loop thread.
                // `eventLoop.execute` schedules the write back onto the correct thread.
                eventLoop.execute { [weak self] in
                    guard let self, let context = self.context else { return }
                    self.write(response: response, context: context)
                }
            }
        }
    }

    /// Serialises an `HTTPResponse` into NIO's three-part response format and writes
    /// it to the channel, then closes the connection.
    ///
    /// HTTP/1.1 responses consist of:
    /// 1. A response head (status line + headers)
    /// 2. A body (as a `ByteBuffer`)
    /// 3. An end marker (allows trailing headers, which we don't use)
    ///
    /// We set `Connection: close` because this server uses a simple one-request-per-connection
    /// model rather than HTTP keep-alive.
    private func write(response: HTTPResponse, context: ChannelHandlerContext) {
        // Allocate a NIO `ByteBuffer` sized to the response body and copy the bytes in.
        var buffer = context.channel.allocator.buffer(capacity: response.bodyData.count)
        buffer.writeBytes(response.bodyData)

        var headers = HTTPHeaders()
        headers.add(name: "Content-Type", value: response.contentType)
        // Telling the client the exact byte count avoids chunked transfer encoding
        // and lets browsers display progress correctly.
        headers.add(name: "Content-Length", value: "\(buffer.readableBytes)")
        headers.add(name: "Connection", value: "close")

        let responseHead = HTTPResponseHead(version: .http1_1, status: response.status, headers: headers)

        // Write all three parts. The first two use `write` (buffered); the last uses
        // `writeAndFlush` to push everything to the network in one syscall.
        context.write(wrapOutboundOut(.head(responseHead)), promise: nil)
        context.write(wrapOutboundOut(.body(.byteBuffer(buffer))), promise: nil)

        let channel = context.channel
        context.writeAndFlush(wrapOutboundOut(.end(nil))).whenComplete { _ in
            // Close the TCP connection once all bytes have been sent.
            channel.close(promise: nil)
        }
    }

    /// Called by NIO when an unrecoverable error occurs on the channel (e.g. a malformed
    /// HTTP request that the pipeline decoder couldn't handle). We just close the connection.
    func errorCaught(context: ChannelHandlerContext, error: Error) {
        context.close(promise: nil)
    }
}

// MARK: - HTTPServer

/// The public entry point that binds a TCP port and starts accepting HTTP connections.
///
/// Internally it uses SwiftNIO's `ServerBootstrap` to set up a non-blocking I/O pipeline.
/// Each accepted connection gets its own `HTTPHandler` instance.
public final class HTTPServer {
    private let host: String
    private let port: Int
    /// The thread pool that drives NIO's event loops. One thread per CPU core is the
    /// recommended default for maximising throughput on multi-core servers.
    private let group: MultiThreadedEventLoopGroup
    private let router: Router

    public init(host: String, port: Int, router: Router) {
        self.host = host
        self.port = port
        self.router = router
        // Spin up one event loop thread per CPU core for maximum parallelism.
        self.group = MultiThreadedEventLoopGroup(numberOfThreads: System.coreCount)
    }

    /// Binds the server to the configured host and port and begins accepting connections.
    ///
    /// This method suspends indefinitely — it only returns (or throws) if the server
    /// channel is closed externally (e.g. by a signal handler or test teardown).
    public func start() async throws {
        let router = self.router

        let bootstrap = ServerBootstrap(group: group)
            // How many pending connections the OS kernel should queue before the
            // application has a chance to accept them.
            .serverChannelOption(ChannelOptions.backlog, value: 256)
            // Allow the port to be reused immediately after the process restarts,
            // without waiting for the OS TIME_WAIT period to expire.
            .serverChannelOption(ChannelOptions.socketOption(.so_reuseaddr), value: 1)
            // For each accepted connection, configure the NIO pipeline:
            //   1. Built-in HTTP/1.1 encoder + decoder
            //   2. Our custom HTTPHandler for routing
            .childChannelInitializer { channel in
                channel.pipeline.configureHTTPServerPipeline().flatMap {
                    channel.pipeline.addHandler(HTTPHandler(router: router))
                }
            }

        let channel = try await bootstrap.bind(host: host, port: port).get()
        print("Server running on http://\(host):\(port)")

        // Suspend here until the channel is closed. In normal operation this never
        // returns — the server runs until the process is killed.
        try await channel.closeFuture.get()
    }
}
