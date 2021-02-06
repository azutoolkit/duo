require "http/headers"
require "./data"
require "./state"
require "./priority"

module Duo
  class Stream
    # The stream identifier. Odd-numbered for client streams (requests),
    # even-numbered for server initiated streams (server-push).
    getter id : Int32
    getter state : State
    property priority : Priority
    private getter connection : Connection
    getter outbound_window_size : Int32
    getter headers = HTTP::Headers.new

    # :nodoc:
    def initialize(@connection, @id, @priority = DEFAULT_PRIORITY.dup, @state = State::Idle)
      @outbound_window_size = connection.remote_settings.initial_window_size
    end

    def state=(@state)
    end

    def active? : Bool
      state.active?
    end

    def data? : Bool
      data.size != 0
    end

    def data : Data
      @data ||= Data.new(self, connection.local_settings.initial_window_size)
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

    def increment_outbound_window_size(increment) : Nil
      if @outbound_window_size.to_i64 + increment > MAXIMUM_WINDOW_SIZE
        rst_stream(Error::Code::FlowControlError)
        return
      end
      @outbound_window_size += increment
      resume_writeable
    end

    def consume_outbound_window_size(size)
      @outbound_window_size -= size
    end

    def window_update(increment)
      unless MINIMUM_WINDOW_SIZE <= increment <= MAXIMUM_WINDOW_SIZE
        raise Error.protocol_error("invalid WindowUpdate increment: #{increment}")
      end
      io = IO::Memory.new(WINDOW_UPDATE_FRAME_SIZE)
      io.write_bytes(increment.to_u32 & 0x7fffffff_u32, IO::ByteFormat::BigEndian)
      connection.send Frame.new(Frame::Type::WindowUpdate, self, payload: io.to_slice)
    end

    def priority : Nil
      exclusive = priority.exclusive ? 0x80000000_u32 : 0_u32
      dep_stream_id = priority.dep_stream_id.to_u32 & 0x7fffffff_u32

      io = IO::Memory.new(PRIORITY_FRAME_SIZE)
      io.write_bytes(exclusive | dep_stream_id, IO::ByteFormat::BigEndian)
      io.write_byte((priority.weight - 1).to_u8)

      connection.send Frame.new(Frame::Type::Priority, self, payload: io.to_slice)
    end

    def headers(headers : HTTP::Headers, flags : Frame::Flags = Frame::Flags::None) : Nil
      payload = connection.hpack_encoder.encode(headers)
      headers(Frame::Type::Headers, headers, flags, payload)
    end

    def push_promise(headers : HTTP::Headers, flags : Frame::Flags = Frame::Flags::None) : Stream?
      unless connection.remote_settings.enable_push
        return
      end
      connection.streams.create(state: Stream::State::ReservedLocal).tap do |stream|
        io = IO::Memory.new
        io.write_bytes(stream.id.to_u32 & 0x7fffffff_u32, IO::ByteFormat::BigEndian)
        payload = connection.hpack_encoder.encode(headers, writer: io)
        headers(Frame::Type::PushPromise, headers, flags, payload)
      end
    end

    def headers(type : Frame::Type, headers, flags, payload) : Nil
      max_frame_size = connection.remote_settings.max_frame_size

      if payload.size <= max_frame_size
        flags |= flags | Frame::Flags::EndHeaders
        frame = Frame.new(type, self, flags, payload)
        connection.send(frame)
      else
        num = (payload.size / max_frame_size).ceil.to_i
        count = max_frame_size
        offset = 0

        frames = num.times.map do |index|
          type = Frame::Type::Continuation if index > 1
          offset = index * max_frame_size
          if index == num
            count = payload.size - offset
            flags |= Frame::Flags::EndHeaders
          end
          Frame.new(type, self, flags, payload[offset, count])
        end

        connection.send(frames.to_a)
      end
    end

    # Writes data to the stream.
    #
    # This may be part of a request body (client context), or a response body
    # (server context).
    #
    # This will send one or many Data frames, respecting SETTINGS_MAX_FRAME_SIZE
    # as defined by the remote peer, as well as available window sizes for the
    # stream and the connection, exhausting them as much as possible.
    #
    # This will block the current fiber if *data* is too big than allowed by any
    # window size (stream or connection). The fiber will be eventually resumed
    # when the remote peer sends a WindowUpdate frame to increment window
    # sizes.
    #
    # Eventually returns when *data* has been fully sent.
    def data(data : String, flags : Frame::Flags = Frame::Flags::None) : Nil
      data(data.to_slice, flags)
    end

    # ditto
    def data(data : Bytes, flags : Frame::Flags = Frame::Flags::None) : Nil
      if flags.end_stream? && data.size > 0
        end_stream = true
        flags ^= Frame::Flags::EndStream
      else
        end_stream = false
      end

      frame = Frame.new(Frame::Type::Data, self, flags)

      if data.size == 0
        connection.send(frame)
        return
      end

      until data.size == 0
        if @outbound_window_size < 1 || connection.outbound_window_size < 1
          wait_writeable
        end

        size = {data.size, @outbound_window_size, connection.remote_settings.max_frame_size}.min
        if size > 0
          actual = connection.consume_outbound_window_size(size)

          if actual > 0
            frame.payload = data[0, actual]

            consume_outbound_window_size(actual)
            data += actual

            frame.flags |= Frame::Flags::EndStream if data.size == 0 && end_stream
            connection.send(frame)
          end
        end

        # allow other fibers to do their job (e.g. let the connection send or
        # receive frames, let other streams send data, ...)
        Fiber.yield
      end
    end

    # Block current fiber until the stream can send data. I.e. it's window size
    # or the connection window size have been increased.
    private def wait_writeable
      @fiber = Fiber.current
      Crystal::Scheduler.reschedule
    ensure
      @fiber = nil
    end

    # Resume a previously paused fiber waiting to send data, if any.
    def resume_writeable
      if (fiber = @fiber) && @outbound_window_size > 0
        Crystal::Scheduler.enqueue(Fiber.current)
        fiber.resume
      end
    end

    # Closes the stream. Optionally reporting an error status.
    def rst_stream(error_code : Error::Code) : Nil
      io = IO::Memory.new(RST_STREAM_FRAME_SIZE)
      io.write_bytes(error_code.value.to_u32, IO::ByteFormat::BigEndian)
      connection.send Frame.new(Frame::Type::RstStream, self, payload: io.to_slice)
    end

    def receiving(frame : Frame)
      state.transition(frame, receiving: true)
    end

    def sending(frame : Frame)
      state.transition(frame, receiving: false)
    end

    # :nodoc:
    def hash(hasher)
      id.hash(hasher)
    end
  end
end
