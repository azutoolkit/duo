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
