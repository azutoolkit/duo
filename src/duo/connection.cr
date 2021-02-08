require "colorize"
require "./hpack"
require "./errors"
require "./frame"
require "./settings"
require "./streams"
require "./flow_control"

module Duo
  class Connection
    include FlowControl

    enum Type
      Client
      Server
    end

    private getter io : IO
    private ACK = Frame::Flags::EndStream
    getter local_settings : Settings = Settings::DEFAULT.dup
    getter remote_settings : Settings = Settings.new
    protected getter encoder : HPACK::Encoder = HPack.encoder
    protected getter decoder : HPACK::Decoder = HPack.decoder


    def initialize(@io : IO, @type : Type)
      spawn receive_frame
    end

    # Holds streams associated to the connection. Can be used to find an
    # existing stream or create a new stream —odd numbered for client requests,
    # even numbered for server pushed requests.
    def streams : Streams
      # FIXME: thread safety?
      #        can't be in #initialize because of self reference
      @streams ||= Streams.new(self, @type)
    end

    # Reads the expected `Duo::CLIENT_PREFACE` for a server context.
    #
    # You may set *truncated* to true if the request line was already read, for
    # example when trying to figure out whether the request was a HTTP/1 or
    # HTTP/2 direct request, where `"PRI * HTTP/2.0\r\n"` was already consumed.
    def read_client_preface(truncated = false) : Nil
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

    # Writes the `Duo::CLIENT_PREFACE` to initialize an HTTP/2 client
    # connection.
    def write_client_preface : Nil
      raise "can't write HTTP/2 client preface on a server connection" unless @type.client?
      io << CLIENT_PREFACE
    end

    # Reads padding information and yields the actual frame size without the
    # padding size. Eventually skips the padding.
    private def read_padded(frame)
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

      frame_type = FrameType.new(type.to_i)
      unless frame_type.priority? || streams.valid?(stream_id)
        raise Error.protocol_error("INVALID stream_id ##{stream_id}")
      end

      stream = streams.find(stream_id, consume: !frame_type.priority?)
      Frame.new(frame_type, stream, flags, size: size)
    end

    private def validate_request_headers(headers : HTTP::Headers) : Nil
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

    private def validate_response_headers(headers : HTTP::Headers) : Nil
      validate_headers(headers, RESPONSE_PSEUDO_HEADERS)
    end

    private def validate_headers(headers : HTTP::Headers, pseudo : Array(String)) : Nil
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

    # OPTIMIZE: consider IO::CircularBuffer and decompressing HPACK headers
    # in-parallel instead of reallocating pointers and eventually
    # decompressing everything
    private def read_headers_payload(frame, size)
      stream = frame.stream

      pointer = GC.malloc_atomic(size).as(UInt8*)
      io.read_fully(pointer.to_slice(size))

      loop do
        break if frame.flags.end_headers?

        frame = read_frame_header
        unless frame.type.continuation?
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
      error_code = Error::Code.new(io.read_bytes(UInt32, IO::ByteFormat::BigEndian))
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
      buffer = uninitialized UInt8[8] # PING_FRAME_SIZE
      io.read_fully(buffer.to_slice)

      unless frame.flags.ack?
        send Frame.new(FrameType::Ping, frame.stream, ACK, buffer.to_slice)
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
      raise Error.protocol_error unless MINIMUM_WINDOW_SIZE <= window_size_increment <= MAXIMUM_WINDOW_SIZE
      stream.process_window_update(window_size_increment)
    end

    private def read_unsupported_frame(frame)
      frame.payload = Bytes.new(frame.size)
      io.read(frame.payload)
    end
    
    def write_settings : Nil
      write Frame.new(Duo::FrameType::Settings, streams.find(0), payload: local_settings.to_payload)
    end

    def send_settings : Nil
      send Frame.new(Duo::FrameType::Settings, streams.find(0), payload: local_settings.to_payload)
    end

    private def write(frame : Frame, flush = true)
      size = frame.payload?.try(&.size.to_u32) || 0_u32
      stream = frame.stream

      State.sending(frame) unless frame.type.push_promise?

      io.write_bytes((size << 8) | frame.type.to_u8, IO::ByteFormat::BigEndian)
      io.write_byte(frame.flags.to_u8)
      io.write_bytes(stream.id.to_u32, IO::ByteFormat::BigEndian)

      if payload = frame.payload?
        io.write(payload) if payload.size > 0
      end

      if flush
        io.flush # unless io.sync?
      end
    end

    def close(error : Error = Error.no_error, notify : Bool = true)
      return if closed?
      @closed = true

      unless io.closed?
        if notify
          message = error.message || ""
          code = error.code
          payload = IO::Memory.new(8 + message.bytesize)
          payload.write_bytes(streams.last_stream_id.to_u32, IO::ByteFormat::BigEndian)
          payload.write_bytes(code.to_u32, IO::ByteFormat::BigEndian)
          payload << message
          send Frame.new(FrameType::GoAway, streams.find(0), payload: payload.to_slice)
        end
      end

      close_channel!
    end

    def closed?
      @closed
    end

    private def read_byte
      io.read_byte.not_nil!
    end

    private def read_stream_id
      buf = io.read_bytes(UInt32, IO::ByteFormat::BigEndian)
      {buf.bit(31), (buf & 0x7fffffff_u32).to_i32}
    end
  end
end
