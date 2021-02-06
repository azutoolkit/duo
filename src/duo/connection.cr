require "colorize"
require "./hpack"
require "./connection/errors"
require "./connection/frame"
require "./connection/settings"
require "./connection/streams"

module Duo
  class Connection
    enum Type
      CLIENT
      SERVER
    end

    private getter io : IO
    private ACK = Frame::Flags::EndStream
    getter local_settings : Settings = Settings::DEFAULT.dup
    getter remote_settings : Settings = Settings.new
    protected getter hpack_encoder : HPACK::Encoder
    protected getter hpack_decoder : HPACK::Decoder

    @channel = Channel(Frame | Array(Frame) | Nil).new(10)
    @closed = false
    @hpack_encoder = HPack.encoder
    @hpack_decoder = HPack.decoder
    @inbound_window_size = DEFAULT_INITIAL_WINDOW_SIZE
    @outbound_window_size = Atomic(Int32).new(DEFAULT_INITIAL_WINDOW_SIZE)

    def initialize(@io : IO, @type : Type)
      spawn frame_writer
    end

    # Holds streams associated to the connection. Can be used to find an
    # existing stream or create a new stream —odd numbered for client requests,
    # even numbered for server pushed requests.
    def streams : Streams
      # FIXME: thread safety?
      #        can't be in #initialize because of self reference
      @streams ||= Streams.new(self, @type)
    end

    # TODO: Maybe extract as a nicer struct?
    private def frame_writer
      loop do
        # OPTIMIZE: follow stream priority to send frames
        begin
          case frame = @channel.receive
          when Array(Frame) then frame.each { |f| write(f, flush: false) }
          when Frame then write(frame, flush: false)
          else
            io.close unless io.closed?
            break
          end
        rescue Channel::ClosedError
          break
        ensure
          # flush pending frames when there are no more frames to send,
          # otherwise let IO::Buffered do its job:
          #
          # NOTE: accessing internal @queue until Channel#empty? makes a comeback
          io.flush if @channel.@queue.not_nil!.empty?
        end
      end
    end

    # Reads the expected `Duo::CLIENT_PREFACE` for a server context.
    #
    # You may set *truncated* to true if the request line was already read, for
    # example when trying to figure out whether the request was a HTTP/1 or
    # HTTP/2 direct request, where `"PRI * HTTP/2.0\r\n"` was already consumed.
    def read_client_preface(truncated = false) : Nil
      raise "can't read HTTP/2 client preface on a client connection" unless @type.server?
      if truncated
        buf1 = uninitialized UInt8[8]; buffer = buf1.to_slice
        preface = CLIENT_PREFACE[-8, 8]
      else
        buf2 = uninitialized UInt8[24]; buffer = buf2.to_slice
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

    # Call in the main loop to receive individual frames.
    #
    # Most frames are already being taken care of, so only Headers, Data or
    # PushPromise frames should really be interesting. Other frames can be
    # ignored safely.
    #
    # Unknown frame types are reported with a raw `Frame#payload`, so a client
    # or server may handle them (e.g. custom extensions). They can be safely
    # ignored.
    def receive : Frame?
      frame = read_frame_header
      stream = frame.stream

      stream.receiving(frame)

      case frame.type
      when Frame::Type::Data
        raise Error.protocol_error if stream.id == 0
        read_data_frame(frame)
      when Frame::Type::Headers
        raise Error.protocol_error if stream.id == 0
        read_headers_frame(frame)
      when Frame::Type::PushPromise
        raise Error.protocol_error if stream.id == 0
        read_push_promise_frame(frame)
      when Frame::Type::Priority
        raise Error.protocol_error if stream.id == 0
        read_priority_frame(frame)
      when Frame::Type::RstStream
        raise Error.protocol_error if stream.id == 0
        read_rst_stream_frame(frame)
      when Frame::Type::Settings
        raise Error.protocol_error unless stream.id == 0
        read_settings_frame(frame)
      when Frame::Type::Ping
        raise Error.protocol_error unless stream.id == 0
        read_ping_frame(frame)
      when Frame::Type::GoAway
        read_goaway_frame(frame)
      when Frame::Type::WindowUpdate
        read_window_update_frame(frame)
      when Frame::Type::Continuation
        raise Error.protocol_error("UNEXPECTED Continuation frame")
      else
        read_unsupported_frame(frame)
      end

      frame
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

    private def read_frame_header
      buf = io.read_bytes(UInt32, IO::ByteFormat::BigEndian)
      size, type = (buf >> 8).to_i, buf & 0xff
      
      flags = Frame::Flags.new(read_byte)
      _, stream_id = read_stream_id

      if size > remote_settings.max_frame_size
        raise Error.frame_size_error
      end

      frame_type = Frame::Type.new(type.to_i)
      unless frame_type.priority? || streams.valid?(stream_id)
        raise Error.protocol_error("INVALID stream_id ##{stream_id}")
      end

      stream = streams.find(stream_id, consume: !frame_type.priority?)
      frame = Frame.new(frame_type, stream, flags, size: size)

      frame
    end

    private def read_data_frame(frame)
      stream = frame.stream

      read_padded(frame) do |size|
        consume_inbound_window_size(size)
        stream.data.copy_from(io, size)

        if frame.flags.end_stream?
          stream.data.close_write

          if content_length = stream.headers["content-length"]?
            unless content_length.to_i == stream.data.size
              # stream.send_rst_stream(Error::Code::ProtocolError)
              raise Error.protocol_error("MALFORMED data frame")
            end
          end
        end
      end
    end

    # TODO: if Headers has EndStream flag tell STREAM that it WON'T receive Data
    private def read_headers_frame(frame)
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
            hpack_decoder.decode(buffer, stream.trailing_headers)
          else
            hpack_decoder.decode(buffer, stream.headers)
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
          # https://tools.ietf.org/html/rfc7540#section-8.1
          # https://tools.ietf.org/html/rfc7230#section-4.1.2
          stream.data.close_write

          if content_length = stream.headers["content-length"]?
            unless content_length.to_i == stream.data.size
              # connection.send_rst_stream(Error::Code::ProtocolError)
              raise Error.protocol_error("MALFORMED data frame")
            end
          end
        end
      end
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
        unless frame.type == Frame::Type::Continuation
          raise Error.protocol_error("EXPECTED continuation frame")
        end
        unless frame.stream == stream
          raise Error.protocol_error("EXPECTED continuation frame for stream ##{stream.id} not ##{frame.stream.id}")
        end

        # FIXME: raise if the payload grows too big
        pointer = pointer.realloc(size + frame.size)
        io.read_fully((pointer + size).to_slice(frame.size))

        size += frame.size
      end

      pointer.to_slice(size)
    end

    private def read_push_promise_frame(frame)
      stream = frame.stream

      read_padded(frame) do |size|
        _, promised_stream_id = read_stream_id
        streams.find(promised_stream_id).receiving(frame)
        buffer = read_headers_payload(frame, size - 4)
        hpack_decoder.decode(buffer, stream.headers)
      end
    end

    private def read_priority_frame(frame)
      stream = frame.stream
      raise Error.frame_size_error unless frame.size == PRIORITY_FRAME_SIZE

      exclusive, dep_stream_id = read_stream_id
      raise Error.protocol_error("INVALID stream dependency") if stream.id == dep_stream_id

      weight = 1 + read_byte
      stream.priority = Priority.new(exclusive == 1, dep_stream_id, weight)
    end

    private def read_rst_stream_frame(frame)
      raise Error.frame_size_error unless frame.size == RST_STREAM_FRAME_SIZE
      error_code = Error::Code.new(io.read_bytes(UInt32, IO::ByteFormat::BigEndian))
    end

    private def read_settings_frame(frame)
      raise Error.frame_size_error unless frame.size % 6 == 0
      return if frame.flags.ack?

      remote_settings.parse(io, frame.size // 6) do |id, value|
        case id
        when Settings::Identifier::HeaderTableSize
          hpack_decoder.max_table_size = value
        when Settings::Identifier::InitialWindowSize
          difference = value - remote_settings.initial_window_size

          # adjust windows size for all control-flow streams (doesn't affect
          # the connection window size):
          unless difference == 0
            streams.each do |stream|
              next if stream.id == 0
              stream.increment_outbound_window_size(difference)
            end
          end
        else
          # shut up, crystal
        end
      end

      # ACK reception of remote Settings:
      send Frame.new(Frame::Type::Settings, frame.stream, ACK)
    end

    private def read_ping_frame(frame)
      raise Error.frame_size_error unless frame.size == PING_FRAME_SIZE
      buffer = uninitialized UInt8[8] # PING_FRAME_SIZE
      io.read_fully(buffer.to_slice)

      if frame.flags.ack?
        print buffer
        # TODO: validate buffer == previously sent Ping value
        # send Frame.new(Frame::Type::GoAway, frame.stream, ACK, buffer.to_slice)
      else
        send Frame.new(Frame::Type::Ping, frame.stream, ACK, buffer.to_slice)
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
      # reserved = buf.bit(31)
      window_size_increment = (buf & 0x7fffffff_u32).to_i32
      raise Error.protocol_error unless MINIMUM_WINDOW_SIZE <= window_size_increment <= MAXIMUM_WINDOW_SIZE
      if stream.id == 0
        increment_outbound_window_size(window_size_increment)
      else
        stream.increment_outbound_window_size(window_size_increment)
      end
    end

    private def read_unsupported_frame(frame)
      frame.payload = Bytes.new(frame.size)
      io.read(frame.payload)
    end

    # Sends a frame to the connected peer.
    #
    # One may also send an Array(Frame) for the case when some frames must be
    # sliced (in order to respect max frame size) but must be sent as a single
    # block (multiplexing would cause a protocol error).
    #
    # So far this only applies to Headers (and PushPromise) and Continuation
    # frames, otherwise HPACK compression synchronisation could end up corrupted
    # if another Headers frame for another stream was sent in between.
    def send(frame : Frame | Array(Frame)) : Nil
      @channel.send(frame) unless @channel.closed?
    end

    # Immediately writes local settings to the connection.
    #
    # This is UNSAFE and MUST only be called for sending the initial Settings
    # frame. Sending changes to `#local_settings` once the connection
    # established MUST use `#send_settings` instead!
    def write_settings : Nil
      write Frame.new(Duo::Frame::Type::Settings, streams.find(0), payload: local_settings.to_payload)
    end

    # Sends a Settings frame for the current `#local_settings` values.
    def send_settings : Nil
      send Frame.new(Duo::Frame::Type::Settings, streams.find(0), payload: local_settings.to_payload)
    end

    private def write(frame : Frame, flush = true)
      size = frame.payload?.try(&.size.to_u32) || 0_u32
      stream = frame.stream

      stream.sending(frame) unless frame.type == Frame::Type::PushPromise

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

    # Keeps the inbound window size (when receiving Data frames). If the
    # available size shrinks below half the initial window size, then we send a
    # WindowUpdate frame to increment it by the initial window size * the
    # number of active streams, respecting `MAXIMUM_WINDOW_SIZE`.
    private def consume_inbound_window_size(len)
      @inbound_window_size -= len
      initial_window_size = local_settings.initial_window_size

      if @inbound_window_size < (initial_window_size // 2)
        # if @inbound_window_size <= 0
        increment = Math.min(initial_window_size * streams.active_count(1), MAXIMUM_WINDOW_SIZE)
        @inbound_window_size += increment
        streams.find(0).window_update(increment)
      end
    end

    protected def outbound_window_size
      @outbound_window_size.get
    end

    # Tries to consume *len* bytes from the connection outbound window size, but
    # may return a lower value, or even 0.
    protected def consume_outbound_window_size(len)
      loop do
        window_size = @outbound_window_size.get
        return 0 if window_size == 0

        actual = Math.min(len, window_size)
        _, success = @outbound_window_size.compare_and_set(window_size, window_size - actual)
        return actual if success
      end
    end

    # Increments the connection outbound window size.
    private def increment_outbound_window_size(increment) : Nil
      if outbound_window_size.to_i64 + increment > MAXIMUM_WINDOW_SIZE
        raise Error.flow_control_error
      end
      @outbound_window_size.add(increment)

      if outbound_window_size > 0
        streams.each(&.resume_writeable)
      end
    end

    # Terminates the HTTP/2 connection.
    #
    # This will send a GoAway frame if *notify* is true, reporting an
    # `Error::Code` optional message if present to report an error, or
    # `Error::Code::NoError` to terminate the connection cleanly.
    def close(error : Error? = nil, notify : Bool = true)
      return if closed?
      @closed = true

      unless io.closed?
        if notify
          if error
            message, code = error.message || "", error.code
          else
            message, code = "", Error::Code::NoError
          end
          payload = IO::Memory.new(8 + message.bytesize)
          payload.write_bytes(streams.last_stream_id.to_u32, IO::ByteFormat::BigEndian)
          payload.write_bytes(code.to_u32, IO::ByteFormat::BigEndian)
          payload << message

          # FIXME: shouldn't write directly to IO
          write Frame.new(Frame::Type::GoAway, streams.find(0), payload: payload.to_slice)
        end
      end

      unless @channel.closed?
        @channel.send(nil)
        @channel.close
      end
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
