require "../spec_helper"

describe Duo::Core::FrameParser do
  describe "#parse_frame_header" do
    it "parses DATA frame header correctly" do
      io = IO::Memory.new
      # Write frame header: size=100, type=0 (DATA), flags=0, stream_id=1
      io.write_bytes((100_u32 << 8) | 0_u8, IO::ByteFormat::BigEndian)
      io.write_byte(0_u8) # flags
      io.write_bytes(1_u32, IO::ByteFormat::BigEndian) # stream_id
      
      parser = Duo::Core::FrameParser.new(io, 16384)
      header = parser.parse_frame_header
      
      header.type.should eq(Duo::FrameType::Data)
      header.size.should eq(100)
      header.flags.should eq(Duo::Frame::Flags::None)
      header.stream_id.should eq(1)
    end

    it "parses HEADERS frame header correctly" do
      io = IO::Memory.new
      # Write frame header: size=200, type=1 (HEADERS), flags=4 (END_HEADERS), stream_id=3
      io.write_bytes((200_u32 << 8) | 1_u8, IO::ByteFormat::BigEndian)
      io.write_byte(4_u8) # flags (END_HEADERS)
      io.write_bytes(3_u32, IO::ByteFormat::BigEndian) # stream_id
      
      parser = Duo::Core::FrameParser.new(io, 16384)
      header = parser.parse_frame_header
      
      header.type.should eq(Duo::FrameType::Headers)
      header.size.should eq(200)
      header.flags.should eq(Duo::Frame::Flags::EndHeaders)
      header.stream_id.should eq(3)
    end

    it "raises error for frame size exceeding maximum" do
      io = IO::Memory.new
      # Write frame header with size larger than max
      io.write_bytes((20000_u32 << 8) | 0_u8, IO::ByteFormat::BigEndian)
      io.write_byte(0_u8)
      io.write_bytes(1_u32, IO::ByteFormat::BigEndian)
      
      parser = Duo::Core::FrameParser.new(io, 16384)
      
      expect_raises(Duo::Error::FrameSizeError, "Frame size 20000 exceeds maximum 16384") do
        parser.parse_frame_header
      end
    end

    it "handles unknown frame types gracefully" do
      io = IO::Memory.new
      # Write frame header with unknown type (255)
      io.write_bytes((100_u32 << 8) | 255_u8, IO::ByteFormat::BigEndian)
      io.write_byte(0_u8)
      io.write_bytes(1_u32, IO::ByteFormat::BigEndian)
      
      parser = Duo::Core::FrameParser.new(io, 16384)
      header = parser.parse_frame_header
      
      # Should default to Data frame type for unknown types
      header.type.should eq(Duo::FrameType::Data)
      header.raw_type.should eq(255)
    end
  end

  describe "#parse_frame_payload" do
    it "parses DATA frame payload correctly" do
      io = IO::Memory.new
      # Write frame header
      io.write_bytes((5_u32 << 8) | 0_u8, IO::ByteFormat::BigEndian)
      io.write_byte(0_u8)
      io.write_bytes(1_u32, IO::ByteFormat::BigEndian)
      # Write payload
      io.write("Hello".to_slice)
      
      parser = Duo::Core::FrameParser.new(io, 16384)
      header = parser.parse_frame_header
      payload = parser.parse_frame_payload(header)
      
      payload.should be_a(Duo::Core::DataPayload)
      data_payload = payload.as(Duo::Core::DataPayload)
      data_payload.data.should eq("Hello".to_slice)
      data_payload.padded.should be_false
    end

    it "parses padded DATA frame payload correctly" do
      io = IO::Memory.new
      # Write frame header with PADDED flag
      io.write_bytes((7_u32 << 8) | 0_u8, IO::ByteFormat::BigEndian)
      io.write_byte(8_u8) # PADDED flag
      io.write_bytes(1_u32, IO::ByteFormat::BigEndian)
      # Write payload: pad_length=2, data="Hi", padding=2 bytes
      io.write_byte(2_u8) # pad_length
      io.write("Hi".to_slice)
      io.write_bytes(0_u16, IO::ByteFormat::BigEndian) # padding
      
      parser = Duo::Core::FrameParser.new(io, 16384)
      header = parser.parse_frame_header
      payload = parser.parse_frame_payload(header)
      
      payload.should be_a(Duo::Core::DataPayload)
      data_payload = payload.as(Duo::Core::DataPayload)
      data_payload.data.should eq("Hi".to_slice)
      data_payload.padded.should be_true
    end

    it "parses HEADERS frame payload correctly" do
      io = IO::Memory.new
      # Write frame header
      io.write_bytes((10_u32 << 8) | 1_u8, IO::ByteFormat::BigEndian)
      io.write_byte(4_u8) # END_HEADERS flag
      io.write_bytes(1_u32, IO::ByteFormat::BigEndian)
      # Write HPACK encoded headers (simplified)
      io.write_bytes(0x82_u8) # indexed header (":method" = "GET")
      
      parser = Duo::Core::FrameParser.new(io, 16384)
      header = parser.parse_frame_header
      payload = parser.parse_frame_payload(header)
      
      payload.should be_a(Duo::Core::HeadersPayload)
      headers_payload = payload.as(Duo::Core::HeadersPayload)
      headers_payload.headers_data.size.should eq(1)
      headers_payload.padded.should be_false
    end

    it "parses PRIORITY frame payload correctly" do
      io = IO::Memory.new
      # Write frame header
      io.write_bytes((5_u32 << 8) | 2_u8, IO::ByteFormat::BigEndian)
      io.write_byte(0_u8)
      io.write_bytes(1_u32, IO::ByteFormat::BigEndian)
      # Write priority payload: exclusive=0, dependency=0, weight=16
      io.write_bytes(0_u32, IO::ByteFormat::BigEndian) # exclusive + dependency
      io.write_byte(15_u8) # weight - 1
      
      parser = Duo::Core::FrameParser.new(io, 16384)
      header = parser.parse_frame_header
      payload = parser.parse_frame_payload(header)
      
      payload.should be_a(Duo::Core::PriorityPayload)
      priority_payload = payload.as(Duo::Core::PriorityPayload)
      priority_payload.exclusive.should be_false
      priority_payload.dependency_stream_id.should eq(0)
      priority_payload.weight.should eq(16)
    end

    it "raises error for invalid PRIORITY frame size" do
      io = IO::Memory.new
      # Write frame header with wrong size
      io.write_bytes((6_u32 << 8) | 2_u8, IO::ByteFormat::BigEndian)
      io.write_byte(0_u8)
      io.write_bytes(1_u32, IO::ByteFormat::BigEndian)
      # Write payload
      io.write_bytes(0_u32, IO::ByteFormat::BigEndian)
      io.write_byte(15_u8)
      io.write_byte(0_u8) # extra byte
      
      parser = Duo::Core::FrameParser.new(io, 16384)
      header = parser.parse_frame_header
      
      expect_raises(Duo::Error::FrameSizeError) do
        parser.parse_frame_payload(header)
      end
    end

    it "parses RST_STREAM frame payload correctly" do
      io = IO::Memory.new
      # Write frame header
      io.write_bytes((4_u32 << 8) | 3_u8, IO::ByteFormat::BigEndian)
      io.write_byte(0_u8)
      io.write_bytes(1_u32, IO::ByteFormat::BigEndian)
      # Write error code
      io.write_bytes(Duo::Error::Code::ProtocolError.value.to_u32, IO::ByteFormat::BigEndian)
      
      parser = Duo::Core::FrameParser.new(io, 16384)
      header = parser.parse_frame_header
      payload = parser.parse_frame_payload(header)
      
      payload.should be_a(Duo::Core::RstStreamPayload)
      rst_payload = payload.as(Duo::Core::RstStreamPayload)
      rst_payload.error_code.should eq(Duo::Error::Code::ProtocolError)
    end

    it "parses SETTINGS frame payload correctly" do
      io = IO::Memory.new
      # Write frame header
      io.write_bytes((6_u32 << 8) | 4_u8, IO::ByteFormat::BigEndian)
      io.write_byte(0_u8)
      io.write_bytes(0_u32, IO::ByteFormat::BigEndian)
      # Write settings: HEADER_TABLE_SIZE = 4096
      io.write_bytes(Duo::Settings::Identifier::HeaderTableSize.to_u16, IO::ByteFormat::BigEndian)
      io.write_bytes(4096_u32, IO::ByteFormat::BigEndian)
      
      parser = Duo::Core::FrameParser.new(io, 16384)
      header = parser.parse_frame_header
      payload = parser.parse_frame_payload(header)
      
      payload.should be_a(Duo::Core::SettingsPayload)
      settings_payload = payload.as(Duo::Core::SettingsPayload)
      settings_payload.settings.size.should eq(1)
      settings_payload.settings.first.should eq({Duo::Settings::Identifier::HeaderTableSize, 4096})
      settings_payload.ack.should be_false
    end

    it "parses SETTINGS ACK frame payload correctly" do
      io = IO::Memory.new
      # Write frame header with ACK flag
      io.write_bytes((0_u32 << 8) | 4_u8, IO::ByteFormat::BigEndian)
      io.write_byte(1_u8) # ACK flag
      io.write_bytes(0_u32, IO::ByteFormat::BigEndian)
      
      parser = Duo::Core::FrameParser.new(io, 16384)
      header = parser.parse_frame_header
      payload = parser.parse_frame_payload(header)
      
      payload.should be_a(Duo::Core::SettingsPayload)
      settings_payload = payload.as(Duo::Core::SettingsPayload)
      settings_payload.ack.should be_true
      settings_payload.settings.should be_empty
    end

    it "parses PING frame payload correctly" do
      io = IO::Memory.new
      # Write frame header
      io.write_bytes((8_u32 << 8) | 6_u8, IO::ByteFormat::BigEndian)
      io.write_byte(0_u8)
      io.write_bytes(0_u32, IO::ByteFormat::BigEndian)
      # Write ping data
      io.write_bytes(0x1234567890ABCDEF_u64, IO::ByteFormat::BigEndian)
      
      parser = Duo::Core::FrameParser.new(io, 16384)
      header = parser.parse_frame_header
      payload = parser.parse_frame_payload(header)
      
      payload.should be_a(Duo::Core::PingPayload)
      ping_payload = payload.as(Duo::Core::PingPayload)
      ping_payload.opaque_data.size.should eq(8)
      ping_payload.ack.should be_false
    end

    it "parses GOAWAY frame payload correctly" do
      io = IO::Memory.new
      # Write frame header
      io.write_bytes((12_u32 << 8) | 7_u8, IO::ByteFormat::BigEndian)
      io.write_byte(0_u8)
      io.write_bytes(0_u32, IO::ByteFormat::BigEndian)
      # Write last stream ID and error code
      io.write_bytes(5_u32, IO::ByteFormat::BigEndian)
      io.write_bytes(Duo::Error::Code::ProtocolError.value.to_u32, IO::ByteFormat::BigEndian)
      # Write debug data
      io.write("Error".to_slice)
      
      parser = Duo::Core::FrameParser.new(io, 16384)
      header = parser.parse_frame_header
      payload = parser.parse_frame_payload(header)
      
      payload.should be_a(Duo::Core::GoAwayPayload)
      goaway_payload = payload.as(Duo::Core::GoAwayPayload)
      goaway_payload.last_stream_id.should eq(5)
      goaway_payload.error_code.should eq(Duo::Error::Code::ProtocolError)
      goaway_payload.debug_data.should eq("Error".to_slice)
    end

    it "parses WINDOW_UPDATE frame payload correctly" do
      io = IO::Memory.new
      # Write frame header
      io.write_bytes((4_u32 << 8) | 8_u8, IO::ByteFormat::BigEndian)
      io.write_byte(0_u8)
      io.write_bytes(1_u32, IO::ByteFormat::BigEndian)
      # Write window size increment
      io.write_bytes(1000_u32, IO::ByteFormat::BigEndian)
      
      parser = Duo::Core::FrameParser.new(io, 16384)
      header = parser.parse_frame_header
      payload = parser.parse_frame_payload(header)
      
      payload.should be_a(Duo::Core::WindowUpdatePayload)
      window_payload = payload.as(Duo::Core::WindowUpdatePayload)
      window_payload.window_size_increment.should eq(1000)
    end

    it "handles CONTINUATION frames correctly" do
      io = IO::Memory.new
      # Write frame header
      io.write_bytes((5_u32 << 8) | 9_u8, IO::ByteFormat::BigEndian)
      io.write_byte(0_u8)
      io.write_bytes(1_u32, IO::ByteFormat::BigEndian)
      # Write continuation data
      io.write("data".to_slice)
      
      parser = Duo::Core::FrameParser.new(io, 16384)
      header = parser.parse_frame_header
      payload = parser.parse_frame_payload(header)
      
      payload.should be_a(Duo::Core::ContinuationPayload)
      cont_payload = payload.as(Duo::Core::ContinuationPayload)
      cont_payload.headers_data.should eq("data".to_slice)
    end

    it "handles unknown frame types correctly" do
      io = IO::Memory.new
      # Write frame header with unknown type
      io.write_bytes((5_u32 << 8) | 255_u8, IO::ByteFormat::BigEndian)
      io.write_byte(0_u8)
      io.write_bytes(1_u32, IO::ByteFormat::BigEndian)
      # Write unknown payload
      io.write("unknown".to_slice)
      
      parser = Duo::Core::FrameParser.new(io, 16384)
      header = parser.parse_frame_header
      payload = parser.parse_frame_payload(header)
      
      payload.should be_a(Duo::Core::UnknownPayload)
      unknown_payload = payload.as(Duo::Core::UnknownPayload)
      unknown_payload.data.should eq("unknown".to_slice)
      unknown_payload.raw_type.should eq(255)
    end
  end

  describe "error handling" do
    it "raises error for invalid pad length" do
      io = IO::Memory.new
      # Write frame header with PADDED flag
      io.write_bytes((2_u32 << 8) | 0_u8, IO::ByteFormat::BigEndian)
      io.write_byte(8_u8) # PADDED flag
      io.write_bytes(1_u32, IO::ByteFormat::BigEndian)
      # Write invalid pad length (larger than frame size)
      io.write_byte(3_u8) # pad_length > frame_size - 1
      
      parser = Duo::Core::FrameParser.new(io, 16384)
      header = parser.parse_frame_header
      
      expect_raises(Duo::Error::ProtocolError, "Invalid pad length") do
        parser.parse_frame_payload(header)
      end
    end

    it "raises error for malformed CONTINUATION frame sequence" do
      io = IO::Memory.new
      # Write HEADERS frame header without END_HEADERS flag
      io.write_bytes((5_u32 << 8) | 1_u8, IO::ByteFormat::BigEndian)
      io.write_byte(0_u8) # no END_HEADERS flag
      io.write_bytes(1_u32, IO::ByteFormat::BigEndian)
      io.write("data".to_slice)
      
      # Write non-CONTINUATION frame
      io.write_bytes((5_u32 << 8) | 0_u8, IO::ByteFormat::BigEndian) # DATA frame
      io.write_byte(0_u8)
      io.write_bytes(1_u32, IO::ByteFormat::BigEndian)
      io.write("data".to_slice)
      
      parser = Duo::Core::FrameParser.new(io, 16384)
      header = parser.parse_frame_header
      
      expect_raises(Duo::Error::ProtocolError, "Expected continuation frame") do
        parser.parse_frame_payload(header)
      end
    end

    it "raises error for CONTINUATION frame on wrong stream" do
      io = IO::Memory.new
      # Write HEADERS frame header
      io.write_bytes((5_u32 << 8) | 1_u8, IO::ByteFormat::BigEndian)
      io.write_byte(0_u8) # no END_HEADERS flag
      io.write_bytes(1_u32, IO::ByteFormat::BigEndian)
      io.write("data".to_slice)
      
      # Write CONTINUATION frame on different stream
      io.write_bytes((5_u32 << 8) | 9_u8, IO::ByteFormat::BigEndian)
      io.write_byte(0_u8)
      io.write_bytes(3_u32, IO::ByteFormat::BigEndian) # different stream
      io.write("data".to_slice)
      
      parser = Duo::Core::FrameParser.new(io, 16384)
      header = parser.parse_frame_header
      
      expect_raises(Duo::Error::ProtocolError, "Continuation frame for wrong stream") do
        parser.parse_frame_payload(header)
      end
    end
  end
end