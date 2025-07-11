# HTTP/2 Test Server Examples

This directory contains comprehensive examples demonstrating HTTP/2 functionality using the Duo framework.

## Files

- `server.cr` - Basic HTTP/2 server example
- `test_server.cr` - Comprehensive HTTP/2 test server with multiple endpoints
- `test_client.cr` - Test client demonstrating various HTTP/2 features
- `client.cr` - Basic HTTP/2 client example

## Quick Start

### 1. Start the Test Server

```bash
# From the project root directory
crystal run examples/test_server.cr
```

The server will start on `https://localhost:4000` with SSL/TLS enabled.

### 2. Run the Test Client

```bash
# In another terminal
crystal run examples/test_client.cr
```

## Test Server Endpoints

The test server provides various endpoints to demonstrate HTTP/2 features:

### Basic Endpoints

- `GET /echo` - Echo request information (headers, method, path, etc.)
- `GET /` - Default 404 with available endpoints list

### JSON API Endpoints

- `GET /api/users` - Returns a JSON array of users
- `GET /api/status` - Returns server status information

### Streaming Endpoints

- `GET /stream/countdown` - Streaming countdown (10 to 1)
- `GET /stream/events` - Server-sent events stream

### File Serving Endpoints

- `GET /files/html` - HTML page demonstrating HTTP/2 features
- `GET /files/css` - CSS stylesheet
- `GET /files/js` - JavaScript file

### Error Testing Endpoints

- `GET /error/400` - Bad Request (400)
- `GET /error/401` - Unauthorized (401)
- `GET /error/403` - Forbidden (403)
- `GET /error/404` - Not Found (404)
- `GET /error/500` - Internal Server Error (500)
- `GET /error/503` - Service Unavailable (503)

### Performance Testing Endpoints

- `GET /perf/small` - Small response (~30 bytes)
- `GET /perf/medium` - Medium response (~1.5KB)
- `GET /perf/large` - Large response (~15KB)
- `GET /perf/binary` - Binary data (1KB random bytes)

## HTTP/2 Features Demonstrated

### 1. Multiplexing

Multiple requests can be processed concurrently over a single connection. The test client demonstrates this with concurrent requests.

### 2. Header Compression

Headers are compressed using HPACK to reduce overhead. You can observe this by examining the network traffic.

### 3. Streaming Responses

The server supports streaming responses, demonstrated by the countdown and server-sent events endpoints.

### 4. Different Content Types

The server handles various content types including:

- `text/plain`
- `application/json`
- `text/html`
- `text/css`
- `application/javascript`
- `text/event-stream`
- `application/octet-stream`

### 5. Error Handling

Comprehensive error handling with proper HTTP status codes and JSON error responses.

## Testing with curl

You can also test the server using curl with HTTP/2 support:

```bash
# Test echo endpoint
curl -k --http2 https://localhost:4000/echo

# Test JSON API
curl -k --http2 https://localhost:4000/api/users

# Test streaming
curl -k --http2 https://localhost:4000/stream/countdown

# Test error endpoints
curl -k --http2 https://localhost:4000/error/404
```

## SSL Certificate

The server uses a self-signed certificate located in `examples/ssl/`. For production use, replace these with proper certificates.

## Handler Chain

The test server uses a chain of handlers in this order:

1. `EchoHandler` - Handles `/echo`
2. `JsonApiHandler` - Handles `/api/*`
3. `StreamingHandler` - Handles `/stream/*`
4. `FileHandler` - Handles `/files/*`
5. `ErrorHandler` - Handles `/error/*`
6. `PerformanceHandler` - Handles `/perf/*`
7. `NotFoundHandler` - Handles everything else (404)

Each handler can either:

- Process the request and return a response
- Call `call_next(context)` to pass control to the next handler
- Return the context to end the chain

## Customization

You can easily extend the test server by:

1. Adding new handler classes that include `Duo::Server::Handler`
2. Implementing the `call(context : Duo::Server::Context)` method
3. Adding the handler to the handlers array in the correct order

Example:

```crystal
class CustomHandler
  include Duo::Server::Handler

  def call(context : Duo::Server::Context)
    request = context.request
    response = context.response

    if request.path == "/custom"
      response.headers["content-type"] = "text/plain"
      response << "Custom endpoint response"
    else
      call_next(context)
    end

    context
  end
end
```

## Performance Considerations

- The server uses fibers for concurrent request handling
- HTTP/2 multiplexing allows multiple requests over a single connection
- Streaming responses demonstrate real-time data delivery
- Binary data endpoints test raw data transfer performance

## Troubleshooting

1. **SSL Certificate Errors**: The server uses a self-signed certificate. Use `-k` flag with curl or ignore certificate warnings in browsers.

2. **Port Already in Use**: Change the port by setting the `PORT` environment variable:

   ```bash
   PORT=8080 crystal run examples/test_server.cr
   ```

3. **Connection Refused**: Ensure the server is running and the port is accessible.

4. **HTTP/2 Not Working**: Verify that your client supports HTTP/2 and that ALPN is properly configured.

5. **SSL Shutdown Errors**: The server now handles SSL shutdown errors gracefully. These errors are common when clients disconnect abruptly and are now logged at debug level instead of causing crashes.
