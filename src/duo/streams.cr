require "./stream"

module Duo
  class Streams
    @max_concurrent_streams : Int32
    # :nodoc:
    protected def initialize(@connection : Connection, type : Connection::Type)
      @max_concurrent_streams = @connection.remote_settings.max_concurrent_streams
      @streams = {} of Int32 => Stream
      @mutex = Mutex.new
      @highest_remote_id = 0

      if type.server?
        @id_counter = 0
      else
        @id_counter = -1
      end
    end

    def find(id : Int32, consume : Bool = true)
      @mutex.synchronize do
        @streams[id] ||= begin
          if active_count(1) >= @max_concurrent_streams
            raise Error.refused_stream("MAXIMUM capacity reached")
          end
          if id > @highest_remote_id && consume
            @highest_remote_id = id
          end
          Stream.new(@connection, id: id)
        end
      end
    end

    protected def each
      @mutex.synchronize do
        @streams.each { |_, stream| yield stream }
      end
    end

    # Returns true if the incoming stream id is valid for the current connection.
    protected def valid?(id : Int32)
      id.zero? || ((id % 2) == 1 && (@streams[id]? || id >= @highest_remote_id))
    end

    # Creates an outgoing stream. For example to handle a client request or a
    # server push.
    def create(state = Stream::State::Idle)
      @mutex.synchronize do
        if active_count(0) >= @max_concurrent_streams
          raise Error.internal_error("MAXIMUM outgoing stream capacity reached")
        end
        id = @id_counter += 2
        raise Error.internal_error("STREAM #{id} already exists") if @streams[id]?
        @streams[id] = Stream.new(@connection, id: id, state: state)
      end
    end

    # Counts active ingoing (type=1) or outgoing (type=0) streams.
    protected def active_count(type)
      @streams.reduce(0) do |count, (_, stream)|
        if stream.id == 0 || stream.id % 2 == type && stream.active?
          count + 1
        else
          count
        end
      end
    end

    protected def last_stream_id
      @mutex.synchronize do
        if @streams.any?
          @streams.keys.max
        else
          0
        end
      end
    end
  end
end
