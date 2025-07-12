module Duo
  module Core
    module Events
      # Base event class
      abstract class Event
        getter timestamp : Time
        getter connection_id : String

        def initialize(@connection_id)
          @timestamp = Time.utc
        end
      end

      # Stream lifecycle events
      class StreamCreatedEvent < Event
        getter stream_id : Int32
        getter state : State

        def initialize(@connection_id, @stream_id, @state)
          super(@connection_id)
        end
      end

      class StreamStateChangedEvent < Event
        getter stream_id : Int32
        getter old_state : State
        getter new_state : State

        def initialize(@connection_id, @stream_id, @old_state, @new_state)
          super(@connection_id)
        end
      end

      class StreamClosedEvent < Event
        getter stream_id : Int32
        getter reason : String?

        def initialize(@connection_id, @stream_id, @reason = nil)
          super(@connection_id)
        end
      end

      class StreamDataReceivedEvent < Event
        getter stream_id : Int32
        getter data_size : Int32
        getter end_stream : Bool

        def initialize(@connection_id, @stream_id, @data_size, @end_stream)
          super(@connection_id)
        end
      end

      class StreamHeadersReceivedEvent < Event
        getter stream_id : Int32
        getter headers : HTTP::Headers
        getter end_stream : Bool

        def initialize(@connection_id, @stream_id, @headers, @end_stream)
          super(@connection_id)
        end
      end

      # Flow control events
      class WindowUpdateEvent < Event
        getter stream_id : Int32
        getter increment : Int32
        getter new_window_size : Int32

        def initialize(@connection_id, @stream_id, @increment, @new_window_size)
          super(@connection_id)
        end
      end

      class FlowControlErrorEvent < Event
        getter stream_id : Int32?
        getter error_code : Error::Code
        getter message : String

        def initialize(@connection_id, @error_code, @message, @stream_id = nil)
          super(@connection_id)
        end
      end

      # Connection events
      class ConnectionEstablishedEvent < Event
        getter connection_type : Connection::Type
        getter settings : Settings

        def initialize(@connection_id, @connection_type, @settings)
          super(@connection_id)
        end
      end

      class ConnectionClosedEvent < Event
        getter reason : String?
        getter error_code : Error::Code?

        def initialize(@connection_id, @reason = nil, @error_code = nil)
          super(@connection_id)
        end
      end

      class SettingsChangedEvent < Event
        getter old_settings : Settings
        getter new_settings : Settings

        def initialize(@connection_id, @old_settings, @new_settings)
          super(@connection_id)
        end
      end

      # Frame events
      class FrameReceivedEvent < Event
        getter frame_type : FrameType
        getter stream_id : Int32
        getter frame_size : Int32

        def initialize(@connection_id, @frame_type, @stream_id, @frame_size)
          super(@connection_id)
        end
      end

      class FrameSentEvent < Event
        getter frame_type : FrameType
        getter stream_id : Int32
        getter frame_size : Int32

        def initialize(@connection_id, @frame_type, @stream_id, @frame_size)
          super(@connection_id)
        end
      end

      # Error events
      class ProtocolErrorEvent < Event
        getter error_code : Error::Code
        getter message : String
        getter stream_id : Int32?

        def initialize(@connection_id, @error_code, @message, @stream_id = nil)
          super(@connection_id)
        end
      end

      class StreamErrorEvent < Event
        getter stream_id : Int32
        getter error_code : Error::Code
        getter message : String

        def initialize(@connection_id, @stream_id, @error_code, @message)
          super(@connection_id)
        end
      end

      # Performance events
      class PerformanceEvent < Event
        getter metric_name : String
        getter value : Float64
        getter unit : String

        def initialize(@connection_id, @metric_name, @value, @unit)
          super(@connection_id)
        end
      end

      # Observer interface
      abstract class EventObserver
        abstract def on_event(event : Event) : Nil
      end

      # Event manager that handles event distribution
      class EventManager
        private getter observers : Array(EventObserver)
        private getter mutex : Mutex
        private getter enabled : Bool

        def initialize(@enabled = true)
          @observers = [] of EventObserver
          @mutex = Mutex.new
        end

        # Registers an observer
        def add_observer(observer : EventObserver) : Nil
          @mutex.synchronize do
            @observers << observer
          end
        end

        # Unregisters an observer
        def remove_observer(observer : EventObserver) : Nil
          @mutex.synchronize do
            @observers.delete(observer)
          end
        end

        # Publishes an event to all observers
        def publish_event(event : Event) : Nil
          return unless @enabled

          @mutex.synchronize do
            @observers.each do |observer|
              begin
                observer.on_event(event)
              rescue ex : Exception
                # Log error but don't let it break the event system
                Log.error(exception: ex) { "Error in event observer: #{ex.message}" }
              end
            end
          end
        end

        # Enables or disables event publishing
        def enabled=(@enabled : Bool) : Nil
        end

        # Gets the number of registered observers
        def observer_count : Int32
          @mutex.synchronize do
            @observers.size
          end
        end
      end

      # Concrete observers
      class LoggingObserver < EventObserver
        def on_event(event : Event) : Nil
          case event
          when StreamCreatedEvent
            Log.info { "Stream #{event.stream_id} created in state #{event.state}" }
          when StreamStateChangedEvent
            Log.info { "Stream #{event.stream_id} state changed: #{event.old_state} -> #{event.new_state}" }
          when StreamClosedEvent
            Log.info { "Stream #{event.stream_id} closed#{event.reason ? " (#{event.reason})" : ""}" }
          when ConnectionEstablishedEvent
            Log.info { "Connection established (#{event.connection_type})" }
          when ConnectionClosedEvent
            Log.info { "Connection closed#{event.reason ? " (#{event.reason})" : ""}" }
          when ProtocolErrorEvent
            Log.error { "Protocol error: #{event.error_code} - #{event.message}" }
          when StreamErrorEvent
            Log.error { "Stream #{event.stream_id} error: #{event.error_code} - #{event.message}" }
          when FlowControlErrorEvent
            Log.warn { "Flow control error: #{event.error_code} - #{event.message}" }
          when PerformanceEvent
            Log.debug { "Performance: #{event.metric_name} = #{event.value} #{event.unit}" }
          end
        end
      end

      class MetricsObserver < EventObserver
        private getter metrics : Hash(String, Float64)
        private getter mutex : Mutex

        def initialize
          @metrics = {} of String => Float64
          @mutex = Mutex.new
        end

        def on_event(event : Event) : Nil
          @mutex.synchronize do
            case event
            when StreamCreatedEvent
              increment_metric("streams.created")
            when StreamClosedEvent
              increment_metric("streams.closed")
            when FrameReceivedEvent
              increment_metric("frames.received")
              increment_metric("frames.received.#{event.frame_type.to_s.downcase}")
              add_metric("frames.received.bytes", event.frame_size.to_f64)
            when FrameSentEvent
              increment_metric("frames.sent")
              increment_metric("frames.sent.#{event.frame_type.to_s.downcase}")
              add_metric("frames.sent.bytes", event.frame_size.to_f64)
            when WindowUpdateEvent
              increment_metric("window_updates")
              add_metric("window_updates.increment", event.increment.to_f64)
            when PerformanceEvent
              set_metric(event.metric_name, event.value)
            end
          end
        end

        def get_metrics : Hash(String, Float64)
          @mutex.synchronize do
            @metrics.dup
          end
        end

        def get_metric(name : String) : Float64?
          @mutex.synchronize do
            @metrics[name]?
          end
        end

        private def increment_metric(name : String) : Nil
          @metrics[name] = (@metrics[name]? || 0.0) + 1.0
        end

        private def add_metric(name : String, value : Float64) : Nil
          @metrics[name] = (@metrics[name]? || 0.0) + value
        end

        private def set_metric(name : String, value : Float64) : Nil
          @metrics[name] = value
        end
      end

      class DebugObserver < EventObserver
        private getter events : Array(Event)
        private getter mutex : Mutex
        private getter max_events : Int32

        def initialize(@max_events = 1000)
          @events = [] of Event
          @mutex = Mutex.new
        end

        def on_event(event : Event) : Nil
          @mutex.synchronize do
            @events << event
            if @events.size > @max_events
              @events.shift
            end
          end
        end

        def get_events : Array(Event)
          @mutex.synchronize do
            @events.dup
          end
        end

        def clear_events : Nil
          @mutex.synchronize do
            @events.clear
          end
        end

        def get_events_by_type(type : Event.class) : Array(Event)
          @mutex.synchronize do
            @events.select { |e| e.is_a?(type) }
          end
        end
      end
    end
  end
end