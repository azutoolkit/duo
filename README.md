<div align="center">
  <img src="https://raw.githubusercontent.com/azutoolkit/duo/main/duo.png" alt="Duo HTTP/2 Server" width="200"/>

# 🚀 Duo HTTP/2 Server

**A high-performance, fully compliant HTTP/2 server written in Crystal**

[![Crystal CI](https://github.com/azutoolkit/duo/actions/workflows/crystal.yml/badge.svg?branch=main)](https://github.com/azutoolkit/duo/actions/workflows/crystal.yml)
[![Codacy Badge](https://app.codacy.com/project/badge/Grade/3b282e9b818c4efdb7b0ba94b62a262f)](https://www.codacy.com/gh/azutoolkit/duo/dashboard?utm_source=github.com&utm_medium=referral&utm_content=azutoolkit/duo&utm_campaign=Badge_Grade)
[![H2Spec Compliant](https://img.shields.io/badge/H2Spec-146%2F146%20✅-brightgreen)](https://github.com/summerwind/h2spec)
[![Performance](https://img.shields.io/badge/Performance-7K%2B%20req%2Fs-blue)](https://github.com/azutoolkit/duo)

</div>

## 🌟 Why Choose Duo?

Duo is not just another HTTP server—it's a **fully compliant HTTP/2 implementation** that brings the power of modern web protocols to Crystal applications. Built from the ground up with performance, compliance, and developer experience in mind.

### ✨ Key Features

- 🔥 **Full HTTP/2 Compliance** - Passes all 146 H2Spec tests
- ⚡ **High Performance** - 7,000+ requests/second with multiplexing
- 🔒 **TLS by Default** - Built-in SSL/TLS support with ALPN
- 🧩 **Modular Design** - Clean handler-based architecture
- 📦 **Zero Dependencies** - Pure Crystal implementation
- 🌐 **HTTP/1.1 Fallback** - Automatic protocol negotiation
- 🛡️ **Production Ready** - Robust error handling and connection management
- 🎯 **Developer Friendly** - Simple API with powerful features

## 🚀 Quick Start

### Installation

Add this to your application's `shard.yml`:

```yaml
dependencies:
  duo:
    github: azutoolkit/duo
```

Run `shards install`

### Hello World Server

```crystal
require "duo"

class HelloHandler
  include Duo::Server::Handler

  def call(context : Duo::Server::Context)
    context.response << "Hello, HTTP/2 World! 🚀"
    context
  end
end

# Create SSL context (required for HTTP/2)
ssl_context = OpenSSL::SSL::Context::Server.new
ssl_context.certificate_chain = "cert.pem"
ssl_context.private_key = "key.pem"
ssl_context.alpn_protocol = "h2"

# Start the server
server = Duo::Server.new("::", 9876, ssl_context)
server.listen([HelloHandler.new])
```

**That's it!** You now have a fully compliant HTTP/2 server running.

## 📊 HTTP/2 Spec Compliance

Duo achieves **100% compliance** with the HTTP/2 specification (RFC 7540):

### H2Spec Results ✅

```bash
h2spec -h 127.0.0.1 -p 9876 --tls -k

Hypertext Transfer Protocol Version 2 (HTTP/2)
├─ 3. Starting HTTP/2
│  ├─ 3.5. HTTP/2 Connection Preface
│  │  ├─ 1: Sends client connection preface ✅
│  │  ├─ 2: Sends invalid connection preface ✅
│  │  └─ 3: HTTP/2 connection preface ✅
│  └─ (more tests...)
├─ 4. HTTP Frames
├─ 5. Streams and Multiplexing
├─ 6. Frame Definitions
├─ 7. Error Handling
├─ 8. HTTP Semantics
└─ 9. Additional Requirements

**Result: 146/146 tests passed ✅**
```

### Performance Benchmarks 🏆

```bash
h2load -n 100000 -c 100 -m 32 https://127.0.0.1:9876/

finished in 13.91s, 7187.18 req/s, 407.42KB/s
requests: 100000 total, 100000 succeeded
status codes: 100000 2xx
traffic: 5.54MB total, headers savings: 76.92%
```

## 🎯 Real-World Examples

### JSON API Server

```crystal
require "duo"
require "json"

class APIHandler
  include Duo::Server::Handler

  def call(context : Duo::Server::Context)
    request = context.request
    response = context.response

    case request.path
    when "/api/users"
      response.headers["content-type"] = "application/json"
      response << {
        users: [
          {id: 1, name: "Alice", email: "alice@example.com"},
          {id: 2, name: "Bob", email: "bob@example.com"}
        ],
        total: 2
      }.to_json
    when "/api/health"
      response.headers["content-type"] = "application/json"
      response << {status: "healthy", timestamp: Time.utc}.to_json
    else
      call_next(context)
    end

    context
  end
end

class NotFoundHandler
  include Duo::Server::Handler

  def call(context : Duo::Server::Context)
    context.response.status = 404
    context.response.headers["content-type"] = "application/json"
    context.response << {error: "Not Found", path: context.request.path}.to_json
    context
  end
end

# Chain handlers
handlers = [APIHandler.new, NotFoundHandler.new]
server = Duo::Server.new("::", 3000, ssl_context)
server.listen(handlers)
```

### File Server with Caching

```crystal
class StaticFileHandler
  include Duo::Server::Handler

  def call(context : Duo::Server::Context)
    request = context.request
    response = context.response

    # Only handle static file requests
    unless request.path.starts_with?("/static/")
      return call_next(context)
    end

    file_path = request.path.lchop("/static/")
    full_path = File.join("public", file_path)

    if File.exists?(full_path) && File.file?(full_path)
      # Set appropriate content type
      case File.extname(file_path)
      when ".html" then response.headers["content-type"] = "text/html"
      when ".css"  then response.headers["content-type"] = "text/css"
      when ".js"   then response.headers["content-type"] = "application/javascript"
      when ".json" then response.headers["content-type"] = "application/json"
      else              response.headers["content-type"] = "application/octet-stream"
      end

      # Add caching headers
      response.headers["cache-control"] = "public, max-age=3600"
      response.headers["etag"] = %("#{File.info(full_path).modification_time.to_unix}")

      # Stream file content
      File.open(full_path, "r") do |file|
        IO.copy(file, response)
      end
    else
      call_next(context)
    end

    context
  end
end
```

### WebSocket Upgrade (HTTP/1.1)

```crystal
class WebSocketHandler
  include Duo::Server::Handler

  def call(context : Duo::Server::Context)
    request = context.request
    response = context.response

    if request.path == "/ws" && request.headers["upgrade"]? == "websocket"
      # Handle WebSocket upgrade
      response.upgrade("websocket") do |socket|
        # WebSocket communication
        socket << "Hello WebSocket!"
      end
    else
      call_next(context)
    end

    context
  end
end
```

## 🧪 Comprehensive Test Server

Duo includes a full-featured test server showcasing all HTTP/2 capabilities:

```bash
# Build and run the test server
crystal build examples/test_server.cr -o test_server
./test_server

# Test endpoints
curl -k https://localhost:9876/health          # Health check
curl -k https://localhost:9876/api/users       # JSON API
curl -k https://localhost:9876/stream/events   # Server-sent events
curl -k https://localhost:9876/files/html      # Static files
curl -k https://localhost:9876/perf/large      # Performance testing
```

### Available Test Endpoints

| Endpoint    | Purpose              | Features                         |
| ----------- | -------------------- | -------------------------------- |
| `/health`   | Health monitoring    | JSON response with server status |
| `/api/*`    | REST API examples    | JSON data, error handling        |
| `/stream/*` | Real-time streaming  | SSE, progressive responses       |
| `/files/*`  | Static file serving  | HTML, CSS, JS, JSON              |
| `/error/*`  | Error handling demos | HTTP status codes 400-503        |
| `/perf/*`   | Performance testing  | Small to large payloads          |

## 🏗️ Architecture

### Handler Chain Pattern

Duo uses a clean, composable handler architecture:

```crystal
# Handlers are processed in order
handlers = [
  AuthHandler.new,           # Authentication
  CORSHandler.new,          # CORS headers
  LoggingHandler.new,       # Request logging
  StaticFileHandler.new,    # Static files
  APIHandler.new,           # API routes
  NotFoundHandler.new,      # 404 fallback
]

server.listen(handlers)
```

Each handler can:

- ✅ Process the request and return a response
- ✅ Modify the request/response and pass to the next handler
- ✅ Short-circuit the chain by not calling `call_next`

### HTTP/2 Features Implemented

- 🔄 **Multiplexing** - Multiple concurrent requests over single connection
- 📦 **Header Compression** - HPACK compression reduces overhead
- ⚡ **Binary Framing** - Efficient binary protocol vs text-based HTTP/1.1
- 🚀 **Server Push** - Proactive resource delivery (framework level)
- 🌊 **Flow Control** - Per-stream and connection-level flow control
- 🔒 **TLS Required** - Security by default
- 📡 **Stream Prioritization** - Request priority management

## 🚀 HTTP/2 Client

Duo also provides a high-performance HTTP/2 client:

```crystal
require "duo/client"

client = Duo::Client.new("httpbin.org", 443, tls: true)

# Make concurrent requests
10.times do |i|
  headers = HTTP::Headers{
    ":method" => "GET",
    ":path" => "/json",
    "user-agent" => "duo-client/1.0"
  }

  client.request(headers) do |response_headers, body|
    puts "Response #{i}: #{response_headers[":status"]}"
    puts body.gets_to_end
  end
end

client.close
```

### Client Features

- ✅ **Connection Multiplexing** - Reuse connections efficiently
- ✅ **Automatic Flow Control** - Handles backpressure automatically
- ✅ **Stream Management** - Concurrent request handling
- ✅ **Error Recovery** - Robust error handling and reconnection
- ✅ **TLS Support** - Secure connections with ALPN negotiation

## 🛡️ Production Considerations

### SSL/TLS Setup

```crystal
# Production SSL setup
ssl_context = OpenSSL::SSL::Context::Server.new
ssl_context.certificate_chain = "/path/to/cert.pem"
ssl_context.private_key = "/path/to/private.key"

# Security configurations
ssl_context.verify_mode = OpenSSL::SSL::VerifyMode::PEER
ssl_context.alpn_protocol = "h2"

# Cipher configuration
ssl_context.set_ciphers("ECDHE+AESGCM:ECDHE+CHACHA20:DHE+AESGCM:DHE+CHACHA20:!aNULL:!MD5:!DSS")
```

### Performance Tuning

```crystal
# Environment variables for tuning
ENV["DUO_MAX_CONNECTIONS"] = "1000"
ENV["DUO_WORKER_THREADS"] = "8"
ENV["DUO_BUFFER_SIZE"] = "8192"

# Connection pooling
server = Duo::Server.new(host, port, ssl_context)
server.max_connections = 1000
server.keepalive_timeout = 30.seconds
```

### Monitoring and Logging

```crystal
# Configure logging
Log.for("Duo").level = Log::Severity::Info

class MetricsHandler
  include Duo::Server::Handler

  def call(context : Duo::Server::Context)
    start_time = Time.monotonic

    result = call_next(context)

    duration = Time.monotonic - start_time
    status = context.response.status

    Log.info { "#{context.request.method} #{context.request.path} #{status} #{duration.total_milliseconds}ms" }

    result
  end
end
```

## 🆚 Comparison with Other Servers

| Feature                      | Duo        | nginx   | Apache  | Node.js |
| ---------------------------- | ---------- | ------- | ------- | ------- |
| HTTP/2 Full Compliance       | ✅ 146/146 | ✅      | ✅      | ✅      |
| Pure Language Implementation | ✅ Crystal | ❌ C    | ❌ C    | ❌ C++  |
| Memory Safety                | ✅         | ❌      | ❌      | ✅      |
| Built-in TLS                 | ✅         | ✅      | ✅      | ✅      |
| Multiplexing                 | ✅         | ✅      | ✅      | ✅      |
| Zero Dependencies            | ✅         | ❌      | ❌      | ❌      |
| Development Speed            | ⚡ Fast    | 🐌 Slow | 🐌 Slow | ⚡ Fast |

## 🔧 Advanced Usage

### Custom Error Handling

```crystal
class ErrorHandler
  include Duo::Server::Handler

  def call(context : Duo::Server::Context)
    call_next(context)
  rescue ex : Exception
    context.response.status = 500
    context.response.headers["content-type"] = "application/json"
    context.response << {
      error: "Internal Server Error",
      message: ex.message,
      timestamp: Time.utc.to_rfc3339
    }.to_json
    context
  end
end
```

### Middleware Pattern

```crystal
def with_timing(handler)
  ->(context : Duo::Server::Context) {
    start = Time.monotonic
    result = handler.call(context)
    duration = Time.monotonic - start
    context.response.headers["x-response-time"] = "#{duration.total_milliseconds}ms"
    result
  }
end
```

### Rate Limiting

```crystal
class RateLimitHandler
  include Duo::Server::Handler

  def initialize(@limit : Int32 = 100, @window : Time::Span = 1.minute)
    @requests = {} of String => Array(Time)
  end

  def call(context : Duo::Server::Context)
    client_ip = context.request.headers["x-forwarded-for"]? || "unknown"
    now = Time.utc

    @requests[client_ip] ||= [] of Time
    @requests[client_ip] = @requests[client_ip].select { |time| now - time < @window }

    if @requests[client_ip].size >= @limit
      context.response.status = 429
      context.response.headers["retry-after"] = @window.total_seconds.to_i.to_s
      context.response << "Rate limit exceeded"
      return context
    end

    @requests[client_ip] << now
    call_next(context)
  end
end
```

## 🤝 Contributing

We welcome contributions! Duo is designed to be approachable for developers of all levels.

### Getting Started

1. **Fork** the repository
2. **Clone** your fork: `git clone https://github.com/yourusername/duo.git`
3. **Install** dependencies: `shards install`
4. **Run** tests: `crystal spec`
5. **Build** examples: `crystal build examples/test_server.cr`

### Development Workflow

```bash
# Run the full test suite
crystal spec

# Run H2Spec compliance tests
h2spec -h 127.0.0.1 -p 9876 --tls -k

# Performance benchmarking
h2load -n 10000 -c 10 https://127.0.0.1:9876/

# Code formatting
crystal tool format
```

### What We Need

- 📚 **Documentation** - Examples, guides, API docs
- 🧪 **Tests** - More test coverage, edge cases
- 🚀 **Performance** - Optimizations, benchmarks
- 🔧 **Features** - Server push, WebSocket integration
- 🐛 **Bug Reports** - Real-world usage feedback

## 📚 Resources

- 📖 [HTTP/2 RFC 7540](https://tools.ietf.org/html/rfc7540)
- 🧪 [H2Spec Testing Tool](https://github.com/summerwind/h2spec)
- ⚡ [H2Load Benchmarking](https://nghttp2.org/documentation/h2load.1.html)
- 💎 [Crystal Language](https://crystal-lang.org/)
- 🔍 [Examples Directory](./examples/)

## 📜 License

Duo is released under the [MIT License](LICENSE). Feel free to use it in both open source and commercial projects.

---

<div align="center">
  <p><strong>Built with ❤️ by the Crystal community</strong></p>
  <p>
    <a href="https://github.com/azutoolkit/duo/stargazers">⭐ Star us on GitHub</a> •
    <a href="https://github.com/azutoolkit/duo/issues">🐛 Report Bug</a> •
    <a href="https://github.com/azutoolkit/duo/discussions">💬 Discussions</a>
  </p>
</div>
