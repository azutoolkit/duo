module Duo
  class Frame
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

    getter type : FrameType
    protected setter type : FrameType

    getter stream : Stream

    getter flags : Flags
    protected setter flags : Flags

    getter! payload : Bytes

    @size : Int32?

    protected def initialize(@type : FrameType, @stream : Stream, @flags : Flags = Flags::None, @payload : Bytes? = nil, size : Int32? = nil)
      @size = size.try(&.to_i32)
    end

    def size
      @size || payload?.try(&.size) || 0
    end

    protected def payload=(@payload : Bytes)
    end
  end
end
