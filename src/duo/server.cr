require "base64"
require "openssl"
require "./connection"
require "./server/handler"
require "./server/http1"
require "./server/context"

module Duo
  class Server
    @handler : Handler?
    @ssl_context : OpenSSL::SSL::Context::Server?

    def initialize(host : String, port : Int32, ssl_context = nil)
      @server = TCPServer.new(host, port)

      if ssl_context
        ssl_context.alpn_protocol = "h2"
        @ssl_context = ssl_context
      end
    end

    def listen(handlers : Array(Handler))
      raise ArgumentError.new("you must have at least one handler") if handlers.size == 0
      handlers.reduce { |a, b| a.next = b; b }
      @handler = handlers.first
      loop { spawn handle_socket(@server.accept) }
    end

    private def handle_socket(io : IO) : Nil
      must_close = true

      if ssl_context = @ssl_context
        io = OpenSSL::SSL::Socket::Server.new(io, ssl_context)

        if io.alpn_protocol == "h2"
          must_close = false
          return handle_http2_connection(io, alpn: "h2")
        end
      end

      connection = HTTP1::Connection.new(io)

      loop do
        break unless request_line = connection.read_request_line
        method, path = request_line

        case connection.version
        when "HTTP/1.1", "HTTP/1.0"
          headers = HTTP::Headers{
            ":method" => method,
            ":path"   => path,
          }
          unless connection.read_headers(headers)
            return bad_request(io)
          end

          body = decode_body(connection.content(headers), headers)
          request = Request.new(headers, body, connection.version)

          if settings = http2_upgrade?(headers)
            connection.upgrade("h2c")
            must_close = false
            return handle_http2_connection(connection.io, request, Base64.decode(settings), alpn: "h2c")
          end

          response = Response.new(connection)
          response.headers["connection"] = "keep-alive" if request.keep_alive?

          context = Context.new(request, response)
          handle_request(context)

          if response.upgraded?
            must_close = false
            break
          end

          unless request.keep_alive? && response.headers["connection"] == "keep-alive"
            break
          end
        when "HTTP/2.0"
          if method == "PRI" && path == "*"
            must_close = false
            return handle_http2_connection(io)
          else
            return bad_request(io)
          end
        else
          return bad_request(io)
        end
      end
    ensure
      begin
        io.close if must_close
      rescue IO::EOFError | IO::Error
      end
    end

    private def decode_body(body, headers)
      return unless body

      case headers["Content-Encoding"]?
      when "gzip"
        body = Compress::Gzip::Reader.new(body, sync_close: true)
      when "deflate"
        body = Compress::Deflate::Reader.new(body, sync_close: true)
      end

      check_content_type_charset(body, headers)

      body
    end

    private def check_content_type_charset(body, headers)
      content_type = headers["Content-Type"]?
      return unless content_type

      mime_type = MIME::MediaType.parse?(content_type)
      return unless mime_type

      charset = mime_type["charset"]?
      return unless charset

      body.set_encoding(charset, invalid: :skip)
    end

    private def bad_request(io) : Nil
      io << "HTTP/1.1 400 BAD REQUEST\r\nConnection: close\r\n\r\n"
    end

    private def handle_http1_connection(connection, method, path)
    end

    private def http2_upgrade?(headers)
      return unless headers["upgrade"]? == "h2c"
      return unless settings = headers.get?("Duo-settings")
      settings.first if settings.size == 1
    end

    private def handle_http2_connection(io, request = nil, settings = nil, alpn = nil) : Nil
      connection = Connection.new(io, Connection::Type::Server)

      if settings
        connection.remote_settings.parse(settings) do |_, value|
        end
      end

      connection.read_client_preface(truncated: alpn.nil?)
      connection.write_settings

      frame = connection.call
      unless frame.try(&.type) == FrameType::Settings
        raise Error.protocol_error("Expected Settings frame")
      end

      if request
        stream = connection.streams.find(1)
        context = context_for(stream, request)
        spawn handle_request(context.as(Context))
      end

      loop do
        unless frame = connection.call
          next
        end

        case frame.type
        when FrameType::Headers
          next if frame.stream.trailing_headers?
          context = context_for(frame.stream)
          spawn handle_request(context.as(Context))
        when FrameType::PushPromise
          raise Error.protocol_error("Unexpected PushPromise frame")
        when FrameType::GoAway
          break
        end
      end
    rescue ex : Duo::ClientError
      Log.error(exception: ex) { "RECV: #{ex.code}: #{ex.message}" }
    rescue ex : Duo::Error
      connection.close(error: ex) if connection
    ensure
      connection.close if connection
    end

    private def context_for(stream : Stream, request = nil)
      unless request
        if stream.state.open?
          body = decode_body(stream.data, stream.headers)
        end
        request = Request.new(stream.headers, body, "HTTP/2.0")
      end
      response = Response.new(stream)
      Context.new(request, response)
    end

    private def handle_request(context : Context)
      @handler.not_nil!.call(context)
    ensure
      context.response.close
      context.request.close
    end
  end
end
