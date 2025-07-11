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

    case request.path
    when "/files/html"
      response.headers["content-type"] = "text/html"
      response << "<!DOCTYPE html>\n"
      response << "<html>\n"
      response << "<head>\n"
      response << "  <title>HTTP/2 Test Page</title>\n"
      response << "  <style>\n"
      response << "    body { font-family: Arial, sans-serif; margin: 40px; }\n"
      response << "    .container { max-width: 800px; margin: 0 auto; }\n"
      response << "    .feature { background: #f5f5f5; padding: 20px; margin: 10px 0; border-radius: 5px; }\n"
      response << "  </style>\n"
      response << "</head>\n"
      response << "<body>\n"
      response << "  <div class=\"container\">\n"
      response << "    <h1>HTTP/2 Test Server</h1>\n"
      response << "    <p>This page is served over HTTP/2 with the following features:</p>\n"
      response << "    <div class=\"feature\">\n"
      response << "      <h3>Multiplexing</h3>\n"
      response << "      <p>Multiple requests can be processed concurrently over a single connection.</p>\n"
      response << "    </div>\n"
      response << "    <div class=\"feature\">\n"
      response << "      <h3>Header Compression</h3>\n"
      response << "      <p>Headers are compressed using HPACK to reduce overhead.</p>\n"
      response << "    </div>\n"
      response << "    <div class=\"feature\">\n"
      response << "      <h3>Server Push</h3>\n"
      response << "      <p>Resources can be pushed proactively to improve performance.</p>\n"
      response << "    </div>\n"
      response << "  </div>\n"
      response << "</body>\n"
      response << "</html>\n"
    when "/files/css"
      response.headers["content-type"] = "text/css"
      response << "body {\n"
      response << "  font-family: 'Segoe UI', Tahoma, Geneva, Verdana, sans-serif;\n"
      response << "  line-height: 1.6;\n"
      response << "  color: #333;\n"
      response << "}\n"
      response << ".header {\n"
      response << "  background: linear-gradient(135deg, #667eea 0%, #764ba2 100%);\n"
      response << "  color: white;\n"
      response << "  padding: 2rem;\n"
      response << "  text-align: center;\n"
      response << "}\n"
      response << ".content {\n"
      response << "  padding: 2rem;\n"
      response << "}\n"
    when "/files/js"
      response.headers["content-type"] = "application/javascript"
      response << "console.log('HTTP/2 Test Server JavaScript loaded');\n"
      response << "document.addEventListener('DOMContentLoaded', function() {\n"
      response << "  console.log('DOM loaded via HTTP/2');\n"
      response << "});\n"
    else
      response.status = 404
      response.headers["content-type"] = "text/plain"
      response << "File not found: #{request.path}\n"
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

    response.headers["content-type"] = "application/json"
    response.headers["server"] = "duo-http2-test-server"

    case request.path
    when "/error/400"
      response.status = 400
      response << JSON.build do |json|
        json.object do
          json.field "error", "Bad Request"
          json.field "code", 400
          json.field "message", "The request could not be understood by the server"
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
        end
      end
    when "/error/403"
      response.status = 403
      response << JSON.build do |json|
        json.object do
          json.field "error", "Forbidden"
          json.field "code", 403
          json.field "message", "Access to this resource is forbidden"
        end
      end
    when "/error/404"
      response.status = 404
      response << JSON.build do |json|
        json.object do
          json.field "error", "Not Found"
          json.field "code", 404
          json.field "message", "The requested resource was not found"
        end
      end
    when "/error/500"
      response.status = 500
      response << JSON.build do |json|
        json.object do
          json.field "error", "Internal Server Error"
          json.field "code", 500
          json.field "message", "An unexpected error occurred"
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
        end
      end
    else
      # Continue to next handler
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

    case request.path
    when "/perf/small"
      response.headers["content-type"] = "text/plain"
      response << "Small response for performance testing"
    when "/perf/medium"
      response.headers["content-type"] = "text/plain"
      response << "Medium response " * 100
    when "/perf/large"
      response.headers["content-type"] = "text/plain"
      response << "Large response " * 1000
    when "/perf/binary"
      response.headers["content-type"] = "application/octet-stream"
      # Generate 1KB of random data
      1024.times { response << rand(256).chr }
    else
      call_next(context)
    end

    context
  end
end

# Default 404 handler
class NotFoundHandler
  include Duo::Server::Handler

  def call(context : Duo::Server::Context)
    response = context.response
    response.status = 404
    response.headers["content-type"] = "text/plain"
    response.headers["server"] = "duo-http2-test-server"
    response << "404 NOT FOUND\n"
    response << "Path: #{context.request.path}\n"
    response << "Available endpoints:\n"
    response << "  /echo - Echo request information\n"
    response << "  /api/* - JSON API endpoints\n"
    response << "  /stream/* - Streaming endpoints\n"
    response << "  /files/* - File serving endpoints\n"
    response << "  /error/* - Error testing endpoints\n"
    response << "  /perf/* - Performance testing endpoints\n"

    context
  end
end

# SSL Configuration
tls_context = OpenSSL::SSL::Context::Server.new
tls_context.certificate_chain = "./ssl/localhost.pem"
tls_context.private_key = "./ssl/localhost-key.pem"
tls_context.alpn_protocol = "h2"

# Server Configuration
host = ENV["HOST"]? || "::"
port = (ENV["PORT"]? || 4000).to_i

# Handler Chain - Order matters!
handlers = [
  EchoHandler.new,           # Handle /echo
  JsonApiHandler.new,        # Handle /api/*
  StreamingHandler.new,      # Handle /stream/*
  FileHandler.new,           # Handle /files/*
  ErrorHandler.new,          # Handle /error/*
  PerformanceHandler.new,    # Handle /perf/*
  NotFoundHandler.new,       # Handle everything else (404)
]

# Create and start server
server = Duo::Server.new(host, port, tls_context)

puts "🚀 HTTP/2 Test Server Starting..."
puts "📍 Listening on https://#{host}:#{port}/"
puts "🔗 Available endpoints:"
puts "   GET  /echo                    - Echo request information"
puts "   GET  /api/users               - JSON API example"
puts "   GET  /api/status              - Server status"
puts "   GET  /stream/countdown        - Streaming countdown"
puts "   GET  /stream/events           - Server-sent events"
puts "   GET  /files/html              - HTML page"
puts "   GET  /files/css               - CSS stylesheet"
puts "   GET  /files/js                - JavaScript file"
puts "   GET  /error/{400,401,403,404,500,503} - Error testing"
puts "   GET  /perf/{small,medium,large,binary} - Performance testing"
puts ""
puts "Press Ctrl+C to stop the server"

server.listen(handlers)
