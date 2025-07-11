require "http/headers"

module Duo
  # Core interfaces for HTTP/2 implementation following SOLID principles
  
  # Interface for frame processing
  abstract class FrameProcessor
    abstract def process_frame(frame : Frame) : Nil
    abstract def can_process?(frame_type : FrameType) : Bool
  end
  
  # Interface for stream management
  abstract class StreamManager
    abstract def create_stream(id : Int32, state : Stream::State) : Stream
    abstract def find_stream(id : Int32) : Stream?
    abstract def remove_stream(id : Int32) : Nil
    abstract def active_streams_count : Int32
  end
  
  # Interface for connection state management
  abstract class ConnectionStateManager
    abstract def transition_to(state : Connection::State) : Nil
    abstract def current_state : Connection::State
    abstract def can_transition_to?(state : Connection::State) : Bool
  end
  
  # Interface for flow control
  abstract class FlowController
    abstract def update_window_size(stream_id : Int32, increment : Int32) : Nil
    abstract def can_send_data?(stream_id : Int32, size : Int32) : Bool
    abstract def consume_window(stream_id : Int32, size : Int32) : Bool
  end
  
  # Interface for header compression/decompression
  abstract class HeaderProcessor
    abstract def encode_headers(headers : HTTP::Headers) : Bytes
    abstract def decode_headers(data : Bytes) : HTTP::Headers
    abstract def update_table_size(size : Int32) : Nil
  end
  
  # Interface for IO operations
  abstract class IOHandler
    abstract def read_frame : Frame?
    abstract def write_frame(frame : Frame) : Nil
    abstract def flush : Nil
    abstract def close : Nil
  end
  
  # Interface for error handling
  abstract class ErrorHandler
    abstract def handle_error(error : Error) : Nil
    abstract def should_close_connection?(error : Error) : Bool
  end
  
  # Interface for connection lifecycle management
  abstract class ConnectionLifecycle
    abstract def initialize_connection : Nil
    abstract def start_connection : Nil
    abstract def stop_connection : Nil
    abstract def cleanup_connection : Nil
  end
  
  # Interface for settings management
  abstract class SettingsManager
    abstract def update_settings(settings : Settings) : Nil
    abstract def get_settings : Settings
    abstract def validate_settings(settings : Settings) : Bool
  end
  
  # Interface for priority management
  abstract class PriorityManager
    abstract def update_priority(stream_id : Int32, priority : Priority) : Nil
    abstract def get_priority(stream_id : Int32) : Priority
    abstract def process_priority_tree : Nil
  end
  
  # Interface for buffer management
  abstract class BufferManager
    abstract def acquire_buffer(size : Int32) : Bytes
    abstract def release_buffer(buffer : Bytes) : Nil
    abstract def pool_size : Int32
  end
  
  # Interface for metrics and monitoring
  abstract class MetricsCollector
    abstract def record_frame_processed(frame_type : FrameType) : Nil
    abstract def record_stream_created(stream_id : Int32) : Nil
    abstract def record_stream_closed(stream_id : Int32) : Nil
    abstract def record_error(error : Error) : Nil
  end
end