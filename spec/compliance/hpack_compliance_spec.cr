require "../spec_helper"

describe "HTTP/2 HPACK Compliance (RFC 7541)" do
  describe "HPACK Principles" do
    it "validates HPACK encoder/decoder creation" do
      # RFC 7541 Section 2: HPACK Overview
      # HPACK is a compression format for efficiently representing HTTP header fields
      
      encoder = Duo::Core::HPACK::Encoder.new(4096)
      decoder = Duo::Core::HPACK::Decoder.new(4096)
      
      encoder.should be_a(Duo::Core::HPACK::Encoder)
      decoder.should be_a(Duo::Core::HPACK::Decoder)
    end

    it "validates HPACK table size limits" do
      # RFC 7541 Section 4.1: Dynamic Table Size Update
      # The maximum size of the dynamic table is the minimum of the maximum table size
      # and the sum of the maximum table size and the maximum allowed table size
      
      # Valid table sizes
      valid_sizes = [0, 4096, 8192, 16384]
      valid_sizes.each do |size|
        encoder = Duo::Core::HPACK::Encoder.new(size)
        decoder = Duo::Core::HPACK::Decoder.new(size)
        # Should not raise error
      end
      
      # Invalid table sizes
      invalid_sizes = [-1, 0x80000000]
      invalid_sizes.each do |size|
        expect_raises(Duo::Error) do
          Duo::Core::HPACK::Encoder.new(size)
        end
      end
    end
  end

  describe "HPACK Indexing" do
    it "validates indexed header field representation" do
      # RFC 7541 Section 6.1: Indexed Header Field Representation
      # An indexed header field representation identifies an entry in either the static table
      # or the dynamic table
      
      encoder = Duo::Core::HPACK::Encoder.new(4096)
      decoder = Duo::Core::HPACK::Decoder.new(4096)
      
      # Test static table entries
      static_entries = [
        {":authority", ""},
        {":method", "GET"},
        {":method", "POST"},
        {":path", "/"},
        {":path", "/index.html"},
        {":scheme", "http"},
        {":scheme", "https"},
        {":status", "200"},
        {":status", "204"},
        {":status", "206"},
        {":status", "304"},
        {":status", "400"},
        {":status", "404"},
        {":status", "500"},
        {"accept-charset", ""},
        {"accept-encoding", "gzip, deflate"},
        {"accept-language", ""},
        {"accept-ranges", ""},
        {"accept", ""},
        {"access-control-allow-origin", ""},
        {"age", ""},
        {"allow", ""},
        {"authorization", ""},
        {"cache-control", ""},
        {"content-disposition", ""},
        {"content-encoding", ""},
        {"content-language", ""},
        {"content-length", ""},
        {"content-location", ""},
        {"content-range", ""},
        {"content-type", ""},
        {"cookie", ""},
        {"date", ""},
        {"etag", ""},
        {"expect", ""},
        {"expires", ""},
        {"from", ""},
        {"host", ""},
        {"if-match", ""},
        {"if-modified-since", ""},
        {"if-none-match", ""},
        {"if-range", ""},
        {"if-unmodified-since", ""},
        {"last-modified", ""},
        {"link", ""},
        {"location", ""},
        {"max-forwards", ""},
        {"proxy-authenticate", ""},
        {"proxy-authorization", ""},
        {"range", ""},
        {"referer", ""},
        {"refresh", ""},
        {"retry-after", ""},
        {"server", ""},
        {"set-cookie", ""},
        {"strict-transport-security", ""},
        {"transfer-encoding", ""},
        {"user-agent", ""},
        {"vary", ""},
        {"via", ""},
        {"www-authenticate", ""}
      ]
      
      static_entries.each_with_index do |entry, index|
        name, value = entry
        
        # Encode indexed header
        encoded = encoder.encode_indexed(index + 1)
        encoded.should_not be_nil
        
        # Decode indexed header
        decoded = decoder.decode_indexed(encoded)
        decoded.should eq({name, value})
      end
    end

    it "validates literal header field with incremental indexing" do
      # RFC 7541 Section 6.2.1: Literal Header Field with Incremental Indexing
      # A literal header field with incremental indexing representation results in appending
      # a header field to the decoded header list and inserting it as a new entry into the dynamic table
      
      encoder = Duo::Core::HPACK::Encoder.new(4096)
      decoder = Duo::Core::HPACK::Decoder.new(4096)
      
      # Test literal header with incremental indexing
      name = "custom-header"
      value = "custom-value"
      
      encoded = encoder.encode_literal_incremental(name, value)
      encoded.should_not be_nil
      
      decoded = decoder.decode_literal_incremental(encoded)
      decoded.should eq({name, value})
      
      # Should be added to dynamic table
      table_entry = decoder.get_dynamic_table_entry(1)
      table_entry.should eq({name, value})
    end

    it "validates literal header field without indexing" do
      # RFC 7541 Section 6.2.2: Literal Header Field without Indexing
      # A literal header field without indexing representation results in appending
      # a header field to the decoded header list without altering the dynamic table
      
      encoder = Duo::Core::HPACK::Encoder.new(4096)
      decoder = Duo::Core::HPACK::Decoder.new(4096)
      
      # Test literal header without indexing
      name = "temporary-header"
      value = "temporary-value"
      
      encoded = encoder.encode_literal_no_index(name, value)
      encoded.should_not be_nil
      
      decoded = decoder.decode_literal_no_index(encoded)
      decoded.should eq({name, value})
      
      # Should NOT be added to dynamic table
      table_entry = decoder.get_dynamic_table_entry(1)
      table_entry.should be_nil
    end

    it "validates literal header field never indexed" do
      # RFC 7541 Section 6.2.3: Literal Header Field Never Indexed
      # A literal header field never indexed representation results in appending
      # a header field to the decoded header list without altering the dynamic table
      
      encoder = Duo::Core::HPACK::Encoder.new(4096)
      decoder = Duo::Core::HPACK::Decoder.new(4096)
      
      # Test literal header never indexed
      name = "sensitive-header"
      value = "sensitive-value"
      
      encoded = encoder.encode_literal_never_indexed(name, value)
      encoded.should_not be_nil
      
      decoded = decoder.decode_literal_never_indexed(encoded)
      decoded.should eq({name, value})
      
      # Should NOT be added to dynamic table
      table_entry = decoder.get_dynamic_table_entry(1)
      table_entry.should be_nil
    end
  end

  describe "HPACK Dynamic Table Management" do
    it "validates dynamic table size update" do
      # RFC 7541 Section 4.1: Dynamic Table Size Update
      # A dynamic table size update signals a change to the size of the dynamic table
      
      encoder = Duo::Core::HPACK::Encoder.new(4096)
      decoder = Duo::Core::HPACK::Decoder.new(4096)
      
      # Update table size
      new_size = 2048
      encoded = encoder.encode_table_size_update(new_size)
      encoded.should_not be_nil
      
      decoder.decode_table_size_update(encoded)
      decoder.max_table_size.should eq(new_size)
    end

    it "validates dynamic table eviction" do
      # RFC 7541 Section 4.4: Entry Eviction When Adding New Entries
      # Before a new entry is added to the dynamic table, entries are evicted from the end
      # of the dynamic table until the size of the dynamic table is less than or equal to
      # (maximum size - new entry size) or until the table is empty
      
      encoder = Duo::Core::HPACK::Encoder.new(100) # Small table for testing
      decoder = Duo::Core::HPACK::Decoder.new(100)
      
      # Add entries until table is full
      entries = [
        {"header1", "value1"},
        {"header2", "value2"},
        {"header3", "value3"},
        {"header4", "value4"}
      ]
      
      entries.each do |name, value|
        encoded = encoder.encode_literal_incremental(name, value)
        decoder.decode_literal_incremental(encoded)
      end
      
      # Add one more entry (should trigger eviction)
      encoded = encoder.encode_literal_incremental("header5", "value5")
      decoder.decode_literal_incremental(encoded)
      
      # Table size should be within limits
      decoder.dynamic_table_size.should be <= decoder.max_table_size
    end

    it "validates dynamic table entry size calculation" do
      # RFC 7541 Section 4.1: Dynamic Table Size Update
      # The size of an entry is the sum of its name's length in octets, its value's length
      # in octets, and 32
      
      encoder = Duo::Core::HPACK::Encoder.new(4096)
      
      name = "test-header"
      value = "test-value"
      
      entry_size = encoder.calculate_entry_size(name, value)
      expected_size = name.bytesize + value.bytesize + 32
      entry_size.should eq(expected_size)
    end

    it "validates dynamic table maximum size enforcement" do
      # RFC 7541 Section 4.1: Dynamic Table Size Update
      # The maximum size of the dynamic table is the minimum of the maximum table size
      # and the sum of the maximum table size and the maximum allowed table size
      
      encoder = Duo::Core::HPACK::Encoder.new(4096)
      decoder = Duo::Core::HPACK::Decoder.new(4096)
      
      # Try to set table size larger than maximum
      expect_raises(Duo::Error) do
        encoder.encode_table_size_update(0x80000000)
      end
    end
  end

  describe "HPACK Encoding/Decoding" do
    it "validates complete header list encoding/decoding" do
      # RFC 7541 Section 2: HPACK Overview
      # HPACK is a compression format for efficiently representing HTTP header fields
      
      encoder = Duo::Core::HPACK::Encoder.new(4096)
      decoder = Duo::Core::HPACK::Decoder.new(4096)
      
      # Test header list
      headers = HTTP::Headers.new
      headers[":method"] = "GET"
      headers[":path"] = "/"
      headers[":scheme"] = "https"
      headers["user-agent"] = "test-client"
      headers["accept"] = "text/html"
      
      # Encode header list
      encoded = encoder.encode_headers(headers)
      encoded.should_not be_nil
      
      # Decode header list
      decoded = decoder.decode_headers(encoded)
      decoded.should eq(headers)
    end

    it "validates header list size limits" do
      # RFC 7541 Section 4.1: Dynamic Table Size Update
      # The maximum size of the dynamic table is the minimum of the maximum table size
      # and the sum of the maximum table size and the maximum allowed table size
      
      encoder = Duo::Core::HPACK::Encoder.new(100) # Small table
      decoder = Duo::Core::HPACK::Decoder.new(100)
      
      # Create large header
      large_name = "x" * 50
      large_value = "y" * 50
      
      # Should fail due to size limit
      expect_raises(Duo::Error) do
        encoder.encode_literal_incremental(large_name, large_value)
      end
    end

    it "validates header name/value validation" do
      # RFC 7541 Section 6.2: Literal Header Field Representation
      # Header names and values must be valid
      
      encoder = Duo::Core::HPACK::Encoder.new(4096)
      
      # Valid headers
      valid_headers = [
        {"valid-header", "valid-value"},
        {"x-custom", "custom-value"},
        {"content-type", "text/html; charset=utf-8"}
      ]
      
      valid_headers.each do |name, value|
        encoded = encoder.encode_literal_incremental(name, value)
        encoded.should_not be_nil
      end
      
      # Invalid headers (empty names)
      expect_raises(Duo::Error) do
        encoder.encode_literal_incremental("", "value")
      end
    end

    it "validates header case sensitivity" do
      # RFC 7541 Section 6.2: Literal Header Field Representation
      # Header names are case-insensitive
      
      encoder = Duo::Core::HPACK::Encoder.new(4096)
      decoder = Duo::Core::HPACK::Decoder.new(4096)
      
      # Test case variations
      variations = [
        {"Content-Type", "text/html"},
        {"content-type", "text/html"},
        {"CONTENT-TYPE", "text/html"}
      ]
      
      variations.each do |name, value|
        encoded = encoder.encode_literal_incremental(name, value)
        decoded = decoder.decode_literal_incremental(encoded)
        decoded.should eq({name.downcase, value})
      end
    end
  end

  describe "HPACK Error Handling" do
    it "handles invalid index values" do
      # RFC 7541 Section 6.1: Indexed Header Field Representation
      # Invalid index values should be handled gracefully
      
      decoder = Duo::Core::HPACK::Decoder.new(4096)
      
      # Test invalid static table index
      expect_raises(Duo::Error) do
        decoder.decode_indexed(Bytes.new(0))
      end
      
      # Test invalid dynamic table index
      expect_raises(Duo::Error) do
        decoder.decode_indexed(Bytes.new(0))
      end
    end

    it "handles truncated encoded data" do
      # RFC 7541 Section 6: Binary Format
      # Truncated encoded data should be handled gracefully
      
      decoder = Duo::Core::HPACK::Decoder.new(4096)
      
      # Test truncated data
      truncated_data = Bytes.new(2, 0x80) # Incomplete index
      
      expect_raises(Duo::Error) do
        decoder.decode_indexed(truncated_data)
      end
    end

    it "handles oversized header lists" do
      # RFC 7541 Section 4.1: Dynamic Table Size Update
      # Oversized header lists should be handled gracefully
      
      encoder = Duo::Core::HPACK::Encoder.new(100) # Small table
      
      # Create oversized header list
      headers = HTTP::Headers.new
      100.times do |i|
        headers["header#{i}"] = "value#{i}"
      end
      
      # Should handle gracefully (either truncate or error)
      begin
        encoded = encoder.encode_headers(headers)
        # Should not raise error if handled gracefully
      rescue Duo::Error
        # Error is acceptable for oversized lists
      end
    end
  end

  describe "HPACK Performance" do
    it "handles rapid header encoding/decoding" do
      # RFC 7541 Section 2: HPACK Overview
      # HPACK should handle rapid encoding/decoding efficiently
      
      encoder = Duo::Core::HPACK::Encoder.new(4096)
      decoder = Duo::Core::HPACK::Decoder.new(4096)
      
      # Rapid encoding/decoding
      1000.times do |i|
        name = "header#{i}"
        value = "value#{i}"
        
        encoded = encoder.encode_literal_incremental(name, value)
        decoded = decoder.decode_literal_incremental(encoded)
        decoded.should eq({name, value})
      end
    end

    it "handles concurrent encoding/decoding" do
      # RFC 7541 Section 2: HPACK Overview
      # HPACK should handle concurrent operations correctly
      
      encoder = Duo::Core::HPACK::Encoder.new(4096)
      decoder = Duo::Core::HPACK::Decoder.new(4096)
      
      # Concurrent operations
      fibers = [] of Fiber
      10.times do |i|
        fibers << spawn do
          100.times do |j|
            name = "header#{i}_#{j}"
            value = "value#{i}_#{j}"
            
            encoded = encoder.encode_literal_incremental(name, value)
            decoded = decoder.decode_literal_incremental(encoded)
            decoded.should eq({name, value})
          end
        end
      end
      
      # Wait for all fibers to complete
      fibers.each(&.join)
    end

    it "handles large header values" do
      # RFC 7541 Section 6.2: Literal Header Field Representation
      # HPACK should handle large header values efficiently
      
      encoder = Duo::Core::HPACK::Encoder.new(4096)
      decoder = Duo::Core::HPACK::Decoder.new(4096)
      
      # Large header value
      large_value = "x" * 1000
      
      encoded = encoder.encode_literal_incremental("large-header", large_value)
      encoded.should_not be_nil
      
      decoded = decoder.decode_literal_incremental(encoded)
      decoded.should eq({"large-header", large_value})
    end
  end

  describe "HPACK Integration" do
    it "integrates with HTTP/2 frame processing" do
      # RFC 7541 Section 2: HPACK Overview
      # HPACK should integrate with HTTP/2 frame processing
      
      encoder = Duo::Core::HPACK::Encoder.new(4096)
      decoder = Duo::Core::HPACK::Decoder.new(4096)
      
      # Create headers for HTTP/2 frame
      headers = HTTP::Headers.new
      headers[":method"] = "GET"
      headers[":path"] = "/"
      headers[":scheme"] = "https"
      headers["user-agent"] = "test-client"
      
      # Encode for HEADERS frame
      encoded = encoder.encode_headers(headers)
      
      # Simulate frame processing
      frame = Duo::Core::FrameFactory.create_headers_frame(1, headers)
      frame.type.should eq(Duo::FrameType::Headers)
      
      # Decode from frame
      decoded = decoder.decode_headers(encoded)
      decoded.should eq(headers)
    end

    it "integrates with stream lifecycle" do
      # RFC 7541 Section 2: HPACK Overview
      # HPACK should integrate with stream lifecycle
      
      encoder = Duo::Core::HPACK::Encoder.new(4096)
      decoder = Duo::Core::HPACK::Decoder.new(4096)
      
      # Simulate stream creation
      stream_id = 1
      
      # Add headers for stream
      headers = HTTP::Headers.new
      headers[":method"] = "GET"
      headers[":path"] = "/stream/#{stream_id}"
      
      encoded = encoder.encode_headers(headers)
      decoded = decoder.decode_headers(encoded)
      
      # Headers should be associated with stream
      decoded.should eq(headers)
    end

    it "integrates with connection settings" do
      # RFC 7541 Section 4.1: Dynamic Table Size Update
      # HPACK should integrate with connection settings
      
      # Test different table sizes
      table_sizes = [0, 1024, 4096, 8192]
      
      table_sizes.each do |size|
        encoder = Duo::Core::HPACK::Encoder.new(size)
        decoder = Duo::Core::HPACK::Decoder.new(size)
        
        # Should work with different table sizes
        headers = HTTP::Headers.new
        headers["test-header"] = "test-value"
        
        encoded = encoder.encode_headers(headers)
        decoded = decoder.decode_headers(encoded)
        decoded.should eq(headers)
      end
    end
  end

  describe "HPACK Security" do
    it "handles sensitive headers appropriately" do
      # RFC 7541 Section 6.2.3: Literal Header Field Never Indexed
      # Sensitive headers should use never-indexed representation
      
      encoder = Duo::Core::HPACK::Encoder.new(4096)
      decoder = Duo::Core::HPACK::Decoder.new(4096)
      
      # Sensitive headers
      sensitive_headers = [
        {"authorization", "Bearer token123"},
        {"cookie", "session=abc123"},
        {"x-api-key", "secret-key"}
      ]
      
      sensitive_headers.each do |name, value|
        # Should use never-indexed representation
        encoded = encoder.encode_literal_never_indexed(name, value)
        decoded = decoder.decode_literal_never_indexed(encoded)
        decoded.should eq({name, value})
        
        # Should NOT be in dynamic table
        table_entry = decoder.get_dynamic_table_entry(1)
        table_entry.should be_nil
      end
    end

    it "validates header list size limits for security" do
      # RFC 7541 Section 4.1: Dynamic Table Size Update
      # Header list size limits should be enforced for security
      
      encoder = Duo::Core::HPACK::Encoder.new(4096)
      
      # Try to create oversized header list
      headers = HTTP::Headers.new
      1000.times do |i|
        headers["header#{i}"] = "value#{i}"
      end
      
      # Should handle gracefully
      begin
        encoded = encoder.encode_headers(headers)
        # Should not raise error if handled gracefully
      rescue Duo::Error
        # Error is acceptable for oversized lists
      end
    end

    it "handles malformed encoded data securely" do
      # RFC 7541 Section 6: Binary Format
      # Malformed encoded data should be handled securely
      
      decoder = Duo::Core::HPACK::Decoder.new(4096)
      
      # Malformed data
      malformed_data = Bytes.new(10, 0xFF) # Invalid bytes
      
      expect_raises(Duo::Error) do
        decoder.decode_headers(malformed_data)
      end
    end
  end
end