module Duo
  enum State
    IDLE
    ReservedLocal
    ReservedRemote
    OPEN
    HalfClosedLocal
    HalfClosedRemote
    Closed

    def active?
      self == OPEN ||
      self == HalfClosedLocal ||
      self == HalfClosedRemote
    end

    # :nodoc:
    def to_s(io)
      io << "#{self}"
    end
  end
end
