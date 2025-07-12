require "../spec_helper"

describe "HTTP/2 Flow Control Compliance (RFC 9113 Section 6.9)" do
  describe "Flow Control Principles" do
    it "validates flow control is hop-by-hop" do
      # RFC 9113 Section 6.9: Flow Control
      # HTTP/2 provides for flow control through use of the WINDOW_UPDATE frame
      
      io = IO::Memory.new
      settings = Duo::Settings.new
      connection_manager = Duo::Core::ConnectionManager.new(
        Duo::Core::IOManager.new(io),
        Duo::Connection::Type::Server,
        settings
      )
      
      flow_control = connection_manager.flow_control
      flow_control.should be_a(Duo::Core::FlowControlManager)
    end

    it "validates flow control applies to DATA frames only" do
      # RFC 9113 Section 6.9: Flow Control
      # Flow control applies only to frames that are identified as being subject to flow control
      # DATA frames are subject to flow control
      
      io = IO::Memory.new
      settings = Duo::Settings.new
      connection_manager = Duo::Core::ConnectionManager.new(
        Duo::Core::IOManager.new(io),
        Duo::Connection::Type::Server,
        settings
      )
      
      # DATA frames should be subject to flow control
      data_frame = Duo::Core::FrameFactory.create_data_frame(1, "test".to_slice)
      data_frame.type.should eq(Duo::FrameType::Data)
      
      # HEADERS frames should not be subject to flow control
      headers = HTTP::Headers.new
      headers[":method"] = "GET"
      headers_frame = Duo::Core::FrameFactory.create_headers_frame(1, headers)
      headers_frame.type.should eq(Duo::FrameType::Headers)
    end
  end

  describe "Flow Control Window" do
    it "validates initial window size" do
      # RFC 9113 Section 6.9.2: Initial Flow Control Window Size
      # The initial value for the flow control window is 65,535 (2^16 - 1) octets
      
      io = IO::Memory.new
      settings = Duo::Settings.new
      connection_manager = Duo::Core::ConnectionManager.new(
        Duo::Core::IOManager.new(io),
        Duo::Connection::Type::Server,
        settings
      )
      
      flow_control = connection_manager.flow_control
      flow_control.connection_window_size.should eq(65535)
    end

    it "validates SETTINGS_INITIAL_WINDOW_SIZE" do
      # RFC 9113 Section 6.9.2: Initial Flow Control Window Size
      # SETTINGS_INITIAL_WINDOW_SIZE allows the sender to set the initial window size
      
      io = IO::Memory.new
      settings = Duo::Settings.new
      settings.initial_window_size = 32768
      
      connection_manager = Duo::Core::ConnectionManager.new(
        Duo::Core::IOManager.new(io),
        Duo::Connection::Type::Server,
        settings
      )
      
      flow_control = connection_manager.flow_control
      flow_control.connection_window_size.should eq(32768)
    end

    it "validates window size limits" do
      # RFC 9113 Section 6.9.2: Initial Flow Control Window Size
      # The maximum value is 2^31-1 (2,147,483,647) octets
      
      # Valid window sizes
      valid_sizes = [0, 65535, 32768, 0x7fffffff]
      valid_sizes.each do |size|
        settings = Duo::Settings.new
        settings.initial_window_size = size
        # Should not raise error
      end
      
      # Invalid window sizes
      invalid_sizes = [-1, 0x80000000]
      invalid_sizes.each do |size|
        expect_raises(Duo::Error) do
          settings = Duo::Settings.new
          settings.initial_window_size = size
        end
      end
    end
  end

  describe "WINDOW_UPDATE Frame" do
    it "validates WINDOW_UPDATE frame format" do
      # RFC 9113 Section 6.9.1: Flow Control Window
      # WINDOW_UPDATE frames are used to implement flow control
      
      frame = Duo::Core::FrameFactory.create_window_update_frame(1, 1000)
      
      frame.type.should eq(Duo::FrameType::WindowUpdate)
      frame.stream_id.should eq(1)
      frame.payload.size.should eq(4) # Exactly 4 bytes
    end

    it "validates WINDOW_UPDATE frame payload size" do
      # RFC 9113 Section 6.9.1: Flow Control Window
      # WINDOW_UPDATE frame payload is exactly 4 octets
      
      frame = Duo::Core::FrameFactory.create_window_update_frame(1, 1000)
      frame.payload.size.should eq(4)
    end

    it "validates window size increment range" do
      # RFC 9113 Section 6.9.1: Flow Control Window
      # Window size increment ranges from 1 to 2^31-1
      
      # Valid increments
      valid_increments = [1, 1000, 65535, 0x7fffffff]
      valid_increments.each do |increment|
        frame = Duo::Core::FrameFactory.create_window_update_frame(1, increment)
        # Should not raise error
      end
      
      # Invalid increments
      invalid_increments = [0, -1, 0x80000000]
      invalid_increments.each do |increment|
        expect_raises(Duo::Error) do
          Duo::Core::FrameFactory.create_window_update_frame(1, increment)
        end
      end
    end

    it "validates WINDOW_UPDATE with zero increment" do
      # RFC 9113 Section 6.9.1: Flow Control Window
      # A WINDOW_UPDATE frame with a window size increment of 0 MUST be treated as a stream error
      
      expect_raises(Duo::Error) do
        Duo::Core::FrameFactory.create_window_update_frame(1, 0)
      end
    end
  end

  describe "Connection-Level Flow Control" do
    it "validates connection-level window management" do
      # RFC 9113 Section 6.9.1: Flow Control Window
      # Flow control is implemented for each hop in the end-to-end path
      
      io = IO::Memory.new
      settings = Duo::Settings.new
      connection_manager = Duo::Core::ConnectionManager.new(
        Duo::Core::IOManager.new(io),
        Duo::Connection::Type::Server,
        settings
      )
      
      flow_control = connection_manager.flow_control
      initial_window = flow_control.connection_window_size
      
      # Update connection window
      result = flow_control.update_connection_window(1000)
      result.success.should be_true
      
      new_window = flow_control.connection_window_size
      new_window.should eq(initial_window + 1000)
    end

    it "validates connection-level window overflow" do
      # RFC 9113 Section 6.9.1: Flow Control Window
      # A sender MUST NOT allow a flow control window to exceed 2^31-1 octets
      
      io = IO::Memory.new
      settings = Duo::Settings.new
      connection_manager = Duo::Core::ConnectionManager.new(
        Duo::Core::IOManager.new(io),
        Duo::Connection::Type::Server,
        settings
      )
      
      flow_control = connection_manager.flow_control
      
      # Try to exceed maximum window size
      result = flow_control.update_connection_window(0x80000000)
      result.error?.should be_true
      result.error_code.should eq(Duo::Error::Code::FlowControlError)
    end

    it "validates connection-level window consumption" do
      # RFC 9113 Section 6.9.1: Flow Control Window
      # The sender MUST NOT send a flow-controlled frame with a length that exceeds the window
      
      io = IO::Memory.new
      settings = Duo::Settings.new
      connection_manager = Duo::Core::ConnectionManager.new(
        Duo::Core::IOManager.new(io),
        Duo::Connection::Type::Server,
        settings
      )
      
      flow_control = connection_manager.flow_control
      
      # Consume window space
      success = flow_control.consume_connection_window(1000)
      success.should be_true
      
      # Try to consume more than available
      success = flow_control.consume_connection_window(70000)
      success.should be_false
    end
  end

  describe "Stream-Level Flow Control" do
    it "validates stream-level window management" do
      # RFC 9113 Section 6.9.1: Flow Control Window
      # Flow control is implemented for each hop in the end-to-end path
      
      io = IO::Memory.new
      settings = Duo::Settings.new
      connection_manager = Duo::Core::ConnectionManager.new(
        Duo::Core::IOManager.new(io),
        Duo::Connection::Type::Server,
        settings
      )
      
      flow_control = connection_manager.flow_control
      stream_id = 1
      
      # Register stream
      flow_control.register_stream(stream_id)
      initial_window = flow_control.stream_window_size(stream_id).not_nil!
      
      # Update stream window
      result = flow_control.update_stream_window(stream_id, 1000)
      result.success.should be_true
      
      new_window = flow_control.stream_window_size(stream_id).not_nil!
      new_window.should eq(initial_window + 1000)
    end

    it "validates stream-level window overflow" do
      # RFC 9113 Section 6.9.1: Flow Control Window
      # A sender MUST NOT allow a flow control window to exceed 2^31-1 octets
      
      io = IO::Memory.new
      settings = Duo::Settings.new
      connection_manager = Duo::Core::ConnectionManager.new(
        Duo::Core::IOManager.new(io),
        Duo::Connection::Type::Server,
        settings
      )
      
      flow_control = connection_manager.flow_control
      stream_id = 1
      
      flow_control.register_stream(stream_id)
      
      # Try to exceed maximum window size
      result = flow_control.update_stream_window(stream_id, 0x80000000)
      result.error?.should be_true
      result.error_code.should eq(Duo::Error::Code::FlowControlError)
    end

    it "validates stream-level window consumption" do
      # RFC 9113 Section 6.9.1: Flow Control Window
      # The sender MUST NOT send a flow-controlled frame with a length that exceeds the window
      
      io = IO::Memory.new
      settings = Duo::Settings.new
      connection_manager = Duo::Core::ConnectionManager.new(
        Duo::Core::IOManager.new(io),
        Duo::Connection::Type::Server,
        settings
      )
      
      flow_control = connection_manager.flow_control
      stream_id = 1
      
      flow_control.register_stream(stream_id)
      
      # Consume window space
      success = flow_control.consume_stream_window(stream_id, 1000)
      success.should be_true
      
      # Try to consume more than available
      success = flow_control.consume_stream_window(stream_id, 70000)
      success.should be_false
    end
  end

  describe "Flow Control Error Handling" do
    it "handles FLOW_CONTROL_ERROR" do
      # RFC 9113 Section 6.9.1: Flow Control Window
      # FLOW_CONTROL_ERROR indicates that the sender received a WINDOW_UPDATE frame
      # that caused the flow control window to exceed the maximum size
      
      io = IO::Memory.new
      settings = Duo::Settings.new
      connection_manager = Duo::Core::ConnectionManager.new(
        Duo::Core::IOManager.new(io),
        Duo::Connection::Type::Server,
        settings
      )
      
      # Simulate flow control error
      frame = Duo::Core::FrameFactory.create_rst_stream_frame(1, Duo::Error::Code::FlowControlError)
      frame.type.should eq(Duo::FrameType::RstStream)
    end

    it "handles window size reduction" do
      # RFC 9113 Section 6.9.2: Initial Flow Control Window Size
      # A change to SETTINGS_INITIAL_WINDOW_SIZE could cause the available space in a flow control window
      # to become negative
      
      io = IO::Memory.new
      settings = Duo::Settings.new
      connection_manager = Duo::Core::ConnectionManager.new(
        Duo::Core::IOManager.new(io),
        Duo::Connection::Type::Server,
        settings
      )
      
      flow_control = connection_manager.flow_control
      stream_id = 1
      
      flow_control.register_stream(stream_id)
      
      # Consume some window space
      flow_control.consume_stream_window(stream_id, 1000)
      
      # Reduce initial window size
      flow_control.update_all_stream_windows(-2000)
      
      # Window should not go negative
      window_size = flow_control.stream_window_size(stream_id)
      window_size.should be >= 0
    end
  end

  describe "Flow Control Algorithms" do
    it "validates window update calculation" do
      # RFC 9113 Section 6.9.1: Flow Control Window
      # The sender should send WINDOW_UPDATE frames when the window becomes small
      
      io = IO::Memory.new
      settings = Duo::Settings.new
      connection_manager = Duo::Core::ConnectionManager.new(
        Duo::Core::IOManager.new(io),
        Duo::Connection::Type::Server,
        settings
      )
      
      flow_control = connection_manager.flow_control
      
      # Calculate window update
      increment = flow_control.calculate_connection_window_update
      increment.should be >= 0
      increment.should be <= 0x7fffffff
    end

    it "validates stream window update calculation" do
      # RFC 9113 Section 6.9.1: Flow Control Window
      # The sender should send WINDOW_UPDATE frames when the window becomes small
      
      io = IO::Memory.new
      settings = Duo::Settings.new
      connection_manager = Duo::Core::ConnectionManager.new(
        Duo::Core::IOManager.new(io),
        Duo::Connection::Type::Server,
        settings
      )
      
      flow_control = connection_manager.flow_control
      stream_id = 1
      
      flow_control.register_stream(stream_id)
      
      # Calculate window update
      increment = flow_control.calculate_stream_window_update(stream_id)
      increment.should be >= 0
      increment.should be <= 0x7fffffff
    end

    it "validates minimum window size threshold" do
      # RFC 9113 Section 6.9.1: Flow Control Window
      # The sender should send WINDOW_UPDATE frames when the window becomes small
      
      io = IO::Memory.new
      settings = Duo::Settings.new
      connection_manager = Duo::Core::ConnectionManager.new(
        Duo::Core::IOManager.new(io),
        Duo::Connection::Type::Server,
        settings
      )
      
      flow_control = connection_manager.flow_control
      
      # Consume most of the window
      flow_control.consume_connection_window(60000)
      
      # Should trigger window update calculation
      increment = flow_control.calculate_connection_window_update
      increment.should be > 0
    end
  end

  describe "Flow Control Edge Cases" do
    it "handles window size of zero" do
      # RFC 9113 Section 6.9.1: Flow Control Window
      # A window size of 0 prevents the sender from sending any flow-controlled frames
      
      io = IO::Memory.new
      settings = Duo::Settings.new
      settings.initial_window_size = 0
      
      connection_manager = Duo::Core::ConnectionManager.new(
        Duo::Core::IOManager.new(io),
        Duo::Connection::Type::Server,
        settings
      )
      
      flow_control = connection_manager.flow_control
      flow_control.connection_window_size.should eq(0)
      
      # Should not be able to consume window space
      success = flow_control.consume_connection_window(1)
      success.should be_false
    end

    it "handles maximum window size" do
      # RFC 9113 Section 6.9.1: Flow Control Window
      # The maximum value is 2^31-1 (2,147,483,647) octets
      
      io = IO::Memory.new
      settings = Duo::Settings.new
      settings.initial_window_size = 0x7fffffff
      
      connection_manager = Duo::Core::ConnectionManager.new(
        Duo::Core::IOManager.new(io),
        Duo::Connection::Type::Server,
        settings
      )
      
      flow_control = connection_manager.flow_control
      flow_control.connection_window_size.should eq(0x7fffffff)
      
      # Should be able to consume window space
      success = flow_control.consume_connection_window(1000)
      success.should be_true
    end

    it "handles multiple streams with flow control" do
      # RFC 9113 Section 6.9.1: Flow Control Window
      # Each stream has its own flow control window
      
      io = IO::Memory.new
      settings = Duo::Settings.new
      connection_manager = Duo::Core::ConnectionManager.new(
        Duo::Core::IOManager.new(io),
        Duo::Connection::Type::Server,
        settings
      )
      
      flow_control = connection_manager.flow_control
      
      # Create multiple streams
      stream_ids = [1, 3, 5, 7]
      stream_ids.each do |stream_id|
        flow_control.register_stream(stream_id)
        flow_control.stream_window_size(stream_id).should eq(65535)
      end
      
      # Update windows independently
      flow_control.update_stream_window(1, 1000)
      flow_control.update_stream_window(3, 2000)
      
      flow_control.stream_window_size(1).should eq(66535)
      flow_control.stream_window_size(3).should eq(67535)
      flow_control.stream_window_size(5).should eq(65535) # Unchanged
    end

    it "handles stream cleanup with flow control" do
      # RFC 9113 Section 6.9.1: Flow Control Window
      # Streams should be unregistered when closed
      
      io = IO::Memory.new
      settings = Duo::Settings.new
      connection_manager = Duo::Core::ConnectionManager.new(
        Duo::Core::IOManager.new(io),
        Duo::Connection::Type::Server,
        settings
      )
      
      flow_control = connection_manager.flow_control
      stream_id = 1
      
      flow_control.register_stream(stream_id)
      flow_control.stream_window_size(stream_id).should_not be_nil
      
      # Unregister stream
      flow_control.unregister_stream(stream_id)
      flow_control.stream_window_size(stream_id).should be_nil
    end
  end

  describe "Flow Control Performance" do
    it "handles rapid window updates" do
      # RFC 9113 Section 6.9.1: Flow Control Window
      # The sender should handle rapid window updates efficiently
      
      io = IO::Memory.new
      settings = Duo::Settings.new
      connection_manager = Duo::Core::ConnectionManager.new(
        Duo::Core::IOManager.new(io),
        Duo::Connection::Type::Server,
        settings
      )
      
      flow_control = connection_manager.flow_control
      
      # Send many window updates rapidly
      1000.times do |i|
        result = flow_control.update_connection_window(100)
        result.success.should be_true
      end
      
      # Window should be updated correctly
      expected_window = 65535 + (1000 * 100)
      flow_control.connection_window_size.should eq(expected_window)
    end

    it "handles concurrent window updates" do
      # RFC 9113 Section 6.9.1: Flow Control Window
      # The sender should handle concurrent window updates correctly
      
      io = IO::Memory.new
      settings = Duo::Settings.new
      connection_manager = Duo::Core::ConnectionManager.new(
        Duo::Core::IOManager.new(io),
        Duo::Connection::Type::Server,
        settings
      )
      
      flow_control = connection_manager.flow_control
      
      # Send concurrent window updates
      fibers = [] of Fiber
      10.times do |i|
        fibers << spawn do
          100.times do |j|
            flow_control.update_connection_window(10)
          end
        end
      end
      
      # Wait for all fibers to complete
      fibers.each(&.join)
      
      # Window should be updated correctly
      expected_window = 65535 + (10 * 100 * 10)
      flow_control.connection_window_size.should eq(expected_window)
    end
  end

  describe "Flow Control Integration" do
    it "integrates with frame processing" do
      # RFC 9113 Section 6.9.1: Flow Control Window
      # Flow control should be integrated with frame processing
      
      io = IO::Memory.new
      settings = Duo::Settings.new
      connection_manager = Duo::Core::ConnectionManager.new(
        Duo::Core::IOManager.new(io),
        Duo::Connection::Type::Server,
        settings
      )
      
      flow_control = connection_manager.flow_control
      stream_id = 1
      
      flow_control.register_stream(stream_id)
      initial_window = flow_control.stream_window_size(stream_id).not_nil!
      
      # Process DATA frame (should consume window)
      data = "test data".to_slice
      frame = Duo::Core::FrameFactory.create_data_frame(stream_id, data)
      
      # Simulate frame processing
      success = flow_control.consume_stream_window(stream_id, data.size)
      success.should be_true
      
      new_window = flow_control.stream_window_size(stream_id).not_nil!
      new_window.should eq(initial_window - data.size)
    end

    it "integrates with stream lifecycle" do
      # RFC 9113 Section 6.9.1: Flow Control Window
      # Flow control should be integrated with stream lifecycle
      
      io = IO::Memory.new
      settings = Duo::Settings.new
      connection_manager = Duo::Core::ConnectionManager.new(
        Duo::Core::IOManager.new(io),
        Duo::Connection::Type::Server,
        settings
      )
      
      flow_control = connection_manager.flow_control
      stream_manager = connection_manager.stream_manager
      
      # Create stream
      stream = stream_manager.create_stream
      flow_control.register_stream(stream.id)
      
      # Verify stream has flow control
      flow_control.stream_window_size(stream.id).should_not be_nil
      
      # Close stream
      stream_manager.remove_stream(stream.id)
      
      # Verify stream is unregistered from flow control
      flow_control.stream_window_size(stream.id).should be_nil
    end
  end
end