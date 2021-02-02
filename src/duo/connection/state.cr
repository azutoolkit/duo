module Duo
  enum State
    IDLE
    RESERVED_LOCAL
    RESERVED_REMOTE
    OPEN
    HALF_CLOSED_LOCAL
    HALF_CLOSED_REMOTE
    CLOSED

    def active?
      this == OPEN ||
        this == HALF_CLOSED_LOCAL ||
        this == HALF_CLOSED_REMOTE
    end

    # :nodoc:
    def to_s(io)
      case self
      when IDLE
        io << "idle"
      when RESERVED_LOCAL
        io << "reserved (local)"
      when RESERVED_REMOTE
        io << "reserved (remote)"
      when OPEN
        io << "open"
      when HALF_CLOSED_LOCAL
        io << "half-closed (local)"
      when HALF_CLOSED_REMOTE
        io << "half-closed (remote)"
      when CLOSED
        io << "closed"
      end
    end
  end
end
