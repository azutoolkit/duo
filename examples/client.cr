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
