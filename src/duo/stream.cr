require "http/headers"
require "./data"
require "./state"
require "./priority"

module Duo
  class Stream
    getter id : Int32
    property state : State
    property priority : Priority

    getter max_frame_size : Int32
    getter local_window_size : Int32
    getter remote_window_size : Int32
    getter headers = HTTP::Headers.new
    getter conn : Connection

    forward_missing_to @conn

    def initialize(@conn, @id, @priority = DEFAULT_PRIORITY.dup, @state = State::Idle)
      @max_frame_size = remote_settings.max_frame_size
      @remote_window_size = remote_settings.initial_window_size
      @local_window_size = local_settings.initial_window_size
    end

    def zero?
      id.zero?
    end

    def active? : Bool
      state.active?
    end

    def data? : Bool
      !data.size.zero?
    end

    def data : Data
      @data ||= Data.new(self, @local_window_size)
    end

    def trailing_headers? : HTTP::Headers?
      @trailing_headers
    end

    def trailing_headers : HTTP::Headers
      @trailing_headers ||= HTTP::Headers.new
    end

    def ==(other : Stream)
      id == other.id
    end

    def ==(other)
      false
    end

    def wait_writeable
      @fiber = Fiber.current
      Crystal::Scheduler.reschedule
    ensure
      @fiber = nil
    end

    def resume_writeable
      if (fiber = @fiber) && remote_window_size > 0
        Crystal::Scheduler.enqueue(Fiber.current)
        fiber.resume
      end
    end

    def process_window_update(size) : Nil
      return conn_window_update(size) if id.zero?
      window_update(size)
    end

    def send_rst_stream(error_code : Error::Code) : Nil
      io = IO::Memory.new(RST_STREAM_FRAME_SIZE)
      io.write_bytes(error_code.value.to_u32, IO::ByteFormat::BigEndian)
      send Frame.new(FrameType::RstStream, self, payload: io.to_slice)
    end

    def send_window_update(increment)
      unless MINIMUM_WINDOW_SIZE <= increment <= MAXIMUM_WINDOW_SIZE
        raise Error.protocol_error("invalid WindowUpdate increment: #{increment}")
      end
      io = IO::Memory.new(WINDOW_UPDATE_FRAME_SIZE)
      io.write_bytes(increment.to_u32 & 0x7fffffff_u32, IO::ByteFormat::BigEndian)
      send Frame.new(FrameType::WindowUpdate, self, payload: io.to_slice)
    end

    def send_headers(headers : HTTP::Headers, flags : Frame::Flags = Frame::Flags::None) : Nil
      payload = encoder.encode(headers)
      send_headers(FrameType::Headers, headers, flags, payload)
    end

    def send_push_promise(headers : HTTP::Headers, flags : Frame::Flags = Frame::Flags::None) : Stream?
      return unless remote_settings.enable_push
      streams.create(state: Stream::State::ReservedLocal).tap do |stream|
        io = IO::Memory.new
        io.write_bytes(stream.id.to_u32 & 0x7fffffff_u32, IO::ByteFormat::BigEndian)
        payload = encoder.encode(headers, writer: io)
        send_headers(FrameType::PushPromise, headers, flags, payload)
      end
    end

    def send_headers(type : FrameType, headers, flags, payload) : Nil
      if payload.size <= max_frame_size
        flags |= flags | Frame::Flags::EndHeaders
        frame = Frame.new(type, self, flags, payload)
        send(frame)
      else
        num = (payload.size / max_frame_size).ceil.to_i
        count = max_frame_size
        offset = 0

        frames = num.times.map do |index|
          type = FrameType::Continuation if index > 1
          offset = index * max_frame_size
          if index == num
            count = payload.size - offset
            flags |= Frame::Flags::EndHeaders
          end
          Frame.new(type, self, flags, payload[offset, count])
        end

        send(frames.to_a)
      end
    end

    def send_data(data : String, flags : Frame::Flags = Frame::Flags::None) : Nil
      send_data(data.to_slice, flags)
    end

    def send_data(data : Bytes, flags : Frame::Flags = Frame::Flags::None) : Nil
      if flags.end_stream? && data.size > 0
        end_stream = true
        flags ^= Frame::Flags::EndStream
      else
        end_stream = false
      end

      frame = Frame.new(FrameType::Data, self, flags)

      if data.size == 0
        send(frame)
        return
      end

      until data.size == 0
        if remote_window_size < 1 || remote_window_size < 1
          wait_writeable
        end

        size = {data.size, remote_window_size, max_frame_size}.min
        if size > 0
          actual = consume_remote_window_size(size)

          if actual > 0
            frame.payload = data[0, actual]
            @remote_window_size -= actual
            data += actual

            frame.flags |= Frame::Flags::EndStream if data.size == 0 && end_stream
            send(frame)
          end
        end

        Fiber.yield
      end
    end

    private def conn_window_update(size)
      raise Error.flow_control_error if (remote_window_size.to_i64 + size) > MAXIMUM_WINDOW_SIZE
      remote_window_size + size
      if remote_window_size > 0
        streams.each(&.resume_writeable)
      end
    end

    private def window_update(size)
      if (remote_window_size.to_i64 + size) > MAXIMUM_WINDOW_SIZE
        send_rst_stream(Error::Code::FlowControlError)
        return
      end
      @remote_window_size += size
      resume_writeable
    end

    private def consume_remote_window_size(size)
      loop do
        window_size = remote_window_size
        return 0 if window_size == 0

        actual = Math.min(size, window_size)
        if remote_window_size != window_size
          @remote_window_size = window_size - actual
        end
        return actual
      end
    end
  end
end
