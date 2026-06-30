import Foundation
import NIO
import NIOHTTP1
import NIOFoundationCompat

struct APIConfig: Codable {
    let title: String
    let method: String
    let path: String
    let description: String
    var statusCode: Int
    var responseBody: String

    var statusLabel: String {
        let status = HTTPResponseStatus(statusCode: statusCode)
        return "\(statusCode) \(status.reasonPhrase)"
    }
}

private struct StatusUpdateRequest: Codable {
    let path: String
    let statusCode: Int
}

final class MockServer {
    private let group: EventLoopGroup
    private let configQueue = DispatchQueue(label: "MockServer.config")
    private var apiConfigs: [APIConfig]
    private var channel: Channel?
    private let port = 8080

    init() {
        group = MultiThreadedEventLoopGroup(numberOfThreads: 1)
        apiConfigs = [
            APIConfig(
                title: "GET /Products API",
                method: "GET",
                path: "/api/products",
                description: "Editable product response used by the mobile app.",
                statusCode: 200,
                responseBody: try! String(data: JSONEncoder().encode(BookData.sampleBooks), encoding: .utf8) ?? "[]"
            )
        ]
    }

    func currentConfigs() -> [APIConfig] {
        configQueue.sync { apiConfigs }
    }

    func config(for path: String) -> APIConfig? {
        configQueue.sync {
            apiConfigs.first(where: { $0.path == path })
        }
    }

    func updateStatus(for path: String, to statusCode: Int) {
        configQueue.sync {
            if let index = apiConfigs.firstIndex(where: { $0.path == path }) {
                apiConfigs[index].statusCode = statusCode
            }
        }
    }

    func updateResponseBody(for path: String, to responseBody: String) {
        configQueue.sync {
            if let index = apiConfigs.firstIndex(where: { $0.path == path }) {
                apiConfigs[index].responseBody = responseBody
            }
        }
    }

    func start() {
        guard channel == nil else { return }

        let bootstrap = ServerBootstrap(group: group)
            .serverChannelOption(ChannelOptions.backlog, value: 256)
            .serverChannelOption(ChannelOptions.socketOption(.so_reuseaddr), value: 1)
            .childChannelInitializer { channel in
                channel.pipeline.configureHTTPServerPipeline(withErrorHandling: true).flatMap {
                    channel.pipeline.addHandler(HTTPHandler(server: self))
                }
            }
            .childChannelOption(ChannelOptions.socketOption(.so_reuseaddr), value: 1)

        do {
            channel = try bootstrap.bind(host: "0.0.0.0", port: port).wait()
            print("Mock server started at http://127.0.0.1:\(port) and http://localhost:\(port)")
        } catch {
            print("Mock server failed to start: \(error)")
        }
    }

    func stop() {
        do {
            try channel?.close().wait()
            try group.syncShutdownGracefully()
        } catch {
            print("Mock server stop failed: \(error)")
        }
    }
}

private final class HTTPHandler: ChannelInboundHandler {
    typealias InboundIn = HTTPServerRequestPart
    typealias OutboundOut = HTTPServerResponsePart

    private let server: MockServer
    private var requestHead: HTTPRequestHead?
    private var bodyBuffer: ByteBuffer?

    init(server: MockServer) {
        self.server = server
    }

    func channelRead(context: ChannelHandlerContext, data: NIOAny) {
        let part = self.unwrapInboundIn(data)
        switch part {
        case .head(let head):
            requestHead = head
            bodyBuffer = context.channel.allocator.buffer(capacity: 0)
        case .body(var buffer):
            bodyBuffer?.writeBuffer(&buffer)
        case .end:
            if let request = requestHead {
                respond(to: request, context: context)
            }
            requestHead = nil
            bodyBuffer = nil
        }
    }

    func errorCaught(context: ChannelHandlerContext, error: Error) {
        print("Mock server error:", error)
        context.close(promise: nil)
    }

    private func respond(to request: HTTPRequestHead, context: ChannelHandlerContext) {
        let path = request.uri.components(separatedBy: "?").first ?? request.uri
        switch path {
        case "/", "/index.html":
            respondRedirectToProducts(context: context, request: request)
        case "/products":
            respondWithProducts(context: context, request: request)
        case "/update-status":
            respondUpdateStatus(context: context, request: request)
        case "/update-json":
            respondUpdateJSON(context: context, request: request)
        case "/config":
            respondConfig(context: context, request: request)
        case "/api/products":
            respondWithAPI(context: context, request: request, path: path)
        default:
            respondNotFound(context: context, request: request)
        }
    }

    private func respondRedirectToProducts(context: ChannelHandlerContext, request: HTTPRequestHead) {
        var headers = HTTPHeaders()
        headers.add(name: "location", value: "/products")
        let responseHead = HTTPResponseHead(version: request.version, status: .found, headers: headers)
        context.write(self.wrapOutboundOut(.head(responseHead)), promise: nil)
        context.writeAndFlush(self.wrapOutboundOut(.end(nil)), promise: nil)
    }

    private func respondWithProducts(context: ChannelHandlerContext, request: HTTPRequestHead) {
        if let acceptHeader = request.headers["accept"].first, acceptHeader.contains("text/html") {
            let htmlString = renderProductsHTML()
            sendResponse(context: context, request: request, status: .ok, contentType: "text/html; charset=utf-8", body: htmlString)
            return
        }

        if let config = server.config(for: "/api/products") {
            sendResponse(context: context, request: request, status: .ok, contentType: "application/json; charset=utf-8", body: config.responseBody)
        } else {
            let body = "[]"
            sendResponse(context: context, request: request, status: .ok, contentType: "application/json; charset=utf-8", body: body)
        }
    }

    private func respondUpdateStatus(context: ChannelHandlerContext, request: HTTPRequestHead) {
        guard request.method == .POST, let buffer = bodyBuffer, let body = buffer.getString(at: buffer.readerIndex, length: buffer.readableBytes) else {
            sendResponse(context: context, request: request, status: .badRequest, contentType: "application/json; charset=utf-8", body: "{\"error\": \"Missing request body\"}")
            return
        }

        do {
            let requestData = try JSONDecoder().decode(StatusUpdateRequest.self, from: Data(body.utf8))
            guard HTTPResponseStatus(statusCode: requestData.statusCode).reasonPhrase != "" else {
                sendResponse(context: context, request: request, status: .badRequest, contentType: "application/json; charset=utf-8", body: "{\"error\": \"Invalid status code\"}")
                return
            }
            server.updateStatus(for: requestData.path, to: requestData.statusCode)
            sendResponse(context: context, request: request, status: .ok, contentType: "application/json; charset=utf-8", body: "{\"success\": true}")
        } catch {
            sendResponse(context: context, request: request, status: .badRequest, contentType: "application/json; charset=utf-8", body: "{\"error\": \"Invalid JSON\"}")
        }
    }

    private func respondUpdateJSON(context: ChannelHandlerContext, request: HTTPRequestHead) {
        struct ResponseUpdateRequest: Codable {
            let path: String
            let responseBody: String
        }

        guard request.method == .POST, let buffer = bodyBuffer, let body = buffer.getString(at: buffer.readerIndex, length: buffer.readableBytes) else {
            sendResponse(context: context, request: request, status: .badRequest, contentType: "application/json; charset=utf-8", body: "{\"error\": \"Missing request body\"}")
            return
        }

        do {
            let requestData = try JSONDecoder().decode(ResponseUpdateRequest.self, from: Data(body.utf8))
            server.updateResponseBody(for: requestData.path, to: requestData.responseBody)
            sendResponse(context: context, request: request, status: .ok, contentType: "application/json; charset=utf-8", body: "{\"success\": true}")
        } catch {
            sendResponse(context: context, request: request, status: .badRequest, contentType: "application/json; charset=utf-8", body: "{\"error\": \"Invalid JSON\"}")
        }
    }

    private func respondConfig(context: ChannelHandlerContext, request: HTTPRequestHead) {
        guard request.method == .GET, let path = queryValue(named: "path", from: request.uri) else {
            sendResponse(context: context, request: request, status: .badRequest, contentType: "application/json; charset=utf-8", body: "{\"error\": \"Missing path parameter\"}")
            return
        }

        guard let config = server.config(for: path) else {
            respondNotFound(context: context, request: request)
            return
        }

        let payload = ["path": config.path, "statusCode": config.statusCode, "responseBody": config.responseBody] as [String: Any]
        if let bodyData = try? JSONSerialization.data(withJSONObject: payload, options: []), let bodyString = String(data: bodyData, encoding: .utf8) {
            sendResponse(context: context, request: request, status: .ok, contentType: "application/json; charset=utf-8", body: bodyString)
        } else {
            sendResponse(context: context, request: request, status: .internalServerError, contentType: "application/json; charset=utf-8", body: "{\"error\": \"Unable to encode config\"}")
        }
    }

    private func queryValue(named name: String, from uri: String) -> String? {
        guard let components = URLComponents(string: "http://localhost\(uri)") else { return nil }
        return components.queryItems?.first(where: { $0.name == name })?.value
    }

    private func respondWithAPI(context: ChannelHandlerContext, request: HTTPRequestHead, path: String) {
        guard let config = server.config(for: path) else {
            respondNotFound(context: context, request: request)
            return
        }

        let status = HTTPResponseStatus(statusCode: config.statusCode)
        sendResponse(context: context, request: request, status: status, contentType: "application/json; charset=utf-8", body: config.responseBody)
    }

    private func renderProductsHTML() -> String {
        let apiRows = server.currentConfigs()

        let items = apiRows.map { row in
            let statusOptions = [200, 201, 400, 401, 403, 404, 429, 500, 502, 503].map { code in
                let selected = code == row.statusCode ? " selected" : ""
                let reason = HTTPResponseStatus(statusCode: code).reasonPhrase
                return "<option value=\"\(code)\"\(selected)>\(code) \(reason)</option>"
            }.joined(separator: "\n")

            return """
            <div class=\"panel-item\">
                <div class=\"panel-item-row\">
                    <div class=\"row-left\">
                        <span class=\"api-name\">\(row.title)</span>
                        <span class=\"method\">\(row.method)</span>
                        <span class=\"path\">\(row.path)</span>
                    </div>
                    <div class=\"row-right\">
                        <select class=\"status-select\" data-path=\"\(row.path)\">\n\(statusOptions)\n</select>
                        <button class=\"edit-button\" data-path=\"\(row.path)\">Edit JSON</button>
                    </div>
                </div>
            </div>
            """
        }.joined(separator: "\n")

        return """
        <!DOCTYPE html>
        <html lang=\"en\">
        <head>
            <meta charset=\"UTF-8\" />
            <meta name=\"viewport\" content=\"width=device-width, initial-scale=1.0\" />
            <title>SwiftNIO Mock Server Control Panel</title>
            <style>
                :root { color-scheme: light; font-family: Inter, system-ui, -apple-system, BlinkMacSystemFont, sans-serif; background: #0b1222; color: #f8fafc; }
                body { margin: 0; min-height: 100vh; background: linear-gradient(180deg, #090c14 0%, #0f172a 100%); }
                .page { max-width: 1040px; margin: 0 auto; padding: 32px 24px 48px; }
                .hero { text-align: center; margin-bottom: 32px; }
                .hero h1 { margin: 0; font-size: clamp(2rem, 4vw, 3.5rem); letter-spacing: -0.04em; }
                .hero p { margin: 12px auto 0; max-width: 720px; color: #cbd5e1; }
                .panel { background: rgba(15, 23, 42, 0.92); border: 1px solid rgba(148, 163, 184, 0.14); border-radius: 24px; padding: 20px; box-shadow: 0 30px 60px rgba(15, 23, 42, 0.35); }
                .panel-item { border-bottom: 1px solid rgba(148, 163, 184, 0.12); padding: 18px 0; }
                .panel-item:last-child { border-bottom: none; }
                .panel-item-row { display: flex; flex-wrap: wrap; align-items: center; justify-content: space-between; gap: 12px; }
                .row-left { display: flex; flex-wrap: wrap; align-items: center; gap: 12px; min-width: 0; }
                .api-name { font-weight: 700; font-size: 1rem; color: #e2e8f0; white-space: nowrap; }
                .method { background: #1e293b; color: #a5b4fc; font-size: 0.85rem; padding: 6px 10px; border-radius: 999px; }
                .path { color: #94a3b8; font-size: 0.95rem; }
                .row-right { display: flex; flex-wrap: wrap; align-items: center; gap: 10px; justify-content: flex-end; }
                .status-select { min-width: 220px; padding: 10px 12px; border-radius: 12px; border: 1px solid rgba(148, 163, 184, 0.18); background: #0f172a; color: #f8fafc; font-size: 0.95rem; }
                .edit-button { appearance: none; border: none; padding: 11px 18px; border-radius: 12px; font-weight: 700; background: #f59e0b; color: #0f172a; cursor: pointer; transition: transform 0.15s ease, background 0.15s ease; }
                .edit-button:hover { transform: translateY(-1px); background: #eab308; }
                .button-row { margin-top: 28px; display: flex; flex-wrap: wrap; gap: 12px; justify-content: center; }
                .button { display: inline-flex; align-items: center; justify-content: center; min-width: 160px; gap: 8px; padding: 14px 18px; border-radius: 999px; border: 1px solid rgba(148, 163, 184, 0.16); background: #1e293b; color: #e2e8f0; text-decoration: none; font-weight: 600; transition: transform 0.2s ease, background 0.2s ease; }
                .button:hover { transform: translateY(-1px); background: #334155; }
                .toast { position: fixed; left: 50%; top: 24px; transform: translateX(-50%); min-width: 280px; padding: 14px 18px; border-radius: 14px; background: rgba(15, 23, 42, 0.95); color: #f8fafc; border: 1px solid rgba(148, 163, 184, 0.2); display: none; align-items: center; justify-content: space-between; gap: 12px; }
                .toast.show { display: flex; }
                .modal-overlay { position: fixed; inset: 0; background: rgba(15, 23, 42, 0.72); display: flex; align-items: center; justify-content: center; padding: 24px; z-index: 20; }
                .modal-overlay[hidden] { display: none !important; }
                .modal { background: #0f172a; border: 1px solid rgba(148, 163, 184, 0.18); border-radius: 24px; max-width: 760px; width: 100%; padding: 24px; box-shadow: 0 30px 60px rgba(0, 0, 0, 0.4); }
                .modal-header { display: flex; align-items: flex-start; justify-content: space-between; gap: 16px; margin-bottom: 18px; }
                .modal-title { font-size: 1.15rem; font-weight: 700; color: #f8fafc; }
                .modal-description { margin-top: 6px; color: #94a3b8; font-size: 0.95rem; }
                .modal-close { appearance: none; border: none; background: transparent; color: #cbd5e1; font-size: 1.25rem; cursor: pointer; }
                #json-editor { width: 100%; min-height: 320px; border: 1px solid rgba(148, 163, 184, 0.18); border-radius: 16px; background: #020617; color: #e2e8f0; padding: 16px; font-family: ui-monospace, SFMono-Regular, Menlo, Monaco, Consolas, monospace; font-size: 0.95rem; resize: vertical; }
                .modal-actions { margin-top: 18px; display: flex; flex-wrap: wrap; gap: 12px; justify-content: flex-end; }
            </style>
        </head>
        <body>
            <div class=\"page\">
                <div class=\"hero\">
                    <h1>SwiftNIO Mock Server Control Panel</h1>
                    <p>JSON editor for your mobile app testing. Change response status codes and preview endpoints instantly.</p>
                </div>
                <div class=\"panel\">
                    \(items)
                </div>
                <div class=\"button-row\">
                    <a class=\"button\" href=\"/products\">Refresh Panel</a>

                </div>
            </div>
            <div class="modal-overlay" id="modalOverlay" hidden>
                <div class="modal">
                    <div class="modal-header">
                        <div>
                            <div class="modal-title">Edit JSON for <span id="editor-path"></span></div>
                            <div class="modal-description">Update the response body returned by this endpoint.</div>
                        </div>
                        <button class="modal-close" id="modalClose">✕</button>
                    </div>
                    <textarea id="json-editor" spellcheck="false"></textarea>
                    <div class="modal-actions">
                        <button type="button" class="button" id="cancelEdit">Cancel</button>
                        <button type="button" class="button" id="saveJson">Save JSON</button>
                    </div>
                </div>
            </div>
            <div class="toast" id="toast">Status updated successfully</div>
            <script>
                function initMockServerControls() {
                    const toast = document.getElementById('toast');
                    const modalOverlay = document.getElementById('modalOverlay');
                    const editorPath = document.getElementById('editor-path');
                    const jsonEditor = document.getElementById('json-editor');
                    const saveJson = document.getElementById('saveJson');
                    const cancelEdit = document.getElementById('cancelEdit');
                    const modalClose = document.getElementById('modalClose');

                    function showToast(message) {
                        toast.textContent = message;
                        toast.classList.add('show');
                        setTimeout(() => toast.classList.remove('show'), 2400);
                    }

                    function openEditor(path) {
                        editorPath.textContent = path;
                        jsonEditor.value = '';
                        modalOverlay.hidden = false;
                        fetch(`/config?path=${encodeURIComponent(path)}`)
                            .then(response => {
                                if (!response.ok) throw new Error('Failed to load config');
                                return response.json();
                            })
                            .then(config => {
                                jsonEditor.value = config.responseBody || '';
                            })
                            .catch(() => {
                                showToast('Failed to load JSON config');
                                modalOverlay.hidden = true;
                            });
                    }

                    function closeEditor() {
                        modalOverlay.hidden = true;
                    }

                    document.querySelectorAll('.status-select').forEach(select => {
                        select.addEventListener('change', async event => {
                            const path = event.target.dataset.path;
                            const statusCode = parseInt(event.target.value, 10);
                            try {
                                const response = await fetch('/update-status', {
                                    method: 'POST',
                                    headers: { 'Content-Type': 'application/json' },
                                    body: JSON.stringify({ path, statusCode })
                                });
                                if (response.ok) {
                                    showToast(`Status updated for ${path} to ${statusCode}`);
                                } else {
                                    showToast('Unable to update status');
                                }
                            } catch (error) {
                                showToast('Network error updating status');
                            }
                        });
                    });

                    document.querySelectorAll('.edit-button').forEach(button => {
                        button.addEventListener('click', () => {
                            openEditor(button.dataset.path);
                        });
                    });

                    saveJson.addEventListener('click', async () => {
                        const path = editorPath.textContent;
                        try {
                            JSON.parse(jsonEditor.value);
                        } catch (parseError) {
                            showToast('Invalid JSON. Please fix syntax before saving.');
                            return;
                        }

                        try {
                            const response = await fetch('/update-json', {
                                method: 'POST',
                                headers: { 'Content-Type': 'application/json' },
                                body: JSON.stringify({ path, responseBody: jsonEditor.value })
                            });
                            if (response.ok) {
                                showToast(`JSON updated for ${path}`);
                                closeEditor();
                            } else {
                                showToast('Unable to save JSON');
                            }
                        } catch (error) {
                            showToast('Network error saving JSON');
                        }
                    });

                    cancelEdit.addEventListener('click', closeEditor);
                    modalClose.addEventListener('click', closeEditor);
                    modalOverlay.addEventListener('click', event => {
                        if (event.target === modalOverlay) {
                            closeEditor();
                        }
                    });
                }

                if (document.readyState === 'loading') {
                    document.addEventListener('DOMContentLoaded', initMockServerControls);
                } else {
                    initMockServerControls();
                }
            </script>
        </body>
        </html>
        """
    }

    private func respondNotFound(context: ChannelHandlerContext, request: HTTPRequestHead) {
        sendResponse(context: context, request: request, status: .notFound, contentType: "text/plain; charset=utf-8", body: "Not found")
    }

    private func sendResponse(context: ChannelHandlerContext, request: HTTPRequestHead, status: HTTPResponseStatus, contentType: String, body: String) {
        var buffer = context.channel.allocator.buffer(capacity: body.utf8.count)
        buffer.writeString(body)
        var headers = HTTPHeaders()
        headers.add(name: "content-type", value: contentType)
        headers.add(name: "content-length", value: "\(buffer.readableBytes)")
        if request.version == .http1_1 {
            headers.add(name: "connection", value: "close")
        }
        let responseHead = HTTPResponseHead(version: request.version, status: status, headers: headers)

        context.write(self.wrapOutboundOut(.head(responseHead)), promise: nil)
        context.write(self.wrapOutboundOut(.body(.byteBuffer(buffer))), promise: nil)
        context.writeAndFlush(self.wrapOutboundOut(.end(nil)), promise: nil)
    }
}
