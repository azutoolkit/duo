module Duo
  module Core
    # Factory for creating HTTP/2 frames according to RFC 9113
    class FrameFactory
      # Creates a DATA frame
      def self.create_data_frame(stream_id : Int32, data : Bytes, flags : Frame::Flags = Frame::Flags::None) : Frame
        validate_stream_id(stream_id)
        validate_frame_size(data.size)
        
        Frame.new(
          type: FrameType::Data,
          stream_id: stream_id,
          flags: flags,
          payload: data
        )
      end

      # Creates a HEADERS frame
      def self.create_headers_frame(stream_id : Int32, headers : HTTP::Headers, flags : Frame::Flags = Frame::Flags::None, priority : Priority? = nil) : Frame
        validate_stream_id(stream_id)
        
        payload = build_headers_payload(headers, priority)
        validate_frame_size(payload.size)
        
        Frame.new(
          type: FrameType::Headers,
          stream_id: stream_id,
          flags: flags,
          payload: payload
        )
      end

      # Creates a PRIORITY frame
      def self.create_priority_frame(stream_id : Int32, exclusive : Bool, dependency_stream_id : Int32, weight : Int32) : Frame
        validate_stream_id(stream_id)
        validate_priority_parameters(exclusive, dependency_stream_id, weight)
        
        payload = build_priority_payload(exclusive, dependency_stream_id, weight)
        
        Frame.new(
          type: FrameType::Priority,
          stream_id: stream_id,
          flags: Frame::Flags::None,
          payload: payload
        )
      end

      # Creates a RST_STREAM frame
      def self.create_rst_stream_frame(stream_id : Int32, error_code : Error::Code) : Frame
        validate_stream_id(stream_id)
        
        payload = build_rst_stream_payload(error_code)
        
        Frame.new(
          type: FrameType::RstStream,
          stream_id: stream_id,
          flags: Frame::Flags::None,
          payload: payload
        )
      end

      # Creates a SETTINGS frame
      def self.create_settings_frame(settings : Array({Settings::Identifier, Int32})) : Frame
        payload = build_settings_payload(settings)
        validate_frame_size(payload.size)
        
        Frame.new(
          type: FrameType::Settings,
          stream_id: 0,
          flags: Frame::Flags::None,
          payload: payload
        )
      end

      # Creates a SETTINGS ACK frame
      def self.create_settings_ack : Frame
        Frame.new(
          type: FrameType::Settings,
          stream_id: 0,
          flags: Frame::Flags::Ack,
          payload: Bytes.new(0)
        )
      end

      # Creates a PUSH_PROMISE frame
      def self.create_push_promise_frame(stream_id : Int32, promised_stream_id : Int32, headers : HTTP::Headers, flags : Frame::Flags = Frame::Flags::None) : Frame
        validate_stream_id(stream_id)
        validate_stream_id(promised_stream_id)
        
        payload = build_push_promise_payload(promised_stream_id, headers)
        validate_frame_size(payload.size)
        
        Frame.new(
          type: FrameType::PushPromise,
          stream_id: stream_id,
          flags: flags,
          payload: payload
        )
      end

      # Creates a PING frame
      def self.create_ping_frame(opaque_data : Bytes = Bytes.new(8)) : Frame
        validate_ping_data(opaque_data)
        
        Frame.new(
          type: FrameType::Ping,
          stream_id: 0,
          flags: Frame::Flags::None,
          payload: opaque_data
        )
      end

      # Creates a PING ACK frame
      def self.create_ping_ack(opaque_data : Bytes) : Frame
        validate_ping_data(opaque_data)
        
        Frame.new(
          type: FrameType::Ping,
          stream_id: 0,
          flags: Frame::Flags::Ack,
          payload: opaque_data
        )
      end

      # Creates a GOAWAY frame
      def self.create_goaway_frame(last_stream_id : Int32, error_code : Error::Code, debug_data : String = "") : Frame
        validate_goaway_parameters(last_stream_id, debug_data)
        
        payload = build_goaway_payload(last_stream_id, error_code, debug_data)
        validate_frame_size(payload.size)
        
        Frame.new(
          type: FrameType::GoAway,
          stream_id: 0,
          flags: Frame::Flags::None,
          payload: payload
        )
      end

      # Creates a WINDOW_UPDATE frame
      def self.create_window_update_frame(stream_id : Int32, window_size_increment : Int32) : Frame
        validate_window_update_parameters(window_size_increment)
        
        payload = build_window_update_payload(window_size_increment)
        
        Frame.new(
          type: FrameType::WindowUpdate,
          stream_id: stream_id,
          flags: Frame::Flags::None,
          payload: payload
        )
      end

      # Creates a CONTINUATION frame
      def self.create_continuation_frame(stream_id : Int32, headers_data : Bytes, flags : Frame::Flags = Frame::Flags::None) : Frame
        validate_stream_id(stream_id)
        validate_frame_size(headers_data.size)
        
        Frame.new(
          type: FrameType::Continuation,
          stream_id: stream_id,
          flags: flags,
          payload: headers_data
        )
      end

      # Private helper methods for building payloads
      private def self.build_headers_payload(headers : HTTP::Headers, priority : Priority?) : Bytes
        io = IO::Memory.new
        
        # Add priority if present
        if priority
          io.write_byte(priority.exclusive ? 0x80_u8 : 0x00_u8)
          io.write_bytes(priority.dependency_stream_id.to_u32 & 0x7fffffff_u32, IO::ByteFormat::BigEndian)
          io.write_byte((priority.weight - 1).to_u8)
        end
        
        # Add headers (encoded by HPACK)
        headers_encoded = HPACK::Encoder.new.encode(headers)
        io.write(headers_encoded)
        
        io.to_slice
      end

      private def self.build_priority_payload(exclusive : Bool, dependency_stream_id : Int32, weight : Int32) : Bytes
        io = IO::Memory.new
        io.write_byte(exclusive ? 0x80_u8 : 0x00_u8)
        io.write_bytes(dependency_stream_id.to_u32 & 0x7fffffff_u32, IO::ByteFormat::BigEndian)
        io.write_byte((weight - 1).to_u8)
        io.to_slice
      end

      private def self.build_rst_stream_payload(error_code : Error::Code) : Bytes
        io = IO::Memory.new
        io.write_bytes(error_code.to_u32, IO::ByteFormat::BigEndian)
        io.to_slice
      end

      private def self.build_settings_payload(settings : Array({Settings::Identifier, Int32})) : Bytes
        io = IO::Memory.new
        settings.each do |id, value|
          io.write_bytes(id.to_u16, IO::ByteFormat::BigEndian)
          io.write_bytes(value.to_u32, IO::ByteFormat::BigEndian)
        end
        io.to_slice
      end

      private def self.build_push_promise_payload(promised_stream_id : Int32, headers : HTTP::Headers) : Bytes
        io = IO::Memory.new
        io.write_bytes(promised_stream_id.to_u32 & 0x7fffffff_u32, IO::ByteFormat::BigEndian)
        headers_encoded = HPACK::Encoder.new.encode(headers)
        io.write(headers_encoded)
        io.to_slice
      end

      private def self.build_goaway_payload(last_stream_id : Int32, error_code : Error::Code, debug_data : String) : Bytes
        io = IO::Memory.new
        io.write_bytes(last_stream_id.to_u32 & 0x7fffffff_u32, IO::ByteFormat::BigEndian)
        io.write_bytes(error_code.to_u32, IO::ByteFormat::BigEndian)
        io.write(debug_data.to_slice)
        io.to_slice
      end

      private def self.build_window_update_payload(window_size_increment : Int32) : Bytes
        io = IO::Memory.new
        io.write_bytes(window_size_increment.to_u32 & 0x7fffffff_u32, IO::ByteFormat::BigEndian)
        io.to_slice
      end

      # Validation methods
      private def self.validate_stream_id(stream_id : Int32)
        if stream_id < 0
          raise Error.protocol_error("Invalid stream ID: #{stream_id}")
        end
      end

      private def self.validate_frame_size(size : Int32)
        if size > MAXIMUM_FRAME_SIZE
          raise Error.frame_size_error("Frame size #{size} exceeds maximum #{MAXIMUM_FRAME_SIZE}")
        end
      end

      private def self.validate_priority_parameters(exclusive : Bool, dependency_stream_id : Int32, weight : Int32)
        if dependency_stream_id < 0
          raise Error.protocol_error("Invalid dependency stream ID: #{dependency_stream_id}")
        end
        
        unless 1 <= weight <= 256
          raise Error.protocol_error("Invalid weight: #{weight}")
        end
      end

      private def self.validate_ping_data(data : Bytes)
        unless data.size == 8
          raise Error.frame_size_error("PING frame must have exactly 8 bytes")
        end
      end

      private def self.validate_goaway_parameters(last_stream_id : Int32, debug_data : String)
        if last_stream_id < 0
          raise Error.protocol_error("Invalid last stream ID: #{last_stream_id}")
        end
        
        if debug_data.bytesize > MAXIMUM_GOAWAY_DEBUG_DATA_SIZE
          raise Error.protocol_error("GOAWAY debug data too large")
        end
      end

      private def self.validate_window_update_parameters(window_size_increment : Int32)
        if window_size_increment <= 0
          raise Error.protocol_error("Window size increment must be positive")
        end
        
        if window_size_increment > MAXIMUM_WINDOW_SIZE
          raise Error.protocol_error("Window size increment too large")
        end
      end
    end
  end
end