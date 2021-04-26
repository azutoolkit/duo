# DUO

[![Crystal CI](https://github.com/azutoolkit/duo/actions/workflows/crystal.yml/badge.svg?branch=main)](https://github.com/azutoolkit/duo/actions/workflows/crystal.yml)

An HTTP/2 Server written purely in Crystal

HTTP/2 is binary, instead of textual. HTTP/2 is fully multiplexed. This means that HTTP/2 can send multiple requests for data in parallel over a single TCP connection. This is the most advanced feature of the HTTP/2 protocol because it allows you to download web files via ASync mode from one server.

## Http 2 Spec Coverage


### H2Spec

```crystal 
./h2spec -p 9876 -k -t -S
Generic tests for HTTP/2 server
  1. Starting HTTP/2
    ✔ 1: Sends a client connection preface

  2. Streams and Multiplexing
    ✔ 1: Sends a PRIORITY frame on idle stream
    ✔ 2: Sends a WINDOW_UPDATE frame on half-closed (remote) stream
    ✔ 3: Sends a PRIORITY frame on half-closed (remote) stream
    ✔ 4: Sends a RST_STREAM frame on half-closed (remote) stream
    ✔ 5: Sends a PRIORITY frame on closed stream

  3. Frame Definitions
    3.1. DATA
      ✔ 1: Sends a DATA frame
      ✔ 2: Sends multiple DATA frames
      ✔ 3: Sends a DATA frame with padding

    3.2. HEADERS
      ✔ 1: Sends a HEADERS frame
      ✔ 2: Sends a HEADERS frame with padding
      ✔ 3: Sends a HEADERS frame with priority

    3.3. PRIORITY
      ✔ 1: Sends a PRIORITY frame with priority 1
      ✔ 2: Sends a PRIORITY frame with priority 256
      ✔ 3: Sends a PRIORITY frame with stream dependency
      ✔ 4: Sends a PRIORITY frame with exclusive
      ✔ 5: Sends a PRIORITY frame for an idle stream, then send a HEADER frame for a lower stream ID

    3.4. RST_STREAM
      ✔ 1: Sends a RST_STREAM frame

    3.5. SETTINGS
      ✔ 1: Sends a SETTINGS frame

    3.7. PING
      ✔ 1: Sends a PING frame

    3.8. GOAWAY
      ✔ 1: Sends a GOAWAY frame

    3.9. WINDOW_UPDATE
      ✔ 1: Sends a WINDOW_UPDATE frame with stream ID 0
      ✔ 2: Sends a WINDOW_UPDATE frame with stream ID 1

    3.10. CONTINUATION
      ✔ 1: Sends a CONTINUATION frame
      ✔ 2: Sends multiple CONTINUATION frames

  4. HTTP Message Exchanges
    ✔ 1: Sends a GET request
    ✔ 2: Sends a HEAD request
    ✔ 3: Sends a POST request
    ✔ 4: Sends a POST request with trailers

  5. HPACK
    ✔ 1: Sends a indexed header field representation
    ✔ 2: Sends a literal header field with incremental indexing - indexed name
    ✔ 3: Sends a literal header field with incremental indexing - indexed name (with Huffman coding)
    ✔ 4: Sends a literal header field with incremental indexing - new name
    ✔ 5: Sends a literal header field with incremental indexing - new name (with Huffman coding)
    ✔ 6: Sends a literal header field without indexing - indexed name
    ✔ 7: Sends a literal header field without indexing - indexed name (with Huffman coding)
    ✔ 8: Sends a literal header field without indexing - new name
    ✔ 9: Sends a literal header field without indexing - new name (huffman encoded)
    ✔ 10: Sends a literal header field never indexed - indexed name
    ✔ 11: Sends a literal header field never indexed - indexed name (huffman encoded)
    ✔ 12: Sends a literal header field never indexed - new name
    ✔ 13: Sends a literal header field never indexed - new name (huffman encoded)
    ✔ 14: Sends a dynamic table size update
    ✔ 15: Sends multiple dynamic table size update

Hypertext Transfer Protocol Version 2 (HTTP/2)
  3. Starting HTTP/2
    3.5. HTTP/2 Connection Preface
      ✔ 1: Sends client connection preface
      ✔ 2: Sends invalid connection preface

  4. HTTP Frames
    4.1. Frame Format
      ✔ 1: Sends a frame with unknown type
      ✔ 2: Sends a frame with undefined flag
      ✔ 3: Sends a frame with reserved field bit

    4.2. Frame Size
      ✔ 1: Sends a DATA frame with 2^14 octets in length
      ✔ 2: Sends a large size DATA frame that exceeds the SETTINGS_MAX_FRAME_SIZE
      ✔ 3: Sends a large size HEADERS frame that exceeds the SETTINGS_MAX_FRAME_SIZE

    4.3. Header Compression and Decompression
      ✔ 1: Sends invalid header block fragment
      ✔ 2: Sends a PRIORITY frame while sending the header blocks
      ✔ 3: Sends a HEADERS frame to another stream while sending the header blocks

  5. Streams and Multiplexing
    5.1. Stream States
      ✔ 1: idle: Sends a DATA frame
      ✔ 2: idle: Sends a RST_STREAM frame
      ✔ 3: idle: Sends a WINDOW_UPDATE frame
      ✔ 4: idle: Sends a CONTINUATION frame
      ✔ 5: half closed (remote): Sends a DATA frame
      ✔ 6: half closed (remote): Sends a HEADERS frame
      ✔ 7: half closed (remote): Sends a CONTINUATION frame
      ✔ 8: closed: Sends a DATA frame after sending RST_STREAM frame
      ✔ 9: closed: Sends a HEADERS frame after sending RST_STREAM frame
      ✔ 10: closed: Sends a CONTINUATION frame after sending RST_STREAM frame
      ✔ 11: closed: Sends a DATA frame
      ✔ 12: closed: Sends a HEADERS frame
      ✔ 13: closed: Sends a CONTINUATION frame

      5.1.1. Stream Identifiers
        ✔ 1: Sends even-numbered stream identifier
        ✔ 2: Sends stream identifier that is numerically smaller than previous

      5.1.2. Stream Concurrency
        ✔ 1: Sends HEADERS frames that causes their advertised concurrent stream limit to be exceeded

    5.3. Stream Priority
      5.3.1. Stream Dependencies
        ✔ 1: Sends HEADERS frame that depends on itself
        ✔ 2: Sends PRIORITY frame that depend on itself

    5.4. Error Handling
      5.4.1. Connection Error Handling
        ✔ 1: Sends an invalid PING frame for connection close
        ✔ 2: Sends an invalid PING frame to receive GOAWAY frame

    5.5. Extending HTTP/2
      ✔ 1: Sends an unknown extension frame
      ✔ 2: Sends an unknown extension frame in the middle of a header block

  6. Frame Definitions
    6.1. DATA
      ✔ 1: Sends a DATA frame with 0x0 stream identifier
      ✔ 2: Sends a DATA frame on the stream that is not in "open" or "half-closed (local)" state
      ✔ 3: Sends a DATA frame with invalid pad length

    6.2. HEADERS
      ✔ 1: Sends a HEADERS frame without the END_HEADERS flag, and a PRIORITY frame
      ✔ 2: Sends a HEADERS frame to another stream while sending a HEADERS frame
      ✔ 3: Sends a HEADERS frame with 0x0 stream identifier
      ✔ 4: Sends a HEADERS frame with invalid pad length

    6.3. PRIORITY
      ✔ 1: Sends a PRIORITY frame with 0x0 stream identifier
      ✔ 2: Sends a PRIORITY frame with a length other than 5 octets

    6.4. RST_STREAM
      ✔ 1: Sends a RST_STREAM frame with 0x0 stream identifier
      ✔ 2: Sends a RST_STREAM frame on a idle stream
      ✔ 3: Sends a RST_STREAM frame with a length other than 4 octets

    6.5. SETTINGS
      ✔ 1: Sends a SETTINGS frame with ACK flag and payload
      ✔ 2: Sends a SETTINGS frame with a stream identifier other than 0x0
      ✔ 3: Sends a SETTINGS frame with a length other than a multiple of 6 octets

      6.5.2. Defined SETTINGS Parameters
        ✔ 1: SETTINGS_ENABLE_PUSH (0x2): Sends the value other than 0 or 1
        ✔ 2: SETTINGS_INITIAL_WINDOW_SIZE (0x4): Sends the value above the maximum flow control window size
        ✔ 3: SETTINGS_MAX_FRAME_SIZE (0x5): Sends the value below the initial value
        ✔ 4: SETTINGS_MAX_FRAME_SIZE (0x5): Sends the value above the maximum allowed frame size
        ✔ 5: Sends a SETTINGS frame with unknown identifier

      6.5.3. Settings Synchronization
        ✔ 1: Sends multiple values of SETTINGS_INITIAL_WINDOW_SIZE
        ✔ 2: Sends a SETTINGS frame without ACK flag

    6.7. PING
      ✔ 1: Sends a PING frame
      ✔ 2: Sends a PING frame with ACK
      ✔ 3: Sends a PING frame with a stream identifier field value other than 0x0
      ✔ 4: Sends a PING frame with a length field value other than 8

    6.8. GOAWAY
      ✔ 1: Sends a GOAWAY frame with a stream identifier other than 0x0

    6.9. WINDOW_UPDATE
      ✔ 1: Sends a WINDOW_UPDATE frame with a flow control window increment of 0
      ✔ 2: Sends a WINDOW_UPDATE frame with a flow control window increment of 0 on a stream
      ✔ 3: Sends a WINDOW_UPDATE frame with a length other than 4 octets

      6.9.1. The Flow-Control Window
        ✔ 1: Sends SETTINGS frame to set the initial window size to 1 and sends HEADERS frame
        ✔ 2: Sends multiple WINDOW_UPDATE frames increasing the flow control window to above 2^31-1
        ✔ 3: Sends multiple WINDOW_UPDATE frames increasing the flow control window to above 2^31-1 on a stream

      6.9.2. Initial Flow-Control Window Size
        ✔ 1: Changes SETTINGS_INITIAL_WINDOW_SIZE after sending HEADERS frame
        ✔ 2: Sends a SETTINGS frame for window size to be negative
        ✔ 3: Sends a SETTINGS_INITIAL_WINDOW_SIZE settings with an exceeded maximum window size value

    6.10. CONTINUATION
      ✔ 1: Sends multiple CONTINUATION frames preceded by a HEADERS frame
      ✔ 2: Sends a CONTINUATION frame followed by any frame other than CONTINUATION
      ✔ 3: Sends a CONTINUATION frame with 0x0 stream identifier
      ✔ 4: Sends a CONTINUATION frame preceded by a HEADERS frame with END_HEADERS flag
      ✔ 5: Sends a CONTINUATION frame preceded by a CONTINUATION frame with END_HEADERS flag
      ✔ 6: Sends a CONTINUATION frame preceded by a DATA frame

  7. Error Codes
    ✔ 1: Sends a GOAWAY frame with unknown error code
    ✔ 2: Sends a RST_STREAM frame with unknown error code

  8. HTTP Message Exchanges
    8.1. HTTP Request/Response Exchange
      ✔ 1: Sends a second HEADERS frame without the END_STREAM flag

      8.1.2. HTTP Header Fields
        ✔ 1: Sends a HEADERS frame that contains the header field name in uppercase letters

        8.1.2.1. Pseudo-Header Fields
          ✔ 1: Sends a HEADERS frame that contains a unknown pseudo-header field
          ✔ 2: Sends a HEADERS frame that contains the pseudo-header field defined for response
          ✔ 3: Sends a HEADERS frame that contains a pseudo-header field as trailers
          ✔ 4: Sends a HEADERS frame that contains a pseudo-header field that appears in a header block after a regular header field

        8.1.2.2. Connection-Specific Header Fields
          ✔ 1: Sends a HEADERS frame that contains the connection-specific header field
          ✔ 2: Sends a HEADERS frame that contains the TE header field with any value other than "trailers"

        8.1.2.3. Request Pseudo-Header Fields
          ✔ 1: Sends a HEADERS frame with empty ":path" pseudo-header field
          ✔ 2: Sends a HEADERS frame that omits ":method" pseudo-header field
          ✔ 3: Sends a HEADERS frame that omits ":scheme" pseudo-header field
          ✔ 4: Sends a HEADERS frame that omits ":path" pseudo-header field
          ✔ 5: Sends a HEADERS frame with duplicated ":method" pseudo-header field
          ✔ 6: Sends a HEADERS frame with duplicated ":scheme" pseudo-header field
          ✔ 7: Sends a HEADERS frame with duplicated ":path" pseudo-header field

        8.1.2.6. Malformed Requests and Responses
          ✔ 1: Sends a HEADERS frame with the "content-length" header field which does not equal the DATA frame payload length
          ✔ 2: Sends a HEADERS frame with the "content-length" header field which does not equal the sum of the multiple DATA frames payload length

    8.2. Server Push
      ✔ 1: Sends a PUSH_PROMISE frame

HPACK: Header Compression for HTTP/2
  2. Compression Process Overview
    2.3. Indexing Tables
      2.3.3. Index Address Space
        ✔ 1: Sends a indexed header field representation with invalid index
        ✔ 2: Sends a literal header field representation with invalid index

  4. Dynamic Table Management
    4.2. Maximum Table Size
      ✔ 1: Sends a dynamic table size update at the end of header block

  5. Primitive Type Representations
    5.2. String Literal Representation
      ✔ 1: Sends a Huffman-encoded string literal representation with padding longer than 7 bits
      ✔ 2: Sends a Huffman-encoded string literal representation padded by zero
      ✔ 3: Sends a Huffman-encoded string literal representation containing the EOS symbol

  6. Binary Format
    6.1. Indexed Header Field Representation
      ✔ 1: Sends a indexed header field representation with index 0

    6.3. Dynamic Table Size Update
      ✔ 1: Sends a dynamic table size update larger than the value of SETTINGS_HEADER_TABLE_SIZE

Finished in 3.0364 seconds
147 tests, 147 passed, 0 skipped, 0 failed

```

### H2 Load

```crystal
h2load -n 100000 -c 100 -t 1 -T 2 -m 32 -H 'Accept-Encoding: gzip,deflate' https://127.0.0.1:9876
starting benchmark...
spawning thread #0: 100 total client(s). 100000 total requests
TLS Protocol: TLSv1.3
Cipher: TLS_AES_256_GCM_SHA384
Server Temp Key: ECDH P-256 256 bits
Application protocol: h2
progress: 10% done
progress: 20% done
progress: 30% done
progress: 40% done
progress: 50% done
progress: 60% done
progress: 70% done
progress: 80% done
progress: 90% done
progress: 100% done

finished in 13.91s, 7187.18 req/s, 407.42KB/s
requests: 100000 total, 100000 started, 100000 done, 100000 succeeded, 0 failed, 0 errored, 0 timeout
status codes: 100000 2xx, 0 3xx, 0 4xx, 0 5xx
traffic: 5.54MB (5804800) total, 585.94KB (600000) headers (space savings 76.92%), 1.14MB (1200000) data
                     min         max         mean         sd        +/- sd
time for request:    94.66ms       1.61s    417.91ms    159.33ms    90.55%
time for connect:    62.29ms       1.40s    736.79ms    394.58ms    57.00%
time to 1st byte:      1.44s       1.75s       1.67s    112.38ms    80.00%
req/s           :      71.88       72.18       72.00        0.11    68.00%

```

## Installation

1. Add the dependency to your `shard.yml`:

   ```yaml
   dependencies:
     duo:
       github: eliasjpr/duo
   ```

2. Run `shards install`

## Usage

```crystal
require "duo"
```

## Server Example

```crystal
require "../src/duo"

class EchoHandler
  include Duo::Server::Handler

  def call(context : Duo::Server::Context)
    request, response = context.request, context.response
    context.response << "Hello World!"
    context
  end
end

class NotFoundHandler
  include Duo::Server::Handler

  def call(context : Duo::Server::Context)
    response = context.response
    response.status = 404
    response.headers["server"] = "h2/0.0.0"
    response.headers["content-type"] = "text/plain"
    response << "404 NOT FOUND\n"
  end
end

ssl_context = OpenSSL::SSL::Context::Server.new
ssl_context.certificate_chain = File.join(__DIR__, "ssl", "example.crt")
ssl_context.private_key = File.join(__DIR__, "ssl", "example.key")
ssl_context.alpn_protocol = "h2"

host = ENV["HOST"]? || "::"
port = (ENV["PORT"]? || 9876).to_i

handlers = [
  EchoHandler.new,
  NotFoundHandler.new,
]
server = Duo::Server.new(host, port, ssl_context)

if ssl_context
  puts "listening on https://#{host}:#{port}/"
else
  puts "listening on http://#{host}:#{port}/"
end
server.listen(handlers)

```

## Client Example 

```crystal
require "socket"
require "openssl"
require "./src/connection"

Log.for("Duo(Duo)").level = Log::Severity::Debug

client = Duo::Client.new("localhost", 9876, !!ENV["TLS"]?)

10.times do |i|
  headers = HTTP::Headers{
    ":method"    => "GET",
    ":path"      => "/",
    "user-agent" => "crystal h2/0.0.0",
  }

  client.request(headers) do |headers, body|
    puts "REQ ##{i}: #{headers.inspect}"

    while line = body.gets
      puts "REQ ##{i}: #{line}"
    end
  end
end

client.close
```

## Development

TODO: Write development instructions here

## Credits

- Julien Portalier [@ysbaddaden](https://github.com/ysbaddaden)
- [@636f7374](https://github.com/636f7374) 

## Contributing

1. Fork it (<https://github.com/eliasjpr/duo/fork>)
2. Create your feature branch (`git checkout -b my-new-feature`)
3. Commit your changes (`git commit -am 'Add some feature'`)
4. Push to the branch (`git push origin my-new-feature`)
5. Create a new Pull Request

## Contributors

- [Elias J. Perez](https://github.com/eliasjpr) - creator and maintainer
