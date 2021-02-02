require "./frames/*"

module Frames
  # Reads padding information and yields the actual
  # frame size without the padding size.
  # Eventually skips the padding.
  private def read_padded(frame)
    size = frame.size

    if frame.flags.padded?
      pad_size = read_byte
      size -= 1 + pad_size
    end

    raise Error.protocol_error("INVALID pad length") if size < 0

    yield size

    if pad_size
      io.skip(pad_size)
    end
  end
end
