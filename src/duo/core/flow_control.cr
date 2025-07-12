module Duo
  module Core
    # Manages HTTP/2 flow control according to RFC 9113 Section 6.9
    class FlowControlManager
      private getter connection_window_size : Atomic(Int32)
      private getter stream_windows : Hash(Int32, Atomic(Int32))
      private getter mutex : Mutex

      def initialize(initial_window_size : Int32 = DEFAULT_INITIAL_WINDOW_SIZE)
        @connection_window_size = Atomic(Int32).new(initial_window_size)
        @stream_windows = {} of Int32 => Atomic(Int32)
        @mutex = Mutex.new
      end

      # Registers a new stream with flow control
      def register_stream(stream_id : Int32, initial_window_size : Int32 = DEFAULT_INITIAL_WINDOW_SIZE)
        @mutex.synchronize do
          @stream_windows[stream_id] = Atomic(Int32).new(initial_window_size)
        end
      end

      # Unregisters a stream from flow control
      def unregister_stream(stream_id : Int32)
        @mutex.synchronize do
          @stream_windows.delete(stream_id)
        end
      end

      # Updates connection-level window size
      def update_connection_window(increment : Int32) : FlowControlResult
        validate_window_increment(increment, "connection")
        
        current = @connection_window_size.get
        new_size = current.to_i64 + increment
        
        if new_size > MAXIMUM_WINDOW_SIZE
          return FlowControlResult.error(
            Error::Code::FlowControlError,
            "Connection window size #{new_size} exceeds maximum #{MAXIMUM_WINDOW_SIZE}"
          )
        end
        
        @connection_window_size.add(increment)
        FlowControlResult.success
      end

      # Updates stream-level window size
      def update_stream_window(stream_id : Int32, increment : Int32) : FlowControlResult
        validate_window_increment(increment, "stream")
        
        window = get_stream_window(stream_id)
        return FlowControlResult.error(Error::Code::ProtocolError, "Stream #{stream_id} not found") unless window
        
        current = window.get
        new_size = current.to_i64 + increment
        
        if new_size > MAXIMUM_WINDOW_SIZE
          return FlowControlResult.error(
            Error::Code::FlowControlError,
            "Stream #{stream_id} window size #{new_size} exceeds maximum #{MAXIMUM_WINDOW_SIZE}"
          )
        end
        
        window.add(increment)
        FlowControlResult.success
      end

      # Consumes connection-level window space
      def consume_connection_window(size : Int32) : Bool
        current = @connection_window_size.get
        return false if current < size
        
        @connection_window_size.sub(size)
        true
      end

      # Consumes stream-level window space
      def consume_stream_window(stream_id : Int32, size : Int32) : Bool
        window = get_stream_window(stream_id)
        return false unless window
        
        current = window.get
        return false if current < size
        
        window.sub(size)
        true
      end

      # Gets current connection window size
      def connection_window_size : Int32
        @connection_window_size.get
      end

      # Gets current stream window size
      def stream_window_size(stream_id : Int32) : Int32?
        window = get_stream_window(stream_id)
        window.try(&.get)
      end

      # Checks if connection has available window space
      def connection_available?(size : Int32) : Bool
        @connection_window_size.get >= size
      end

      # Checks if stream has available window space
      def stream_available?(stream_id : Int32, size : Int32) : Bool
        window = get_stream_window(stream_id)
        return false unless window
        window.get >= size
      end

      # Updates all stream windows when connection settings change
      def update_all_stream_windows(delta : Int32)
        return if delta == 0
        
        @mutex.synchronize do
          @stream_windows.each do |stream_id, window|
            current = window.get
            new_size = current.to_i64 + delta
            
            if new_size > MAXIMUM_WINDOW_SIZE
              # This should trigger a flow control error
              raise Error.flow_control_error("Stream #{stream_id} window size #{new_size} exceeds maximum")
            elsif new_size < 0
              # This should trigger a flow control error
              raise Error.flow_control_error("Stream #{stream_id} window size #{new_size} is negative")
            else
              window.set(new_size.to_i32)
            end
          end
        end
      end

      # Gets the minimum available window size across all streams
      def min_stream_window_size : Int32
        @mutex.synchronize do
          return 0 if @stream_windows.empty?
          @stream_windows.values.map(&.get).min
        end
      end

      # Calculates optimal window update increment for connection
      def calculate_connection_window_update : Int32
        current = @connection_window_size.get
        initial = DEFAULT_INITIAL_WINDOW_SIZE
        
        if current < (initial // 2)
          increment = Math.min(initial * active_stream_count, MAXIMUM_WINDOW_SIZE)
          increment
        else
          0
        end
      end

      # Calculates optimal window update increment for stream
      def calculate_stream_window_update(stream_id : Int32) : Int32
        window = get_stream_window(stream_id)
        return 0 unless window
        
        current = window.get
        initial = DEFAULT_INITIAL_WINDOW_SIZE
        
        if current < (initial // 2)
          increment = initial // 2
          increment
        else
          0
        end
      end

      private def get_stream_window(stream_id : Int32) : Atomic(Int32)?
        @mutex.synchronize do
          @stream_windows[stream_id]?
        end
      end

      private def active_stream_count : Int32
        @mutex.synchronize do
          @stream_windows.size
        end
      end

      private def validate_window_increment(increment : Int32, context : String)
        if increment == 0
          raise Error.protocol_error("#{context.capitalize} WINDOW_UPDATE with 0 increment")
        end
        
        unless MINIMUM_WINDOW_SIZE <= increment <= MAXIMUM_WINDOW_SIZE
          raise Error.protocol_error("Invalid #{context} window increment: #{increment}")
        end
      end
    end

    # Result of flow control operations
    struct FlowControlResult
      getter success : Bool
      getter error_code : Error::Code?
      getter error_message : String?

      def initialize(@success, @error_code = nil, @error_message = nil)
      end

      def self.success
        new(true)
      end

      def self.error(code : Error::Code, message : String)
        new(false, code, message)
      end

      def error?
        !@success
      end
    end
  end
end