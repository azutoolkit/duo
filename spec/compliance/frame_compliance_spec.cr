require "../spec_helper"

describe "HTTP/2 Frame Compliance (RFC 9113 Section 4.1)" do
  describe "Frame Header Format" do
    it "validates frame header structure" do
      # RFC 9113 Section 4.1: Frame Header
      # +---------------+---------------+
      # | Length (24)   | Type (8)      |
      # +---------------+---------------+
      # | Flags (8)     | R (1)         |
      # +---------------+---------------+
      # | Stream Identifier (31)        |
      # +-------------------------------+
      
      io = IO::Memory.new
      frame_parser = Duo::Core::FrameParser.new(io, 16384)
      
      # Test minimum frame header size
      expect_raises(IO::EOFError) do
        frame_parser.parse_frame_header
      end
    end

    it "validates frame length field" do
      # RFC 9113 Section 4.1.1: Frame Size
      # The 24-bit length field gives the length of the frame payload
      # as an unsigned 24-bit integer.
      
      io = IO::Memory.new
      frame_parser = Duo::Core::FrameParser.new(io, 16384)
      
      # Test maximum frame size (2^14 - 1 = 16383)
      large_payload = Bytes.new(16384) # Exceeds maximum
      
      # Should reject frames larger than max_frame_size
      expect_raises(Duo::Error) do
        frame = Duo::Core::FrameFactory.create_data_frame(1, large_payload)
      end
    end

    it "validates frame type field" do
      # RFC 9113 Section 4.1: Frame Types
      # Unknown frame types MUST be ignored
      
      io = IO::Memory.new
      frame_parser = Duo::Core::FrameParser.new(io, 16384)
      
      # Test all valid frame types
      valid_types = [0x0, 0x1, 0x2, 0x3, 0x4, 0x5, 0x6, 0x7, 0x8, 0x9]
      valid_types.each do |type|
        # Should not raise error for valid types
        frame = create_test_frame_with_type(type)
        frame.type.value.should eq(type)
      end
    end

    it "validates stream identifier field" do
      # RFC 9113 Section 4.1: Stream Identifier
      # The 31-bit stream identifier field
      # The reserved bit MUST be ignored when received
      
      # Test valid stream IDs
      valid_stream_ids = [0, 1, 2, 3, 100, 1000, 0x7fffffff]
      valid_stream_ids.each do |stream_id|
        frame = Duo::Core::FrameFactory.create_ping_frame
        frame.stream_id = stream_id
        frame.stream_id.should eq(stream_id)
      end
      
      # Test invalid stream IDs (negative)
      expect_raises(Duo::Error) do
        Duo::Core::FrameFactory.create_data_frame(-1, Bytes.new(10))
      end
    end
  end

  describe "DATA Frame (Type 0x0)" do
    it "validates DATA frame format" do
      # RFC 9113 Section 6.1: DATA
      # DATA frames MUST be associated with a stream
      
      # Valid DATA frame
      data = "Hello, HTTP/2!".to_slice
      frame = Duo::Core::FrameFactory.create_data_frame(1, data)
      
      frame.type.should eq(Duo::FrameType::Data)
      frame.stream_id.should eq(1)
      frame.payload.should eq(data)
    end

    it "rejects DATA frames on stream 0" do
      # RFC 9113 Section 6.1: DATA frames MUST NOT be sent on stream 0
      
      expect_raises(Duo::Error) do
        Duo::Core::FrameFactory.create_data_frame(0, Bytes.new(10))
      end
    end

    it "validates DATA frame padding" do
      # RFC 9113 Section 6.1: Padding
      # Padding octets MUST be set to zero when sent
      
      data = "test".to_slice
      frame = Duo::Core::FrameFactory.create_data_frame(1, data, Duo::Frame::Flags::Padded)
      
      frame.flags.padded?.should be_true
      # Padding validation should be implemented in frame parsing
    end

    it "validates END_STREAM flag" do
      # RFC 9113 Section 6.1: END_STREAM flag
      
      data = "final data".to_slice
      frame = Duo::Core::FrameFactory.create_data_frame(1, data, Duo::Frame::Flags::EndStream)
      
      frame.flags.end_stream?.should be_true
    end
  end

  describe "HEADERS Frame (Type 0x1)" do
    it "validates HEADERS frame format" do
      # RFC 9113 Section 6.2: HEADERS
      
      headers = HTTP::Headers.new
      headers[":method"] = "GET"
      headers[":path"] = "/"
      headers[":scheme"] = "https"
      
      frame = Duo::Core::FrameFactory.create_headers_frame(1, headers)
      
      frame.type.should eq(Duo::FrameType::Headers)
      frame.stream_id.should eq(1)
    end

    it "rejects HEADERS frames on stream 0" do
      # RFC 9113 Section 6.2: HEADERS frames MUST NOT be sent on stream 0
      
      headers = HTTP::Headers.new
      headers[":method"] = "GET"
      
      expect_raises(Duo::Error) do
        Duo::Core::FrameFactory.create_headers_frame(0, headers)
      end
    end

    it "validates HEADERS frame priority" do
      # RFC 9113 Section 6.2: Priority
      
      headers = HTTP::Headers.new
      headers[":method"] = "GET"
      
      priority = Duo::Priority.new(false, 0, 16)
      frame = Duo::Core::FrameFactory.create_headers_frame(1, headers, Duo::Frame::Flags::Priority, priority)
      
      frame.flags.priority?.should be_true
    end

    it "validates END_STREAM flag" do
      # RFC 9113 Section 6.2: END_STREAM flag
      
      headers = HTTP::Headers.new
      headers[":method"] = "GET"
      
      frame = Duo::Core::FrameFactory.create_headers_frame(1, headers, Duo::Frame::Flags::EndStream)
      
      frame.flags.end_stream?.should be_true
    end

    it "validates END_HEADERS flag" do
      # RFC 9113 Section 6.2: END_HEADERS flag
      
      headers = HTTP::Headers.new
      headers[":method"] = "GET"
      
      frame = Duo::Core::FrameFactory.create_headers_frame(1, headers, Duo::Frame::Flags::EndHeaders)
      
      frame.flags.end_headers?.should be_true
    end
  end

  describe "PRIORITY Frame (Type 0x2)" do
    it "validates PRIORITY frame format" do
      # RFC 9113 Section 6.3: PRIORITY
      # PRIORITY frames MUST be associated with a stream
      
      frame = Duo::Core::FrameFactory.create_priority_frame(1, false, 0, 16)
      
      frame.type.should eq(Duo::FrameType::Priority)
      frame.stream_id.should eq(1)
      frame.payload.size.should eq(5) # Exactly 5 bytes
    end

    it "rejects PRIORITY frames on stream 0" do
      # RFC 9113 Section 6.3: PRIORITY frames MUST NOT be sent on stream 0
      
      expect_raises(Duo::Error) do
        Duo::Core::FrameFactory.create_priority_frame(0, false, 0, 16)
      end
    end

    it "validates PRIORITY frame payload size" do
      # RFC 9113 Section 6.3: PRIORITY frame payload is exactly 5 octets
      
      frame = Duo::Core::FrameFactory.create_priority_frame(1, false, 0, 16)
      frame.payload.size.should eq(5)
    end

    it "validates priority weight range" do
      # RFC 9113 Section 5.3.1: Weight ranges from 1 to 256
      
      # Valid weights
      [1, 16, 256].each do |weight|
        frame = Duo::Core::FrameFactory.create_priority_frame(1, false, 0, weight)
        # Weight should be encoded correctly in payload
      end
      
      # Invalid weights
      [0, 257].each do |weight|
        expect_raises(Duo::Error) do
          Duo::Core::FrameFactory.create_priority_frame(1, false, 0, weight)
        end
      end
    end

    it "validates stream dependency" do
      # RFC 9113 Section 5.3.1: Stream dependency
      
      # Valid dependency (can depend on stream 0)
      frame = Duo::Core::FrameFactory.create_priority_frame(1, false, 0, 16)
      
      # Invalid dependency (cannot depend on itself)
      expect_raises(Duo::Error) do
        Duo::Core::FrameFactory.create_priority_frame(1, false, 1, 16)
      end
    end
  end

  describe "RST_STREAM Frame (Type 0x3)" do
    it "validates RST_STREAM frame format" do
      # RFC 9113 Section 6.4: RST_STREAM
      
      frame = Duo::Core::FrameFactory.create_rst_stream_frame(1, Duo::Error::Code::Cancel)
      
      frame.type.should eq(Duo::FrameType::RstStream)
      frame.stream_id.should eq(1)
      frame.payload.size.should eq(4) # Exactly 4 bytes
    end

    it "rejects RST_STREAM frames on stream 0" do
      # RFC 9113 Section 6.4: RST_STREAM frames MUST NOT be sent on stream 0
      
      expect_raises(Duo::Error) do
        Duo::Core::FrameFactory.create_rst_stream_frame(0, Duo::Error::Code::Cancel)
      end
    end

    it "validates RST_STREAM frame payload size" do
      # RFC 9113 Section 6.4: RST_STREAM frame payload is exactly 4 octets
      
      frame = Duo::Core::FrameFactory.create_rst_stream_frame(1, Duo::Error::Code::Cancel)
      frame.payload.size.should eq(4)
    end

    it "validates error codes" do
      # RFC 9113 Section 7: Error Codes
      
      valid_codes = [
        Duo::Error::Code::NoError,
        Duo::Error::Code::ProtocolError,
        Duo::Error::Code::InternalError,
        Duo::Error::Code::FlowControlError,
        Duo::Error::Code::SettingsTimeout,
        Duo::Error::Code::StreamClosed,
        Duo::Error::Code::FrameSizeError,
        Duo::Error::Code::RefusedStream,
        Duo::Error::Code::Cancel,
        Duo::Error::Code::CompressionError,
        Duo::Error::Code::ConnectError,
        Duo::Error::Code::EnhanceYourCalm,
        Duo::Error::Code::InadequateSecurity,
        Duo::Error::Code::Http11Required
      ]
      
      valid_codes.each do |code|
        frame = Duo::Core::FrameFactory.create_rst_stream_frame(1, code)
        # Error code should be encoded correctly
      end
    end
  end

  describe "SETTINGS Frame (Type 0x4)" do
    it "validates SETTINGS frame format" do
      # RFC 9113 Section 6.5: SETTINGS
      # SETTINGS frames MUST be sent on stream 0
      
      settings = [
        {Duo::Settings::Identifier::HeaderTableSize, 4096},
        {Duo::Settings::Identifier::MaxConcurrentStreams, 100}
      ]
      
      frame = Duo::Core::FrameFactory.create_settings_frame(settings)
      
      frame.type.should eq(Duo::FrameType::Settings)
      frame.stream_id.should eq(0)
    end

    it "requires SETTINGS frames on stream 0" do
      # RFC 9113 Section 6.5: SETTINGS frames MUST be sent on stream 0
      
      settings = [{Duo::Settings::Identifier::HeaderTableSize, 4096}]
      frame = Duo::Core::FrameFactory.create_settings_frame(settings)
      frame.stream_id.should eq(0)
    end

    it "validates SETTINGS ACK frame" do
      # RFC 9113 Section 6.5: SETTINGS ACK
      
      frame = Duo::Core::FrameFactory.create_settings_ack
      
      frame.type.should eq(Duo::FrameType::Settings)
      frame.stream_id.should eq(0)
      frame.flags.ack?.should be_true
      frame.payload.size.should eq(0)
    end

    it "validates SETTINGS frame payload size" do
      # RFC 9113 Section 6.5: SETTINGS frame payload is a multiple of 6 octets
      
      settings = [
        {Duo::Settings::Identifier::HeaderTableSize, 4096},
        {Duo::Settings::Identifier::MaxConcurrentStreams, 100}
      ]
      
      frame = Duo::Core::FrameFactory.create_settings_frame(settings)
      frame.payload.size.should eq(12) # 2 settings * 6 bytes each
    end

    it "validates SETTINGS parameters" do
      # RFC 9113 Section 6.5.2: Defined SETTINGS Parameters
      
      valid_settings = [
        {Duo::Settings::Identifier::HeaderTableSize, 4096},
        {Duo::Settings::Identifier::EnablePush, 1},
        {Duo::Settings::Identifier::MaxConcurrentStreams, 100},
        {Duo::Settings::Identifier::InitialWindowSize, 65535},
        {Duo::Settings::Identifier::MaxFrameSize, 16384},
        {Duo::Settings::Identifier::MaxHeaderListSize, 8192}
      ]
      
      valid_settings.each do |setting|
        frame = Duo::Core::FrameFactory.create_settings_frame([setting])
        # Should not raise error
      end
    end
  end

  describe "PUSH_PROMISE Frame (Type 0x5)" do
    it "validates PUSH_PROMISE frame format" do
      # RFC 9113 Section 6.6: PUSH_PROMISE
      
      headers = HTTP::Headers.new
      headers[":method"] = "GET"
      headers[":path"] = "/pushed"
      
      frame = Duo::Core::FrameFactory.create_push_promise_frame(1, 2, headers)
      
      frame.type.should eq(Duo::FrameType::PushPromise)
      frame.stream_id.should eq(1)
    end

    it "rejects PUSH_PROMISE frames on stream 0" do
      # RFC 9113 Section 6.6: PUSH_PROMISE frames MUST NOT be sent on stream 0
      
      headers = HTTP::Headers.new
      headers[":method"] = "GET"
      
      expect_raises(Duo::Error) do
        Duo::Core::FrameFactory.create_push_promise_frame(0, 2, headers)
      end
    end

    it "validates promised stream ID" do
      # RFC 9113 Section 6.6: Promised Stream ID
      
      headers = HTTP::Headers.new
      headers[":method"] = "GET"
      
      # Valid promised stream ID
      frame = Duo::Core::FrameFactory.create_push_promise_frame(1, 2, headers)
      
      # Invalid promised stream ID (0)
      expect_raises(Duo::Error) do
        Duo::Core::FrameFactory.create_push_promise_frame(1, 0, headers)
      end
    end
  end

  describe "PING Frame (Type 0x6)" do
    it "validates PING frame format" do
      # RFC 9113 Section 6.7: PING
      # PING frames MUST be sent on stream 0
      
      frame = Duo::Core::FrameFactory.create_ping_frame
      
      frame.type.should eq(Duo::FrameType::Ping)
      frame.stream_id.should eq(0)
      frame.payload.size.should eq(8) # Exactly 8 bytes
    end

    it "requires PING frames on stream 0" do
      # RFC 9113 Section 6.7: PING frames MUST be sent on stream 0
      
      frame = Duo::Core::FrameFactory.create_ping_frame
      frame.stream_id.should eq(0)
    end

    it "validates PING frame payload size" do
      # RFC 9113 Section 6.7: PING frame payload is exactly 8 octets
      
      frame = Duo::Core::FrameFactory.create_ping_frame
      frame.payload.size.should eq(8)
    end

    it "validates PING ACK frame" do
      # RFC 9113 Section 6.7: PING ACK
      
      opaque_data = Bytes.new(8)
      frame = Duo::Core::FrameFactory.create_ping_ack(opaque_data)
      
      frame.type.should eq(Duo::FrameType::Ping)
      frame.stream_id.should eq(0)
      frame.flags.ack?.should be_true
      frame.payload.should eq(opaque_data)
    end
  end

  describe "GOAWAY Frame (Type 0x7)" do
    it "validates GOAWAY frame format" do
      # RFC 9113 Section 6.8: GOAWAY
      # GOAWAY frames MUST be sent on stream 0
      
      frame = Duo::Core::FrameFactory.create_goaway_frame(1, Duo::Error::Code::NoError, "test")
      
      frame.type.should eq(Duo::FrameType::GoAway)
      frame.stream_id.should eq(0)
    end

    it "requires GOAWAY frames on stream 0" do
      # RFC 9113 Section 6.8: GOAWAY frames MUST be sent on stream 0
      
      frame = Duo::Core::FrameFactory.create_goaway_frame(1, Duo::Error::Code::NoError, "test")
      frame.stream_id.should eq(0)
    end

    it "validates GOAWAY frame minimum payload size" do
      # RFC 9113 Section 6.8: GOAWAY frame payload is at least 8 octets
      
      frame = Duo::Core::FrameFactory.create_goaway_frame(1, Duo::Error::Code::NoError, "")
      frame.payload.size.should be >= 8
    end

    it "validates last stream ID" do
      # RFC 9113 Section 6.8: Last-Stream-ID
      
      # Valid last stream ID
      frame = Duo::Core::FrameFactory.create_goaway_frame(1, Duo::Error::Code::NoError, "test")
      
      # Invalid last stream ID (negative)
      expect_raises(Duo::Error) do
        Duo::Core::FrameFactory.create_goaway_frame(-1, Duo::Error::Code::NoError, "test")
      end
    end
  end

  describe "WINDOW_UPDATE Frame (Type 0x8)" do
    it "validates WINDOW_UPDATE frame format" do
      # RFC 9113 Section 6.9: WINDOW_UPDATE
      
      frame = Duo::Core::FrameFactory.create_window_update_frame(1, 1000)
      
      frame.type.should eq(Duo::FrameType::WindowUpdate)
      frame.stream_id.should eq(1)
      frame.payload.size.should eq(4) # Exactly 4 bytes
    end

    it "validates WINDOW_UPDATE frame payload size" do
      # RFC 9113 Section 6.9: WINDOW_UPDATE frame payload is exactly 4 octets
      
      frame = Duo::Core::FrameFactory.create_window_update_frame(1, 1000)
      frame.payload.size.should eq(4)
    end

    it "validates window size increment range" do
      # RFC 9113 Section 6.9: Window Size Increment
      # Window size increment ranges from 1 to 2^31-1
      
      # Valid increments
      [1, 1000, 0x7fffffff].each do |increment|
        frame = Duo::Core::FrameFactory.create_window_update_frame(1, increment)
        # Should not raise error
      end
      
      # Invalid increments
      [0, 0x80000000].each do |increment|
        expect_raises(Duo::Error) do
          Duo::Core::FrameFactory.create_window_update_frame(1, increment)
        end
      end
    end
  end

  describe "CONTINUATION Frame (Type 0x9)" do
    it "validates CONTINUATION frame format" do
      # RFC 9113 Section 6.10: CONTINUATION
      
      headers_data = "continuation data".to_slice
      frame = Duo::Core::FrameFactory.create_continuation_frame(1, headers_data)
      
      frame.type.should eq(Duo::FrameType::Continuation)
      frame.stream_id.should eq(1)
      frame.payload.should eq(headers_data)
    end

    it "rejects CONTINUATION frames on stream 0" do
      # RFC 9113 Section 6.10: CONTINUATION frames MUST NOT be sent on stream 0
      
      headers_data = "continuation data".to_slice
      expect_raises(Duo::Error) do
        Duo::Core::FrameFactory.create_continuation_frame(0, headers_data)
      end
    end

    it "validates END_HEADERS flag" do
      # RFC 9113 Section 6.10: END_HEADERS flag
      
      headers_data = "continuation data".to_slice
      frame = Duo::Core::FrameFactory.create_continuation_frame(1, headers_data, Duo::Frame::Flags::EndHeaders)
      
      frame.flags.end_headers?.should be_true
    end
  end

  describe "Unknown Frame Types" do
    it "ignores unknown frame types" do
      # RFC 9113 Section 4.1: Unknown frame types MUST be ignored
      
      # Test with unknown frame type (0x0A)
      unknown_frame = create_test_frame_with_type(0x0A)
      unknown_frame.type.value.should eq(0x0A)
      
      # Should not raise error for unknown types
      # Implementation should handle gracefully
    end
  end

  private def create_test_frame_with_type(type : Int32) : Duo::Frame
    # Helper method to create test frames with specific types
    # This would need to be implemented based on the actual Frame class structure
    Duo::Frame.new(
      Duo::FrameType.new(type),
      1,
      Duo::Frame::Flags::None,
      Bytes.new(0)
    )
  end
end