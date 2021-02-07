module Duo
  class Error < Exception
    enum Code : UInt32
      NoError            = 0x0
      ProtocolError      = 0x1
      InternalError      = 0x2
      FlowControlError   = 0x3
      SettingsTimeout    = 0x4
      StreamClosed       = 0x5
      FrameSizeError     = 0x6
      RefusedStream      = 0x7
      Cancel             = 0x8
      CompressionError   = 0x9
      ConnectError       = 0xa
      EnhanceYourCalm    = 0xb
      InadequateSecurity = 0xc
      Http11Required     = 0xd
    end

    getter code : Code
    getter last_stream_id : UInt32

    def initialize(@code : Code, last_stream_id = 0, message = "")
      @last_stream_id = last_stream_id.to_u32
      super(message)
    end

    {% for code in Code.constants %}
      def self.{{ code.underscore }}(message = "")
        new Code::{{ code.id }}, 0, message
      end
    {% end %}
  end

  class ClientError < Error
  end
end
