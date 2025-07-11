require "../src/duo"
require "json"

# HTTP/2 Test Server demonstrating various features and capabilities
# This server showcases different types of handlers and HTTP/2 specific functionality

# Basic echo handler that returns request information
class EchoHandler
  include Duo::Server::Handler

  def call(context : Duo::Server::Context)
    request = context.request
    response = context.response

    # Only handle echo-related paths
    unless request.path == "/" || request.path == "/echo"
      return call_next(context)
    end

    response.headers["content-type"] = "text/plain"
    response.headers["server"] = "duo-http2-test-server"

    response << "HTTP/2 Echo Response\n"
    response << "==================\n"
    response << "Method: #{request.method}\n"
    response << "Path: #{request.path}\n"
    response << "Version: #{request.version}\n"
    response << "Authority: #{request.authority}\n"
    response << "Scheme: #{request.scheme}\n"
    response << "\nHeaders:\n"
    request.headers.each do |name, value|
      response << "  #{name}: #{value}\n"
    end

    if request.body?
      response << "\nBody:\n"
      response << request.body.gets_to_end
    end

    context
  end
end

# JSON API handler demonstrating structured responses
class JsonApiHandler
  include Duo::Server::Handler

  def call(context : Duo::Server::Context)
    request = context.request
    response = context.response

    # Only handle API paths
    unless request.path.starts_with?("/api/")
      return call_next(context)
    end

    response.headers["content-type"] = "application/json"
    response.headers["server"] = "duo-http2-test-server"

    case request.path
    when "/api/users"
      response.status = 200
      response << JSON.build do |json|
        json.object do
          json.field "users" do
            json.array do
              json.object do
                json.field "id", 1
                json.field "name", "Alice"
                json.field "email", "alice@example.com"
              end
              json.object do
                json.field "id", 2
                json.field "name", "Bob"
                json.field "email", "bob@example.com"
              end
              json.object do
                json.field "id", 3
                json.field "name", "Charlie"
                json.field "email", "charlie@example.com"
              end
            end
          end
          json.field "total", 3
          json.field "timestamp", Time.utc.to_rfc3339
        end
      end
    when "/api/status"
      response.status = 200
      response << JSON.build do |json|
        json.object do
          json.field "status", "healthy"
          json.field "uptime", Time.utc.to_unix
          json.field "version", "1.0.0"
          json.field "protocol", "HTTP/2"
          json.field "time", Time.utc.to_rfc3339
        end
      end
    else
      response.status = 404
      response << JSON.build do |json|
        json.object do
          json.field "error", "Not Found"
          json.field "path", request.path
          json.field "message", "API endpoint not found"
        end
      end
    end

    context
  end
end

# Streaming handler that demonstrates HTTP/2 streaming capabilities
class StreamingHandler
  include Duo::Server::Handler

  def call(context : Duo::Server::Context)
    request = context.request
    response = context.response

    # Only handle streaming paths
    unless request.path.starts_with?("/stream/")
      return call_next(context)
    end

    response.headers["content-type"] = "text/plain"
    response.headers["server"] = "duo-http2-test-server"
    response.headers["cache-control"] = "no-cache"

    case request.path
    when "/stream/countdown"
      response.status = 200
      10.downto(1) do |i|
        response << "Countdown: #{i}\n"
        response.flush
        sleep 0.5.seconds
      end
      response << "Blast off! 🚀\n"
    when "/stream/events"
      response.status = 200
      response.headers["content-type"] = "text/event-stream"
      response.headers["cache-control"] = "no-cache"

      5.times do |i|
        response << "data: Event #{i + 1} at #{Time.utc.to_rfc3339}\n\n"
        response.flush
        sleep 1.seconds
      end
      response << "data: [DONE]\n\n"
    when "/stream/slow"
      response.status = 200
      response << "Starting slow response...\n"
      response.flush

      5.times do |i|
        sleep 1.seconds
        response << "Progress: #{i + 1}/5\n"
        response.flush
      end
      response << "Completed!\n"
    else
      response.status = 404
      response << "Streaming endpoint not found: #{request.path}\n"
    end

    context
  end
end

# File serving handler with different content types
class FileHandler
  include Duo::Server::Handler

  def call(context : Duo::Server::Context)
    request = context.request
    response = context.response

    # Only handle file paths
    unless request.path.starts_with?("/files/")
      return call_next(context)
    end

    case request.path
    when "/files/html"
      response.headers["content-type"] = "text/html; charset=utf-8"
      response.status = 200
      response << "<!DOCTYPE html>\n"
      response << "<html>\n"
      response << "<head>\n"
      response << "  <title>HTTP/2 Test Page</title>\n"
      response << "  <meta charset=\"utf-8\">\n"
      response << "  <style>\n"
      response << "    body { font-family: Arial, sans-serif; margin: 40px; background: #f5f5f5; }\n"
      response << "    .container { max-width: 800px; margin: 0 auto; background: white; padding: 20px; border-radius: 8px; box-shadow: 0 2px 10px rgba(0,0,0,0.1); }\n"
      response << "    .feature { background: #e3f2fd; padding: 20px; margin: 10px 0; border-radius: 5px; border-left: 4px solid #2196f3; }\n"
      response << "    h1 { color: #1976d2; }\n"
      response << "    h3 { color: #1565c0; margin-top: 0; }\n"
      response << "    .status { background: #e8f5e8; color: #2e7d32; padding: 10px; border-radius: 4px; margin: 20px 0; }\n"
      response << "  </style>\n"
      response << "</head>\n"
      response << "<body>\n"
      response << "  <div class=\"container\">\n"
      response << "    <h1>🚀 HTTP/2 Test Server</h1>\n"
      response << "    <div class=\"status\">✅ This page is served over HTTP/2 with TLS encryption</div>\n"
      response << "    <p>This page demonstrates the following HTTP/2 features:</p>\n"
      response << "    <div class=\"feature\">\n"
      response << "      <h3>🔄 Multiplexing</h3>\n"
      response << "      <p>Multiple requests can be processed concurrently over a single connection, improving performance.</p>\n"
      response << "    </div>\n"
      response << "    <div class=\"feature\">\n"
      response << "      <h3>📦 Header Compression</h3>\n"
      response << "      <p>Headers are compressed using HPACK to reduce overhead and improve efficiency.</p>\n"
      response << "    </div>\n"
      response << "    <div class=\"feature\">\n"
      response << "      <h3>⚡ Server Push</h3>\n"
      response << "      <p>Resources can be pushed proactively to improve perceived performance.</p>\n"
      response << "    </div>\n"
      response << "    <div class=\"feature\">\n"
      response << "      <h3>🔒 Secure by Default</h3>\n"
      response << "      <p>HTTP/2 requires TLS encryption, ensuring secure communication.</p>\n"
      response << "    </div>\n"
      response << "  </div>\n"
      response << "</body>\n"
      response << "</html>\n"
    when "/files/css"
      response.headers["content-type"] = "text/css; charset=utf-8"
      response.status = 200
      response << "/* HTTP/2 Test Server Stylesheet */\n"
      response << "body {\n"
      response << "  font-family: 'Segoe UI', Tahoma, Geneva, Verdana, sans-serif;\n"
      response << "  line-height: 1.6;\n"
      response << "  color: #333;\n"
      response << "  margin: 0;\n"
      response << "  padding: 0;\n"
      response << "}\n"
      response << ".header {\n"
      response << "  background: linear-gradient(135deg, #667eea 0%, #764ba2 100%);\n"
      response << "  color: white;\n"
      response << "  padding: 2rem;\n"
      response << "  text-align: center;\n"
      response << "  box-shadow: 0 2px 10px rgba(0,0,0,0.1);\n"
      response << "}\n"
      response << ".content {\n"
      response << "  padding: 2rem;\n"
      response << "  max-width: 1200px;\n"
      response << "  margin: 0 auto;\n"
      response << "}\n"
      response << ".card {\n"
      response << "  background: white;\n"
      response << "  border-radius: 8px;\n"
      response << "  padding: 1.5rem;\n"
      response << "  margin: 1rem 0;\n"
      response << "  box-shadow: 0 2px 8px rgba(0,0,0,0.1);\n"
      response << "}\n"
    when "/files/js"
      response.headers["content-type"] = "application/javascript; charset=utf-8"
      response.status = 200
      response << "// HTTP/2 Test Server JavaScript\n"
      response << "console.log('🚀 HTTP/2 Test Server JavaScript loaded successfully');\n"
      response << "\n"
      response << "document.addEventListener('DOMContentLoaded', function() {\n"
      response << "  console.log('📄 DOM loaded via HTTP/2');\n"
      response << "  \n"
      response << "  // Add some interactive features\n"
      response << "  const features = document.querySelectorAll('.feature');\n"
      response << "  features.forEach(feature => {\n"
      response << "    feature.addEventListener('click', function() {\n"
      response << "      console.log('🖱️ Feature clicked:', this.querySelector('h3').textContent);\n"
      response << "    });\n"
      response << "  });\n"
      response << "  \n"
      response << "  // Display current time\n"
      response << "  const now = new Date();\n"
      response << "  console.log('⏰ Page loaded at:', now.toISOString());\n"
      response << "});\n"
    when "/files/json"
      response.headers["content-type"] = "application/json; charset=utf-8"
      response.status = 200
      response << JSON.build do |json|
        json.object do
          json.field "server", "duo-http2-test-server"
          json.field "protocol", "HTTP/2"
          json.field "endpoint", request.path
          json.field "timestamp", Time.utc.to_rfc3339
          json.field "features" do
            json.array do
              json.string "multiplexing"
              json.string "header-compression"
              json.string "server-push"
              json.string "binary-framing"
            end
          end
        end
      end
    else
      response.status = 404
      response.headers["content-type"] = "text/plain; charset=utf-8"
      response << "File not found: #{request.path}\n"
      response << "Available file endpoints:\n"
      response << "  /files/html - HTML demo page\n"
      response << "  /files/css  - CSS stylesheet\n"
      response << "  /files/js   - JavaScript file\n"
      response << "  /files/json - JSON response\n"
    end

    context
  end
end

# Error handling handler demonstrating different HTTP status codes
class ErrorHandler
  include Duo::Server::Handler

  def call(context : Duo::Server::Context)
    request = context.request
    response = context.response

    # Only handle error paths
    unless request.path.starts_with?("/error/")
      return call_next(context)
    end

    response.headers["content-type"] = "application/json; charset=utf-8"
    response.headers["server"] = "duo-http2-test-server"

    case request.path
    when "/error/400"
      response.status = 400
      response << JSON.build do |json|
        json.object do
          json.field "error", "Bad Request"
          json.field "code", 400
          json.field "message", "The request could not be understood by the server"
          json.field "timestamp", Time.utc.to_rfc3339
        end
      end
    when "/error/401"
      response.status = 401
      response.headers["www-authenticate"] = "Basic realm=\"Test Server\""
      response << JSON.build do |json|
        json.object do
          json.field "error", "Unauthorized"
          json.field "code", 401
          json.field "message", "Authentication required"
          json.field "timestamp", Time.utc.to_rfc3339
        end
      end
    when "/error/403"
      response.status = 403
      response << JSON.build do |json|
        json.object do
          json.field "error", "Forbidden"
          json.field "code", 403
          json.field "message", "Access to this resource is forbidden"
          json.field "timestamp", Time.utc.to_rfc3339
        end
      end
    when "/error/404"
      response.status = 404
      response << JSON.build do |json|
        json.object do
          json.field "error", "Not Found"
          json.field "code", 404
          json.field "message", "The requested resource was not found"
          json.field "timestamp", Time.utc.to_rfc3339
        end
      end
    when "/error/500"
      response.status = 500
      response << JSON.build do |json|
        json.object do
          json.field "error", "Internal Server Error"
          json.field "code", 500
          json.field "message", "An unexpected error occurred"
          json.field "timestamp", Time.utc.to_rfc3339
        end
      end
    when "/error/503"
      response.status = 503
      response.headers["retry-after"] = "30"
      response << JSON.build do |json|
        json.object do
          json.field "error", "Service Unavailable"
          json.field "code", 503
          json.field "message", "The service is temporarily unavailable"
          json.field "retry_after", 30
          json.field "timestamp", Time.utc.to_rfc3339
        end
      end
    else
      # Continue to next handler for unknown error codes
      call_next(context)
    end

    context
  end
end

# Performance testing handler
class PerformanceHandler
  include Duo::Server::Handler

  def call(context : Duo::Server::Context)
    request = context.request
    response = context.response

    # Only handle performance paths
    unless request.path.starts_with?("/perf/")
      return call_next(context)
    end

    case request.path
    when "/perf/small"
      response.headers["content-type"] = "text/plain; charset=utf-8"
      response.status = 200
      response << "Small response for performance testing - #{Time.utc.to_rfc3339}"
    when "/perf/medium"
      response.headers["content-type"] = "text/plain; charset=utf-8"
      response.status = 200
      1000.times do |i|
        response << "Medium response data chunk #{i + 1} - "
      end
      response << "END"
    when "/perf/large"
      response.headers["content-type"] = "text/plain; charset=utf-8"
      response.status = 200
      10000.times do |i|
        response << "Large response data chunk #{i + 1} with some additional text to make it larger. "
      end
      response << "END"
    when "/perf/binary"
      response.headers["content-type"] = "application/octet-stream"
      response.status = 200
      # Generate 1KB of binary data safely
      data = Bytes.new(1024) { |i| (i % 256).to_u8 }
      response.write(data)
    when "/perf/json"
      response.headers["content-type"] = "application/json; charset=utf-8"
      response.status = 200
      response << JSON.build do |json|
        json.object do
          json.field "test", "performance"
          json.field "data" do
            json.array do
              1000.times do |i|
                json.object do
                  json.field "id", i
                  json.field "value", "test_value_#{i}"
                  json.field "timestamp", Time.utc.to_unix_ms
                end
              end
            end
          end
        end
      end
    else
      call_next(context)
    end

    context
  end
end

# Health check handler
class HealthHandler
  include Duo::Server::Handler

  def call(context : Duo::Server::Context)
    request = context.request
    response = context.response

    # Only handle health check path
    unless request.path == "/health"
      return call_next(context)
    end

    response.headers["content-type"] = "application/json; charset=utf-8"
    response.headers["server"] = "duo-http2-test-server"
    response.status = 200

    response << JSON.build do |json|
      json.object do
        json.field "status", "healthy"
        json.field "server", "duo-http2-test-server"
        json.field "protocol", "HTTP/2"
        json.field "timestamp", Time.utc.to_rfc3339
        json.field "uptime_seconds", Process.times.utime + Process.times.stime
        json.field "version", "1.0.0"
      end
    end

    context
  end
end

# Default 404 handler (should be last in the chain)
class NotFoundHandler
  include Duo::Server::Handler

  def call(context : Duo::Server::Context)
    response = context.response
    response.status = 404
    response.headers["content-type"] = "text/plain; charset=utf-8"
    response.headers["server"] = "duo-http2-test-server"

    response << "404 NOT FOUND\n"
    response << "==============\n"
    response << "Path: #{context.request.path}\n"
    response << "Method: #{context.request.method}\n"
    response << "\nAvailable endpoints:\n"
    response << "  GET  /                        - Echo request information\n"
    response << "  GET  /echo                    - Echo request information\n"
    response << "  GET  /health                  - Health check\n"
    response << "  GET  /api/users               - JSON API example\n"
    response << "  GET  /api/status              - Server status\n"
    response << "  GET  /stream/countdown        - Streaming countdown\n"
    response << "  GET  /stream/events           - Server-sent events\n"
    response << "  GET  /stream/slow             - Slow response demo\n"
    response << "  GET  /files/html              - HTML page\n"
    response << "  GET  /files/css               - CSS stylesheet\n"
    response << "  GET  /files/js                - JavaScript file\n"
    response << "  GET  /files/json              - JSON file\n"
    response << "  GET  /error/{400,401,403,404,500,503} - Error testing\n"
    response << "  GET  /perf/{small,medium,large,binary,json} - Performance testing\n"

    context
  end
end

# SSL Configuration
def create_ssl_context
  # Try to find existing certificates
  cert_paths = [
    {File.join(__DIR__, "ssl", "localhost.pem"), File.join(__DIR__, "ssl", "localhost-key.pem")},
    {File.join(__DIR__, "ssl", "example.crt"), File.join(__DIR__, "ssl", "example.key")},
    {File.join(__DIR__, "ssl", "localhost.crt"), File.join(__DIR__, "ssl", "localhost.key")},
    {File.join(__DIR__, "ssl", "server.crt"), File.join(__DIR__, "ssl", "server.key")},
  ]

  cert_path = nil
  key_path = nil

  cert_paths.each do |cert_file, key_file|
    if File.exists?(cert_file) && File.exists?(key_file)
      cert_path = cert_file
      key_path = key_file
      break
    end
  end

  unless cert_path && key_path
    puts "⚠️  No SSL certificates found. Please create certificates or the server will run without SSL."
    puts "💡 You can create self-signed certificates with:"
    puts "   mkdir -p #{File.join(__DIR__, "ssl")}"
    puts "   openssl req -x509 -newkey rsa:2048 -keyout #{File.join(__DIR__, "ssl", "localhost-key.pem")} -out #{File.join(__DIR__, "ssl", "localhost.pem")} -days 365 -nodes -subj '/CN=localhost'"
    puts "🔄 Falling back to HTTP/1.1 mode without SSL"
    return nil
  end

  ssl_context = OpenSSL::SSL::Context::Server.new
  ssl_context.certificate_chain = cert_path
  ssl_context.private_key = key_path
  ssl_context.alpn_protocol = "h2"
  ssl_context
rescue ex
  puts "❌ SSL Error: #{ex.message}"
  puts "💡 Running without SSL (HTTP/1.1 only)"
  nil
end

# Server Configuration
host = ENV["HOST"]? || "::"
port = (ENV["PORT"]? || 9876).to_i
ssl_context = create_ssl_context

# Handler Chain - Order matters! Each handler should call_next() if it doesn't handle the request
handlers = [
  EchoHandler.new,        # Handle / and /echo
  HealthHandler.new,      # Handle /health
  JsonApiHandler.new,     # Handle /api/*
  StreamingHandler.new,   # Handle /stream/*
  FileHandler.new,        # Handle /files/*
  ErrorHandler.new,       # Handle /error/*
  PerformanceHandler.new, # Handle /perf/*
  NotFoundHandler.new,    # Handle everything else (404) - MUST be last
]

# Create and start server
server = Duo::Server.new(host, port, ssl_context)

puts "🚀 HTTP/2 Test Server Starting..."
if ssl_context
  puts "📍 Listening on https://#{host}:#{port}/"
  puts "🔒 TLS/SSL enabled with HTTP/2 support"
else
  puts "📍 Listening on http://#{host}:#{port}/"
  puts "⚠️  Running without SSL (HTTP/1.1 only)"
end

puts ""
puts "🔗 Available endpoints:"
puts "   GET  /                        - Echo request information"
puts "   GET  /echo                    - Echo request information"
puts "   GET  /health                  - Health check endpoint"
puts "   GET  /api/users               - JSON API example"
puts "   GET  /api/status              - Server status"
puts "   GET  /stream/countdown        - Streaming countdown"
puts "   GET  /stream/events           - Server-sent events"
puts "   GET  /stream/slow             - Slow response demo"
puts "   GET  /files/html              - HTML page"
puts "   GET  /files/css               - CSS stylesheet"
puts "   GET  /files/js                - JavaScript file"
puts "   GET  /files/json              - JSON file"
puts "   GET  /error/{400,401,403,404,500,503} - Error testing"
puts "   GET  /perf/{small,medium,large,binary,json} - Performance testing"
puts ""
puts "💡 Tips:"
puts "   • Test multiplexing by opening multiple browser tabs"
puts "   • Use browser dev tools to see HTTP/2 features"
puts "   • Try streaming endpoints to see real-time responses"
puts ""
puts "Press Ctrl+C to stop the server"

# Graceful shutdown handling
Signal::INT.trap do
  puts "\n🛑 Shutting down server gracefully..."
  exit(0)
end

Signal::TERM.trap do
  puts "\n🛑 Shutting down server gracefully..."
  exit(0)
end

server.listen(handlers)
