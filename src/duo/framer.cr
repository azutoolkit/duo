module Duo
  def receive : Frame?
    frame = read_frame_header
    stream = frame.stream

    stream.receiving(frame)

    case frame.type
    when Frame::Type::Data
      raise Error.protocol_error if stream.id == 0
      read_data_frame(frame)
    when Frame::Type::Headers
      raise Error.protocol_error if stream.id == 0
      read_headers_frame(frame)
    when Frame::Type::PushPromise
      raise Error.protocol_error if stream.id == 0
      read_push_promise_frame(frame)
    when Frame::Type::Priority
      raise Error.protocol_error if stream.id == 0
      read_priority_frame(frame)
    when Frame::Type::RstStream
      raise Error.protocol_error if stream.id == 0
      read_rst_stream_frame(frame)
    when Frame::Type::Settings
      raise Error.protocol_error unless stream.id == 0
      read_settings_frame(frame)
    when Frame::Type::Ping
      raise Error.protocol_error unless stream.id == 0
      read_ping_frame(frame)
    when Frame::Type::GoAway
      read_goaway_frame(frame)
    when Frame::Type::WindowUpdate
      read_window_update_frame(frame)
    when Frame::Type::Continuation
      raise Error.protocol_error("UNEXPECTED Continuation frame")
    else
      read_unsupported_frame(frame)
    end

    frame
  end



  private def read_frame_header
    buf = io.read_bytes(UInt32, IO::ByteFormat::BigEndian)
    size, type = (buf >> 8).to_i, buf & 0xff
    
    flags = Frame::Flags.new(read_byte)
    _, stream_id = read_stream_id

    if size > remote_settings.max_frame_size
      raise Error.frame_size_error
    end

    frame_type = Frame::Type.new(type.to_i)
    unless frame_type.priority? || streams.valid?(stream_id)
      raise Error.protocol_error("INVALID stream_id ##{stream_id}")
    end

    stream = streams.find(stream_id, consume: !frame_type.priority?)
    frame = Frame.new(frame_type, stream, flags, size: size)

    frame
  end

end