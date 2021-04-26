<div style="text-align:center"><img src="https://raw.githubusercontent.com/azutoolkit/duo/main/duo.png" /></div>

# DUO

[![Crystal CI](https://github.com/azutoolkit/duo/actions/workflows/crystal.yml/badge.svg?branch=main)](https://github.com/azutoolkit/duo/actions/workflows/crystal.yml)

An HTTP/2 Server written purely in Crystal

HTTP/2 is binary, instead of textual. HTTP/2 is fully multiplexed. This means that HTTP/2 can send multiple requests for data in parallel over a single TCP connection. This is the most advanced feature of the HTTP/2 protocol because it allows you to download web files via ASync mode from one server.

## Http 2 Spec Coverage

Full H2Spec and H2Load Coverage

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
