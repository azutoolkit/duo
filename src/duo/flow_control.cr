module Duo
  module FlowControl
    macro included
      @closed = false
      @channel = Channel(Frame | Array(Frame) | Nil).new(10)
      getter remote_window_size = DEFAULT_INITIAL_WINDOW_SIZE
      getter local_window_size = DEFAULT_INITIAL_WINDOW_SIZE
    end

    def receive_frame
      loop do
        begin
          case frame = @channel.receive
          when Array(Frame) then frame.each { |f| write(f, flush: false) }
          when Frame        then write(frame, flush: false)
          else
            io.close unless io.closed?
            break
          end
        rescue Channel::ClosedError
          break
        ensure
          io.flush if @channel.@queue.not_nil!.empty?
        end
      end
    end

    def process_frame
      frame = read_frame_header
      stream = frame.stream

      State.receiving(frame)

      case frame.type
      when FrameType::Data         then read_data_frame(frame)
      when FrameType::Headers      then read_headers_frame(frame)
      when FrameType::PushPromise  then read_push_promise_frame(frame)
      when FrameType::Priority     then read_priority_frame(frame)
      when FrameType::RstStream    then read_rst_stream_frame(frame)
      when FrameType::Settings     then read_settings_frame(frame)
      when FrameType::Ping         then read_ping_frame(frame)
      when FrameType::GoAway       then read_goaway_frame(frame)
      when FrameType::WindowUpdate then read_window_update_frame(frame)
      when FrameType::Continuation
        raise Error.protocol_error("UNEXPECTED Continuation frame")
      else
        read_unsupported_frame(frame)
      end

      frame
    end

    def send(frame : Frame)
      @channel.send(frame) unless @channel.closed?
    end

    def send(frame : Array(Frame))
      @channel.send(frame) unless @channel.closed?
    end

    def close_channel!
      unless @channel.closed?
        @channel.send(nil)
        @channel.close
      end
    end

    def update_local_window(size)
      @local_window_size -= size
      initial_window_size = local_settings.initial_window_size

      if local_window_size < (initial_window_size // 2)
        increment = Math.min(initial_window_size * streams.active_count(1), MAXIMUM_WINDOW_SIZE)
        @local_window_size += increment
        streams.find(0).send_window_update(increment)
      end
    end

    def consume_remote_window_size(size)
      loop do
        window_size = remote_window_size
        return 0 if window_size == 0

        actual = Math.min(size, window_size)
        if remote_window_size != window_size
          remote_window_size = window_size - actual
        end
        return actual
      end
    end
  end
end
