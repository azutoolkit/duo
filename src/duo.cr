require "./duo/frame_types"
require "./duo/client"
require "./duo/server"

module Duo
  VERSION                     = "0.1.0"
  Log                         = ::Log.for("Duo (Duo)")
  DEFAULT_PRIORITY            = Priority.new(false, 0, 16)
  CLIENT_PREFACE              = "PRI * HTTP/2.0\r\n\r\nSM\r\n\r\n"
  MINIMUM_FRAME_SIZE          =        16_384
  MAXIMUM_FRAME_SIZE          =    16_777_215
  MINIMUM_WINDOW_SIZE         =             1
  MAXIMUM_WINDOW_SIZE         = 2_147_483_647
  PING_FRAME_SIZE             =             8
  PRIORITY_FRAME_SIZE         =             5
  RST_STREAM_FRAME_SIZE       =             4
  WINDOW_UPDATE_FRAME_SIZE    =             4
  DEFAULT_HEADER_TABLE_SIZE   =         4_096
  DEFAULT_ENABLE_PUSH         = false
  DEFAULT_INITIAL_WINDOW_SIZE = 65_535
  DEFAULT_MAX_FRAME_SIZE      = MINIMUM_FRAME_SIZE
  REQUEST_PSEUDO_HEADERS      = %w(:method :scheme :authority :path)
  RESPONSE_PSEUDO_HEADERS     = %w(:status)
end
