require "socket"
require "openssl"
require "../src/duo"

# HTTP/2 Test Client demonstrating various features
# This client shows how to interact with the test server

Log.for("Duo").level = Log::Severity::Info

puts "🚀 HTTP/2 Test Client Starting..."
puts "Connecting to test server..."

# Create HTTP/2 client
client = Duo::Client.new("localhost", 4000, true) # true for TLS

# Test 1: Basic echo endpoint
puts "\n📡 Test 1: Echo endpoint"
headers = HTTP::Headers{
  ":method"    => "GET",
  ":path"      => "/echo",
  "user-agent" => "duo-test-client/1.0",
  "x-test"     => "echo-test",
}

client.request(headers) do |response_headers, body|
  puts "Response Status: #{response_headers[":status"]}"
  puts "Response Body:"
  puts body.gets_to_end
end

# Test 2: JSON API endpoints
puts "\n📡 Test 2: JSON API endpoints"

# Test /api/users
headers = HTTP::Headers{
  ":method" => "GET",
  ":path"   => "/api/users",
}

client.request(headers) do |response_headers, body|
  puts "Users API Response:"
  puts body.gets_to_end
end

# Test /api/status
headers = HTTP::Headers{
  ":method" => "GET",
  ":path"   => "/api/status",
}

client.request(headers) do |response_headers, body|
  puts "Status API Response:"
  puts body.gets_to_end
end

# Test 3: File serving endpoints
puts "\n📡 Test 3: File serving endpoints"

# Test HTML file
headers = HTTP::Headers{
  ":method" => "GET",
  ":path"   => "/files/html",
}

client.request(headers) do |response_headers, body|
  puts "HTML File Response (first 200 chars):"
  content = body.gets_to_end
  puts content[0..200] + "..." if content.size > 200
end

# Test 4: Error endpoints
puts "\n📡 Test 4: Error endpoints"

error_codes = [400, 401, 403, 404, 500, 503]
error_codes.each do |code|
  headers = HTTP::Headers{
    ":method" => "GET",
    ":path"   => "/error/#{code}",
  }

  client.request(headers) do |response_headers, body|
    puts "Error #{code} Response:"
    puts body.gets_to_end
  end
end

# Test 5: Performance endpoints
puts "\n📡 Test 5: Performance endpoints"

perf_endpoints = ["small", "medium", "large", "binary"]
perf_endpoints.each do |endpoint|
  headers = HTTP::Headers{
    ":method" => "GET",
    ":path"   => "/perf/#{endpoint}",
  }

  client.request(headers) do |response_headers, body|
    content = body.gets_to_end
    puts "Performance #{endpoint}: #{content.size} bytes"
  end
end

# Test 6: Concurrent requests (demonstrating HTTP/2 multiplexing)
puts "\n📡 Test 6: Concurrent requests (HTTP/2 multiplexing)"

requests = [] of Fiber
5.times do |i|
  requests << spawn do
    headers = HTTP::Headers{
      ":method"      => "GET",
      ":path"        => "/echo",
      "x-request-id" => "req-#{i}",
    }

    client.request(headers) do |response_headers, body|
      puts "Concurrent request #{i}: #{response_headers[":status"]}"
    end
  end
end

# Wait for all concurrent requests to complete
requests.each(&.join)

puts "\n✅ All tests completed!"
begin
  client.close
rescue ex : OpenSSL::SSL::Error | IO::Error
  puts "Note: Connection close error (normal): #{ex.message}"
end
