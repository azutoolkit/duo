module Duo
  module Core
    # Manages HTTP/2 connection lifecycle and coordination
    class ConnectionManager
      private getter frame_parser : FrameParser
      private getter stream_manager : StreamManager
      private getter flow_control : FlowControlManager
      private getter hpack_manager : HPackManager
      private getter io_manager : IOManager
      private getter connection_type : Connection::Type
      private getter settings : Settings
      
      private getter connection_state : ConnectionState
      private getter error_handler : ErrorHandler

      def initialize(@io_manager, @connection_type, @settings)
        @flow_control = FlowControlManager.new(@settings.initial_window_size)
        @stream_manager = StreamManager.new(@flow_control, @connection_type, @settings.max_concurrent_streams)
        @frame_parser = FrameParser.new(@io_manager.io, @settings.max_frame_size)
        @hpack_manager = HPackManager.new(@settings.header_table_size)
        @connection_state = ConnectionState.new
        @error_handler = ErrorHandler.new(self)
      end

      # Main connection processing loop
      def process_connection
        loop do
          break if @connection_state.closed?
          
          begin
            header = @frame_parser.parse_frame_header
            payload = @frame_parser.parse_frame_payload(header)
            
            process_frame(header, payload)
          rescue ex : Error
            @error_handler.handle_error(ex)
            break
          rescue ex : IO::EOFError
            @connection_state.close
            break
          end
        end
      end

      # Processes individual frames
      private def process_frame(header : FrameHeader, payload : FramePayload)
        case payload
        when SettingsPayload
          process_settings_frame(header, payload)
        when GoAwayPayload
          process_goaway_frame(header, payload)
        when PingPayload
          process_ping_frame(header, payload)
        when WindowUpdatePayload
          process_window_update_frame(header, payload)
        else
          # Stream-level frames
          stream = @stream_manager.process_frame(header, payload)
          raise Error.protocol_error("Invalid stream") unless stream
        end
      end

      # Connection-level frame processing
      private def process_settings_frame(header : FrameHeader, payload : SettingsPayload)
        return if payload.ack?
        
        payload.settings.each do |id, value|
          @settings.update_setting(id, value)
          
          case id
          when Settings::Identifier::HeaderTableSize
            @hpack_manager.update_table_size(value)
          when Settings::Identifier::InitialWindowSize
            @flow_control.update_all_stream_windows(value - @settings.initial_window_size)
          end
        end
        
        # Send ACK
        send_settings_ack
      end

      private def process_goaway_frame(header : FrameHeader, payload : GoAwayPayload)
        @connection_state.close_with_error(payload.error_code, payload.last_stream_id)
        @stream_manager.close_streams_after(payload.last_stream_id)
      end

      private def process_ping_frame(header : FrameHeader, payload : PingPayload)
        return if payload.ack?
        send_ping_ack(payload.opaque_data)
      end

      private def process_window_update_frame(header : FrameHeader, payload : WindowUpdatePayload)
        if header.stream_id == 0
          result = @flow_control.update_connection_window(payload.window_size_increment)
          raise Error.new(result.error_code.not_nil!, 0, result.error_message) if result.error?
        else
          result = @flow_control.update_stream_window(header.stream_id, payload.window_size_increment)
          raise Error.new(result.error_code.not_nil!, header.stream_id, result.error_message) if result.error?
        end
      end

      # Sends frames through IO manager
      private def send_frame(frame : Frame)
        @io_manager.send_frame(frame)
      end

      private def send_settings_ack
        ack_frame = FrameFactory.create_settings_ack
        send_frame(ack_frame)
      end

      private def send_ping_ack(opaque_data : Bytes)
        ack_frame = FrameFactory.create_ping_ack(opaque_data)
        send_frame(ack_frame)
      end

      # Public interface for external components
      def send_goaway(error_code : Error::Code, last_stream_id : Int32, debug_data : String = "")
        goaway_frame = FrameFactory.create_goaway(last_stream_id, error_code, debug_data)
        send_frame(goaway_frame)
        @connection_state.close
      end

      def close
        @connection_state.close
        @stream_manager.close_all_streams
        @io_manager.close
      end

      # Getters for external access
      def stream_manager : StreamManager
        @stream_manager
      end

      def flow_control : FlowControlManager
        @flow_control
      end

      def hpack_manager : HPackManager
        @hpack_manager
      end

      def connection_state : ConnectionState
        @connection_state
      end
    end

    # Manages connection state
    class ConnectionState
      private getter state : State
      private getter error_code : Error::Code?
      private getter last_stream_id : Int32

      enum State
        Connecting
        Open
        Closing
        Closed
      end

      def initialize
        @state = State::Connecting
        @error_code = nil
        @last_stream_id = 0
      end

      def open!
        @state = State::Open
      end

      def close
        @state = State::Closed
      end

      def close_with_error(error_code : Error::Code, last_stream_id : Int32)
        @error_code = error_code
        @last_stream_id = last_stream_id
        @state = State::Closing
      end

      def closed? : Bool
        @state == State::Closed || @state == State::Closing
      end

      def open? : Bool
        @state == State::Open
      end
    end

    # Manages HPACK encoding/decoding
    class HPackManager
      private getter encoder : HPACK::Encoder
      private getter decoder : HPACK::Decoder
      private getter max_header_list_size : Int32

      def initialize(max_table_size : Int32, max_header_list_size : Int32 = 16384)
        @encoder = HPACK::Encoder.new
        @decoder = HPACK::Decoder.new(max_table_size)
        @max_header_list_size = max_header_list_size
      end

      def encode_headers(headers : HTTP::Headers) : Bytes
        validate_header_list_size(headers)
        @encoder.encode(headers)
      end

      def decode_headers(data : Bytes) : HTTP::Headers
        headers = @decoder.decode(data)
        validate_header_list_size(headers)
        headers
      end

      def update_table_size(new_size : Int32)
        @decoder.max_table_size = new_size
      end

      private def validate_header_list_size(headers : HTTP::Headers)
        total_size = headers.sum { |name, value| name.bytesize + value.bytesize }
        if total_size > @max_header_list_size
          raise Error.protocol_error("Header list size #{total_size} exceeds maximum #{@max_header_list_size}")
        end
      end
    end

    # Manages IO operations
    class IOManager
      getter io : IO
      private getter frame_writer : FrameWriter
      private getter buffer_pool : BufferPool

      def initialize(@io)
        @frame_writer = FrameWriter.new(@io)
        @buffer_pool = BufferPool.new
      end

      def send_frame(frame : Frame)
        @frame_writer.write_frame(frame)
      end

      def close
        @io.close unless @io.closed?
      end
    end

    # Handles errors according to HTTP/2 specification
    class ErrorHandler
      private getter connection_manager : ConnectionManager

      def initialize(@connection_manager)
      end

      def handle_error(error : Error)
        case error.code
        when Error::Code::ProtocolError, Error::Code::FrameSizeError, Error::Code::CompressionError
          # Connection-level errors - send GOAWAY and close
          @connection_manager.send_goaway(error.code, 0, error.message)
        when Error::Code::FlowControlError
          # Flow control errors - send GOAWAY
          @connection_manager.send_goaway(error.code, 0, "Flow control error")
        else
          # Stream-level errors - send RST_STREAM if possible
          if error.last_stream_id > 0
            stream = @connection_manager.stream_manager.find_stream(error.last_stream_id, create: false)
            stream.try(&.send_rst_stream(error.code))
          end
        end
      end
    end
  end
end