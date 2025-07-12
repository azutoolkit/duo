require "../spec_helper"

describe Duo::Core::ConnectionManager do
  describe "RFC 9113 Compliance" do
    it "handles connection establishment correctly" do
      io = IO::Memory.new
      settings = Duo::Settings.new
      connection_manager = Duo::Core::ConnectionManager.new(
        Duo::Core::IOManager.new(io),
        Duo::Connection::Type::Server,
        settings
      )

      # Should start in connecting state
      connection_manager.connection_state.open?.should be_false
      connection_manager.connection_state.closed?.should be_false
    end

    it "processes settings frames correctly" do
      io = IO::Memory.new
      settings = Duo::Settings.new
      connection_manager = Duo::Core::ConnectionManager.new(
        Duo::Core::IOManager.new(io),
        Duo::Connection::Type::Server,
        settings
      )

      # Create a settings frame
      settings_payload = Duo::Core::SettingsPayload.new([
        {Duo::Settings::Identifier::HeaderTableSize, 4096},
        {Duo::Settings::Identifier::MaxConcurrentStreams, 100}
      ])

      header = Duo::Core::FrameHeader.new(
        Duo::FrameType::Settings,
        Duo::Frame::Flags::None,
        0,
        settings_payload.settings.size * 6,
        4
      )

      # Process the frame
      connection_manager.send("process_frame", header, settings_payload)

      # Should send ACK
      io.size.should be > 0
    end

    it "handles flow control errors correctly" do
      io = IO::Memory.new
      settings = Duo::Settings.new
      connection_manager = Duo::Core::ConnectionManager.new(
        Duo::Core::IOManager.new(io),
        Duo::Connection::Type::Server,
        settings
      )

      # Try to update window with invalid increment
      expect_raises(Duo::Error) do
        window_update_payload = Duo::Core::WindowUpdatePayload.new(0)
        header = Duo::Core::FrameHeader.new(
          Duo::FrameType::WindowUpdate,
          Duo::Frame::Flags::None,
          0,
          4,
          8
        )
        connection_manager.send("process_window_update_frame", header, window_update_payload)
      end
    end

    it "validates frame sizes correctly" do
      io = IO::Memory.new
      settings = Duo::Settings.new
      connection_manager = Duo::Core::ConnectionManager.new(
        Duo::Core::IOManager.new(io),
        Duo::Connection::Type::Server,
        settings
      )

      # Try to send frame larger than max frame size
      large_data = Bytes.new(settings.max_frame_size + 1)
      expect_raises(Duo::Error) do
        frame = Duo::Core::FrameFactory.create_data_frame(1, large_data)
        connection_manager.send("send_frame", frame)
      end
    end
  end

  describe "Error Handling" do
    it "handles protocol errors with GOAWAY" do
      io = IO::Memory.new
      settings = Duo::Settings.new
      connection_manager = Duo::Core::ConnectionManager.new(
        Duo::Core::IOManager.new(io),
        Duo::Connection::Type::Server,
        settings
      )

      # Simulate protocol error
      connection_manager.send_goaway(Duo::Error::Code::ProtocolError, 0, "Test error")

      # Should close connection
      connection_manager.connection_state.closed?.should be_true
    end

    it "handles stream errors with RST_STREAM" do
      io = IO::Memory.new
      settings = Duo::Settings.new
      connection_manager = Duo::Core::ConnectionManager.new(
        Duo::Core::IOManager.new(io),
        Duo::Connection::Type::Server,
        settings
      )

      # Create a stream
      stream = connection_manager.stream_manager.create_stream

      # Simulate stream error
      stream.send_rst_stream(Duo::Error::Code::StreamClosed)

      # Stream should be closed
      stream.closed?.should be_true
    end
  end

  describe "Flow Control" do
    it "manages connection-level flow control correctly" do
      io = IO::Memory.new
      settings = Duo::Settings.new
      connection_manager = Duo::Core::ConnectionManager.new(
        Duo::Core::IOManager.new(io),
        Duo::Connection::Type::Server,
        settings
      )

      flow_control = connection_manager.flow_control

      # Initial window size
      flow_control.connection_window_size.should eq(settings.initial_window_size)

      # Update window
      result = flow_control.update_connection_window(1000)
      result.success.should be_true

      # Check new window size
      flow_control.connection_window_size.should eq(settings.initial_window_size + 1000)
    end

    it "manages stream-level flow control correctly" do
      io = IO::Memory.new
      settings = Duo::Settings.new
      connection_manager = Duo::Core::ConnectionManager.new(
        Duo::Core::IOManager.new(io),
        Duo::Connection::Type::Server,
        settings
      )

      flow_control = connection_manager.flow_control

      # Register stream
      flow_control.register_stream(1)

      # Update stream window
      result = flow_control.update_stream_window(1, 500)
      result.success.should be_true

      # Check stream window size
      flow_control.stream_window_size(1).should eq(settings.initial_window_size + 500)
    end

    it "prevents flow control window overflow" do
      io = IO::Memory.new
      settings = Duo::Settings.new
      connection_manager = Duo::Core::ConnectionManager.new(
        Duo::Core::IOManager.new(io),
        Duo::Connection::Type::Server,
        settings
      )

      flow_control = connection_manager.flow_control

      # Try to exceed maximum window size
      result = flow_control.update_connection_window(Duo::MAXIMUM_WINDOW_SIZE + 1)
      result.error?.should be_true
      result.error_code.should eq(Duo::Error::Code::FlowControlError)
    end
  end

  describe "Stream Management" do
    it "creates and manages streams correctly" do
      io = IO::Memory.new
      settings = Duo::Settings.new
      connection_manager = Duo::Core::ConnectionManager.new(
        Duo::Core::IOManager.new(io),
        Duo::Connection::Type::Server,
        settings
      )

      stream_manager = connection_manager.stream_manager

      # Create stream
      stream = stream_manager.create_stream
      stream.id.should be > 0
      stream.active?.should be_true

      # Find stream
      found_stream = stream_manager.find_stream(stream.id, create: false)
      found_stream.should eq(stream)

      # Remove stream
      stream_manager.remove_stream(stream.id)
      stream_manager.find_stream(stream.id, create: false).should be_nil
    end

    it "enforces concurrent stream limits" do
      io = IO::Memory.new
      settings = Duo::Settings.new
      connection_manager = Duo::Core::ConnectionManager.new(
        Duo::Core::IOManager.new(io),
        Duo::Connection::Type::Server,
        settings
      )

      stream_manager = connection_manager.stream_manager

      # Create maximum number of streams
      settings.max_concurrent_streams.times do
        stream_manager.create_stream
      end

      # Next stream should fail
      expect_raises(Duo::Error) do
        stream_manager.create_stream
      end
    end
  end

  describe "HPACK Management" do
    it "encodes and decodes headers correctly" do
      io = IO::Memory.new
      settings = Duo::Settings.new
      connection_manager = Duo::Core::ConnectionManager.new(
        Duo::Core::IOManager.new(io),
        Duo::Connection::Type::Server,
        settings
      )

      hpack_manager = connection_manager.hpack_manager

      # Create headers
      headers = HTTP::Headers.new
      headers["content-type"] = "text/plain"
      headers["content-length"] = "100"

      # Encode headers
      encoded = hpack_manager.encode_headers(headers)
      encoded.size.should be > 0

      # Decode headers
      decoded = hpack_manager.decode_headers(encoded)
      decoded["content-type"].should eq("text/plain")
      decoded["content-length"].should eq("100")
    end

    it "validates header list size limits" do
      io = IO::Memory.new
      settings = Duo::Settings.new
      connection_manager = Duo::Core::ConnectionManager.new(
        Duo::Core::IOManager.new(io),
        Duo::Connection::Type::Server,
        settings
      )

      hpack_manager = connection_manager.hpack_manager

      # Create headers that exceed limit
      headers = HTTP::Headers.new
      large_value = "x" * (settings.max_header_list_size + 1)
      headers["x-large-header"] = large_value

      # Should raise error
      expect_raises(Duo::Error) do
        hpack_manager.encode_headers(headers)
      end
    end
  end

  describe "Memory Management" do
    it "properly cleans up resources" do
      io = IO::Memory.new
      settings = Duo::Settings.new
      connection_manager = Duo::Core::ConnectionManager.new(
        Duo::Core::IOManager.new(io),
        Duo::Connection::Type::Server,
        settings
      )

      # Create some streams
      5.times { connection_manager.stream_manager.create_stream }

      # Close connection
      connection_manager.close

      # Should be closed
      connection_manager.connection_state.closed?.should be_true

      # All streams should be closed
      connection_manager.stream_manager.all_streams.size.should eq(0)
    end

    it "prevents memory leaks in buffer pools" do
      io = IO::Memory.new
      settings = Duo::Settings.new
      connection_manager = Duo::Core::ConnectionManager.new(
        Duo::Core::IOManager.new(io),
        Duo::Connection::Type::Server,
        settings
      )

      # Send multiple frames to test buffer pool
      100.times do
        frame = Duo::Core::FrameFactory.create_ping_frame
        connection_manager.send("send_frame", frame)
      end

      # Close connection
      connection_manager.close

      # Should not leak memory
      # (This is a basic test - in practice you'd use memory profiling tools)
    end
  end
end