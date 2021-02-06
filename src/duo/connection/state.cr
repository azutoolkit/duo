module Duo
  enum State
    Idle
    ReservedLocal
    ReservedRemote
    Open
    HalfClosedLocal
    HalfClosedRemote
    Closed

    def active?
      self == Open ||
        self == HalfClosedLocal ||
        self == HalfClosedRemote
    end

    def transition(frame : Frame, receiving = false)
      return if frame.stream.id == 0 || Frame::Type.non_transitional?(frame.type)
      stream = frame.stream

      case self
      when Idle
        case frame.type
        when Frame::Type::Headers
          stream.state = frame.flags.end_stream? ? HalfClosedRemote : Open
        when Frame::Type::PushPromise
          stream.state = receiving ? ReservedRemote : ReservedLocal
        else
          error!(receiving)
        end
      when ReservedLocal
        error!(receiving) if receiving

        case frame.type
        when Frame::Type::Headers
          stream.state = HalfClosedLocal
        when Frame::Type::RstStream
          stream.state = Closed
        else
          error!(receiving)
        end
      when ReservedRemote
        error!(receiving) unless receiving

        case frame.type
        when Frame::Type::Headers
          stream.state = HalfClosedRemote
        when Frame::Type::RstStream
          stream.state = Closed
        else
          error!(receiving)
        end
      when Open
        case frame.type
        when Frame::Type::Headers, Frame::Type::Data
          if frame.flags.end_stream?
            stream.state = receiving ? HalfClosedRemote : HalfClosedLocal
          end
        when Frame::Type::RstStream
          stream.state = Closed
        when Frame::Type::WindowUpdate
          # ignore
        else
          error!(receiving)
        end
      when HalfClosedLocal
        if frame.flags.end_stream? || frame.type == Frame::Type::RstStream
          stream.state = Closed
        end
      when HalfClosedRemote
        if receiving
          case frame.type
          when Frame::Type::Headers, Frame::Type::Continuation, Frame::Type::Data
            raise Error.stream_closed
          else
            # shut up, crystal
          end
        end
        if frame.flags.end_stream? || frame.type == Frame::Type::RstStream
          stream.state = Closed
        end
      when Closed
        case frame.type
        when Frame::Type::WindowUpdate, Frame::Type::RstStream
          # ignore
        else
          if receiving
            raise Error.stream_closed
          else
            raise Error.internal_error
          end
        end
      end
    end

    def error!(receiving = false)
      if receiving
        raise Error.protocol_error
      else
        raise Error.internal_error
      end
    end

    # :nodoc:
    def to_s(io)
      io << "#{self}"
    end
  end
end
