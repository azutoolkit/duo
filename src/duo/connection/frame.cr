module Duo
  class Frame
    # See https://tools.ietf.org/html/rfc7540#section-11.2
    enum Type
      Data         = 0x0
      Headers      = 0x1
      Priority     = 0x2
      RstStream    = 0x3
      Settings     = 0x4
      PushPromise  = 0x5
      Ping         = 0x6
      GoAway       = 0x7
      WindowUpdate = 0x8
      Continuation = 0x9

      def self.non_transitional?(type)
        [
          Frame::Type::Priority,
          Frame::Type::GoAway,
          Frame::Type::Ping,
        ].includes?(type)
      end
    end

    @[Flags]
    enum Flags : UInt8
      EndStream  =  0x1_u8
      EndHeaders =  0x4_u8
      Padded     =  0x8_u8
      Priority   = 0x20_u8

      def ack?
        end_stream?
      end

      def inspect(io)
        to_s(io)
      end

      def to_s(io)
        if value == 0
          io << "NONE"
          return
        end

        i = 0
        {% for name in @type.constants %}
          {% unless name.stringify == "None" || name.stringify == "All" %}
            if {{ name.downcase }}?
              io << "|" unless i == 0
              io << {{ name.stringify }}
              i += 1
            end
          {% end %}
        {% end %}
      end
    end

    getter type : Type
    protected setter type : Type

    getter stream : Stream

    getter flags : Flags
    protected setter flags : Flags

    getter! payload : Bytes

    @size : Int32?

    # :nodoc:
    protected def initialize(@type : Type, @stream : Stream, @flags : Flags = Flags::None, @payload : Bytes? = nil, size : Int32? = nil)
      @size = size.try(&.to_i32)
    end

    # The frame's payload size.
    def size
      @size || payload?.try(&.size) || 0
    end

    protected def payload=(@payload : Bytes)
    end
  end
end
