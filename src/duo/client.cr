require "socket"
require "openssl"
require "./connection"

module Duo
  class Client
    @connection : Connection
    @requests = {} of Stream => Channel(Nil)

    def initialize(host : String, port : Int32, ssl_context)
      @authority = "#{host}:#{port}"

      io = TCPSocket.new(host, port)

      case ssl_context
      when true
        ssl_context = OpenSSL::SSL::Context::Client.new
        ssl_context.alpn_protocol = "h2"
        io = OpenSSL::SSL::Socket::Client.new(io, ssl_context)
        @scheme = "https"
      when OpenSSL::SSL::Context::Client
        ssl_context.alpn_protocol = "h2"
        io = OpenSSL::SSL::Socket::Client.new(io, ssl_context)
        @scheme = "https"
      else
        @scheme = "http"
      end

      connection = Connection.new(io, Connection::Type::Client)
      connection.write_client_preface
      connection.write_settings

      frame = connection.call
      unless frame.try(&.type) == FrameType::Settings
        raise Error.protocol_error("Expected Settings frame")
      end

      @connection = connection
      spawn handle_connection
    end

    private def handle_connection
      loop do
        unless frame = @connection.call
          next
        end
        case frame.type
        when FrameType::Headers
          @requests[frame.stream].send(nil)
        when FrameType::PushPromise
          # TODO: got SERVER PUSHed headers
        when FrameType::GoAway
          break
        else
          # shut up, crystal
        end
      end
    end

    def request(headers : HTTP::Headers)
      headers[":authority"] = @authority
      headers[":scheme"] ||= @scheme

      stream = @connection.streams.create
      @requests[stream] = Channel(Nil).new

      stream.send_headers(headers)
      @requests[stream].receive

      yield stream.headers, stream.data

      if stream.active?
        stream.send_rst_stream(Error::Code::NoError)
      end
    end

    def close
      @connection.close unless closed?
    end

    def closed?
      @connection.closed?
    end
  end
end
