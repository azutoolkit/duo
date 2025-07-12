module Duo
  module Core
    # Manages HTTP/2 stream lifecycle according to RFC 9113 Section 5.1
    class StreamManager
      private getter streams : Hash(Int32, Stream)
      private getter mutex : Mutex
      private getter flow_control : FlowControlManager
      private getter connection_type : Connection::Type
      private getter max_concurrent_streams : Int32
      private getter highest_remote_id : Int32
      private getter id_counter : Int32

      def initialize(@flow_control, @connection_type, @max_concurrent_streams)
        @streams = {} of Int32 => Stream
        @mutex = Mutex.new
        @highest_remote_id = 0
        @id_counter = @connection_type.server? ? 0 : -1
      end

      # Finds or creates a stream by ID
      def find_stream(id : Int32, create : Bool = true) : Stream?
        @mutex.synchronize do
          if stream = @streams[id]?
            return stream
          end

          return nil unless create

          # Validate stream ID
          unless valid_stream_id?(id)
            raise Error.protocol_error("Invalid stream ID: #{id}")
          end

          # Check concurrent stream limits
          if active_incoming_stream_count >= @max_concurrent_streams
            raise Error.refused_stream("Maximum concurrent streams reached")
          end

          # Update highest remote ID for incoming streams
          if id > @highest_remote_id && incoming_stream?(id)
            @highest_remote_id = id
          end

          # Create new stream
          stream = Stream.new(id, @connection_type)
          @streams[id] = stream
          
          # Register with flow control
          @flow_control.register_stream(id)
          
          stream
        end
      end

      # Creates a new outgoing stream
      def create_stream(initial_state : State = State::Idle) : Stream
        @mutex.synchronize do
          if active_outgoing_stream_count >= @max_concurrent_streams
            raise Error.internal_error("Maximum outgoing stream capacity reached")
          end

          id = @id_counter += 2
          
          if @streams[id]?
            raise Error.internal_error("Stream #{id} already exists")
          end

          stream = Stream.new(id, @connection_type, initial_state)
          @streams[id] = stream
          
          # Register with flow control
          @flow_control.register_stream(id)
          
          stream
        end
      end

      # Removes a stream from management
      def remove_stream(id : Int32)
        @mutex.synchronize do
          if stream = @streams.delete(id)
            # Unregister from flow control
            @flow_control.unregister_stream(id)
            
            # Clean up stream resources
            stream.cleanup
          end
        end
      end

      # Gets all active streams
      def active_streams : Array(Stream)
        @mutex.synchronize do
          @streams.values.select(&.active?)
        end
      end

      # Gets all streams
      def all_streams : Array(Stream)
        @mutex.synchronize do
          @streams.values
        end
      end

      # Counts active incoming streams
      def active_incoming_stream_count : Int32
        @mutex.synchronize do
          @streams.values.count { |s| incoming_stream?(s.id) && s.active? }
        end
      end

      # Counts active outgoing streams
      def active_outgoing_stream_count : Int32
        @mutex.synchronize do
          @streams.values.count { |s| outgoing_stream?(s.id) && s.active? }
        end
      end

      # Gets the highest stream ID
      def highest_stream_id : Int32
        @mutex.synchronize do
          @streams.keys.max? || 0
        end
      end

      # Validates if a stream ID is valid for the current connection
      def valid_stream_id?(id : Int32) : Bool
        return true if id == 0 # Connection-level frames
        
        # Check if it's a valid incoming stream ID
        if incoming_stream?(id)
          return id >= @highest_remote_id || @streams[id]?
        end
        
        # Check if it's a valid outgoing stream ID
        if outgoing_stream?(id)
          return @streams[id]?
        end
        
        false
      end

      # Checks if a stream ID represents an incoming stream
      def incoming_stream?(id : Int32) : Bool
        (@connection_type.server? && id.odd?) || (@connection_type.client? && id.even?)
      end

      # Checks if a stream ID represents an outgoing stream
      def outgoing_stream?(id : Int32) : Bool
        (@connection_type.server? && id.even?) || (@connection_type.client? && id.odd?)
      end

      # Updates max concurrent streams setting
      def update_max_concurrent_streams(new_max : Int32)
        @mutex.synchronize do
          @max_concurrent_streams = new_max
        end
      end

      # Closes all streams
      def close_all_streams
        @mutex.synchronize do
          @streams.values.each(&.close)
          @streams.clear
        end
      end

      # Gets streams that need window updates
      def streams_needing_window_updates : Array(Stream)
        @mutex.synchronize do
          @streams.values.select do |stream|
            window_size = @flow_control.stream_window_size(stream.id)
            window_size && window_size < (DEFAULT_INITIAL_WINDOW_SIZE // 2)
          end
        end
      end

      # Processes a frame for a stream
      def process_frame(header : Core::FrameHeader, payload : Core::FramePayload) : Stream?
        stream = find_stream(header.stream_id, create: !header.type.priority?)
        return nil unless stream

        # Handle priority frames for non-existent streams
        if header.type.priority? && !stream
          # Priority frames can be sent for streams that don't exist yet
          return nil
        end

        # Process frame based on type
        case payload
        when Core::DataPayload
          process_data_frame(stream, header, payload)
        when Core::HeadersPayload
          process_headers_frame(stream, header, payload)
        when Core::PriorityPayload
          process_priority_frame(stream, payload)
        when Core::RstStreamPayload
          process_rst_stream_frame(stream, payload)
        when Core::WindowUpdatePayload
          process_window_update_frame(stream, payload)
        when Core::PushPromisePayload
          process_push_promise_frame(stream, header, payload)
        end

        stream
      end

      private def process_data_frame(stream : Stream, header : Core::FrameHeader, payload : Core::DataPayload)
        # Validate stream state
        unless stream.state.can_receive_data?
          raise Error.stream_closed("Stream #{stream.id} cannot receive data in state #{stream.state}")
        end

        # Check flow control
        unless @flow_control.stream_available?(stream.id, payload.data.size)
          raise Error.flow_control_error("Insufficient stream window space")
        end

        # Consume window space
        @flow_control.consume_stream_window(stream.id, payload.data.size)

        # Add data to stream
        stream.add_data(payload.data)

        # Update stream state
        if header.flags.end_stream?
          stream.state = stream.state.transition_to_half_closed_remote
        end
      end

      private def process_headers_frame(stream : Stream, header : Core::FrameHeader, payload : Core::HeadersPayload)
        # Validate stream state
        unless stream.state.can_receive_headers?
          raise Error.stream_closed("Stream #{stream.id} cannot receive headers in state #{stream.state}")
        end

        # Set priority if present
        if priority = payload.priority
          stream.priority = priority
        end

        # Decode headers
        headers = HPack.decoder.decode(payload.headers_data)
        stream.add_headers(headers)

        # Update stream state
        if header.flags.end_stream?
          stream.state = stream.state.transition_to_half_closed_remote
        else
          stream.state = stream.state.transition_to_open
        end
      end

      private def process_priority_frame(stream : Stream, payload : Core::PriorityPayload)
        # Priority frames can be sent on any stream, including non-existent ones
        stream.priority = Priority.new(payload.exclusive, payload.dependency_stream_id, payload.weight)
      end

      private def process_rst_stream_frame(stream : Stream, payload : Core::RstStreamPayload)
        stream.state = State::Closed
        stream.error_code = payload.error_code
        remove_stream(stream.id)
      end

      private def process_window_update_frame(stream : Stream, payload : Core::WindowUpdatePayload)
        result = if stream.id == 0
          @flow_control.update_connection_window(payload.window_size_increment)
        else
          @flow_control.update_stream_window(stream.id, payload.window_size_increment)
        end

        if result.error?
          raise Error.new(result.error_code.not_nil!, stream.id, result.error_message)
        end
      end

      private def process_push_promise_frame(stream : Stream, header : Core::FrameHeader, payload : Core::PushPromisePayload)
        # Validate push promise
        unless @connection_type.server?
          raise Error.protocol_error("Client cannot receive push promises")
        end

        # Create promised stream
        promised_stream = create_stream(State::ReservedRemote)
        promised_stream.add_headers(HPack.decoder.decode(payload.headers_data))
      end
    end

    # Enhanced Stream class with better state management
    class Stream
      getter id : Int32
      getter state : State
      property priority : Priority
      property error_code : Error::Code?
      
      private getter connection_type : Connection::Type
      private getter headers : HTTP::Headers
      private getter data_buffer : IO::Memory
      private getter created_at : Time

      def initialize(@id, @connection_type, @state = State::Idle, @priority = DEFAULT_PRIORITY.dup)
        @headers = HTTP::Headers.new
        @data_buffer = IO::Memory.new
        @created_at = Time.utc
      end

      def active? : Bool
        @state.active?
      end

      def closed? : Bool
        @state.closed?
      end

      def add_headers(headers : HTTP::Headers)
        headers.each do |name, value|
          @headers.add(name, value)
        end
      end

      def add_data(data : Bytes)
        @data_buffer.write(data)
      end

      def cleanup
        @data_buffer.close
      end

      def close
        @state = State::Closed
        cleanup
      end

      def data_size : Int32
        @data_buffer.size
      end

      def headers : HTTP::Headers
        @headers.dup
      end

      def data : Bytes
        @data_buffer.to_slice
      end
    end

    # Enhanced State enum with transition methods
    enum State
      Idle
      ReservedLocal
      ReservedRemote
      Open
      HalfClosedLocal
      HalfClosedRemote
      Closed

      def active? : Bool
        open? || half_closed_local? || half_closed_remote?
      end

      def closed? : Bool
        self == Closed
      end

      def can_receive_headers? : Bool
        case self
        when Idle, ReservedRemote
          true
        when Open, HalfClosedRemote
          true
        else
          false
        end
      end

      def can_receive_data? : Bool
        case self
        when Open, HalfClosedRemote
          true
        else
          false
        end
      end

      def can_send_headers? : Bool
        case self
        when Idle, ReservedLocal, Open, HalfClosedRemote
          true
        else
          false
        end
      end

      def can_send_data? : Bool
        case self
        when Open, HalfClosedLocal
          true
        else
          false
        end
      end

      def transition_to_open : State
        case self
        when Idle
          Open
        else
          self
        end
      end

      def transition_to_half_closed_local : State
        case self
        when Open
          HalfClosedLocal
        else
          self
        end
      end

      def transition_to_half_closed_remote : State
        case self
        when Idle, Open
          HalfClosedRemote
        else
          self
        end
      end

      def transition_to_closed : State
        Closed
      end
    end
  end
end