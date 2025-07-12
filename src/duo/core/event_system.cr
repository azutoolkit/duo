module Duo
  module Core
    # Event system for HTTP/2 connection and stream lifecycle management
    class EventSystem
      private getter listeners : Hash(EventType, Array(EventListener))
      private getter event_history : Array(Event)
      private getter mutex : Mutex
      private getter max_history_size : Int32

      def initialize(@max_history_size = 1000)
        @listeners = {} of EventType => Array(EventListener)
        @event_history = [] of Event
        @mutex = Mutex.new
      end

      # Registers an event listener
      def subscribe(event_type : EventType, listener : EventListener)
        @mutex.synchronize do
          @listeners[event_type] ||= [] of EventListener
          @listeners[event_type] << listener
        end
      end

      # Unregisters an event listener
      def unsubscribe(event_type : EventType, listener : EventListener)
        @mutex.synchronize do
          if listeners = @listeners[event_type]?
            listeners.delete(listener)
          end
        end
      end

      # Publishes an event to all registered listeners
      def publish(event : Event)
        @mutex.synchronize do
          # Add to history
          add_to_history(event)
          
          # Notify listeners
          if listeners = @listeners[event.type]?
            listeners.each do |listener|
              begin
                listener.on_event(event)
              rescue ex : Exception
                # Log error but don't fail the event system
                Log.error { "Event listener error: #{ex.message}" }
              end
            end
          end
        end
      end

      # Gets recent events for debugging/monitoring
      def recent_events(limit : Int32 = 100) : Array(Event)
        @mutex.synchronize do
          @event_history.last(limit)
        end
      end

      # Gets events for a specific stream
      def stream_events(stream_id : Int32) : Array(Event)
        @mutex.synchronize do
          @event_history.select { |event| event.stream_id == stream_id }
        end
      end

      # Clears event history
      def clear_history
        @mutex.synchronize do
          @event_history.clear
        end
      end

      private def add_to_history(event : Event)
        @event_history << event
        
        # Maintain history size limit
        if @event_history.size > @max_history_size
          @event_history.shift(@event_history.size - @max_history_size)
        end
      end
    end

    # Event types for HTTP/2 lifecycle
    enum EventType
      # Connection events
      ConnectionEstablished
      ConnectionClosed
      ConnectionError
      
      # Stream events
      StreamCreated
      StreamOpened
      StreamHalfClosedLocal
      StreamHalfClosedRemote
      StreamClosed
      StreamError
      
      # Frame events
      FrameReceived
      FrameSent
      FrameError
      
      # Flow control events
      WindowUpdate
      FlowControlBlocked
      FlowControlUnblocked
      
      # Priority events
      PriorityUpdated
      
      # Settings events
      SettingsReceived
      SettingsAcknowledged
      
      # Error events
      ProtocolError
      CompressionError
      FlowControlError
    end

    # Base event class
    abstract class Event
      getter type : EventType
      getter timestamp : Time
      getter stream_id : Int32
      getter connection_id : String

      def initialize(@type, @stream_id, @connection_id)
        @timestamp = Time.utc
      end

      abstract def to_s : String
    end

    # Connection events
    class ConnectionEstablishedEvent < Event
      def initialize(connection_id : String)
        super(EventType::ConnectionEstablished, 0, connection_id)
      end

      def to_s : String
        "Connection #{@connection_id} established at #{@timestamp}"
      end
    end

    class ConnectionClosedEvent < Event
      getter error_code : Error::Code?
      getter reason : String?

      def initialize(connection_id : String, @error_code = nil, @reason = nil)
        super(EventType::ConnectionClosed, 0, connection_id)
      end

      def to_s : String
        if @error_code
          "Connection #{@connection_id} closed with error #{@error_code} at #{@timestamp}"
        else
          "Connection #{@connection_id} closed normally at #{@timestamp}"
        end
      end
    end

    class ConnectionErrorEvent < Event
      getter error : Error

      def initialize(connection_id : String, @error)
        super(EventType::ConnectionError, 0, connection_id)
      end

      def to_s : String
        "Connection #{@connection_id} error: #{@error.message} at #{@timestamp}"
      end
    end

    # Stream events
    class StreamCreatedEvent < Event
      getter initial_state : State

      def initialize(connection_id : String, stream_id : Int32, @initial_state)
        super(EventType::StreamCreated, stream_id, connection_id)
      end

      def to_s : String
        "Stream #{@stream_id} created in state #{@initial_state} at #{@timestamp}"
      end
    end

    class StreamStateChangedEvent < Event
      getter old_state : State
      getter new_state : State
      getter reason : String?

      def initialize(connection_id : String, stream_id : Int32, @old_state, @new_state, @reason = nil)
        super(EventType::StreamOpened, stream_id, connection_id)
      end

      def to_s : String
        if @reason
          "Stream #{@stream_id} changed from #{@old_state} to #{@new_state} (#{@reason}) at #{@timestamp}"
        else
          "Stream #{@stream_id} changed from #{@old_state} to #{@new_state} at #{@timestamp}"
        end
      end
    end

    class StreamClosedEvent < Event
      getter error_code : Error::Code?

      def initialize(connection_id : String, stream_id : Int32, @error_code = nil)
        super(EventType::StreamClosed, stream_id, connection_id)
      end

      def to_s : String
        if @error_code
          "Stream #{@stream_id} closed with error #{@error_code} at #{@timestamp}"
        else
          "Stream #{@stream_id} closed normally at #{@timestamp}"
        end
      end
    end

    class StreamErrorEvent < Event
      getter error : Error

      def initialize(connection_id : String, stream_id : Int32, @error)
        super(EventType::StreamError, stream_id, connection_id)
      end

      def to_s : String
        "Stream #{@stream_id} error: #{@error.message} at #{@timestamp}"
      end
    end

    # Frame events
    class FrameEvent < Event
      getter frame_type : FrameType
      getter frame_size : Int32
      getter flags : Frame::Flags

      def initialize(event_type : EventType, connection_id : String, stream_id : Int32, @frame_type, @frame_size, @flags)
        super(event_type, stream_id, connection_id)
      end

      def to_s : String
        "#{@type} #{@frame_type} frame (size: #{@frame_size}, flags: #{@flags}) for stream #{@stream_id} at #{@timestamp}"
      end
    end

    class FrameReceivedEvent < FrameEvent
      def initialize(connection_id : String, stream_id : Int32, frame_type : FrameType, frame_size : Int32, flags : Frame::Flags)
        super(EventType::FrameReceived, connection_id, stream_id, frame_type, frame_size, flags)
      end
    end

    class FrameSentEvent < FrameEvent
      def initialize(connection_id : String, stream_id : Int32, frame_type : FrameType, frame_size : Int32, flags : Frame::Flags)
        super(EventType::FrameSent, connection_id, stream_id, frame_type, frame_size, flags)
      end
    end

    class FrameErrorEvent < Event
      getter frame_type : FrameType
      getter error : Error

      def initialize(connection_id : String, stream_id : Int32, @frame_type, @error)
        super(EventType::FrameError, stream_id, connection_id)
      end

      def to_s : String
        "Frame error for #{@frame_type} frame on stream #{@stream_id}: #{@error.message} at #{@timestamp}"
      end
    end

    # Flow control events
    class WindowUpdateEvent < Event
      getter increment : Int32
      getter new_window_size : Int32

      def initialize(connection_id : String, stream_id : Int32, @increment, @new_window_size)
        super(EventType::WindowUpdate, stream_id, connection_id)
      end

      def to_s : String
        "Window update for stream #{@stream_id}: +#{@increment} = #{@new_window_size} at #{@timestamp}"
      end
    end

    class FlowControlBlockedEvent < Event
      getter reason : String

      def initialize(connection_id : String, stream_id : Int32, @reason)
        super(EventType::FlowControlBlocked, stream_id, connection_id)
      end

      def to_s : String
        "Stream #{@stream_id} blocked: #{@reason} at #{@timestamp}"
      end
    end

    class FlowControlUnblockedEvent < Event
      def initialize(connection_id : String, stream_id : Int32)
        super(EventType::FlowControlUnblocked, stream_id, connection_id)
      end

      def to_s : String
        "Stream #{@stream_id} unblocked at #{@timestamp}"
      end
    end

    # Priority events
    class PriorityUpdatedEvent < Event
      getter exclusive : Bool
      getter dependency_stream_id : Int32
      getter weight : Int32

      def initialize(connection_id : String, stream_id : Int32, @exclusive, @dependency_stream_id, @weight)
        super(EventType::PriorityUpdated, stream_id, connection_id)
      end

      def to_s : String
        "Stream #{@stream_id} priority updated: exclusive=#{@exclusive}, dependency=#{@dependency_stream_id}, weight=#{@weight} at #{@timestamp}"
      end
    end

    # Settings events
    class SettingsReceivedEvent < Event
      getter settings : Array({Settings::Identifier, Int32})

      def initialize(connection_id : String, @settings)
        super(EventType::SettingsReceived, 0, connection_id)
      end

      def to_s : String
        "Settings received: #{@settings.map { |id, value| "#{id}=#{value}" }.join(", ")} at #{@timestamp}"
      end
    end

    class SettingsAcknowledgedEvent < Event
      def initialize(connection_id : String)
        super(EventType::SettingsAcknowledged, 0, connection_id)
      end

      def to_s : String
        "Settings acknowledged at #{@timestamp}"
      end
    end

    # Error events
    class ProtocolErrorEvent < Event
      getter error : Error

      def initialize(connection_id : String, stream_id : Int32, @error)
        super(EventType::ProtocolError, stream_id, connection_id)
      end

      def to_s : String
        "Protocol error on stream #{@stream_id}: #{@error.message} at #{@timestamp}"
      end
    end

    class CompressionErrorEvent < Event
      getter error : Error

      def initialize(connection_id : String, stream_id : Int32, @error)
        super(EventType::CompressionError, stream_id, connection_id)
      end

      def to_s : String
        "Compression error on stream #{@stream_id}: #{@error.message} at #{@timestamp}"
      end
    end

    class FlowControlErrorEvent < Event
      getter error : Error

      def initialize(connection_id : String, stream_id : Int32, @error)
        super(EventType::FlowControlError, stream_id, connection_id)
      end

      def to_s : String
        "Flow control error on stream #{@stream_id}: #{@error.message} at #{@timestamp}"
      end
    end

    # Event listener interface
    abstract class EventListener
      abstract def on_event(event : Event)
    end

    # Built-in event listeners
    class LoggingEventListener < EventListener
      def on_event(event : Event)
        case event.type
        when EventType::ConnectionError, EventType::StreamError, EventType::FrameError, EventType::ProtocolError, EventType::CompressionError, EventType::FlowControlError
          Log.error { event.to_s }
        when EventType::ConnectionEstablished, EventType::ConnectionClosed
          Log.info { event.to_s }
        else
          Log.debug { event.to_s }
        end
      end
    end

    class MetricsEventListener < EventListener
      private getter metrics : MetricsCollector

      def initialize(@metrics)
      end

      def on_event(event : Event)
        case event.type
        when EventType::ConnectionEstablished
          @metrics.increment_connection_count
        when EventType::ConnectionClosed
          @metrics.decrement_connection_count
        when EventType::StreamCreated
          @metrics.increment_stream_count
        when EventType::StreamClosed
          @metrics.decrement_stream_count
        when EventType::FrameReceived
          @metrics.increment_frames_received
        when EventType::FrameSent
          @metrics.increment_frames_sent
        when EventType::WindowUpdate
          @metrics.record_window_update(event.as(WindowUpdateEvent).increment)
        end
      end
    end

    # Metrics collector for monitoring
    class MetricsCollector
      private getter connection_count : Atomic(Int32)
      private getter stream_count : Atomic(Int32)
      private getter frames_received : Atomic(Int32)
      private getter frames_sent : Atomic(Int32)
      private getter window_updates : Atomic(Int32)
      private getter start_time : Time

      def initialize
        @connection_count = Atomic(Int32).new(0)
        @stream_count = Atomic(Int32).new(0)
        @frames_received = Atomic(Int32).new(0)
        @frames_sent = Atomic(Int32).new(0)
        @window_updates = Atomic(Int32).new(0)
        @start_time = Time.utc
      end

      def increment_connection_count
        @connection_count.add(1)
      end

      def decrement_connection_count
        @connection_count.sub(1)
      end

      def increment_stream_count
        @stream_count.add(1)
      end

      def decrement_stream_count
        @stream_count.sub(1)
      end

      def increment_frames_received
        @frames_received.add(1)
      end

      def increment_frames_sent
        @frames_sent.add(1)
      end

      def record_window_update(increment : Int32)
        @window_updates.add(1)
      end

      def current_metrics : Hash(String, Int32)
        {
          "connections" => @connection_count.get,
          "streams" => @stream_count.get,
          "frames_received" => @frames_received.get,
          "frames_sent" => @frames_sent.get,
          "window_updates" => @window_updates.get,
          "uptime_seconds" => (Time.utc - @start_time).total_seconds.to_i32
        }
      end
    end
  end
end