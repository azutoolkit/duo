module Duo
  module Core
    # Handles HTTP/2 frame parsing according to RFC 9113 Section 4.1
    class FrameParser
      private getter io : IO
      private getter max_frame_size : Int32

      def initialize(@io, @max_frame_size)
      end

      # Parses frame header according to RFC 9113 Section 4.1
      def parse_frame_header : FrameHeader
        buf = io.read_bytes(UInt32, IO::ByteFormat::BigEndian)
        size, type = (buf >> 8).to_i, buf & 0xff

        if size > max_frame_size
          raise Error.frame_size_error("Frame size #{size} exceeds maximum #{max_frame_size}")
        end

        flags = Frame::Flags.new(io.read_byte)
        _, stream_id = read_stream_id

        frame_type = type <= 9 ? FrameType.new(type.to_i) : FrameType::Data

        FrameHeader.new(
          type: frame_type,
          flags: flags,
          stream_id: stream_id,
          size: size,
          raw_type: type
        )
      end

      # Parses frame payload based on frame type
      def parse_frame_payload(header : FrameHeader) : FramePayload
        case header.type
        when .data?
          parse_data_payload(header)
        when .headers?
          parse_headers_payload(header)
        when .priority?
          parse_priority_payload(header)
        when .rst_stream?
          parse_rst_stream_payload(header)
        when .settings?
          parse_settings_payload(header)
        when .push_promise?
          parse_push_promise_payload(header)
        when .ping?
          parse_ping_payload(header)
        when .goaway?
          parse_goaway_payload(header)
        when .window_update?
          parse_window_update_payload(header)
        when .continuation?
          parse_continuation_payload(header)
        else
          parse_unknown_payload(header)
        end
      end

      private def read_stream_id : {Bool, Int32}
        buf = io.read_bytes(UInt32, IO::ByteFormat::BigEndian)
        {buf.bit(31), (buf & 0x7fffffff_u32).to_i32}
      end

      private def parse_data_payload(header : FrameHeader) : DataPayload
        read_padded(header) do |size|
          payload = Bytes.new(size)
          io.read_fully(payload)
          DataPayload.new(payload, header.flags.padded?)
        end
      end

      private def parse_headers_payload(header : FrameHeader) : HeadersPayload
        read_padded(header) do |size|
          # Handle priority if present
          priority = nil
          if header.flags.priority?
            exclusive, dep_stream_id = read_stream_id
            weight = io.read_byte.to_i32 + 1
            priority = Priority.new(exclusive == 1, dep_stream_id, weight)
            size -= 5
          end

          # Read headers payload
          payload = read_headers_payload_bytes(header, size)
          
          HeadersPayload.new(payload, priority, header.flags.padded?)
        end
      end

      private def parse_priority_payload(header : FrameHeader) : PriorityPayload
        raise Error.frame_size_error unless header.size == PRIORITY_FRAME_SIZE
        
        exclusive, dep_stream_id = read_stream_id
        weight = 1 + io.read_byte
        
        PriorityPayload.new(exclusive == 1, dep_stream_id, weight)
      end

      private def parse_rst_stream_payload(header : FrameHeader) : RstStreamPayload
        raise Error.frame_size_error unless header.size == RST_STREAM_FRAME_SIZE
        
        error_code = Error::Code.new(io.read_bytes(UInt32, IO::ByteFormat::BigEndian))
        RstStreamPayload.new(error_code)
      end

      private def parse_settings_payload(header : FrameHeader) : SettingsPayload
        raise Error.frame_size_error unless header.size % 6 == 0
        
        if header.flags.ack?
          return SettingsPayload.new_ack
        end

        settings = [] of {Settings::Identifier, Int32}
        (header.size // 6).times do
          id = Settings::Identifier.from_value?(io.read_bytes(UInt16, IO::ByteFormat::BigEndian))
          value = io.read_bytes(UInt32, IO::ByteFormat::BigEndian).to_i32
          settings << {id, value} if id
        end
        
        SettingsPayload.new(settings)
      end

      private def parse_ping_payload(header : FrameHeader) : PingPayload
        raise Error.frame_size_error unless header.size == PING_FRAME_SIZE
        
        opaque_data = Bytes.new(8)
        io.read_fully(opaque_data)
        
        PingPayload.new(opaque_data, header.flags.ack?)
      end

      private def parse_goaway_payload(header : FrameHeader) : GoAwayPayload
        _, last_stream_id = read_stream_id
        error_code = Error::Code.new(io.read_bytes(UInt32, IO::ByteFormat::BigEndian))
        
        debug_data = Bytes.new(header.size - 8)
        io.read_fully(debug_data)
        
        GoAwayPayload.new(last_stream_id, error_code, debug_data)
      end

      private def parse_window_update_payload(header : FrameHeader) : WindowUpdatePayload
        raise Error.frame_size_error unless header.size == WINDOW_UPDATE_FRAME_SIZE
        
        buf = io.read_bytes(UInt32, IO::ByteFormat::BigEndian)
        window_size_increment = (buf & 0x7fffffff_u32).to_i32
        
        WindowUpdatePayload.new(window_size_increment)
      end

      private def parse_push_promise_payload(header : FrameHeader) : PushPromisePayload
        read_padded(header) do |size|
          _, promised_stream_id = read_stream_id
          headers_payload = read_headers_payload_bytes(header, size - 4)
          
          PushPromisePayload.new(promised_stream_id, headers_payload, header.flags.padded?)
        end
      end

      private def parse_continuation_payload(header : FrameHeader) : ContinuationPayload
        payload = Bytes.new(header.size)
        io.read_fully(payload)
        
        ContinuationPayload.new(payload)
      end

      private def parse_unknown_payload(header : FrameHeader) : UnknownPayload
        payload = Bytes.new(header.size)
        io.read_fully(payload)
        
        UnknownPayload.new(payload, header.raw_type)
      end

      private def read_padded(header : FrameHeader, &)
        size = header.size
        pad_size = nil

        if header.flags.padded?
          pad_size = io.read_byte
          size -= 1 + pad_size
        end

        raise Error.protocol_error("Invalid pad length") if size < 0

        result = yield size

        if pad_size
          io.skip(pad_size)
        end

        result
      end

      private def read_headers_payload_bytes(header : FrameHeader, initial_size : Int32) : Bytes
        # Handle CONTINUATION frames for large headers
        total_size = initial_size
        payload = GC.malloc_atomic(total_size).as(UInt8*)
        io.read_fully(payload.to_slice(total_size))

        until header.flags.end_headers?
          cont_header = parse_frame_header
          unless cont_header.type.continuation?
            raise Error.protocol_error("Expected continuation frame")
          end
          unless cont_header.stream_id == header.stream_id
            raise Error.protocol_error("Continuation frame for wrong stream")
          end

          payload = payload.realloc(total_size + cont_header.size)
          io.read_fully((payload + total_size).to_slice(cont_header.size))
          total_size += cont_header.size
        end

        payload.to_slice(total_size)
      end
    end

    # Frame header structure
    struct FrameHeader
      getter type : FrameType
      getter flags : Frame::Flags
      getter stream_id : Int32
      getter size : Int32
      getter raw_type : Int32

      def initialize(@type, @flags, @stream_id, @size, @raw_type)
      end
    end

    # Frame payload structures
    abstract struct FramePayload
    end

    struct DataPayload < FramePayload
      getter data : Bytes
      getter padded : Bool

      def initialize(@data, @padded)
      end
    end

    struct HeadersPayload < FramePayload
      getter headers_data : Bytes
      getter priority : Priority?
      getter padded : Bool

      def initialize(@headers_data, @priority, @padded)
      end
    end

    struct PriorityPayload < FramePayload
      getter exclusive : Bool
      getter dependency_stream_id : Int32
      getter weight : Int32

      def initialize(@exclusive, @dependency_stream_id, @weight)
      end
    end

    struct RstStreamPayload < FramePayload
      getter error_code : Error::Code

      def initialize(@error_code)
      end
    end

    struct SettingsPayload < FramePayload
      getter settings : Array({Settings::Identifier, Int32})
      getter ack : Bool

      def initialize(@settings, @ack = false)
      end

      def self.new_ack
        new([] of {Settings::Identifier, Int32}, true)
      end
    end

    struct PingPayload < FramePayload
      getter opaque_data : Bytes
      getter ack : Bool

      def initialize(@opaque_data, @ack)
      end
    end

    struct GoAwayPayload < FramePayload
      getter last_stream_id : Int32
      getter error_code : Error::Code
      getter debug_data : Bytes

      def initialize(@last_stream_id, @error_code, @debug_data)
      end
    end

    struct WindowUpdatePayload < FramePayload
      getter window_size_increment : Int32

      def initialize(@window_size_increment)
      end
    end

    struct PushPromisePayload < FramePayload
      getter promised_stream_id : Int32
      getter headers_data : Bytes
      getter padded : Bool

      def initialize(@promised_stream_id, @headers_data, @padded)
      end
    end

    struct ContinuationPayload < FramePayload
      getter headers_data : Bytes

      def initialize(@headers_data)
      end
    end

    struct UnknownPayload < FramePayload
      getter data : Bytes
      getter raw_type : Int32

      def initialize(@data, @raw_type)
      end
    end
  end
end