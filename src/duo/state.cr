module Duo
  enum State
    Idle
    ReservedLocal
    ReservedRemote
    Open
    HalfClosedLocal
    HalfClosedRemote
    Closed

    def self.receiving(frame : Frame)
      state = frame.stream.state
      state.transition(frame, receiving: true)
    end

    def self.sending(frame : Frame)
      state = frame.stream.state
      state.transition(frame, receiving: false)
    end

    def active?
      open? || half_closed_local? || half_closed_remote?
    end

    def transition(frame : Frame, receiving = false)
      return if frame.stream.id == 0 || FrameType.non_transitional?(frame.type)
      stream = frame.stream

      case self
      when Idle
        case frame.type
        when FrameType::Headers
          stream.state = frame.flags.end_stream? ? HalfClosedRemote : Open
        when FrameType::PushPromise
          stream.state = receiving ? ReservedRemote : ReservedLocal
        when FrameType::Priority
          # PRIORITY frames are allowed on idle streams
        else
          error!(receiving)
        end
      when ReservedLocal
        error!(receiving) if receiving

        case frame.type
        when FrameType::Headers   then stream.state = HalfClosedLocal
        when FrameType::RstStream then stream.state = Closed
        else                           error!(receiving)
        end
      when ReservedRemote
        error!(receiving) unless receiving
        case frame.type
        when FrameType::Headers   then stream.state = HalfClosedRemote
        when FrameType::RstStream then stream.state = Closed
        else                           error!(receiving)
        end
      when Open
        case frame.type
        when FrameType::Headers, FrameType::Data
          if frame.flags.end_stream?
            stream.state = receiving ? HalfClosedRemote : HalfClosedLocal
          end
        when FrameType::RstStream
          stream.state = Closed
        when FrameType::WindowUpdate
          # ignore
        else
          error!(receiving)
        end
      when HalfClosedLocal
        if frame.flags.end_stream? || frame.type.rst_stream?
          stream.state = Closed
        end
      when HalfClosedRemote
        if receiving
          case frame.type
          when FrameType::Headers, FrameType::Continuation, FrameType::Data
            raise Error.stream_closed
          end
        end
        if frame.flags.end_stream? || frame.type.rst_stream?
          stream.state = Closed
        end
      when Closed
        case frame.type
        when FrameType::WindowUpdate, FrameType::RstStream
        else
          if receiving
            raise Error.stream_closed
          else
            frame.stream.send_rst_stream(Error::Code::InternalError)
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

    def to_s(io)
      io << "#{self}"
    end
  end
end
