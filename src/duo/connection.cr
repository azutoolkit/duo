require "colorize"
require "./hpack"
require "./errors"
require "./frame"
require "./settings"
require "./streams"

module Duo
  class Connection
    enum Type
      Client
      Server
    end

    private ACK = Frame::Flags::EndStream
    private getter io : IO

    getter? closed = false
    getter local_settings : Settings = Settings::DEFAULT.dup
    getter remote_settings : Settings = Settings.new
    getter local_window_size = DEFAULT_INITIAL_WINDOW_SIZE
    getter channel : Channel(Frame | Array(Frame) | Nil) = Channel(Frame | Array(Frame) | Nil).new(32)
    getter encoder : HPACK::Encoder = HPack.encoder
    getter decoder : HPACK::Decoder = HPack.decoder

    def initialize(@io : IO, @type : Type)
      spawn listen
    end

    private def read_byte
      io.read_byte.not_nil!
    end

    def streams
      @streams ||= Streams.new self, @type
    end

    def receive
      channel.receive
    end

    def empty?
      @channel.@queue.not_nil!
    end

    def send(frame : Frame)
      @channel.send(frame) unless @channel.closed?
    end

    def send(frame : Array(Frame))
      @channel.send(frame) unless @channel.closed?
    end

    private def close_channel!
      unless @channel.closed?
        @channel.send(nil)
        @channel.close
      end
    end

    def call
      frame, raw_type = read_frame_header
      State.receiving(frame) unless raw_type > 9 # Don't transition state for unknown frames

      case raw_type
      when 0 then read_data_frame(frame)
      when 1 then read_headers_frame(frame)
      when 2 then read_priority_frame(frame)
      when 3 then read_rst_stream_frame(frame)
      when 4 then read_settings_frame(frame)
      when 5 then read_push_promise_frame(frame)
      when 6 then read_ping_frame(frame)
      when 7 then read_goaway_frame(frame)
      when 8 then read_window_update_frame(frame)
      when 9
        raise Error.protocol_error("UNEXPECTED Continuation frame")
      else
        # Unknown frame type - just read and discard
        read_unsupported_frame(frame)
      end

      frame
    rescue ex : IO::EOFError
      Log.debug { "Client disconnected (EOF): #{ex.message}" }
      close(notify: false)
      nil
    rescue ex : OpenSSL::SSL::Error
      Log.debug { "SSL error during call (ignored): #{ex.message}" }
      close(notify: false)
      nil
    rescue ex : IO::Error
      Log.debug { "IO error during call (ignored): #{ex.message}" }
      close(notify: false)
      nil
    end

    def write_client_preface
      raise "can't write HTTP/2 client preface on a server connection" unless @type.client?
      io << CLIENT_PREFACE
    end

    def write_settings
      write Frame.new(Duo::FrameType::Settings, streams.find(0), payload: local_settings.to_payload)
    end

    private def listen
      loop do
        begin
          case frame = receive
          when Array(Frame) then frame.each { |f| write(f, flush: false) }
          when Frame        then write(frame, flush: false)
          else
            begin
              io.close unless io.closed?
            rescue ex : OpenSSL::SSL::Error
              # Ignore SSL shutdown errors as they're common when clients disconnect abruptly
              Log.debug { "SSL shutdown error in listen (ignored): #{ex.message}" }
            rescue ex : IO::Error
              # Ignore IO errors during close
              Log.debug { "IO error during close in listen (ignored): #{ex.message}" }
            end
            break
          end
        rescue Channel::ClosedError
          break
        rescue ex : OpenSSL::SSL::Error
          # Ignore SSL errors in the main listen loop
          Log.debug { "SSL error in listen loop (ignored): #{ex.message}" }
          break
        rescue ex : IO::Error
          # Ignore IO errors in the main listen loop
          Log.debug { "IO error in listen loop (ignored): #{ex.message}" }
          break
        ensure
          begin
            io.flush if empty? && !io.closed?
          rescue ex : OpenSSL::SSL::Error
            # Ignore SSL errors during flush
            Log.debug { "SSL error during flush (ignored): #{ex.message}" }
          rescue ex : IO::Error
            # Ignore IO errors during flush
            Log.debug { "IO error during flush (ignored): #{ex.message}" }
          end
        end
      end
    end

    def read_client_preface(truncated = false)
      raise "can't read HTTP/2 client preface on a client connection" unless @type.server?
      if truncated
        buf1 = uninitialized UInt8[8]
        buffer = buf1.to_slice
        preface = CLIENT_PREFACE[-8, 8]
      else
        buf2 = uninitialized UInt8[24]
        buffer = buf2.to_slice
        preface = CLIENT_PREFACE
      end
      io.read_fully(buffer.to_slice)
      unless String.new(buffer.to_slice) == preface
        raise Error.protocol_error("PREFACE expected")
      end
    end

    private def read_padded(frame, &)
      size = frame.size

      if frame.flags.padded?
        pad_size = read_byte
        size -= 1 + pad_size
      end

      raise Error.protocol_error("INVALID pad length") if size < 0

      yield size

      if pad_size
        io.skip(pad_size)
      end
    end

    private def read_data_frame(frame)
      raise Error.protocol_error if frame.stream.zero?
      stream = frame.stream

      read_padded(frame) do |size|
        update_local_window(size)
        stream.data.copy_from(io, size)
        if frame.flags.end_stream?
          stream.data.close_write
          if content_length = stream.headers["content-length"]?
            unless content_length.to_i == stream.data.size
              raise Error.protocol_error("MALFORMED data frame")
            end
          end
        end
      end
    end

    private def read_headers_frame(frame)
      raise Error.protocol_error if frame.stream.zero?
      stream = frame.stream

      read_padded(frame) do |size|
        if frame.flags.priority?
          exclusive, dep_stream_id = read_stream_id
          raise Error.protocol_error("INVALID stream dependency") if stream.id == dep_stream_id
          weight = read_byte.to_i32 + 1
          stream.priority = Priority.new(exclusive == 1, dep_stream_id, weight)
          size -= 5
        end

        if stream.data? && !frame.flags.end_stream?
          raise Error.protocol_error("INVALID trailer part")
        end

        buffer = read_headers_payload(frame, size)

        begin
          if stream.data?
            decoder.decode(buffer, stream.trailing_headers)
          else
            decoder.decode(buffer, stream.headers)
            if @type.server?
              validate_request_headers(stream.headers)
            else
              validate_response_headers(stream.headers)
            end
          end
        rescue ex : HPACK::Error
          raise Error.compression_error
        end

        if stream.data?
          stream.data.close_write

          if content_length = stream.headers["content-length"]?
            unless content_length.to_i == stream.data.size
              raise Error.protocol_error("MALFORMED data frame")
            end
          end
        end
      end
    end

    private def read_frame_header
      buf = io.read_bytes(UInt32, IO::ByteFormat::BigEndian)
      size, type = (buf >> 8).to_i, buf & 0xff

      flags = Frame::Flags.new(read_byte)
      _, stream_id = read_stream_id

      if size > remote_settings.max_frame_size
        raise Error.frame_size_error
      end

      # For unknown frame types (> 9), use Data as placeholder
      frame_type = type <= 9 ? FrameType.new(type.to_i) : FrameType::Data

      # PRIORITY frames can be sent on any stream ID, even non-existent ones
      # Unknown frames should also be allowed on any stream
      unless frame_type.priority? || type > 9 || streams.valid?(stream_id)
        raise Error.protocol_error("INVALID stream_id ##{stream_id}")
      end

      stream = streams.find(stream_id, consume: !frame_type.priority? && type <= 9)
      frame = Frame.new(frame_type, stream, flags, size: size)
      {frame, type}
    end

    private def validate_request_headers(headers : HTTP::Headers)
      validate_headers(headers, REQUEST_PSEUDO_HEADERS)

      unless headers.get?(":method").try(&.size) == 1
        raise Error.protocol_error("INVALID :method pseudo-header")
      end

      unless headers[":method"] == "CONNECT"
        unless headers.get?(":scheme").try(&.size) == 1
          raise Error.protocol_error("INVALID :scheme pseudo-header")
        end

        paths = headers.get?(":path")
        unless paths.try(&.size) == 1 && !paths.try(&.first.empty?)
          raise Error.protocol_error("INVALID :path pseudo-header")
        end
      end
    end

    private def validate_response_headers(headers : HTTP::Headers)
      validate_headers(headers, RESPONSE_PSEUDO_HEADERS)
    end

    private def validate_headers(headers : HTTP::Headers, pseudo : Array(String))
      regular = false

      headers.each_key do |name|
        # special colon (:) headers MUST come before the regular headers
        regular ||= !name.starts_with?(':')

        if (name.starts_with?(':') && (regular || !pseudo.includes?(name))) || ("A".."Z").covers?(name)
          raise Error.protocol_error("MALFORMED #{name} header")
        end

        if name == "connection"
          raise Error.protocol_error("MALFORMED #{name} header")
        end

        if name == "te" && headers["te"] != "trailers"
          raise Error.protocol_error("MALFORMED #{name} header")
        end
      end
    end

    private def update_local_window(size)
      @local_window_size -= size
      initial_window_size = local_window_size

      if local_window_size < (initial_window_size // 2)
        increment = Math.min(initial_window_size * streams.active_count(1), MAXIMUM_WINDOW_SIZE)
        @local_window_size += increment
        streams.find(0).send_window_update(increment)
      end
    end

    private def read_headers_payload(frame, size)
      stream = frame.stream

      pointer = GC.malloc_atomic(size).as(UInt8*)
      io.read_fully(pointer.to_slice(size))

      loop do
        break if frame.flags.end_headers?

        frame, raw_type = read_frame_header
        unless raw_type == 9 # Continuation frame
          raise Error.protocol_error("EXPECTED continuation frame")
        end
        unless frame.stream == stream
          raise Error.protocol_error("EXPECTED continuation frame for stream ##{stream.id} not ##{frame.stream.id}")
        end

        pointer = pointer.realloc(size + frame.size)
        io.read_fully((pointer + size).to_slice(frame.size))

        size += frame.size
      end

      pointer.to_slice(size)
    end

    private def read_push_promise_frame(frame)
      raise Error.protocol_error if frame.stream.zero?
      stream = frame.stream

      read_padded(frame) do |size|
        _, promised_stream_id = read_stream_id
        stream = streams.find(promised_stream_id)
        stream.state.transition(frame, receiving: true)
        buffer = read_headers_payload(frame, size - 4)
        decoder.decode(buffer, stream.headers)
      end
    end

    private def read_priority_frame(frame)
      raise Error.protocol_error if frame.stream.zero?
      stream = frame.stream
      raise Error.frame_size_error unless frame.size == PRIORITY_FRAME_SIZE

      exclusive, dep_stream_id = read_stream_id
      raise Error.protocol_error("INVALID stream dependency") if stream.id == dep_stream_id

      weight = 1 + read_byte
      stream.priority = Priority.new(exclusive == 1, dep_stream_id, weight)
    end

    private def read_rst_stream_frame(frame)
      raise Error.protocol_error if frame.stream.zero?
      raise Error.frame_size_error unless frame.size == RST_STREAM_FRAME_SIZE
      Error::Code.new(io.read_bytes(UInt32, IO::ByteFormat::BigEndian))
    end

    private def read_settings_frame(frame)
      raise Error.protocol_error unless frame.stream.zero?
      raise Error.frame_size_error unless frame.size % 6 == 0
      return if frame.flags.ack?

      remote_settings.parse(io, frame.size // 6) do |id, value|
        case id
        when Settings::Identifier::HeaderTableSize
          decoder.max_table_size = value
        when Settings::Identifier::InitialWindowSize
          difference = value - remote_settings.initial_window_size
          unless difference == 0
            streams.each do |stream|
              next if stream.zero?
              stream.process_window_update(difference)
            end
          end
        end
      end
      send Frame.new(FrameType::Settings, frame.stream, ACK)
    end

    private def read_ping_frame(frame)
      raise Error.protocol_error unless frame.stream.zero?
      raise Error.frame_size_error unless frame.size == PING_FRAME_SIZE
      buffer = Bytes.new(8)
      io.read_fully(buffer)

      unless frame.flags.ack?
        send Frame.new(FrameType::Ping, frame.stream, ACK, payload: buffer)
      end
    end

    private def read_goaway_frame(frame)
      _, last_stream_id = read_stream_id
      error_code = Error::Code.new(io.read_bytes(UInt32, IO::ByteFormat::BigEndian))

      buffer = Bytes.new(frame.size - 8)
      io.read_fully(buffer)
      error_message = String.new(buffer)

      close(notify: false)

      unless error_code == Error::Code::NoError
        raise ClientError.new(error_code, last_stream_id, error_message)
      end
    end

    private def read_window_update_frame(frame)
      stream = frame.stream

      raise Error.frame_size_error unless frame.size == WINDOW_UPDATE_FRAME_SIZE
      buf = io.read_bytes(UInt32, IO::ByteFormat::BigEndian)
      window_size_increment = (buf & 0x7fffffff_u32).to_i32

      # WINDOW_UPDATE with 0 increment is a protocol error
      if window_size_increment == 0
        if frame.stream.zero?
          raise Error.protocol_error("WINDOW_UPDATE with 0 increment on connection")
        else
          # Send RST_STREAM for stream-level errors
          frame.stream.send_rst_stream(Error::Code::ProtocolError)
          return
        end
      end

      raise Error.protocol_error unless MINIMUM_WINDOW_SIZE <= window_size_increment <= MAXIMUM_WINDOW_SIZE

      # Check for flow control window overflow before processing
      if frame.stream.zero?
        # Connection-level window update
        current_window = streams.find(0).remote_window_size
        if current_window.to_i64 + window_size_increment > MAXIMUM_WINDOW_SIZE
          # RFC 7540: Must send GOAWAY with FLOW_CONTROL_ERROR before closing
          # Send the GOAWAY frame directly to ensure it's sent before closing
          message = "Connection flow control window overflow"
          payload = IO::Memory.new(8 + message.bytesize)
          payload.write_bytes(streams.last_stream_id.to_u32, IO::ByteFormat::BigEndian)
          payload.write_bytes(Error::Code::FlowControlError.to_u32, IO::ByteFormat::BigEndian)
          payload << message

          goaway_frame = Frame.new(FrameType::GoAway, streams.find(0), payload: payload.to_slice)
          write(goaway_frame, flush: true)

          # Close the connection after sending GOAWAY
          close(notify: false)
          return
        end
      else
        # Stream-level window update - check overflow
        current_window = frame.stream.remote_window_size
        if current_window.to_i64 + window_size_increment > MAXIMUM_WINDOW_SIZE
          # RFC 7540: Must send RST_STREAM with FLOW_CONTROL_ERROR
          frame.stream.send_rst_stream(Error::Code::FlowControlError)
          return
        end
      end

      stream.process_window_update(window_size_increment)
    end

    private def read_unsupported_frame(frame)
      frame.payload = Bytes.new(frame.size)
      io.read(frame.payload)
    end

    private def write(frame : Frame, flush = true)
      return if closed? || io.closed?

      size = frame.payload?.try(&.size.to_u32) || 0_u32
      stream = frame.stream

      State.sending(frame) unless frame.type.push_promise?

      begin
        io.write_bytes((size << 8) | frame.type.to_u8, IO::ByteFormat::BigEndian)
        io.write_byte(frame.flags.to_u8)
        io.write_bytes(stream.id.to_u32, IO::ByteFormat::BigEndian)

        if payload = frame.payload?
          io.write(payload) if payload.size > 0
        end

        if flush
          io.flush
        end
      rescue ex : OpenSSL::SSL::Error
        Log.debug { "SSL error during write (ignored): #{ex.message}" }
        close(notify: false)
      rescue ex : IO::Error
        Log.debug { "IO error during write (ignored): #{ex.message}" }
        close(notify: false)
      end
    end

    def close(error : Error = Error.no_error, notify : Bool = true)
      return if closed?
      @closed = true

      begin
        unless io.closed?
          if notify
            message = error.message || ""
            code = error.code
            payload = IO::Memory.new(8 + message.bytesize)
            payload.write_bytes(streams.last_stream_id.to_u32, IO::ByteFormat::BigEndian)
            payload.write_bytes(code.to_u32, IO::ByteFormat::BigEndian)
            payload << message

            # Send GOAWAY frame through the channel
            goaway_frame = Frame.new(FrameType::GoAway, streams.find(0), payload: payload.to_slice)
            send(goaway_frame)

            # Give a small delay to ensure the frame is processed, but don't block the main thread
            spawn do
              sleep 10.milliseconds
              close_channel!
            end
            return
          end
        end
      rescue ex : OpenSSL::SSL::Error
        # Ignore SSL errors during close as they're common when clients disconnect
        Log.debug { "SSL error during close (ignored): #{ex.message}" }
      rescue ex : IO::Error
        # Ignore IO errors during close
        Log.debug { "IO error during close (ignored): #{ex.message}" }
      end

      close_channel!
    end

    private def read_stream_id
      buf = io.read_bytes(UInt32, IO::ByteFormat::BigEndian)
      {buf.bit(31), (buf & 0x7fffffff_u32).to_i32}
    end
  end
end
