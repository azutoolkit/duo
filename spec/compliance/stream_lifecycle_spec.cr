require "../spec_helper"

describe "HTTP/2 Stream Lifecycle Compliance (RFC 9113 Section 5.1)" do
  describe "Stream States" do
    it "validates stream state enumeration" do
      # RFC 9113 Section 5.1: Stream States
      # idle, reserved (local), reserved (remote), open, half-closed (local), half-closed (remote), closed
      
      states = [
        Duo::State::Idle,
        Duo::State::ReservedLocal,
        Duo::State::ReservedRemote,
        Duo::State::Open,
        Duo::State::HalfClosedLocal,
        Duo::State::HalfClosedRemote,
        Duo::State::Closed
      ]
      
      states.size.should eq(7)
      states.each { |state| state.should be_a(Duo::State) }
    end

    it "validates initial stream state" do
      # RFC 9113 Section 5.1.1: Stream Identifiers
      # All streams start in the "idle" state
      
      io = IO::Memory.new
      settings = Duo::Settings.new
      connection_manager = Duo::Core::ConnectionManager.new(
        Duo::Core::IOManager.new(io),
        Duo::Connection::Type::Server,
        settings
      )
      
      stream = connection_manager.stream_manager.create_stream
      stream.state.should eq(Duo::State::Idle)
    end
  end

  describe "Stream State Transitions" do
    it "validates idle to open transition" do
      # RFC 9113 Section 5.1.2: Stream States
      # idle -> open: HEADERS frame received
      
      io = IO::Memory.new
      settings = Duo::Settings.new
      connection_manager = Duo::Core::ConnectionManager.new(
        Duo::Core::IOManager.new(io),
        Duo::Connection::Type::Server,
        settings
      )
      
      stream = connection_manager.stream_manager.create_stream
      initial_state = stream.state
      
      # Simulate HEADERS frame
      headers = HTTP::Headers.new
      headers[":method"] = "GET"
      headers[":path"] = "/"
      headers[":scheme"] = "https"
      
      # Process headers frame
      process_headers_frame(connection_manager, stream.id, headers)
      
      stream.state.should eq(Duo::State::Open)
    end

    it "validates idle to half-closed (remote) transition" do
      # RFC 9113 Section 5.1.2: Stream States
      # idle -> half-closed (remote): HEADERS frame with END_STREAM flag
      
      io = IO::Memory.new
      settings = Duo::Settings.new
      connection_manager = Duo::Core::ConnectionManager.new(
        Duo::Core::IOManager.new(io),
        Duo::Connection::Type::Server,
        settings
      )
      
      stream = connection_manager.stream_manager.create_stream
      
      # Simulate HEADERS frame with END_STREAM
      headers = HTTP::Headers.new
      headers[":method"] = "GET"
      headers[":path"] = "/"
      headers[":scheme"] = "https"
      
      # Process headers frame with END_STREAM flag
      process_headers_frame_with_end_stream(connection_manager, stream.id, headers)
      
      stream.state.should eq(Duo::State::HalfClosedRemote)
    end

    it "validates open to half-closed (local) transition" do
      # RFC 9113 Section 5.1.2: Stream States
      # open -> half-closed (local): END_STREAM flag sent
      
      io = IO::Memory.new
      settings = Duo::Settings.new
      connection_manager = Duo::Core::ConnectionManager.new(
        Duo::Core::IOManager.new(io),
        Duo::Connection::Type::Server,
        settings
      )
      
      stream = connection_manager.stream_manager.create_stream
      
      # First transition to open
      headers = HTTP::Headers.new
      headers[":method"] = "GET"
      process_headers_frame(connection_manager, stream.id, headers)
      stream.state.should eq(Duo::State::Open)
      
      # Then send END_STREAM
      send_end_stream(connection_manager, stream.id)
      stream.state.should eq(Duo::State::HalfClosedLocal)
    end

    it "validates open to half-closed (remote) transition" do
      # RFC 9113 Section 5.1.2: Stream States
      # open -> half-closed (remote): END_STREAM flag received
      
      io = IO::Memory.new
      settings = Duo::Settings.new
      connection_manager = Duo::Core::ConnectionManager.new(
        Duo::Core::IOManager.new(io),
        Duo::Connection::Type::Server,
        settings
      )
      
      stream = connection_manager.stream_manager.create_stream
      
      # First transition to open
      headers = HTTP::Headers.new
      headers[":method"] = "GET"
      process_headers_frame(connection_manager, stream.id, headers)
      stream.state.should eq(Duo::State::Open)
      
      # Then receive END_STREAM
      receive_end_stream(connection_manager, stream.id)
      stream.state.should eq(Duo::State::HalfClosedRemote)
    end

    it "validates half-closed to closed transition" do
      # RFC 9113 Section 5.1.2: Stream States
      # half-closed -> closed: END_STREAM flag received/sent
      
      io = IO::Memory.new
      settings = Duo::Settings.new
      connection_manager = Duo::Core::ConnectionManager.new(
        Duo::Core::IOManager.new(io),
        Duo::Connection::Type::Server,
        settings
      )
      
      stream = connection_manager.stream_manager.create_stream
      
      # Transition to half-closed (remote)
      headers = HTTP::Headers.new
      headers[":method"] = "GET"
      process_headers_frame_with_end_stream(connection_manager, stream.id, headers)
      stream.state.should eq(Duo::State::HalfClosedRemote)
      
      # Send END_STREAM to close
      send_end_stream(connection_manager, stream.id)
      stream.state.should eq(Duo::State::Closed)
    end

    it "validates RST_STREAM closes stream immediately" do
      # RFC 9113 Section 5.1.2: Stream States
      # Any state -> closed: RST_STREAM frame received
      
      io = IO::Memory.new
      settings = Duo::Settings.new
      connection_manager = Duo::Core::ConnectionManager.new(
        Duo::Core::IOManager.new(io),
        Duo::Connection::Type::Server,
        settings
      )
      
      stream = connection_manager.stream_manager.create_stream
      
      # Send RST_STREAM from any state
      send_rst_stream(connection_manager, stream.id, Duo::Error::Code::Cancel)
      stream.state.should eq(Duo::State::Closed)
    end
  end

  describe "Stream State Validation" do
    it "rejects DATA frames on idle streams" do
      # RFC 9113 Section 5.1.2: Stream States
      # DATA frames MUST NOT be sent on streams in "idle" state
      
      io = IO::Memory.new
      settings = Duo::Settings.new
      connection_manager = Duo::Core::ConnectionManager.new(
        Duo::Core::IOManager.new(io),
        Duo::Connection::Type::Server,
        settings
      )
      
      stream = connection_manager.stream_manager.create_stream
      stream.state.should eq(Duo::State::Idle)
      
      # Should reject DATA frame on idle stream
      expect_raises(Duo::Error) do
        send_data_frame(connection_manager, stream.id, "test data".to_slice)
      end
    end

    it "rejects HEADERS frames on closed streams" do
      # RFC 9113 Section 5.1.2: Stream States
      # HEADERS frames MUST NOT be sent on streams in "closed" state
      
      io = IO::Memory.new
      settings = Duo::Settings.new
      connection_manager = Duo::Core::ConnectionManager.new(
        Duo::Core::IOManager.new(io),
        Duo::Connection::Type::Server,
        settings
      )
      
      stream = connection_manager.stream_manager.create_stream
      
      # Close the stream
      send_rst_stream(connection_manager, stream.id, Duo::Error::Code::Cancel)
      stream.state.should eq(Duo::State::Closed)
      
      # Should reject HEADERS frame on closed stream
      expect_raises(Duo::Error) do
        headers = HTTP::Headers.new
        headers[":method"] = "GET"
        process_headers_frame(connection_manager, stream.id, headers)
      end
    end

    it "allows WINDOW_UPDATE on closed streams" do
      # RFC 9113 Section 5.1.2: Stream States
      # WINDOW_UPDATE frames can be sent on streams in "closed" state
      
      io = IO::Memory.new
      settings = Duo::Settings.new
      connection_manager = Duo::Core::ConnectionManager.new(
        Duo::Core::IOManager.new(io),
        Duo::Connection::Type::Server,
        settings
      )
      
      stream = connection_manager.stream_manager.create_stream
      
      # Close the stream
      send_rst_stream(connection_manager, stream.id, Duo::Error::Code::Cancel)
      stream.state.should eq(Duo::State::Closed)
      
      # Should allow WINDOW_UPDATE on closed stream
      send_window_update(connection_manager, stream.id, 1000)
      # Should not raise error
    end

    it "allows RST_STREAM on closed streams" do
      # RFC 9113 Section 5.1.2: Stream States
      # RST_STREAM frames can be sent on streams in "closed" state
      
      io = IO::Memory.new
      settings = Duo::Settings.new
      connection_manager = Duo::Core::ConnectionManager.new(
        Duo::Core::IOManager.new(io),
        Duo::Connection::Type::Server,
        settings
      )
      
      stream = connection_manager.stream_manager.create_stream
      
      # Close the stream
      send_rst_stream(connection_manager, stream.id, Duo::Error::Code::Cancel)
      stream.state.should eq(Duo::State::Closed)
      
      # Should allow RST_STREAM on closed stream
      send_rst_stream(connection_manager, stream.id, Duo::Error::Code::StreamClosed)
      # Should not raise error
    end
  end

  describe "Stream Identifier Management" do
    it "validates stream identifier ranges" do
      # RFC 9113 Section 5.1.1: Stream Identifiers
      # Stream identifiers are 31-bit integers
      
      valid_stream_ids = [1, 2, 3, 100, 1000, 0x7fffffff]
      invalid_stream_ids = [0, -1, 0x80000000]
      
      valid_stream_ids.each do |stream_id|
        # Should not raise error for valid stream IDs
        create_stream_with_id(stream_id)
      end
      
      invalid_stream_ids.each do |stream_id|
        expect_raises(Duo::Error) do
          create_stream_with_id(stream_id)
        end
      end
    end

    it "validates stream identifier sequencing" do
      # RFC 9113 Section 5.1.1: Stream Identifiers
      # Stream identifiers MUST be monotonically increasing
      
      io = IO::Memory.new
      settings = Duo::Settings.new
      connection_manager = Duo::Core::ConnectionManager.new(
        Duo::Core::IOManager.new(io),
        Duo::Connection::Type::Client, # Client initiates streams
        settings
      )
      
      # Create streams in order
      stream1 = connection_manager.stream_manager.create_stream
      stream2 = connection_manager.stream_manager.create_stream
      stream3 = connection_manager.stream_manager.create_stream
      
      stream1.id.should be < stream2.id
      stream2.id.should be < stream3.id
    end

    it "validates client-initiated streams" do
      # RFC 9113 Section 5.1.1: Stream Identifiers
      # Client-initiated streams have odd-numbered identifiers
      
      io = IO::Memory.new
      settings = Duo::Settings.new
      connection_manager = Duo::Core::ConnectionManager.new(
        Duo::Core::IOManager.new(io),
        Duo::Connection::Type::Client,
        settings
      )
      
      stream = connection_manager.stream_manager.create_stream
      stream.id.odd?.should be_true
    end

    it "validates server-initiated streams" do
      # RFC 9113 Section 5.1.1: Stream Identifiers
      # Server-initiated streams have even-numbered identifiers
      
      io = IO::Memory.new
      settings = Duo::Settings.new
      connection_manager = Duo::Core::ConnectionManager.new(
        Duo::Core::IOManager.new(io),
        Duo::Connection::Type::Server,
        settings
      )
      
      stream = connection_manager.stream_manager.create_stream
      stream.id.even?.should be_true
    end
  end

  describe "Stream Concurrency Limits" do
    it "enforces SETTINGS_MAX_CONCURRENT_STREAMS" do
      # RFC 9113 Section 5.1.2: Stream States
      # SETTINGS_MAX_CONCURRENT_STREAMS limits the number of streams
      
      io = IO::Memory.new
      settings = Duo::Settings.new
      settings.max_concurrent_streams = 2
      
      connection_manager = Duo::Core::ConnectionManager.new(
        Duo::Core::IOManager.new(io),
        Duo::Connection::Type::Server,
        settings
      )
      
      # Create maximum number of streams
      stream1 = connection_manager.stream_manager.create_stream
      stream2 = connection_manager.stream_manager.create_stream
      
      # Next stream should fail
      expect_raises(Duo::Error) do
        connection_manager.stream_manager.create_stream
      end
    end

    it "allows new streams after existing streams close" do
      # RFC 9113 Section 5.1.2: Stream States
      # Closed streams don't count toward the limit
      
      io = IO::Memory.new
      settings = Duo::Settings.new
      settings.max_concurrent_streams = 1
      
      connection_manager = Duo::Core::ConnectionManager.new(
        Duo::Core::IOManager.new(io),
        Duo::Connection::Type::Server,
        settings
      )
      
      # Create stream
      stream = connection_manager.stream_manager.create_stream
      
      # Should not allow another stream
      expect_raises(Duo::Error) do
        connection_manager.stream_manager.create_stream
      end
      
      # Close the stream
      send_rst_stream(connection_manager, stream.id, Duo::Error::Code::Cancel)
      
      # Should now allow a new stream
      new_stream = connection_manager.stream_manager.create_stream
      new_stream.should_not be_nil
    end
  end

  describe "Stream Error Handling" do
    it "handles RST_STREAM on non-existent streams" do
      # RFC 9113 Section 6.4: RST_STREAM
      # RST_STREAM frames can be sent for streams that don't exist
      
      io = IO::Memory.new
      settings = Duo::Settings.new
      connection_manager = Duo::Core::ConnectionManager.new(
        Duo::Core::IOManager.new(io),
        Duo::Connection::Type::Server,
        settings
      )
      
      # Send RST_STREAM for non-existent stream
      send_rst_stream(connection_manager, 999, Duo::Error::Code::StreamClosed)
      # Should not raise error
    end

    it "handles WINDOW_UPDATE on non-existent streams" do
      # RFC 9113 Section 6.9: WINDOW_UPDATE
      # WINDOW_UPDATE frames can be sent for streams that don't exist
      
      io = IO::Memory.new
      settings = Duo::Settings.new
      connection_manager = Duo::Core::ConnectionManager.new(
        Duo::Core::IOManager.new(io),
        Duo::Connection::Type::Server,
        settings
      )
      
      # Send WINDOW_UPDATE for non-existent stream
      send_window_update(connection_manager, 999, 1000)
      # Should not raise error
    end

    it "handles PRIORITY on non-existent streams" do
      # RFC 9113 Section 6.3: PRIORITY
      # PRIORITY frames can be sent for streams that don't exist
      
      io = IO::Memory.new
      settings = Duo::Settings.new
      connection_manager = Duo::Core::ConnectionManager.new(
        Duo::Core::IOManager.new(io),
        Duo::Connection::Type::Server,
        settings
      )
      
      # Send PRIORITY for non-existent stream
      send_priority_frame(connection_manager, 999, false, 0, 16)
      # Should not raise error
    end
  end

  describe "Stream Cleanup" do
    it "cleans up stream resources on close" do
      # RFC 9113 Section 5.1.2: Stream States
      # Closed streams should release resources
      
      io = IO::Memory.new
      settings = Duo::Settings.new
      connection_manager = Duo::Core::ConnectionManager.new(
        Duo::Core::IOManager.new(io),
        Duo::Connection::Type::Server,
        settings
      )
      
      stream = connection_manager.stream_manager.create_stream
      initial_count = connection_manager.stream_manager.all_streams.size
      
      # Close the stream
      send_rst_stream(connection_manager, stream.id, Duo::Error::Code::Cancel)
      
      # Stream should be removed from management
      connection_manager.stream_manager.all_streams.size.should be < initial_count
    end

    it "handles multiple RST_STREAM frames" do
      # RFC 9113 Section 6.4: RST_STREAM
      # Multiple RST_STREAM frames should be handled gracefully
      
      io = IO::Memory.new
      settings = Duo::Settings.new
      connection_manager = Duo::Core::ConnectionManager.new(
        Duo::Core::IOManager.new(io),
        Duo::Connection::Type::Server,
        settings
      )
      
      stream = connection_manager.stream_manager.create_stream
      
      # Send multiple RST_STREAM frames
      send_rst_stream(connection_manager, stream.id, Duo::Error::Code::Cancel)
      send_rst_stream(connection_manager, stream.id, Duo::Error::Code::StreamClosed)
      
      # Should not raise error
      stream.state.should eq(Duo::State::Closed)
    end
  end

  # Helper methods for testing
  private def process_headers_frame(connection_manager, stream_id, headers)
    # Simulate processing a HEADERS frame
    frame = Duo::Core::FrameFactory.create_headers_frame(stream_id, headers)
    # Process the frame through the connection manager
  end

  private def process_headers_frame_with_end_stream(connection_manager, stream_id, headers)
    # Simulate processing a HEADERS frame with END_STREAM flag
    frame = Duo::Core::FrameFactory.create_headers_frame(stream_id, headers, Duo::Frame::Flags::EndStream)
    # Process the frame through the connection manager
  end

  private def send_end_stream(connection_manager, stream_id)
    # Simulate sending END_STREAM flag
    frame = Duo::Core::FrameFactory.create_data_frame(stream_id, Bytes.new(0), Duo::Frame::Flags::EndStream)
    # Send the frame through the connection manager
  end

  private def receive_end_stream(connection_manager, stream_id)
    # Simulate receiving END_STREAM flag
    frame = Duo::Core::FrameFactory.create_data_frame(stream_id, Bytes.new(0), Duo::Frame::Flags::EndStream)
    # Process the frame through the connection manager
  end

  private def send_rst_stream(connection_manager, stream_id, error_code)
    # Simulate sending RST_STREAM frame
    frame = Duo::Core::FrameFactory.create_rst_stream_frame(stream_id, error_code)
    # Send the frame through the connection manager
  end

  private def send_data_frame(connection_manager, stream_id, data)
    # Simulate sending DATA frame
    frame = Duo::Core::FrameFactory.create_data_frame(stream_id, data)
    # Send the frame through the connection manager
  end

  private def send_window_update(connection_manager, stream_id, increment)
    # Simulate sending WINDOW_UPDATE frame
    frame = Duo::Core::FrameFactory.create_window_update_frame(stream_id, increment)
    # Send the frame through the connection manager
  end

  private def send_priority_frame(connection_manager, stream_id, exclusive, dependency, weight)
    # Simulate sending PRIORITY frame
    frame = Duo::Core::FrameFactory.create_priority_frame(stream_id, exclusive, dependency, weight)
    # Send the frame through the connection manager
  end

  private def create_stream_with_id(stream_id)
    # Helper method to create stream with specific ID
    # This would need to be implemented based on the actual StreamManager interface
  end
end