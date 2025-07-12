module Duo
  module Core
    # Handles writing HTTP/2 frames to IO according to RFC 9113 Section 4.1
    class FrameWriter
      private getter io : IO
      private getter buffer_pool : BufferPool
      private getter max_frame_size : Int32

      def initialize(@io, @max_frame_size = DEFAULT_MAX_FRAME_SIZE)
        @buffer_pool = BufferPool.new
      end

      # Writes a frame to the underlying IO
      def write_frame(frame : Frame)
        validate_frame(frame)
        
        # Get buffer from pool
        buffer = @buffer_pool.acquire
        
        begin
          # Serialize frame to buffer
          serialized = serialize_frame(frame, buffer)
          
          # Write to IO
          @io.write(serialized)
          @io.flush
        ensure
          # Return buffer to pool
          @buffer_pool.release(buffer)
        end
      end

      # Writes multiple frames efficiently
      def write_frames(frames : Array(Frame))
        frames.each { |frame| validate_frame(frame) }
        
        # Get buffer from pool
        buffer = @buffer_pool.acquire
        
        begin
          frames.each do |frame|
            serialized = serialize_frame(frame, buffer)
            @io.write(serialized)
          end
          
          @io.flush
        ensure
          @buffer_pool.release(buffer)
        end
      end

      # Serializes a frame to bytes
      private def serialize_frame(frame : Frame, buffer : IO::Memory) : Bytes
        buffer.clear
        
        # Write frame header (9 bytes)
        write_frame_header(buffer, frame)
        
        # Write payload if present
        if payload = frame.payload?
          buffer.write(payload)
        end
        
        buffer.to_slice
      end

      # Writes frame header according to RFC 9113 Section 4.1
      private def write_frame_header(buffer : IO::Memory, frame : Frame)
        payload_size = frame.payload?.try(&.size) || 0
        
        # Length (24 bits) and Type (8 bits)
        buffer.write_bytes((payload_size.to_u32 << 8) | frame.type.to_u8, IO::ByteFormat::BigEndian)
        
        # Flags (8 bits)
        buffer.write_byte(frame.flags.to_u8)
        
        # Stream ID (31 bits, with reserved bit)
        buffer.write_bytes(frame.stream_id.to_u32 & 0x7fffffff_u32, IO::ByteFormat::BigEndian)
      end

      # Validates frame before writing
      private def validate_frame(frame : Frame)
        # Validate stream ID
        if frame.stream_id < 0
          raise Error.protocol_error("Frame has negative stream ID: #{frame.stream_id}")
        end
        
        # Validate frame size
        payload_size = frame.payload?.try(&.size) || 0
        if payload_size > @max_frame_size
          raise Error.frame_size_error("Frame payload size #{payload_size} exceeds maximum #{@max_frame_size}")
        end
        
        # Validate frame type specific constraints
        validate_frame_type_constraints(frame)
      end

      # Validates frame type specific constraints
      private def validate_frame_type_constraints(frame : Frame)
        case frame.type
        when FrameType::Data
          validate_data_frame(frame)
        when FrameType::Headers
          validate_headers_frame(frame)
        when FrameType::Priority
          validate_priority_frame(frame)
        when FrameType::RstStream
          validate_rst_stream_frame(frame)
        when FrameType::Settings
          validate_settings_frame(frame)
        when FrameType::PushPromise
          validate_push_promise_frame(frame)
        when FrameType::Ping
          validate_ping_frame(frame)
        when FrameType::GoAway
          validate_goaway_frame(frame)
        when FrameType::WindowUpdate
          validate_window_update_frame(frame)
        when FrameType::Continuation
          validate_continuation_frame(frame)
        end
      end

      private def validate_data_frame(frame : Frame)
        # DATA frames cannot be sent on stream 0
        if frame.stream_id == 0
          raise Error.protocol_error("DATA frame cannot be sent on stream 0")
        end
      end

      private def validate_headers_frame(frame : Frame)
        # HEADERS frames cannot be sent on stream 0
        if frame.stream_id == 0
          raise Error.protocol_error("HEADERS frame cannot be sent on stream 0")
        end
      end

      private def validate_priority_frame(frame : Frame)
        # PRIORITY frames cannot be sent on stream 0
        if frame.stream_id == 0
          raise Error.protocol_error("PRIORITY frame cannot be sent on stream 0")
        end
        
        # PRIORITY frame must have exactly 5 bytes of payload
        payload_size = frame.payload?.try(&.size) || 0
        if payload_size != 5
          raise Error.frame_size_error("PRIORITY frame must have exactly 5 bytes")
        end
      end

      private def validate_rst_stream_frame(frame : Frame)
        # RST_STREAM frames cannot be sent on stream 0
        if frame.stream_id == 0
          raise Error.protocol_error("RST_STREAM frame cannot be sent on stream 0")
        end
        
        # RST_STREAM frame must have exactly 4 bytes of payload
        payload_size = frame.payload?.try(&.size) || 0
        if payload_size != 4
          raise Error.frame_size_error("RST_STREAM frame must have exactly 4 bytes")
        end
      end

      private def validate_settings_frame(frame : Frame)
        # SETTINGS frames must be sent on stream 0
        if frame.stream_id != 0
          raise Error.protocol_error("SETTINGS frame must be sent on stream 0")
        end
        
        # SETTINGS frame payload must be multiple of 6 bytes
        payload_size = frame.payload?.try(&.size) || 0
        if payload_size % 6 != 0
          raise Error.frame_size_error("SETTINGS frame payload must be multiple of 6 bytes")
        end
      end

      private def validate_push_promise_frame(frame : Frame)
        # PUSH_PROMISE frames cannot be sent on stream 0
        if frame.stream_id == 0
          raise Error.protocol_error("PUSH_PROMISE frame cannot be sent on stream 0")
        end
        
        # PUSH_PROMISE frame must have at least 4 bytes (promised stream ID)
        payload_size = frame.payload?.try(&.size) || 0
        if payload_size < 4
          raise Error.frame_size_error("PUSH_PROMISE frame must have at least 4 bytes")
        end
      end

      private def validate_ping_frame(frame : Frame)
        # PING frames must be sent on stream 0
        if frame.stream_id != 0
          raise Error.protocol_error("PING frame must be sent on stream 0")
        end
        
        # PING frame must have exactly 8 bytes of payload
        payload_size = frame.payload?.try(&.size) || 0
        if payload_size != 8
          raise Error.frame_size_error("PING frame must have exactly 8 bytes")
        end
      end

      private def validate_goaway_frame(frame : Frame)
        # GOAWAY frames must be sent on stream 0
        if frame.stream_id != 0
          raise Error.protocol_error("GOAWAY frame must be sent on stream 0")
        end
        
        # GOAWAY frame must have at least 8 bytes (last stream ID + error code)
        payload_size = frame.payload?.try(&.size) || 0
        if payload_size < 8
          raise Error.frame_size_error("GOAWAY frame must have at least 8 bytes")
        end
      end

      private def validate_window_update_frame(frame : Frame)
        # WINDOW_UPDATE frame must have exactly 4 bytes of payload
        payload_size = frame.payload?.try(&.size) || 0
        if payload_size != 4
          raise Error.frame_size_error("WINDOW_UPDATE frame must have exactly 4 bytes")
        end
      end

      private def validate_continuation_frame(frame : Frame)
        # CONTINUATION frames cannot be sent on stream 0
        if frame.stream_id == 0
          raise Error.protocol_error("CONTINUATION frame cannot be sent on stream 0")
        end
      end
    end

    # Buffer pool for efficient memory management
    class BufferPool
      private getter buffers : Array(IO::Memory)
      private getter mutex : Mutex
      private getter max_pool_size : Int32

      def initialize(@max_pool_size = 10)
        @buffers = [] of IO::Memory
        @mutex = Mutex.new
      end

      # Acquires a buffer from the pool
      def acquire : IO::Memory
        @mutex.synchronize do
          if buffer = @buffers.pop?
            buffer
          else
            IO::Memory.new(4096) # Default buffer size
          end
        end
      end

      # Releases a buffer back to the pool
      def release(buffer : IO::Memory)
        @mutex.synchronize do
          if @buffers.size < @max_pool_size
            buffer.clear
            @buffers << buffer
          end
        end
      end

      # Clears all buffers in the pool
      def clear
        @mutex.synchronize do
          @buffers.clear
        end
      end
    end
  end
end