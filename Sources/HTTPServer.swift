//
//  HTTPServer.swift
//  ServerApp
//
//  Created by Alex Seifert on 13/06/2026.
//

import NIO
import NIOHTTP1
import Foundation

private final class HTTPHandler: ChannelInboundHandler, @unchecked Sendable {
    typealias InboundIn = HTTPServerRequestPart
    typealias OutboundOut = HTTPServerResponsePart

    private let router: Router
    private var requestHead: HTTPRequestHead?
    private var context: ChannelHandlerContext?

    init(router: Router) {
        self.router = router
    }

    func handlerAdded(context: ChannelHandlerContext) {
        self.context = context
    }

    func handlerRemoved(context: ChannelHandlerContext) {
        self.context = nil
    }

    func channelRead(context: ChannelHandlerContext, data: NIOAny) {
        switch unwrapInboundIn(data) {
        case .head(let head):
            requestHead = head
        case .body:
            break
        case .end:
            guard let head = requestHead else { return }
            requestHead = nil
            let router = self.router
            let eventLoop = context.eventLoop
            Task { [head = head] in
                let response = await router.handle(head: head)
                eventLoop.execute { [weak self] in
                    guard let self, let context = self.context else { return }
                    self.write(response: response, context: context)
                }
            }
        }
    }

    private func write(response: HTTPResponse, context: ChannelHandlerContext) {
        var buffer = context.channel.allocator.buffer(capacity: response.bodyData.count)
        buffer.writeBytes(response.bodyData)

        var headers = HTTPHeaders()
        headers.add(name: "Content-Type", value: response.contentType)
        headers.add(name: "Content-Length", value: "\(buffer.readableBytes)")
        headers.add(name: "Connection", value: "close")

        let responseHead = HTTPResponseHead(version: .http1_1, status: response.status, headers: headers)
        context.write(wrapOutboundOut(.head(responseHead)), promise: nil)
        context.write(wrapOutboundOut(.body(.byteBuffer(buffer))), promise: nil)
        let channel = context.channel
        context.writeAndFlush(wrapOutboundOut(.end(nil))).whenComplete { _ in
            channel.close(promise: nil)
        }
    }

    func errorCaught(context: ChannelHandlerContext, error: Error) {
        context.close(promise: nil)
    }
}

public final class HTTPServer {
    private let host: String
    private let port: Int
    private let group: MultiThreadedEventLoopGroup
    private let router: Router

    public init(host: String, port: Int, router: Router) {
        self.host = host
        self.port = port
        self.router = router
        // Spin up an event loop pool matching CPU core count
        self.group = MultiThreadedEventLoopGroup(numberOfThreads: System.coreCount)
    }

    public func start() async throws {
        let router = self.router
        let bootstrap = ServerBootstrap(group: group)
            .serverChannelOption(ChannelOptions.backlog, value: 256)
            .serverChannelOption(ChannelOptions.socketOption(.so_reuseaddr), value: 1)
            .childChannelInitializer { channel in
                channel.pipeline.configureHTTPServerPipeline().flatMap {
                    channel.pipeline.addHandler(HTTPHandler(router: router))
                }
            }

        let channel = try await bootstrap.bind(host: host, port: port).get()
        print("Server running on http://\(host):\(port)")
        try await channel.closeFuture.get()
    }
}
