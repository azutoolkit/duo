module Duo
  module Core
    module Strategies
      # Strategy interface for flow control algorithms
      abstract class FlowControlStrategy
        abstract def calculate_window_update(current_window : Int32, initial_window : Int32, active_streams : Int32) : Int32
        abstract def should_send_window_update(current_window : Int32, initial_window : Int32) : Bool
        abstract def validate_window_size(window_size : Int32) : Bool
      end

      # Default flow control strategy (RFC 9113 compliant)
      class DefaultFlowControlStrategy < FlowControlStrategy
        def calculate_window_update(current_window : Int32, initial_window : Int32, active_streams : Int32) : Int32
          if current_window < (initial_window // 2)
            # RFC 9113: Send window update when window is less than half full
            increment = Math.min(initial_window * active_streams, MAXIMUM_WINDOW_SIZE)
            increment
          else
            0
          end
        end

        def should_send_window_update(current_window : Int32, initial_window : Int32) : Bool
          current_window < (initial_window // 2)
        end

        def validate_window_size(window_size : Int32) : Bool
          MINIMUM_WINDOW_SIZE <= window_size <= MAXIMUM_WINDOW_SIZE
        end
      end

      # Aggressive flow control strategy (sends updates more frequently)
      class AggressiveFlowControlStrategy < FlowControlStrategy
        def calculate_window_update(current_window : Int32, initial_window : Int32, active_streams : Int32) : Int32
          if current_window < (initial_window * 3 // 4)
            # Send update when window is less than 75% full
            increment = Math.min(initial_window // 2, MAXIMUM_WINDOW_SIZE)
            increment
          else
            0
          end
        end

        def should_send_window_update(current_window : Int32, initial_window : Int32) : Bool
          current_window < (initial_window * 3 // 4)
        end

        def validate_window_size(window_size : Int32) : Bool
          MINIMUM_WINDOW_SIZE <= window_size <= MAXIMUM_WINDOW_SIZE
        end
      end

      # Conservative flow control strategy (sends updates less frequently)
      class ConservativeFlowControlStrategy < FlowControlStrategy
        def calculate_window_update(current_window : Int32, initial_window : Int32, active_streams : Int32) : Int32
          if current_window < (initial_window // 4)
            # Send update only when window is less than 25% full
            increment = Math.min(initial_window, MAXIMUM_WINDOW_SIZE)
            increment
          else
            0
          end
        end

        def should_send_window_update(current_window : Int32, initial_window : Int32) : Bool
          current_window < (initial_window // 4)
        end

        def validate_window_size(window_size : Int32) : Bool
          MINIMUM_WINDOW_SIZE <= window_size <= MAXIMUM_WINDOW_SIZE
        end
      end

      # Strategy interface for stream prioritization algorithms
      abstract class PrioritizationStrategy
        abstract def calculate_priority(stream_id : Int32, dependency_stream_id : Int32, weight : Int32, exclusive : Bool) : Float64
        abstract def should_process_stream(stream : Stream, current_time : Time) : Bool
        abstract def get_processing_order(streams : Array(Stream)) : Array(Stream)
      end

      # Default prioritization strategy (RFC 9113 compliant)
      class DefaultPrioritizationStrategy < PrioritizationStrategy
        def calculate_priority(stream_id : Int32, dependency_stream_id : Int32, weight : Int32, exclusive : Bool) : Float64
          # Simple weight-based priority
          weight.to_f64
        end

        def should_process_stream(stream : Stream, current_time : Time) : Bool
          # Process all active streams
          stream.active?
        end

        def get_processing_order(streams : Array(Stream)) : Array(Stream)
          # Sort by weight (higher weight = higher priority)
          streams.sort_by { |s| -s.priority.weight }
        end
      end

      # Weighted fair queuing prioritization strategy
      class WeightedFairQueuingStrategy < PrioritizationStrategy
        private getter virtual_time : Float64 = 0.0

        def calculate_priority(stream_id : Int32, dependency_stream_id : Int32, weight : Int32, exclusive : Bool) : Float64
          # Calculate virtual finish time for WFQ
          @virtual_time + (1.0 / weight.to_f64)
        end

        def should_process_stream(stream : Stream, current_time : Time) : Bool
          stream.active?
        end

        def get_processing_order(streams : Array(Stream)) : Array(Stream)
          # Sort by virtual finish time
          streams.sort_by { |s| calculate_priority(s.id, s.priority.dependency_stream_id, s.priority.weight, s.priority.exclusive) }
        end

        def update_virtual_time(stream : Stream, processing_time : Float64)
          @virtual_time += processing_time / stream.priority.weight.to_f64
        end
      end

      # Round-robin prioritization strategy
      class RoundRobinStrategy < PrioritizationStrategy
        private getter last_processed_stream_id : Int32 = 0

        def calculate_priority(stream_id : Int32, dependency_stream_id : Int32, weight : Int32, exclusive : Bool) : Float64
          # Round-robin doesn't use traditional priority
          1.0
        end

        def should_process_stream(stream : Stream, current_time : Time) : Bool
          stream.active?
        end

        def get_processing_order(streams : Array(Stream)) : Array(Stream)
          return streams if streams.empty?

          # Find the next stream after the last processed one
          sorted_streams = streams.sort_by(&.id)
          last_index = sorted_streams.index { |s| s.id == @last_processed_stream_id } || -1
          next_index = (last_index + 1) % sorted_streams.size

          # Rotate the array to start from the next stream
          sorted_streams.rotate(next_index)
        end

        def mark_stream_processed(stream_id : Int32)
          @last_processed_stream_id = stream_id
        end
      end

      # Strategy interface for error handling
      abstract class ErrorHandlingStrategy
        abstract def handle_protocol_error(error : Error, connection : Connection) : Nil
        abstract def handle_flow_control_error(error : Error, stream : Stream?) : Nil
        abstract def handle_stream_error(error : Error, stream : Stream) : Nil
        abstract def should_retry_operation(operation : String, attempt_count : Int32) : Bool
      end

      # Default error handling strategy
      class DefaultErrorHandlingStrategy < ErrorHandlingStrategy
        def handle_protocol_error(error : Error, connection : Connection) : Nil
          # Send GOAWAY frame and close connection
          connection.close(error: error)
        end

        def handle_flow_control_error(error : Error, stream : Stream?) : Nil
          if stream
            # Send RST_STREAM for stream-level errors
            stream.send_rst_stream(Error::Code::FlowControlError)
          else
            # Send GOAWAY for connection-level errors
            raise error
          end
        end

        def handle_stream_error(error : Error, stream : Stream) : Nil
          # Send RST_STREAM and close stream
          stream.send_rst_stream(error.code)
          stream.close
        end

        def should_retry_operation(operation : String, attempt_count : Int32) : Bool
          # Don't retry by default for HTTP/2
          false
        end
      end

      # Retry-capable error handling strategy
      class RetryErrorHandlingStrategy < ErrorHandlingStrategy
        private getter max_retries : Int32
        private getter retry_delay : Time::Span

        def initialize(@max_retries = 3, @retry_delay = 100.milliseconds)
        end

        def handle_protocol_error(error : Error, connection : Connection) : Nil
          # Protocol errors are fatal, don't retry
          connection.close(error: error)
        end

        def handle_flow_control_error(error : Error, stream : Stream?) : Nil
          if stream
            stream.send_rst_stream(Error::Code::FlowControlError)
          else
            raise error
          end
        end

        def handle_stream_error(error : Error, stream : Stream) : Nil
          # Some stream errors might be retryable
          case error.code
          when .flow_control_error?
            # Flow control errors are not retryable
            stream.send_rst_stream(error.code)
            stream.close
          when .internal_error?
            # Internal errors might be retryable
            if should_retry_operation("stream_operation", 1)
              # Could implement retry logic here
              stream.send_rst_stream(error.code)
              stream.close
            else
              stream.send_rst_stream(error.code)
              stream.close
            end
          else
            stream.send_rst_stream(error.code)
            stream.close
          end
        end

        def should_retry_operation(operation : String, attempt_count : Int32) : Bool
          attempt_count < @max_retries
        end
      end
    end
  end
end