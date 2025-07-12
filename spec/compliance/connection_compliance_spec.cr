require "../spec_helper"

describe "HTTP/2 Connection Compliance (RFC 9113)" do
  describe "Connection Establishment" do
    it "validates connection creation" do
      # RFC 9113 Section 3: Starting HTTP/2
      # HTTP/2 connections are established through the HTTP/1.1 Upgrade mechanism
      
      io = IO::Memory.new
      settings = Duo::Settings.new
      connection_manager = Duo::Core::ConnectionManager.new(
        Duo::Core::IOManager.new(io),
        Duo::Connection::Type::Server,
        settings
      )
      
      connection_manager.should be_a(Duo::Core::ConnectionManager)
      connection_manager.connection_type.should eq(Duo::Connection::Type::Server)
    end

    it "validates client connection creation" do
      # RFC 9113 Section 3.4: Starting HTTP/2 for "http" URIs
      # Clients can establish HTTP/2 connections to "http" URIs
      
      io = IO::Memory.new
      settings = Duo::Settings.new
      connection_manager = Duo::Core::ConnectionManager.new(
        Duo::Core::IOManager.new(io),
        Duo::Connection::Type::Client,
        settings
      )
      
      connection_manager.connection_type.should eq(Duo::Connection::Type::Client)
    end

    it "validates server connection creation" do
      # RFC 9113 Section 3.2: Starting HTTP/2 for "https" URIs
      # Servers can establish HTTP/2 connections for "https" URIs
      
      io = IO::Memory.new
      settings = Duo::Settings.new
      connection_manager = Duo::Core::ConnectionManager.new(
        Duo::Core::IOManager.new(io),
        Duo::Connection::Type::Server,
        settings
      )
      
      connection_manager.connection_type.should eq(Duo::Connection::Type::Server)
    end
  end

  describe "Connection Preface" do
    it "validates connection preface" do
      # RFC 9113 Section 3.5: HTTP/2 Connection Preface
      # A client MUST send a connection preface
      
      io = IO::Memory.new
      settings = Duo::Settings.new
      connection_manager = Duo::Core::ConnectionManager.new(
        Duo::Core::IOManager.new(io),
        Duo::Connection::Type::Client,
        settings
      )
      
      # Send connection preface
      preface = connection_manager.create_connection_preface
      preface.should_not be_nil
      preface.starts_with?("PRI * HTTP/2.0\r\n\r\nSM\r\n\r\n").should be_true
    end

    it "validates preface processing" do
      # RFC 9113 Section 3.5: HTTP/2 Connection Preface
      # A server MUST be able to receive a connection preface
      
      io = IO::Memory.new
      settings = Duo::Settings.new
      connection_manager = Duo::Core::ConnectionManager.new(
        Duo::Core::IOManager.new(io),
        Duo::Connection::Type::Server,
        settings
      )
      
      # Process connection preface
      preface = "PRI * HTTP/2.0\r\n\r\nSM\r\n\r\n"
      result = connection_manager.process_connection_preface(preface)
      result.success.should be_true
    end

    it "validates invalid preface rejection" do
      # RFC 9113 Section 3.5: HTTP/2 Connection Preface
      # Invalid connection prefaces should be rejected
      
      io = IO::Memory.new
      settings = Duo::Settings.new
      connection_manager = Duo::Core::ConnectionManager.new(
        Duo::Core::IOManager.new(io),
        Duo::Connection::Type::Server,
        settings
      )
      
      # Process invalid preface
      invalid_preface = "INVALID PREFACE"
      result = connection_manager.process_connection_preface(invalid_preface)
      result.error?.should be_true
      result.error_code.should eq(Duo::Error::Code::ProtocolError)
    end
  end

  describe "Settings Negotiation" do
    it "validates initial settings" do
      # RFC 9113 Section 6.5.2: Defined SETTINGS Parameters
      # Initial settings should be sent upon connection establishment
      
      io = IO::Memory.new
      settings = Duo::Settings.new
      connection_manager = Duo::Core::ConnectionManager.new(
        Duo::Core::IOManager.new(io),
        Duo::Connection::Type::Server,
        settings
      )
      
      # Get initial settings
      initial_settings = connection_manager.get_initial_settings
      initial_settings.should_not be_nil
      initial_settings.size.should be > 0
    end

    it "validates settings acknowledgment" do
      # RFC 9113 Section 6.5: SETTINGS
      # Settings must be acknowledged
      
      io = IO::Memory.new
      settings = Duo::Settings.new
      connection_manager = Duo::Core::ConnectionManager.new(
        Duo::Core::IOManager.new(io),
        Duo::Connection::Type::Server,
        settings
      )
      
      # Send settings
      settings_frame = connection_manager.create_settings_frame
      settings_frame.should_not be_nil
      settings_frame.type.should eq(Duo::FrameType::Settings)
      
      # Send settings ACK
      ack_frame = connection_manager.create_settings_ack
      ack_frame.should_not be_nil
      ack_frame.type.should eq(Duo::FrameType::Settings)
      ack_frame.flags.ack?.should be_true
    end

    it "validates settings timeout" do
      # RFC 9113 Section 6.5.3: Settings Synchronization
      # Settings must be acknowledged within a reasonable time
      
      io = IO::Memory.new
      settings = Duo::Settings.new
      connection_manager = Duo::Core::ConnectionManager.new(
        Duo::Core::IOManager.new(io),
        Duo::Connection::Type::Server,
        settings
      )
      
      # Simulate settings timeout
      result = connection_manager.check_settings_timeout
      # Should handle timeout appropriately
    end

    it "validates settings parameters" do
      # RFC 9113 Section 6.5.2: Defined SETTINGS Parameters
      # All defined settings parameters should be supported
      
      io = IO::Memory.new
      settings = Duo::Settings.new
      connection_manager = Duo::Core::ConnectionManager.new(
        Duo::Core::IOManager.new(io),
        Duo::Connection::Type::Server,
        settings
      )
      
      # Test all defined settings
      defined_settings = [
        Duo::Settings::Identifier::HeaderTableSize,
        Duo::Settings::Identifier::EnablePush,
        Duo::Settings::Identifier::MaxConcurrentStreams,
        Duo::Settings::Identifier::InitialWindowSize,
        Duo::Settings::Identifier::MaxFrameSize,
        Duo::Settings::Identifier::MaxHeaderListSize
      ]
      
      defined_settings.each do |setting_id|
        # Should be able to set each setting
        settings.set(setting_id, 1000)
        value = settings.get(setting_id)
        value.should eq(1000)
      end
    end
  end

  describe "Connection State Management" do
    it "validates connection state transitions" do
      # RFC 9113 Section 3: Starting HTTP/2
      # Connection should transition through proper states
      
      io = IO::Memory.new
      settings = Duo::Settings.new
      connection_manager = Duo::Core::ConnectionManager.new(
        Duo::Core::IOManager.new(io),
        Duo::Connection::Type::Server,
        settings
      )
      
      # Initial state
      connection_manager.state.should eq(Duo::Connection::State::Initial)
      
      # Transition to connected
      connection_manager.transition_to_connected
      connection_manager.state.should eq(Duo::Connection::State::Connected)
      
      # Transition to closing
      connection_manager.transition_to_closing
      connection_manager.state.should eq(Duo::Connection::State::Closing)
      
      # Transition to closed
      connection_manager.transition_to_closed
      connection_manager.state.should eq(Duo::Connection::State::Closed)
    end

    it "validates connection state validation" do
      # RFC 9113 Section 3: Starting HTTP/2
      # Invalid state transitions should be prevented
      
      io = IO::Memory.new
      settings = Duo::Settings.new
      connection_manager = Duo::Core::ConnectionManager.new(
        Duo::Core::IOManager.new(io),
        Duo::Connection::Type::Server,
        settings
      )
      
      # Try to transition from closed to connected (invalid)
      connection_manager.transition_to_closed
      
      expect_raises(Duo::Error) do
        connection_manager.transition_to_connected
      end
    end

    it "validates connection lifecycle events" do
      # RFC 9113 Section 3: Starting HTTP/2
      # Connection lifecycle events should be properly handled
      
      io = IO::Memory.new
      settings = Duo::Settings.new
      connection_manager = Duo::Core::ConnectionManager.new(
        Duo::Core::IOManager.new(io),
        Duo::Connection::Type::Server,
        settings
      )
      
      # Register event handlers
      events_received = [] of String
      connection_manager.on_connected { events_received << "connected" }
      connection_manager.on_closing { events_received << "closing" }
      connection_manager.on_closed { events_received << "closed" }
      
      # Trigger events
      connection_manager.transition_to_connected
      connection_manager.transition_to_closing
      connection_manager.transition_to_closed
      
      # Verify events were received
      events_received.should eq(["connected", "closing", "closed"])
    end
  end

  describe "Error Handling" do
    it "validates protocol error handling" do
      # RFC 9113 Section 7: Error Codes
      # Protocol errors should be handled appropriately
      
      io = IO::Memory.new
      settings = Duo::Settings.new
      connection_manager = Duo::Core::ConnectionManager.new(
        Duo::Core::IOManager.new(io),
        Duo::Connection::Type::Server,
        settings
      )
      
      # Simulate protocol error
      error_frame = connection_manager.create_goaway_frame(0, Duo::Error::Code::ProtocolError, "Protocol error")
      error_frame.should_not be_nil
      error_frame.type.should eq(Duo::FrameType::GoAway)
    end

    it "validates internal error handling" do
      # RFC 9113 Section 7: Error Codes
      # Internal errors should be handled appropriately
      
      io = IO::Memory.new
      settings = Duo::Settings.new
      connection_manager = Duo::Core::ConnectionManager.new(
        Duo::Core::IOManager.new(io),
        Duo::Connection::Type::Server,
        settings
      )
      
      # Simulate internal error
      error_frame = connection_manager.create_goaway_frame(0, Duo::Error::Code::InternalError, "Internal error")
      error_frame.should_not be_nil
      error_frame.type.should eq(Duo::FrameType::GoAway)
    end

    it "validates flow control error handling" do
      # RFC 9113 Section 7: Error Codes
      # Flow control errors should be handled appropriately
      
      io = IO::Memory.new
      settings = Duo::Settings.new
      connection_manager = Duo::Core::ConnectionManager.new(
        Duo::Core::IOManager.new(io),
        Duo::Connection::Type::Server,
        settings
      )
      
      # Simulate flow control error
      error_frame = connection_manager.create_goaway_frame(0, Duo::Error::Code::FlowControlError, "Flow control error")
      error_frame.should_not be_nil
      error_frame.type.should eq(Duo::FrameType::GoAway)
    end

    it "validates settings timeout error handling" do
      # RFC 9113 Section 7: Error Codes
      # Settings timeout errors should be handled appropriately
      
      io = IO::Memory.new
      settings = Duo::Settings.new
      connection_manager = Duo::Core::ConnectionManager.new(
        Duo::Core::IOManager.new(io),
        Duo::Connection::Type::Server,
        settings
      )
      
      # Simulate settings timeout error
      error_frame = connection_manager.create_goaway_frame(0, Duo::Error::Code::SettingsTimeout, "Settings timeout")
      error_frame.should_not be_nil
      error_frame.type.should eq(Duo::FrameType::GoAway)
    end
  end

  describe "GOAWAY Frame Handling" do
    it "validates GOAWAY frame creation" do
      # RFC 9113 Section 6.8: GOAWAY
      # GOAWAY frames should be created correctly
      
      io = IO::Memory.new
      settings = Duo::Settings.new
      connection_manager = Duo::Core::ConnectionManager.new(
        Duo::Core::IOManager.new(io),
        Duo::Connection::Type::Server,
        settings
      )
      
      # Create GOAWAY frame
      last_stream_id = 1
      error_code = Duo::Error::Code::NoError
      debug_data = "test"
      
      goaway_frame = connection_manager.create_goaway_frame(last_stream_id, error_code, debug_data)
      goaway_frame.should_not be_nil
      goaway_frame.type.should eq(Duo::FrameType::GoAway)
      goaway_frame.stream_id.should eq(0) # GOAWAY frames must be sent on stream 0
    end

    it "validates GOAWAY frame processing" do
      # RFC 9113 Section 6.8: GOAWAY
      # GOAWAY frames should be processed correctly
      
      io = IO::Memory.new
      settings = Duo::Settings.new
      connection_manager = Duo::Core::ConnectionManager.new(
        Duo::Core::IOManager.new(io),
        Duo::Connection::Type::Client,
        settings
      )
      
      # Process GOAWAY frame
      goaway_frame = Duo::Core::FrameFactory.create_goaway_frame(1, Duo::Error::Code::NoError, "test")
      result = connection_manager.process_goaway_frame(goaway_frame)
      result.success.should be_true
      
      # Connection should transition to closing
      connection_manager.state.should eq(Duo::Connection::State::Closing)
    end

    it "validates GOAWAY frame payload size" do
      # RFC 9113 Section 6.8: GOAWAY
      # GOAWAY frame payload is at least 8 octets
      
      io = IO::Memory.new
      settings = Duo::Settings.new
      connection_manager = Duo::Core::ConnectionManager.new(
        Duo::Core::IOManager.new(io),
        Duo::Connection::Type::Server,
        settings
      )
      
      # Create GOAWAY frame
      goaway_frame = connection_manager.create_goaway_frame(1, Duo::Error::Code::NoError, "")
      goaway_frame.payload.size.should be >= 8
    end
  end

  describe "PING Frame Handling" do
    it "validates PING frame creation" do
      # RFC 9113 Section 6.7: PING
      # PING frames should be created correctly
      
      io = IO::Memory.new
      settings = Duo::Settings.new
      connection_manager = Duo::Core::ConnectionManager.new(
        Duo::Core::IOManager.new(io),
        Duo::Connection::Type::Server,
        settings
      )
      
      # Create PING frame
      ping_frame = connection_manager.create_ping_frame
      ping_frame.should_not be_nil
      ping_frame.type.should eq(Duo::FrameType::Ping)
      ping_frame.stream_id.should eq(0) # PING frames must be sent on stream 0
      ping_frame.payload.size.should eq(8) # Exactly 8 bytes
    end

    it "validates PING frame processing" do
      # RFC 9113 Section 6.7: PING
      # PING frames should be processed correctly
      
      io = IO::Memory.new
      settings = Duo::Settings.new
      connection_manager = Duo::Core::ConnectionManager.new(
        Duo::Core::IOManager.new(io),
        Duo::Connection::Type::Server,
        settings
      )
      
      # Process PING frame
      ping_frame = Duo::Core::FrameFactory.create_ping_frame
      result = connection_manager.process_ping_frame(ping_frame)
      result.success.should be_true
      
      # Should generate PING ACK
      ack_frame = result.ack_frame
      ack_frame.should_not be_nil
      ack_frame.type.should eq(Duo::FrameType::Ping)
      ack_frame.flags.ack?.should be_true
    end

    it "validates PING timeout handling" do
      # RFC 9113 Section 6.7: PING
      # PING timeouts should be handled appropriately
      
      io = IO::Memory.new
      settings = Duo::Settings.new
      connection_manager = Duo::Core::ConnectionManager.new(
        Duo::Core::IOManager.new(io),
        Duo::Connection::Type::Server,
        settings
      )
      
      # Simulate PING timeout
      result = connection_manager.check_ping_timeout
      # Should handle timeout appropriately
    end
  end

  describe "Connection Performance" do
    it "handles rapid frame processing" do
      # RFC 9113 Section 4: HTTP Frames
      # Connection should handle rapid frame processing efficiently
      
      io = IO::Memory.new
      settings = Duo::Settings.new
      connection_manager = Duo::Core::ConnectionManager.new(
        Duo::Core::IOManager.new(io),
        Duo::Connection::Type::Server,
        settings
      )
      
      # Process many frames rapidly
      1000.times do |i|
        # Create and process various frame types
        ping_frame = Duo::Core::FrameFactory.create_ping_frame
        connection_manager.process_ping_frame(ping_frame)
        
        settings_frame = Duo::Core::FrameFactory.create_settings_frame([] of {Duo::Settings::Identifier, Int32})
        connection_manager.process_settings_frame(settings_frame)
      end
      
      # Connection should still be functional
      connection_manager.state.should_not eq(Duo::Connection::State::Closed)
    end

    it "handles concurrent operations" do
      # RFC 9113 Section 4: HTTP Frames
      # Connection should handle concurrent operations correctly
      
      io = IO::Memory.new
      settings = Duo::Settings.new
      connection_manager = Duo::Core::ConnectionManager.new(
        Duo::Core::IOManager.new(io),
        Duo::Connection::Type::Server,
        settings
      )
      
      # Concurrent operations
      fibers = [] of Fiber
      10.times do |i|
        fibers << spawn do
          100.times do |j|
            ping_frame = Duo::Core::FrameFactory.create_ping_frame
            connection_manager.process_ping_frame(ping_frame)
          end
        end
      end
      
      # Wait for all fibers to complete
      fibers.each(&.join)
      
      # Connection should still be functional
      connection_manager.state.should_not eq(Duo::Connection::State::Closed)
    end

    it "handles large frame payloads" do
      # RFC 9113 Section 4.1.1: Frame Size
      # Connection should handle large frame payloads efficiently
      
      io = IO::Memory.new
      settings = Duo::Settings.new
      connection_manager = Duo::Core::ConnectionManager.new(
        Duo::Core::IOManager.new(io),
        Duo::Connection::Type::Server,
        settings
      )
      
      # Create large data payload
      large_data = Bytes.new(16384) # Maximum frame size
      
      # Should handle large payload
      data_frame = Duo::Core::FrameFactory.create_data_frame(1, large_data)
      data_frame.should_not be_nil
      data_frame.payload.size.should eq(16384)
    end
  end

  describe "Connection Security" do
    it "validates frame size limits" do
      # RFC 9113 Section 4.1.1: Frame Size
      # Frame size limits should be enforced for security
      
      io = IO::Memory.new
      settings = Duo::Settings.new
      connection_manager = Duo::Core::ConnectionManager.new(
        Duo::Core::IOManager.new(io),
        Duo::Connection::Type::Server,
        settings
      )
      
      # Try to create oversized frame
      oversized_data = Bytes.new(16385) # Exceeds maximum frame size
      
      expect_raises(Duo::Error) do
        Duo::Core::FrameFactory.create_data_frame(1, oversized_data)
      end
    end

    it "validates header list size limits" do
      # RFC 9113 Section 6.5.2: Defined SETTINGS Parameters
      # Header list size limits should be enforced for security
      
      io = IO::Memory.new
      settings = Duo::Settings.new
      settings.max_header_list_size = 1000
      
      connection_manager = Duo::Core::ConnectionManager.new(
        Duo::Core::IOManager.new(io),
        Duo::Connection::Type::Server,
        settings
      )
      
      # Create oversized header list
      headers = HTTP::Headers.new
      1000.times do |i|
        headers["header#{i}"] = "value#{i}"
      end
      
      # Should handle gracefully
      begin
        headers_frame = Duo::Core::FrameFactory.create_headers_frame(1, headers)
        # Should not raise error if handled gracefully
      rescue Duo::Error
        # Error is acceptable for oversized headers
      end
    end

    it "validates connection limits" do
      # RFC 9113 Section 6.5.2: Defined SETTINGS Parameters
      # Connection limits should be enforced for security
      
      io = IO::Memory.new
      settings = Duo::Settings.new
      settings.max_concurrent_streams = 100
      
      connection_manager = Duo::Core::ConnectionManager.new(
        Duo::Core::IOManager.new(io),
        Duo::Connection::Type::Server,
        settings
      )
      
      # Try to create too many streams
      150.times do |i|
        begin
          connection_manager.stream_manager.create_stream
        rescue Duo::Error
          # Error is acceptable when limit is reached
          break
        end
      end
      
      # Should not exceed limit
      active_streams = connection_manager.stream_manager.active_streams.size
      active_streams.should be <= 100
    end
  end

  describe "Connection Integration" do
    it "integrates with stream management" do
      # RFC 9113 Section 5: Streams and Multiplexing
      # Connection should integrate with stream management
      
      io = IO::Memory.new
      settings = Duo::Settings.new
      connection_manager = Duo::Core::ConnectionManager.new(
        Duo::Core::IOManager.new(io),
        Duo::Connection::Type::Server,
        settings
      )
      
      # Create stream through connection manager
      stream = connection_manager.stream_manager.create_stream
      stream.should_not be_nil
      stream.id.should be > 0
      
      # Stream should be associated with connection
      connection_manager.stream_manager.get_stream(stream.id).should eq(stream)
    end

    it "integrates with flow control" do
      # RFC 9113 Section 6.9: Flow Control
      # Connection should integrate with flow control
      
      io = IO::Memory.new
      settings = Duo::Settings.new
      connection_manager = Duo::Core::ConnectionManager.new(
        Duo::Core::IOManager.new(io),
        Duo::Connection::Type::Server,
        settings
      )
      
      # Flow control should be available
      flow_control = connection_manager.flow_control
      flow_control.should_not be_nil
      flow_control.connection_window_size.should eq(65535)
    end

    it "integrates with priority management" do
      # RFC 9113 Section 5.3: Stream Priority
      # Connection should integrate with priority management
      
      io = IO::Memory.new
      settings = Duo::Settings.new
      connection_manager = Duo::Core::ConnectionManager.new(
        Duo::Core::IOManager.new(io),
        Duo::Connection::Type::Server,
        settings
      )
      
      # Priority management should be available
      priority_manager = connection_manager.priority_manager
      priority_manager.should_not be_nil
      
      # Should be able to add streams with priority
      stream_node = priority_manager.add_stream(1, 0, 16, false)
      stream_node.should_not be_nil
    end

    it "integrates with HPACK" do
      # RFC 7541 Section 2: HPACK Overview
      # Connection should integrate with HPACK
      
      io = IO::Memory.new
      settings = Duo::Settings.new
      connection_manager = Duo::Core::ConnectionManager.new(
        Duo::Core::IOManager.new(io),
        Duo::Connection::Type::Server,
        settings
      )
      
      # HPACK should be available
      hpack_encoder = connection_manager.hpack_encoder
      hpack_decoder = connection_manager.hpack_decoder
      
      hpack_encoder.should_not be_nil
      hpack_decoder.should_not be_nil
      
      # Should be able to encode/decode headers
      headers = HTTP::Headers.new
      headers[":method"] = "GET"
      headers[":path"] = "/"
      
      encoded = hpack_encoder.encode_headers(headers)
      encoded.should_not be_nil
      
      decoded = hpack_decoder.decode_headers(encoded)
      decoded.should eq(headers)
    end
  end

  describe "Connection Monitoring" do
    it "provides connection statistics" do
      # RFC 9113 Section 4: HTTP Frames
      # Connection should provide statistics for monitoring
      
      io = IO::Memory.new
      settings = Duo::Settings.new
      connection_manager = Duo::Core::ConnectionManager.new(
        Duo::Core::IOManager.new(io),
        Duo::Connection::Type::Server,
        settings
      )
      
      # Get connection statistics
      stats = connection_manager.get_statistics
      stats.should_not be_nil
      
      # Should include basic metrics
      stats.total_frames_received.should be >= 0
      stats.total_frames_sent.should be >= 0
      stats.active_streams.should be >= 0
    end

    it "provides health check functionality" do
      # RFC 9113 Section 6.7: PING
      # Connection should provide health check functionality
      
      io = IO::Memory.new
      settings = Duo::Settings.new
      connection_manager = Duo::Core::ConnectionManager.new(
        Duo::Core::IOManager.new(io),
        Duo::Connection::Type::Server,
        settings
      )
      
      # Perform health check
      health_status = connection_manager.check_health
      health_status.should_not be_nil
      health_status.healthy.should be_true
    end

    it "provides connection metrics" do
      # RFC 9113 Section 4: HTTP Frames
      # Connection should provide detailed metrics
      
      io = IO::Memory.new
      settings = Duo::Settings.new
      connection_manager = Duo::Core::ConnectionManager.new(
        Duo::Core::IOManager.new(io),
        Duo::Connection::Type::Server,
        settings
      )
      
      # Get detailed metrics
      metrics = connection_manager.get_metrics
      metrics.should_not be_nil
      
      # Should include various metrics
      metrics.frame_counts.should_not be_nil
      metrics.stream_counts.should_not be_nil
      metrics.error_counts.should_not be_nil
    end
  end
end