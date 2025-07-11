require "./errors"

module Duo
  class Settings
    MAX_CONCURRENT_STREAMS =   100
    MAX_HEADER_LIST_SIZE   = 16384

    DEFAULT = new(
      max_concurrent_streams: MAX_CONCURRENT_STREAMS,
      max_header_list_size: MAX_HEADER_LIST_SIZE,
    )

    enum Identifier : UInt16
      HeaderTableSize      = 0x1
      EnablePush           = 0x2
      MaxConcurrentStreams = 0x3
      InitialWindowSize    = 0x4
      MaxFrameSize         = 0x5
      MaxHeaderListSize    = 0x6

      def self.parse(io : IO, size : Int32, settings) : Nil
        size.times do |_|
          id = from_value?(io.read_bytes(UInt16, IO::ByteFormat::BigEndian))
          raw_value = io.read_bytes(UInt32, IO::ByteFormat::BigEndian)

          # Check for arithmetic overflow before converting to Int32
          if raw_value > Int32::MAX.to_u32
            # For settings that should be positive, this is an error
            case id
            when InitialWindowSize, MaxFrameSize, HeaderTableSize, MaxHeaderListSize, MaxConcurrentStreams
              raise Error.protocol_error("Setting value #{raw_value} exceeds maximum allowed value")
            end
          end

          value = raw_value.to_i32
          next unless id # unknown setting identifier
          yield id, value

          case id
          when HeaderTableSize      then settings.header_table_size = value
          when EnablePush           then settings.enable_push = value
          when MaxConcurrentStreams then settings.max_concurrent_streams = value
          when InitialWindowSize    then settings.initial_window_size = value
          when MaxFrameSize         then settings.max_frame_size = value
          when MaxHeaderListSize    then settings.max_header_list_size = value
          end
        end
      end
    end

    getter header_table_size : Int32
    getter enable_push : Bool
    getter max_concurrent_streams : Int32
    getter max_concurrent_streams : Int32
    getter initial_window_size : Int32
    getter max_header_list_size : Int32
    getter max_frame_size : Int32

    # :nodoc:
    protected def initialize(
      @header_table_size : Int32 = DEFAULT_HEADER_TABLE_SIZE,
      @enable_push : Bool = DEFAULT_ENABLE_PUSH,
      @max_concurrent_streams : Int32 = MAX_CONCURRENT_STREAMS,
      @initial_window_size : Int32 = DEFAULT_INITIAL_WINDOW_SIZE,
      @max_frame_size : Int32 = DEFAULT_MAX_FRAME_SIZE,
      @max_header_list_size : Int32 = MAX_HEADER_LIST_SIZE
    )
    end

    def parse(bytes : Bytes) : Nil
      Identifier.parse(IO::Memory.new(bytes), bytes.size // 6, self) do |identifier, value|
        yield identifier, value
      end
    end

    def parse(io : IO, size : Int32) : Nil
      Identifier.parse(io, size, self) do |identifier, value|
        yield identifier, value
      end
    end

    def max_header_list_size=(value : Int32)
      @max_header_list_size = value
    end

    def max_frame_size=(value : Int32)
      unless MINIMUM_FRAME_SIZE <= value < MAXIMUM_FRAME_SIZE
        raise Error.protocol_error("INVALID frame size: #{value}")
      end
      @max_frame_size = value
    end

    def initial_window_size=(value : Int32)
      raise Error.flow_control_error unless 0 <= value < MAXIMUM_WINDOW_SIZE
      @initial_window_size = value
    end

    def max_concurrent_streams=(value : Int32)
      @max_concurrent_streams = value
    end

    def header_table_size=(value : Int32)
      @header_table_size = value
    end

    def enable_push=(value)
      raise Error.protocol_error unless value == 0 || value == 1
      @enable_push = value == 1
    end

    def to_payload : Bytes
      io = IO::Memory.new(size * 6)

      {% for name in Identifier.constants %}
        if value = @{{ name.underscore }}
          io.write_bytes(Identifier::{{ name }}.to_u16, IO::ByteFormat::BigEndian)
          if value.is_a?(Bool)
            io.write_bytes(value ? 1_u32 : 0_u32, IO::ByteFormat::BigEndian)
          else
            io.write_bytes(value.to_u32, IO::ByteFormat::BigEndian)
          end
        end
      {% end %}

      io.to_slice
    end

    # :nodoc:
    def size : Int32
      num = 0
      {% for name in Identifier.constants %}
        num += 1 if @{{ name.underscore }}
      {% end %}
      num
    end
  end
end
