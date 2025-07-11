# 🚀 Duo HTTP/2 Test Server

A comprehensive test server built with the Duo HTTP/2 framework, demonstrating various HTTP/2 features and providing endpoints for testing different functionality.

## 🌟 Features

- **Full HTTP/2 Support** with TLS encryption
- **Modular Handler Architecture** with proper handler chaining
- **Comprehensive Test Endpoints** for various scenarios
- **Real-time Streaming** demonstrations
- **Error Handling** examples
- **Performance Testing** endpoints
- **Graceful Shutdown** handling

## 🚦 Quick Start

### Prerequisites

- Crystal language (1.16.3+)
- OpenSSL (for certificate generation)

### Running the Server

1. **Build the server:**

   ```bash
   crystal build examples/test_server.cr -o test_server
   ```

2. **Generate SSL certificates (optional):**

   ```bash
   mkdir -p examples/ssl
   openssl req -x509 -newkey rsa:2048 \
     -keyout examples/ssl/localhost-key.pem \
     -out examples/ssl/localhost.pem \
     -days 365 -nodes \
     -subj '/CN=localhost'
   ```

3. **Start the server:**
   ```bash
   ./test_server
   ```

The server will automatically:

- ✅ Try to find existing SSL certificates
- ✅ Fall back to HTTP/1.1 if no certificates found
- ✅ Listen on port 9876 (configurable via `PORT` environment variable)
- ✅ Bind to all interfaces (configurable via `HOST` environment variable)

## 📡 Available Endpoints

### Core Endpoints

| Method | Endpoint  | Description                     |
| ------ | --------- | ------------------------------- |
| `GET`  | `/`       | Echo request information        |
| `GET`  | `/echo`   | Echo request information        |
| `GET`  | `/health` | Health check with server status |

### API Endpoints

| Method | Endpoint      | Description                     |
| ------ | ------------- | ------------------------------- |
| `GET`  | `/api/users`  | JSON API example with user data |
| `GET`  | `/api/status` | Server status and information   |

### Streaming Endpoints

| Method | Endpoint            | Description                         |
| ------ | ------------------- | ----------------------------------- |
| `GET`  | `/stream/countdown` | Real-time countdown demonstration   |
| `GET`  | `/stream/events`    | Server-sent events example          |
| `GET`  | `/stream/slow`      | Slow response with progress updates |

### File Serving Endpoints

| Method | Endpoint      | Description                               |
| ------ | ------------- | ----------------------------------------- |
| `GET`  | `/files/html` | HTML page showcasing HTTP/2 features      |
| `GET`  | `/files/css`  | CSS stylesheet with modern styling        |
| `GET`  | `/files/js`   | JavaScript file with interactive features |
| `GET`  | `/files/json` | JSON response with metadata               |

### Error Testing Endpoints

| Method | Endpoint     | Description                                   |
| ------ | ------------ | --------------------------------------------- |
| `GET`  | `/error/400` | Bad Request error example                     |
| `GET`  | `/error/401` | Unauthorized error with authentication header |
| `GET`  | `/error/403` | Forbidden error example                       |
| `GET`  | `/error/404` | Not Found error example                       |
| `GET`  | `/error/500` | Internal Server Error example                 |
| `GET`  | `/error/503` | Service Unavailable with retry-after header   |

### Performance Testing Endpoints

| Method | Endpoint       | Description                           |
| ------ | -------------- | ------------------------------------- |
| `GET`  | `/perf/small`  | Small response for latency testing    |
| `GET`  | `/perf/medium` | Medium-sized response (~100KB)        |
| `GET`  | `/perf/large`  | Large response (~1MB)                 |
| `GET`  | `/perf/binary` | Binary data response (1KB)            |
| `GET`  | `/perf/json`   | Large JSON response with 1000 objects |

## 🔧 Configuration

### Environment Variables

- `HOST` - Server host (default: `::` - all interfaces)
- `PORT` - Server port (default: `9876`)

### SSL Certificate Paths

The server automatically searches for certificates in the following order:

1. `examples/ssl/localhost.pem` + `examples/ssl/localhost-key.pem`
2. `examples/ssl/example.crt` + `examples/ssl/example.key`
3. `examples/ssl/localhost.crt` + `examples/ssl/localhost.key`
4. `examples/ssl/server.crt` + `examples/ssl/server.key`

If no certificates are found, the server runs in HTTP/1.1 mode without SSL.

## 🧪 Testing Examples

### Basic Health Check

```bash
curl -k https://localhost:9876/health
```

### HTTP/2 Echo Test

```bash
curl -k https://localhost:9876/echo \
  -H "Custom-Header: test-value" \
  -d "test body data"
```

### Streaming Test

```bash
curl -k https://localhost:9876/stream/countdown
```

### Performance Test

```bash
time curl -k -s https://localhost:9876/perf/large > /dev/null
```

### Error Handling Test

```bash
curl -k -i https://localhost:9876/error/404
```

## 🏗️ Architecture

### Handler Chain

The server uses a modular handler architecture where each handler:

1. **Checks** if it should handle the request
2. **Processes** the request if it matches its criteria
3. **Calls** `call_next(context)` to pass unhandled requests to the next handler

**Handler Order:**

1. `EchoHandler` - Handles `/` and `/echo`
2. `HealthHandler` - Handles `/health`
3. `JsonApiHandler` - Handles `/api/*`
4. `StreamingHandler` - Handles `/stream/*`
5. `FileHandler` - Handles `/files/*`
6. `ErrorHandler` - Handles `/error/*`
7. `PerformanceHandler` - Handles `/perf/*`
8. `NotFoundHandler` - Handles everything else (404)

### HTTP/2 Features Demonstrated

- **🔄 Multiplexing** - Multiple concurrent requests over single connection
- **📦 Header Compression** - HPACK compression for reduced overhead
- **⚡ Binary Framing** - Efficient binary protocol vs text-based HTTP/1.1
- **🔒 TLS Required** - Security by default
- **📡 Streaming** - Real-time data transmission
- **🚀 Server Push** - Proactive resource delivery (framework dependent)

## 🛠️ Development

### Adding New Handlers

1. Create a new handler class:

```crystal
class MyHandler
  include Duo::Server::Handler

  def call(context : Duo::Server::Context)
    request = context.request
    response = context.response

    # Check if this handler should process the request
    unless request.path.starts_with?("/my-path/")
      return call_next(context)
    end

    # Process the request
    response.headers["content-type"] = "text/plain"
    response << "My response"

    context
  end
end
```

2. Add it to the handler chain in the correct position.

### Error Handling Best Practices

- Always set appropriate HTTP status codes
- Include helpful error messages
- Add timestamps for debugging
- Use consistent JSON error format for APIs

## 🔍 Debugging

### Logs and Output

The server outputs detailed startup information and can be run with output redirection:

```bash
./test_server > server.log 2>&1 &
```

### Common Issues

1. **SSL Certificate Errors**: Generate certificates as shown in Quick Start
2. **Port Already in Use**: Change the `PORT` environment variable
3. **Permission Denied**: Use ports > 1024 or run with appropriate permissions

## 📊 HTTP/2 Compliance

This test server is built on the Duo framework, which has been tested for full HTTP/2 RFC 7540 compliance using H2Spec:

```bash
h2spec -h 127.0.0.1 -p 9876 --tls -k
```

**Result: All 146 H2Spec tests pass** ✅

## 🤝 Contributing

To extend the test server:

1. Follow the existing handler pattern
2. Add comprehensive error handling
3. Include proper Content-Type headers
4. Update this README with new endpoints
5. Test with various HTTP/2 clients

## 📄 License

This test server is part of the Duo HTTP/2 framework and follows the same license terms.
